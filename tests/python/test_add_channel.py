"""U2 — `scripts/add_channel.py` contract tests (RED phase, mocks only).

WRITER CONTRACT — implement these exact names in `scripts/add_channel.py`:
- `normalize_handle(raw) -> (kind, value)` where kind in `{"handle", "id"}`.
  Preserves case; trims whitespace; prepends `@` when missing; maps
  `youtube.com/@X`, `youtube.com/c/X` URLs to `@X`; maps
  `youtube.com/channel/<UCid>` and bare 24-char `UC...` IDs to `("id", <id>)`.
  IDs match `^UC[a-zA-Z0-9_-]{22}$`.
- `resolve_channel(handle_or_id, api_key, http_get=requests.get)`
  -> `(channel_id, resolved_handle)`. Handle input sends YouTube
  `channels.list` with `part=id,snippet` + `forHandle=` (never `id`+`forHandle`
  together); ID input sends `id=` instead. Parses `items[0].id` and
  `items[0].snippet.customUrl`. Empty `items[]` raises `UnknownHandle`.
  HTTP 403 quotaExceeded raises `QuotaExceededError`; other API failures raise
  `YouTubeApiError`. Exceptions are module attributes with EXACTLY these names:
  `UnknownHandle`, `QuotaExceededError`, `YouTubeApiError`.
- `default_added_by() -> "SimonLiles:add_channel.py"`; script part derived via
  `os.path.basename(__file__)` (not a hardcoded full path).
- `load_template(rel_path) -> str` reads repo-relative template files, e.g.
  `"sql/00_utils/check_channel_exists.sql"`,
  `"sql/01_raw/ops/insert_channel_dim.sql"`,
  `"sql/01_raw/ops/reactivate_channel.sql"`.
- `render_template(text, project, dataset) -> str` replaces `{{project}}` /
  `{{dataset}}`, leaves `@named` params untouched, no residual braces.
- `process_one(kind, value, *, bq, api_key, status=None, type=None,
  added_by=None, reactivate=False, dry_run=False) -> str` outcome in
  `{"added", "already-active", "inactive-skipped", "reactivated", "failed"}`.
  Internally calls module-level `resolve_channel` (tests patch it) and
  `load_template`/`render_template` (tests spy on them). `bq` has
  `.query(sql, params)`; SELECT returns rows (list of dicts with `is_active`),
  INSERT/UPDATE return []. `added_by=None` means use `default_added_by()`.
  `status`/`type` default None. `dry_run` resolves but never sends
  INSERT/UPDATE. Per-row failures in batch surface as `"failed"`, never raise.
- `process_batch(raw_values, *, bq, api_key, reactivate=False, dry_run=False)`
  `-> list[str]`; `raw_values` is a list of raw handle/ID strings; processes
  every row independently (one row's `UnknownHandle` never stops the others).
- `parse_args(argv=None) -> argparse.Namespace` with positional `handles`
  (`nargs="*"`), options `--status/--type/--added-by/--file/--reactivate/
  --dry-run/--dataset/--prod/--yes`; defaults: status None, type None,
  added_by None, file None, reactivate False, dry_run False, dataset None,
  prod False, yes False.
- `check_prod_guard(prod, yes)` raises `SystemExit` when prod True and yes
  False; otherwise returns normally. `main()` must call it BEFORE any
  YouTube/BigQuery I/O.
- `effective_dataset(cli_dataset, config_dataset) -> str` returns
  `cli_dataset` when truthy else `config_dataset`.
- `read_input_csv(path) -> list[dict]`; each dict has keys
  `handle`/`status`/`type` (`status`/`type` None when column missing/empty).
- `main(argv=None)` CLI entry; `--prod` without `--yes` exits before I/O.
- Importability: `import add_channel` must work WITHOUT `google.cloud.bigquery`
  installed (bigquery imported lazily inside functions only). Plain strings for
  outcomes are sufficient (`RecordOutcome` constants optional).

Conventions: pytest plain `test_` functions; `unittest.mock` fakes at the
YouTube-HTTP + BigQuery boundaries; NO live network/BigQuery/GCP calls.
"""

import ast
import importlib
import inspect
import os
import re
import sys

import pytest

sys.path.insert(
    0,
    os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "scripts")
    ),
)

from unittest import mock  # noqa: E402

import add_channel  # noqa: E402  (writer creates scripts/add_channel.py)


CID_1 = "UC" + "x" * 22
CID_2 = "UCabcdefghijklmnopqrstuv"
assert re.match(r"^UC[a-zA-Z0-9_-]{22}$", CID_1)
assert re.match(r"^UC[a-zA-Z0-9_-]{22}$", CID_2)

CHECK_PATH = "sql/00_utils/check_channel_exists.sql"
INSERT_PATH = "sql/01_raw/ops/insert_channel_dim.sql"
REACTIVATE_PATH = "sql/01_raw/ops/reactivate_channel.sql"


# ------------------------------------------------------------------ fakes

class FakeHTTPResponse:
    """Minimal stand-in for `requests.Response` (no network)."""

    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code
        self.text = str(payload)

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            import requests

            raise requests.HTTPError(f"{self.status_code} error")


def _ok_payload(channel_id=CID_1, custom_url="@Foo"):
    return {
        "items": [
            {"id": channel_id, "snippet": {"customUrl": custom_url}}
        ]
    }


def _quota_payload():
    return {
        "error": {
            "code": 403,
            "message": "quotaExceeded",
            "errors": [{"reason": "quotaExceeded"}],
        }
    }


def make_http_get(payload=None, status_code=200, record=None):
    calls = record if record is not None else []

    def _get(url, params=None, **kwargs):
        calls.append({"url": url, "params": dict(params or {}), "kwargs": kwargs})
        return FakeHTTPResponse(payload or {}, status_code)

    _get.calls = calls
    return _get


def _call_text(call):
    return " ".join(
        [str(call.get("url", "")), str(call.get("params", "")), str(call.get("kwargs", ""))]
    )


class FakeBQ:
    """Stands in for the BigQuery boundary: `.query(sql, params)`."""

    def __init__(self, select_rows=None):
        self.select_rows = list(select_rows or [])
        self.calls = []

    def query(self, sql, params=None):
        self.calls.append((sql, dict(params or {})))
        if "SELECT" in sql.upper():
            return list(self.select_rows)

        return []

    def writes(self):
        return [
            (s, p)
            for s, p in self.calls
            if "INSERT" in s.upper() or "UPDATE" in s.upper()
        ]


def _params_get(params, *names):
    for name in names:
        if name in params:
            return params[name]

    return None


def _params_contain(params, value):
    return any(v == value for v in params.values())


# ------------------------------------------------------- 1. normalize_handle

def test_normalize_at_handle_preserved():
    kind, value = add_channel.normalize_handle("@Foo")
    assert kind == "handle"
    assert value == "@Foo"


def test_normalize_bare_name_trimmed_and_prefixed():
    kind, value = add_channel.normalize_handle("  foo  ")
    assert kind == "handle"
    assert value == "@foo"


def test_normalize_bare_name_without_spaces_gets_at():
    kind, value = add_channel.normalize_handle("foo")
    assert kind == "handle"
    assert value == "@foo"


def test_normalize_at_url_extracts_handle():
    kind, value = add_channel.normalize_handle("https://www.youtube.com/@Foo")
    assert kind == "handle"
    assert value == "@Foo"


def test_normalize_c_url_extracts_handle():
    kind, value = add_channel.normalize_handle("https://youtube.com/c/Foo")
    assert kind == "handle"
    assert value == "@Foo"


def test_normalize_channel_url_returns_id_flagged():
    kind, value = add_channel.normalize_handle(
        f"https://www.youtube.com/channel/{CID_1}"
    )
    assert kind == "id"
    assert value == CID_1
    assert re.match(r"^UC[a-zA-Z0-9_-]{22}$", value)


def test_normalize_plain_id_flagged_as_id():
    kind, value = add_channel.normalize_handle(CID_2)
    assert kind == "id"
    assert value == CID_2
    assert re.match(r"^UC[a-zA-Z0-9_-]{22}$", value)


# ------------------------------------------------- 2. resolve via forHandle

def test_resolve_handle_uses_for_handle_only():
    http_get = make_http_get(_ok_payload())
    add_channel.resolve_channel("@Foo", "KEY", http_get=http_get)
    assert len(http_get.calls) == 1
    call = http_get.calls[0]
    assert "channels" in call["url"]
    params = call["params"]
    assert params.get("forHandle") in ("Foo", "@Foo"), params
    assert "id" not in params, f"must never send id+forHandle together: {params}"
    part = params.get("part", "")
    assert "id" in part and "snippet" in part, f"part must be id,snippet: {params}"


def test_resolve_id_uses_id_only():
    http_get = make_http_get(_ok_payload(channel_id=CID_2))
    add_channel.resolve_channel(CID_2, "KEY", http_get=http_get)
    assert len(http_get.calls) == 1
    call = http_get.calls[0]
    params = call["params"]
    assert params.get("id") == CID_2, params
    assert "forHandle" not in params, f"must never send id+forHandle together: {params}"


def test_resolve_parses_id_and_custom_url():
    http_get = make_http_get(_ok_payload(channel_id=CID_1, custom_url="@Foo"))
    channel_id, handle = add_channel.resolve_channel("@Foo", "KEY", http_get=http_get)
    assert channel_id == CID_1
    assert handle == "@Foo"


def test_resolve_empty_items_raises_unknown_handle():
    http_get = make_http_get({"items": []})
    with pytest.raises(add_channel.UnknownHandle):
        add_channel.resolve_channel("@Missing", "KEY", http_get=http_get)


def test_resolve_quota_error_distinguished():
    http_get = make_http_get(_quota_payload(), status_code=403)
    with pytest.raises(add_channel.QuotaExceededError):
        add_channel.resolve_channel("@Foo", "KEY", http_get=http_get)


def test_resolve_generic_api_error_is_not_quota_or_unknown():
    http_get = make_http_get({"error": {"code": 500, "message": "boom"}}, status_code=500)
    with pytest.raises(add_channel.YouTubeApiError):
        try:
            add_channel.resolve_channel("@Foo", "KEY", http_get=http_get)
        except (add_channel.UnknownHandle, add_channel.QuotaExceededError):
            pytest.fail("generic API error must not raise Unknown/Quota types")


# ------------------------------------------------------- 3. added_by default

def test_default_added_by_value():
    assert add_channel.default_added_by() == "SimonLiles:add_channel.py"


def test_default_added_by_derives_basename():
    src = inspect.getsource(add_channel.default_added_by)
    assert "basename" in src, "must derive script name via os.path.basename(__file__)"
    assert "__file__" in src


# ------------------------------------------------- 4. status/type defaults

def test_parse_args_status_type_default_none():
    args = add_channel.parse_args([])
    assert args.status is None
    assert args.type is None


def test_parse_args_status_type_override():
    args = add_channel.parse_args(["@Foo", "--status", "active", "--type", "creator"])
    assert args.status == "active"
    assert args.type == "creator"


def test_parse_args_added_by_default_none_flag_overrides():
    assert add_channel.parse_args(["@Foo"]).added_by is None
    args = add_channel.parse_args(["@Foo", "--added-by", "Tester:x.py"])
    assert args.added_by == "Tester:x.py"


def test_process_one_status_type_none_forwarded_to_bq(tmp_path=None):
    bq = FakeBQ(select_rows=[])
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=False,
        )
    writes = bq.writes()
    assert writes, "new channel must attempt an INSERT write"
    _, params = writes[0]
    assert _params_get(params, "status", "@status") is None
    assert _params_get(params, "type", "@type") is None


def test_read_csv_preserves_status_type_and_defaults(tmp_path):
    path = tmp_path / "channels.csv"
    path.write_text("handle,status,type\n@A,active,creator\n@B,,\n", encoding="utf-8")
    rows = add_channel.read_input_csv(str(path))
    assert rows[0]["handle"] == "@A"
    assert rows[0]["status"] == "active"
    assert rows[0]["type"] == "creator"
    assert rows[1]["handle"] == "@B"
    assert rows[1]["status"] is None
    assert rows[1]["type"] is None


# ------------------------------------------------------------- 5. dup logic

def test_existing_active_yields_already_active_no_insert():
    bq = FakeBQ(
        select_rows=[{"channel_id": CID_1, "channel_handle": "@Foo", "is_active": True}]
    )
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        outcome = add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=False,
        )
    assert outcome == "already-active"
    assert bq.writes() == [], "active dup must not INSERT or UPDATE"


def test_existing_inactive_without_reactivate_skipped():
    bq = FakeBQ(
        select_rows=[{"channel_id": CID_1, "channel_handle": "@Foo", "is_active": False}]
    )
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        outcome = add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=False,
        )
    assert outcome == "inactive-skipped"
    assert bq.writes() == [], "inactive row without --reactivate must not UPDATE"


def test_existing_inactive_with_reactivate_runs_template():
    bq = FakeBQ(
        select_rows=[{"channel_id": CID_1, "channel_handle": "@Foo", "is_active": False}]
    )
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        outcome = add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=True, dry_run=False,
        )
    assert outcome == "reactivated"
    writes = bq.writes()
    assert writes, "reactivate must issue an UPDATE write"
    sql, _ = writes[-1]
    assert "SET" in sql.upper() and "is_active = TRUE".upper() in sql.upper()
    assert "INSERT" not in sql.upper()


# ----------------------------------------------------------- 6. insert path

def test_new_channel_runs_insert_template():
    bq = FakeBQ(select_rows=[])
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        outcome = add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=False,
        )
    assert outcome == "added"
    writes = bq.writes()
    assert writes, "new channel must INSERT"
    sql, _ = writes[0]
    assert "INSERT INTO" in sql.upper()
    assert "channel_dimensions" in sql


def test_insert_params_are_named_mapping():
    bq = FakeBQ(select_rows=[])
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=False,
        )
    _, params = bq.writes()[0]
    assert isinstance(params, dict)
    assert _params_contain(params, CID_1), f"params must include channel_id: {params}"
    assert _params_contain(params, "@Foo"), f"params must include handle: {params}"
    assert _params_get(params, "added_by", "@added_by") == "T:x.py"
    assert _params_get(params, "status", "@status") is None
    assert _params_get(params, "type", "@type") is None


def test_process_one_defaults_added_by_when_none():
    bq = FakeBQ(select_rows=[])
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ):
        add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by=None,
            reactivate=False, dry_run=False,
        )
    _, params = bq.writes()[0]
    assert _params_get(params, "added_by", "@added_by") == add_channel.default_added_by()


def test_dry_run_resolves_but_never_inserts_or_updates():
    bq = FakeBQ(select_rows=[])
    with mock.patch.object(
        add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
    ) as resolve_spy:
        outcome = add_channel.process_one(
            "handle", "@Foo", bq=bq, api_key="k",
            status=None, type=None, added_by="T:x.py",
            reactivate=False, dry_run=True,
        )
    assert resolve_spy.call_count == 1, "dry-run must still resolve the handle"
    assert bq.writes() == [], "dry-run must never INSERT or UPDATE"
    assert outcome == "added"


# ------------------------------------------------- 7. batch independence

def test_batch_middle_failure_still_processes_neighbors():
    bq = FakeBQ(select_rows=[])

    def _fake_resolve(handle_or_id, api_key, http_get=None):
        if "Missing" in str(handle_or_id):
            raise add_channel.UnknownHandle(handle_or_id)

        return (CID_1, handle_or_id)

    with mock.patch.object(add_channel, "resolve_channel", side_effect=_fake_resolve):
        outcomes = add_channel.process_batch(
            ["@Good1", "@Missing", "@Good3"], bq=bq, api_key="k"
        )
    assert len(outcomes) == 3
    assert outcomes[0] == "added"
    assert outcomes[1] == "failed"
    assert outcomes[2] == "added"
    assert len(bq.writes()) == 2, "rows 1 and 3 must still INSERT"


# ------------------------------------------------------------ 8. SQL reuse

def test_load_template_reads_check_file():
    text = add_channel.load_template(CHECK_PATH)
    assert "SELECT" in text.upper()
    assert "channel_dimensions" in text


def test_load_template_reads_insert_and_reactivate_files():
    insert_sql = add_channel.load_template(INSERT_PATH)
    assert "INSERT INTO" in insert_sql.upper()
    assert "channel_dimensions" in insert_sql
    reactivate_sql = add_channel.load_template(REACTIVATE_PATH)
    assert "is_active = TRUE".upper() in reactivate_sql.upper()


def test_render_template_substitutes_project_dataset():
    rendered = add_channel.render_template(
        "SELECT * FROM `{{project}}.{{dataset}}.channel_dimensions` "
        "WHERE channel_id = @channel_id",
        "my-proj",
        "my_ds",
    )
    assert "{{" not in rendered and "}}" not in rendered
    assert "`my-proj.my_ds.channel_dimensions`" in rendered
    assert "@channel_id" in rendered


def test_process_one_loads_u1_templates_from_disk():
    seen = []

    real_load = add_channel.load_template

    def _spy(rel_path):
        seen.append(rel_path)
        return real_load(rel_path)

    bq = FakeBQ(select_rows=[])
    with mock.patch.object(add_channel, "load_template", side_effect=_spy):
        with mock.patch.object(
            add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
        ):
            add_channel.process_one(
                "handle", "@Foo", bq=bq, api_key="k",
                status=None, type=None, added_by="T:x.py",
                reactivate=False, dry_run=False,
            )
    assert CHECK_PATH in seen, f"must load {CHECK_PATH}; saw {seen}"
    assert INSERT_PATH in seen, f"must load {INSERT_PATH}; saw {seen}"

    seen_re = []
    bq2 = FakeBQ(
        select_rows=[{"channel_id": CID_1, "channel_handle": "@Foo", "is_active": False}]
    )

    def _spy2(rel_path):
        seen_re.append(rel_path)
        return real_load(rel_path)

    with mock.patch.object(add_channel, "load_template", side_effect=_spy2):
        with mock.patch.object(
            add_channel, "resolve_channel", return_value=(CID_1, "@Foo")
        ):
            add_channel.process_one(
                "handle", "@Foo", bq=bq2, api_key="k",
                status=None, type=None, added_by="T:x.py",
                reactivate=True, dry_run=False,
            )
    assert REACTIVATE_PATH in seen_re, f"must load {REACTIVATE_PATH}; saw {seen_re}"


# ------------------------------------------------------------ 9. prod guard

def test_prod_without_yes_aborts():
    with pytest.raises(SystemExit):
        add_channel.check_prod_guard(True, False)


def test_prod_with_yes_passes_and_nonprod_passes():
    assert add_channel.check_prod_guard(True, True) is None or True
    assert add_channel.check_prod_guard(False, False) is None or True


def test_effective_dataset_defaults_to_config_unless_overridden():
    assert add_channel.effective_dataset(None, "dev_ds") == "dev_ds"
    assert add_channel.effective_dataset("cli_ds", "dev_ds") == "cli_ds"


def test_main_prod_without_yes_aborts_before_io():
    with mock.patch.object(
        add_channel, "resolve_channel",
        side_effect=AssertionError("must not touch YouTube API"),
    ):
        with mock.patch.object(
            add_channel, "load_template",
            side_effect=AssertionError("must not touch BigQuery/SQL"),
        ):
            with pytest.raises(SystemExit):
                add_channel.main(["@Foo", "--prod"])


def test_parse_args_prod_yes_dataset_defaults():
    args = add_channel.parse_args(["@Foo"])
    assert args.prod is False
    assert args.yes is False
    assert args.dataset is None
    assert args.dry_run is False
    assert args.reactivate is False


# ----------------------------------------------------- 10. importability

def test_module_imports_without_bigquery_installed():
    blocked = {"google.cloud.bigquery": None}
    with mock.patch.dict(sys.modules, blocked):
        reloaded = importlib.reload(add_channel)
    assert reloaded is not None
    assert sys.modules.get("google.cloud.bigquery") is None


def test_no_top_level_bigquery_import():
    path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "add_channel.py")
    )
    with open(path, "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    for node in tree.body:
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert "bigquery" not in alias.name and "google" not in alias.name, (
                    "bigquery must be imported lazily inside functions, "
                    "not at module level"
                )
        elif isinstance(node, ast.ImportFrom):
            assert "bigquery" not in str(node.module) and "google" not in str(node.module), (
                "bigquery must be imported lazily inside functions, "
                "not at module level"
            )
