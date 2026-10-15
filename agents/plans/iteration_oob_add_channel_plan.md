# OOB Iteration — Manual Channel Intake Script — Delivery Plan

Status: **DRAFT — 2026-10-14**
Date: 2026-10-14
Author: Orchestrator

---

## 1. Executive Summary

Unblock curator intake of new channels **before** Admin System U2 lands. A
stopgap Python script resolves a YouTube **handle → `channel_id`** once at
intake (handles are mutable; IDs are not) and inserts a **minimal row** into
BigQuery `channel_dimensions`, which the next scheduled ETL run enriches via
the existing `MERGE`. The daily ETL's `id=`-based collection is unchanged.

Implementation: single Python script at `scripts/add_channel.py` (stopgap —
not under the future `admin/` service layout, so U1/U2 service design stays
clean) plus three reusable SQL templates under `sql/`. TDD per unit:
tester (red) → writer (green) → verifier (gate PASS/FAIL).

Deliverables:
0. U1 — Reusable SQL templates (dup check, minimal insert, reactivate) with
   `{{project}}.{{dataset}}` + BigQuery named parameters, executable from
   both R (`run_sql_file(..., params=)`) and Python (`query_params`).
1. U2 — `scripts/add_channel.py`: single-handle arg + `--file` batch CSV,
   `forHandle=` resolution, safe-default guards, per-row independent commit,
   `--dry-run`, pytest unit tests.

Explicitly out of scope: any change to `get_channel_ids.sql` (forbidden),
ETL/Shiny pipeline logic, backfills, new marts, audit store (lands in U4 —
script logs to stdout for backfill), CI wiring (lands in U0 — script is
written ruff-clean but adds no CI jobs).

**Key constraint(s) honored throughout:** `channel_id` is truth (BR-006),
no manual metadata (BR-008), next-ETL pickup with no trigger (BR-012),
admin-side code is never the data store (NFR-010), prod-gated confirms
(AGENTS.md Project Constraints).

---

## 2. Architecture-Gate Check (all units)

Reference: AGENTS.md Architecture Gate + `docs/architecture/comp_admin_system.puml`
+ UC-2.2 (`docs/use_cases/use_case_spec_admin.md:595-668`).

| Unit | Calls | Must NOT call | Verdict |
|---|---|---|---|
| U1 | `channel_dimensions` DDL contract only (new template files) | Any pipeline behavior change; `get_channel_ids.sql`; fact/mart tables | PASS |
| U2 | YouTube API `channels.list` (`forHandle=`/`id=` intake only), `channel_dimensions` (U1 templates only), `config.yml` read | Store handle as truth (BR-006); write metadata cols (BR-008); trigger ETL (BR-012); fact/mart writes; audit writes (no store yet) | PASS |

Medallion flow stays one-way: the script performs a single dimension-table
insert (UC-2.2 authorized write); all enrichment flows downstream through the
existing `merge_channel_dims.sql` → `append_daily_metrics.sql` path.

---

## 3. Units of Work (serialized)

### U1 — Reusable SQL templates

**Goal:** Dup-check, insert, and reactivate statements live in `sql/` (not
embedded in Python strings) so R and Python share them.

**Deliverables:**

- `sql/00_utils/check_channel_exists.sql` (read, beside `get_channel_ids.sql`):
  ```sql
  SELECT channel_id, channel_handle, is_active
  FROM `{{project}}.{{dataset}}.channel_dimensions`
  WHERE channel_id = @channel_id;
  ```
- `sql/01_raw/ops/insert_channel_dim.sql` (write, beside
  `merge_channel_dims.sql`) — minimal row, metadata cols untouched (`NULL`):
  ```sql
  INSERT INTO `{{project}}.{{dataset}}.channel_dimensions`
    (channel_id, channel_handle, is_active, status, type,
     added_by, created_at, updated_at)
  VALUES (@channel_id, @channel_handle, TRUE, @status, @type,
          @added_by, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
  ```
- `sql/01_raw/ops/reactivate_channel.sql` (write, `--reactivate` path only):
  ```sql
  UPDATE `{{project}}.{{dataset}}.channel_dimensions`
  SET is_active = TRUE, updated_at = CURRENT_TIMESTAMP()
  WHERE channel_id = @channel_id AND is_active = FALSE;
  ```

**Conventions:** `{{project}}.{{dataset}}` placeholders rendered by the
caller's `render_sql` port (assert no `{{` remains, cf.
`tests/testthat/test_sql_orchestration.R:29-30`); values passed only as
BigQuery **named query parameters** (never interpolated). `status`/`type`
params accept `NULL`.

**Test surface (tester writes first):**
- Each template renders cleanly for `project`/`dataset` fixtures with no
  residual placeholders.
- Named parameters are `@channel_id`, `@channel_handle`, `@status`,
  `@type`, `@added_by` exactly (contract test against the Python caller).

**Verification:** render tests green; `Rscript tests/testthat.R` green (no
pipeline change — new files only, never executed by ETL).

**Dependencies:** none. **Architecture gate:** PASS.

### U2 — `scripts/add_channel.py` + tests

**Goal:** Curator runs one command to add one channel or a batch file, safely
by default.

**CLI:**
```
python scripts/add_channel.py "@SomeHandle" [--status X --type Y --added-by Z]
python scripts/add_channel.py --file /tmp/channels.csv [--reactivate] [--dry-run]
# guards: --dataset OVERRIDE | --prod (requires --yes + DATASET/ETL_ENV confirm)
```
- Batch CSV columns: `handle[,status,type,added_by]` (`/tmp` — repo
  `.gitignore` ignores `*.csv`).
- Tolerant normalize: strip whitespace/leading `@`; strip
  `youtube.com/@`, `/c/`, `/channel/`, `/user/` prefixes; input matching
  `^UC[a-zA-Z0-9_-]{22}$` takes the `id=` verification path instead.

**Flow per handle (UC-2.2 main flow, script-sized):**
1. Normalize → resolve via YouTube Data API v3 (intake only):
   `GET .../youtube/v3/channels?part=id,snippet&forHandle=<handle>&key=$YT_API_KEY`
   ([docs](https://developers.google.com/youtube/v3/docs/channels/list):
   exactly one filter per request; `@` prefix optional; `part=id,snippet`
   minimizes quota to 1 unit/call). `items[0].id` = truth (BR-006);
   `items[0].snippet.customUrl` = canonical handle. Empty `items[]` → row
   failure (EF-1), continue batch. Quota vs other API errors distinguished
   (EF-2/EF-3).
2. Dup check via U1 `check_channel_exists.sql`: active → skip
   ("already tracked", AF-1); inactive → skip unless `--reactivate`, then U1
   `reactivate_channel.sql` (AF-2, history intact).
3. Insert via U1 `insert_channel_dim.sql`: `is_active=TRUE`,
   `added_by` default `SimonLiles:<script-basename>` (overridable
   `--added-by`; distinct from ETL's `'ETL_Process_API'`, preserved by later
   `MERGE`s), `status`/`type` default `NULL` (Shiny falls back to
   "Sailing"/"Sailing Vlog", `creator_explorer.R:172-182`; overridable
   `--status`/`--type`, or per-row CSV in batch mode).
4. Per-row independent commit + summary
   (added / already-active / reactivated / failed) — one bad row never rolls
   back siblings (BR-015 spirit). `--dry-run` resolves + prints rows, writes
   nothing. No ETL trigger; no audit write (store lands in U4) — stdout log
   carries actor/channel/timestamp for backfill.

**Config/auth (mirrors R):** `config.yml` (`project`, `dataset`) with env
overrides; GCP creds via `ETL_SERVICE_ACCOUNT_PATH` or
`GOOGLE_APPLICATION_CREDENTIALS`; `YT_API_KEY` required for resolution only.
Default dataset = dev; `--prod` requires explicit `--yes` confirm of
`DATASET`/`ETL_ENV` (prod-gated rule). Deps (documented, not vendored):
`google-cloud-bigquery google-auth pyyaml requests`. Ruff-clean code (U0
owns CI wiring — this unit adds no workflow changes).

**Touchpoints:**
- New: `scripts/add_channel.py`, `tests/python/test_add_channel.py`
  (pytest, mocked YouTube + BigQuery), U1 SQL files (from U1).
- Modified: none in `etl/`, `shiny/`, existing `sql/`.
- Forbidden: `sql/00_utils/get_channel_ids.sql` — do not touch.

**Test surface (tester writes first):**
- Normalization matrix (bare/`@`/URL/ID inputs).
- `forHandle=` vs `id=` branching; empty-`items` row failure; quota-error
  vs generic-error distinction.
- Dup active → abort; dup inactive → skip without flag, reactivate with flag.
- Insert param mapping incl. `None→NULL` for `status`/`type`, `added_by`
  default `SimonLiles:add_channel.py`.
- Batch partial success: failed row doesn't block siblings.
- Template contract: SQL files load, render, and expose the expected named
  params.

**Verification:** pytest green + `Rscript tests/testthat.R` green + ruff
clean on new Python files + `--dry-run` demo on 1–2 known handles against
dev.

**Dependencies:** U1 (templates). **Architecture gate:** PASS.

---

## 4. Dependency Order & Execution

```
U1 (reusable SQL) ─→ U2 (script + tests)
```

U1 first so the script caller is written against frozen template contracts.
TDD loop per unit: tester (red baseline) → writer (green) → verifier (gate
PASS/FAIL). Fail routing: code issue → writer; test issue → tester. Two
identical failed loops → stop and surface to user.

## 5. Verification Strategy

Per-unit gate:

| Unit | Command(s) |
|---|---|
| U1 | SQL render/contract tests green; `Rscript tests/testthat.R` green |
| U2 | pytest green (`tests/python/`) + `Rscript tests/testthat.R` green + ruff clean on new files + `--dry-run` against dev |

Final regression (once, after U2): full `Rscript tests/testthat.R` green;
pytest green; no `etl/`, `shiny/`, or existing `sql/` behavior changed;
`git status` shows only the 5 new files (3 SQL + script + test).

## 6. Decisions & Open Questions

### Resolved (user-confirmed 2026-10-14)

| # | Question | Decision |
|---|---|---|
| OOB-1 | Intake language | Python stopgap at `scripts/add_channel.py` (not `admin/`); R ETL untouched |
| OOB-2 | Input shape | Single handle positional + `--file` batch CSV; tolerant (`@`/URL/ID) |
| OOB-3 | Insert scope | Minimal row (IDs + quality fields); ETL `MERGE` enriches metadata (BR-008) |
| OOB-4 | Handle resolution | `channels.list?part=id,snippet&forHandle=` at intake only; ETL stays `id=`-based (handles mutable, IDs immutable) |
| OOB-5 | SQL reuse | Templates in `sql/` with `{{project}}.{{dataset}}` + named params, shared R/Python (this plan §3.U1) |
| OOB-6 | Quality-field defaults | `added_by` = `SimonLiles:<script>`; `status`/`type` = `NULL`; flags/CSV override |
| OOB-7 | Safety | Dup check (active=abort, inactive=`--reactivate`), dev-default dataset, `--prod`+`--yes` guard, `--dry-run` |
| OOB-8 | `get_channel_ids.sql` | Out of scope — do not touch |

### Open

- None — ready for review. On approval: build U1 → U2 under the TDD loop
  above; leave `agents/iteration_history.md` + U0/U2-traceability updates
  until the OOB ships.
