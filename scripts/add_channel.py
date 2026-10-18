"""Add YouTube channels to `channel_dimensions` (admin ingest helper).

BR-006: `channel_id` is truth for channel identity. This script resolves a
human handle (or URL, or bare channel ID) to a canonical `channel_id` via
the YouTube Data API, then inserts identity-only rows through the U1 SQL
templates. BR-008: no manual metadata — only IDs plus quality fields.
"""

import argparse
import csv
import json
import os
import re
import sys

import requests
import yaml


# ---------------------------------------------------------------------------
# Constants.
# ---------------------------------------------------------------------------

_API_URL = "https://www.googleapis.com/youtube/v3/channels"

_ID_RE = re.compile(r"^UC[a-zA-Z0-9_-]{22}$")

CHECK_SQL_PATH = "sql/00_utils/check_channel_exists.sql"
INSERT_SQL_PATH = "sql/01_raw/ops/insert_channel_dim.sql"
REACTIVATE_SQL_PATH = "sql/01_raw/ops/reactivate_channel.sql"

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Exceptions.
# ---------------------------------------------------------------------------


class YouTubeApiError(Exception):
    """Generic YouTube Data API failure."""


class QuotaExceededError(YouTubeApiError):
    """YouTube API quota exhausted (distinct from generic API errors)."""


class UnknownHandle(Exception):
    """Handle/ID resolved to zero YouTube channels."""


# ---------------------------------------------------------------------------
# Handle normalization (BR-006: resolve everything toward channel_id).
# ---------------------------------------------------------------------------


def normalize_handle(raw):
    """Map raw user input to ("handle", "@name") or ("id", "UC...")."""
    text = raw.strip()

    # Strip any YouTube URL wrapper (scheme/www tolerated, case kept).
    if re.search(r"youtube\.com/|youtu\.be/", text, flags=re.IGNORECASE):
        rest = re.split(
            r"youtube\.com/|youtu\.be/", text, maxsplit=1, flags=re.IGNORECASE
        )[1].lstrip("/")
        rest = re.split(r"[?#]", rest, maxsplit=1)[0].rstrip("/")
        if rest.startswith("channel/"):
            candidate = rest[len("channel/"):].split("/")[0].strip()
            if _ID_RE.match(candidate):
                return ("id", candidate)
            return ("handle", "@" + candidate.lstrip("@"))
        for prefix in ("c/", "user/"):
            if rest.startswith(prefix):
                name = rest[len(prefix):].split("/")[0].strip().lstrip("@")
                return ("handle", "@" + name)
        if rest.startswith("@"):
            return ("handle", "@" + rest[1:].split("/")[0].strip())
        name = rest.split("/")[0].strip().lstrip("@")
        if _ID_RE.match(name):
            return ("id", name)
        return ("handle", "@" + name)

    text = re.split(r"[?#]", text, maxsplit=1)[0].strip().rstrip("/")
    if _ID_RE.match(text):
        return ("id", text)
    return ("handle", "@" + text.split("/")[0].strip().lstrip("@"))


# ---------------------------------------------------------------------------
# YouTube resolution.
# ---------------------------------------------------------------------------


def _indicates_quota(payload, text):
    blob = (text or "") + json.dumps(payload or {}, default=str)
    return "quotaExceeded" in blob


def resolve_channel(handle_or_id, api_key, http_get=requests.get):
    """Resolve a handle (or bare channel ID) to (channel_id, handle)."""
    token = handle_or_id.strip()
    params = {"part": "id,snippet", "key": api_key}
    if _ID_RE.match(token):
        params["id"] = token
    else:
        params["forHandle"] = token.lstrip("@")

    try:
        response = http_get(_API_URL, params=params)
    except QuotaExceededError:
        raise
    except Exception as exc:
        raise YouTubeApiError(str(exc)) from exc

    status = getattr(response, "status_code", 200)
    try:
        payload = response.json()
    except Exception as exc:
        raise YouTubeApiError(f"invalid JSON from YouTube API: {exc}") from exc
    if not isinstance(payload, dict):
        raise YouTubeApiError(f"unexpected YouTube payload: {payload!r}")

    if status == 403 or payload.get("error", {}).get("code") == 403:
        if _indicates_quota(payload, getattr(response, "text", "")):
            raise QuotaExceededError(f"quota exceeded for {handle_or_id!r}")
        raise YouTubeApiError(f"YouTube request forbidden: {payload!r}")
    if status >= 400 or "error" in payload:
        raise YouTubeApiError(f"YouTube request failed: {payload!r}")

    items = payload.get("items", [])
    if not items:
        raise UnknownHandle(handle_or_id)
    item = items[0]
    channel_id = item.get("id")
    if not channel_id:
        raise YouTubeApiError(f"YouTube item missing id: {item!r}")
    snippet = item.get("snippet", {}) or {}
    handle = snippet.get("customUrl") or handle_or_id
    return (channel_id, handle)


# ---------------------------------------------------------------------------
# Templates + config.
# ---------------------------------------------------------------------------


def default_added_by():
    """Stamp rows with the invoking user and script name."""
    return "SimonLiles:" + os.path.basename(__file__)


def load_template(rel_path):
    """Read a U1 SQL template relative to the repo root."""
    path = os.path.join(_REPO_ROOT, rel_path)
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def render_template(text, project, dataset):
    """Fill {{project}}/{{dataset}}; leave @named BigQuery params alone."""
    return text.replace("{{project}}", project).replace("{{dataset}}", dataset)


def _load_config(path=None):
    cfg_path = path or os.path.join(_REPO_ROOT, "config.yml")
    with open(cfg_path, "r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def _resolve_target(project=None, dataset=None):
    if project and dataset:
        return (project, dataset)
    try:
        config = _load_config()
    except OSError:
        config = {}
    return (
        project or config.get("project") or "yt-sailing-dashboard",
        dataset or config.get("dataset") or "yt_sailing_data_dev",
    )


# ---------------------------------------------------------------------------
# BigQuery boundary (lazy client import: module stays importable bare).
# ---------------------------------------------------------------------------


def build_bq_client(project):
    """Wrap a BigQuery client behind a tiny .query(sql, params) facade."""
    from google.cloud import bigquery

    client = bigquery.Client(project=project)

    def _param(name, value):
        if isinstance(value, bool):
            kind = "BOOL"
        elif isinstance(value, int):
            kind = "INT64"
        elif isinstance(value, float):
            kind = "FLOAT64"
        else:
            kind = "STRING"
        return bigquery.ScalarQueryParameter(name, kind, value)

    class _BqClient:
        def query(self, sql, params=None):
            job_config = bigquery.QueryJobConfig(
                query_parameters=[_param(k, v) for k, v in (params or {}).items()]
            )
            return [dict(row) for row in client.query(sql, job_config=job_config).result()]

    return _BqClient()


# ---------------------------------------------------------------------------
# Row processing.
# ---------------------------------------------------------------------------


def process_one(
    kind,
    value,
    *,
    bq,
    api_key,
    status=None,
    type=None,
    added_by=None,
    reactivate=False,
    dry_run=False,
    project=None,
    dataset=None,
):
    """Resolve, dup-check, and insert/reactivate one channel; never raises."""
    try:
        channel_id, resolved_handle = resolve_channel(value, api_key)
    except (UnknownHandle, YouTubeApiError):
        return "failed"

    proj, ds = _resolve_target(project, dataset)
    check_sql = render_template(load_template(CHECK_SQL_PATH), proj, ds)
    rows = bq.query(check_sql, {"channel_id": channel_id}) or []

    if rows:
        first = rows[0]
        is_active = first.get("is_active") if isinstance(first, dict) else first[2]
        if is_active:
            return "already-active"
        if not reactivate:
            return "inactive-skipped"
        if dry_run:
            return "reactivated"
        reactivate_sql = render_template(load_template(REACTIVATE_SQL_PATH), proj, ds)
        bq.query(reactivate_sql, {"channel_id": channel_id})
        return "reactivated"

    if dry_run:
        return "added"
    insert_sql = render_template(load_template(INSERT_SQL_PATH), proj, ds)
    bq.query(
        insert_sql,
        {
            "channel_id": channel_id,
            "channel_handle": resolved_handle,
            "status": status,
            "type": type,
            "added_by": added_by if added_by is not None else default_added_by(),
        },
    )
    return "added"


def process_batch(raw_values, *, bq, api_key, reactivate=False, dry_run=False):
    """Process each raw handle independently; one failure never aborts."""
    outcomes = []
    for raw in raw_values:
        try:
            kind, value = normalize_handle(raw)
            outcomes.append(
                process_one(
                    kind,
                    value,
                    bq=bq,
                    api_key=api_key,
                    reactivate=reactivate,
                    dry_run=dry_run,
                )
            )
        except Exception:
            outcomes.append("failed")
    return outcomes


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------


def parse_args(argv=None):
    """Define the add-channel command line surface."""
    parser = argparse.ArgumentParser(
        description="Add YouTube channels to channel_dimensions."
    )
    parser.add_argument("handles", nargs="*")
    parser.add_argument("--status", default=None)
    parser.add_argument("--type", default=None)
    parser.add_argument("--added-by", dest="added_by", default=None)
    parser.add_argument("--file", default=None)
    parser.add_argument("--reactivate", action="store_true")
    parser.add_argument("--dry-run", dest="dry_run", action="store_true")
    parser.add_argument("--dataset", default=None)
    parser.add_argument("--prod", action="store_true")
    parser.add_argument("--yes", action="store_true")
    return parser.parse_args(argv)


def check_prod_guard(prod, yes):
    """Block accidental prod writes; --prod demands an explicit --yes."""
    if prod and not yes:
        raise SystemExit("refusing prod write without --yes")
    return None


def effective_dataset(cli_dataset, config_dataset):
    """CLI --dataset wins; otherwise fall back to the config value."""
    return cli_dataset if cli_dataset else config_dataset


def read_input_csv(path):
    """Read batch rows with handle/status/type keys (blanks become None)."""
    rows = []
    with open(path, newline="", encoding="utf-8") as handle:
        for record in csv.DictReader(handle):
            rows.append(
                {
                    "handle": (record.get("handle") or "").strip(),
                    "status": (record.get("status") or "").strip() or None,
                    "type": (record.get("type") or "").strip() or None,
                }
            )
    return rows


def main(argv=None):
    """Parse, guard, wire live boundaries, then process every input row."""
    args = parse_args(argv)
    check_prod_guard(args.prod, args.yes)

    try:
        config = _load_config()
    except OSError as exc:
        print(f"error: cannot load config.yml: {exc}", file=sys.stderr)
        return 1
    project = config.get("project")
    dataset = effective_dataset(args.dataset, config.get("dataset"))

    api_key = os.environ.get("YT_API_KEY")
    if not api_key:
        print("error: YT_API_KEY is not set", file=sys.stderr)
        return 1

    try:
        bq = build_bq_client(project)
    except Exception as exc:
        print(f"error: cannot create BigQuery client: {exc}", file=sys.stderr)
        return 1

    added_by = args.added_by or default_added_by()
    jobs = [(raw, args.status, args.type) for raw in args.handles]
    if args.file:
        try:
            csv_rows = read_input_csv(args.file)
        except OSError as exc:
            print(f"error: cannot read input CSV: {exc}", file=sys.stderr)
            return 1
        for row in csv_rows:
            jobs.append(
                (
                    row["handle"],
                    row["status"] if row["status"] is not None else args.status,
                    row["type"] if row["type"] is not None else args.type,
                )
            )
    if not jobs:
        print("nothing to do: provide handles or --file")

    outcomes = []
    for raw, row_status, row_type in jobs:
        try:
            kind, value = normalize_handle(raw)
            outcome = process_one(
                kind,
                value,
                bq=bq,
                api_key=api_key,
                status=row_status,
                type=row_type,
                added_by=added_by,
                reactivate=args.reactivate,
                dry_run=args.dry_run,
                project=project,
                dataset=dataset,
            )
        except Exception as exc:
            outcome = "failed"
            print(f"{raw}: failed ({exc})")
        else:
            print(f"{raw}: {outcome}")
        outcomes.append(outcome)
    return 0 if all(outcome != "failed" for outcome in outcomes) else 1


if __name__ == "__main__":
    raise SystemExit(main())
