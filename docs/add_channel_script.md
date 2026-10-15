# Add-Channel Script — Usage Guide

`scripts/add_channel.py` resolves YouTube handles to canonical `channel_id`
values and inserts identity-only rows into BigQuery `channel_dimensions`,
ready for the next scheduled ETL run to enrich. Handles are mutable; IDs
are not — so the script uses the handle only once at intake (via
`channels.list?forHandle=`), while the daily ETL keeps collecting by
immutable `channel_id` (BR-006).

Related plan: `agents/plans/iteration_oob_add_channel_plan.md`.

## Prerequisites

- Python 3.11+ with dependencies (one-time):
  ```bash
  pip install google-cloud-bigquery requests pyyaml
  ```
- A YouTube Data API key in `YT_API_KEY` (resolution only, ~1 quota unit
  per handle).
- GCP credentials for BigQuery — either a service-account JSON file:
  ```bash
  export GOOGLE_APPLICATION_CREDENTIALS="/path/to/dev-service-account.json"
  ```
  or application-default login (`gcloud auth application-default login`).
- Run from the repo root. The target dataset comes from `config.yml`
  (`dataset`), which should point at the **dev** dataset
  (`yt_sailing_data_dev`) unless you explicitly pass `--prod --yes`.

## Single handle

```bash
YT_API_KEY="$YT_API_KEY" \
  python3 scripts/add_channel.py "@laurenlanders"
```

Accepted input forms (all normalized automatically): `@name`, `name`,
full URLs (`youtube.com/@name`, `/c/name`, `/user/name`,
`/channel/UC...`), or a bare channel ID (`UC...`, verified via `id=`).
The `@` prefix is optional.

## Multiple handles

Space-separated — each is processed independently, so one failure never
blocks the others:

```bash
YT_API_KEY="$YT_API_KEY" \
  python3 scripts/add_channel.py "@handle1" "@handle2" "@handle3"
```

## Batch CSV file

For larger lists or per-channel `status`/`type` values, use a CSV with a
`handle` column plus optional `status` / `type` columns. Keep the file in
`/tmp` (the repo gitignores `*.csv`):

```csv
handle,status,type
@handle1,,
@handle2,Sailing,Sailing Vlog
@handle3,,
```

```bash
YT_API_KEY="$YT_API_KEY" \
  python3 scripts/add_channel.py --file /tmp/channels.csv
```

Blank `status`/`type` cells become `NULL` (the dashboard falls back to
"Sailing" / "Sailing Vlog"). Command-line handles and `--file` may be
combined in one invocation. CLI flags `--status` / `--type` apply to
command-line handles; CSV columns win for file rows.

## Quality fields and defaults

New rows store identity + quality fields only — no YouTube metadata
(BR-008; the ETL `MERGE` fills that in):

| Column          | Value                                              |
|-----------------|----------------------------------------------------|
| `is_active`     | `TRUE` (eligible for the next ETL run)             |
| `added_by`      | `SimonLiles:add_channel.py` (override `--added-by`)|
| `status`        | `NULL` unless `--status` / CSV column              |
| `type`          | `NULL` unless `--type` / CSV column                |
| `created_at` / `updated_at` | `CURRENT_TIMESTAMP()`               |

## Safety flags

- `--dry-run` — resolve handles and report outcomes **without writing**.
  Note: the dup-check read against BigQuery still runs, so credentials
  are required even for dry runs.
- `--reactivate` — required to flip an existing **inactive** row back to
  active; without it, inactive duplicates are skipped. Existing
  **active** channels are always skipped (`already-active`), never
  duplicated.
- `--dataset NAME` — target a dataset other than the configured one.
- `--prod --yes` — required for production writes; `--prod` without
  `--yes` aborts before any API or BigQuery call.

Preview-then-commit workflow:

```bash
YT_API_KEY="$YT_API_KEY" \
  python3 scripts/add_channel.py "@newchannel" --dry-run
YT_API_KEY="$YT_API_KEY" \
  python3 scripts/add_channel.py "@newchannel"
```

## Outcomes and exit codes

Each input prints one line — `<input>: <outcome>` — with outcome one of:

| Outcome           | Meaning                                        |
|-------------------|------------------------------------------------|
| `added`           | Inserted (or would be, under `--dry-run`)      |
| `already-active`  | Channel already tracked; nothing done          |
| `inactive-skipped`| Exists but inactive; rerun with `--reactivate` |
| `reactivated`     | Inactive row re-enabled (history intact)       |
| `failed`          | Unknown handle or API error; nothing written   |

Exit code is `0` unless one or more rows `failed` (or a fatal error such
as missing `YT_API_KEY` occurred).

## After adding

- Nothing else to trigger: the script does **not** run the ETL. The next
  scheduled ETL execution picks up the new `is_active = TRUE` row and
  populates its title, description, join date, keywords, profile picture,
  and daily metrics automatically (BR-012).
- Verify with, e.g.:
  ```sql
  SELECT channel_id, channel_handle, is_active, status, type, added_by,
         created_at, updated_at
  FROM `yt-sailing-dashboard.yt_sailing_data_dev.channel_dimensions`
  WHERE channel_handle = '<new_channel_handle>';
  ```

## Reusable SQL

The script executes shared templates from `sql/` (usable from R via
`run_sql_file(..., params =)` too): `sql/00_utils/check_channel_exists.sql`,
`sql/01_raw/ops/insert_channel_dim.sql`,
`sql/01_raw/ops/reactivate_channel.sql`. Tests live in `tests/python/`
(run `python3 -m pytest tests/python/ -q`).
