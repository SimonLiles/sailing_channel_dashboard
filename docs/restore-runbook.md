# Restore Runbook — Source Tables (DEV rehearsal)

> Rehearsal is DEV ONLY — never run rehearsal writes against prod.
> All rehearsal writes target `yt_sailing_data_dev`. Prod (`yt_sailing_data`)
> is read-only during rehearsal (row-count comparison source only).
> Rehearsal is USER-executed: follow the steps below on DEV and paste the
> evidence into the appendix placeholders.

Scope: `channel_dimensions` and `daily_metrics_history` in project
`yt-sailing-dashboard`. Sources of truth for backups and guards:

- Parquet backups: `gs://yt-sailing-dashboard-cache/backups/YYYY-MM-DD/{channel_dimensions,daily_metrics_history}/*.parquet` (prefix via `backup_prefix()` in `scripts/backup_source_tables.R`).
- Lifecycle: `docs/backup-lifecycle.json` (60d retention on the backups prefix).
- Deletion guards: `terraform/deletion_guards.md`; prod deny: `docs/prod-delete-deny.md`.
- Marts re-derive: `scripts/backfill_marts.R --start_date=YYYY-MM-DD --end_date=YYYY-MM-DD`.
- Pre-migration clone: `yt_sailing_data_pre_migration` (created by the deploy.yml migrate job).

## Path A — <7d: time-travel restore (BigQuery time travel)

Use when the corruption/deletion is within the 7-day time-travel window.

1. Identify the restore timestamp `TS` (e.g. `2026-10-10 12:00:00+00`) just
   before the bad write, via audit log / job history.
2. On DEV (`yt_sailing_data_dev`), recreate from the snapshot with
   `FOR SYSTEM_TIME` and copy into place, per table:

```bash
# Sketch — replace TS and PROJECT as needed; dataset names are fixed.
bq query --project_id=yt-sailing-dashboard --use_legacy_sql=false "
  CREATE OR REPLACE TABLE \`yt-sailing-dashboard.yt_sailing_data_dev.channel_dimensions\`
  AS SELECT * FROM \`yt-sailing-dashboard.yt_sailing_data_dev.channel_dimensions\`
  FOR SYSTEM_TIME AS OF TIMESTAMP '${TS}';
"
bq query --project_id=yt-sailing-dashboard --use_legacy_sql=false "
  CREATE OR REPLACE TABLE \`yt-sailing-dashboard.yt_sailing_data_dev.daily_metrics_history\`
  AS SELECT * FROM \`yt-sailing-dashboard.yt_sailing_data_dev.daily_metrics_history\`
  FOR SYSTEM_TIME AS OF TIMESTAMP '${TS}';
"
```

Alternative with snapshot decorators (milliseconds since epoch, `SNAP_MS`):

```bash
# Sketch — dataset recreate + copy via snapshot decorator.
bq cp 'yt-sailing-dashboard:yt_sailing_data_dev.channel_dimensions@<SNAP_MS>' \
  'yt-sailing-dashboard:yt_sailing_data_dev.channel_dimensions_restored'
bq cp 'yt-sailing-dashboard:yt_sailing_data_dev.daily_metrics_history@<SNAP_MS>' \
  'yt-sailing-dashboard:yt_sailing_data_dev.daily_metrics_history_restored'
```

3. Validate row counts on DEV, then swap/rename the restored tables into
   place (DEV only) and re-derive marts (see step 4 of Path B).

Time travel notes: Time Travel / time-travel queries with `FOR SYSTEM_TIME`
only reach back 7 days; beyond that use Path B (parquet-reload).

## Path B — >7d: parquet-reload from GCS backups (DEV rehearsal)

Use when time travel has expired (>7d) or the dataset was dropped.

1. Pick the latest good backup date `DATE=YYYY-MM-DD` under
   `backups/<DATE>/` in bucket `yt-sailing-dashboard-cache`:

```bash
gsutil ls gs://yt-sailing-dashboard-cache/backups/ | sort | tail -5
DATE=YYYY-MM-DD  # latest verified good date, e.g. 2026-10-15
gsutil ls "gs://yt-sailing-dashboard-cache/backups/${DATE}/channel_dimensions/"
gsutil ls "gs://yt-sailing-dashboard-cache/backups/${DATE}/daily_metrics_history/"
```

2. Reload both tables into DEV with `bq load` (parquet, replace):

```bash
# Sketch — identities vary by DATE; bucket/dataset/table names are fixed.
bq load --project_id=yt-sailing-dashboard --source_format=PARQUET \
  --replace 'yt-sailing-dashboard:yt_sailing_data_dev.channel_dimensions' \
  "gs://yt-sailing-dashboard-cache/backups/${DATE}/channel_dimensions/*.parquet"
bq load --project_id=yt-sailing-dashboard --source_format=PARQUET \
  --replace 'yt-sailing-dashboard:yt_sailing_data_dev.daily_metrics_history' \
  "gs://yt-sailing-dashboard-cache/backups/${DATE}/daily_metrics_history/*.parquet"
```

(`LOAD DATA` from external parquet URIs is an equivalent alternative; `bq load`
above is the rehearsed default.)

3. Re-derive marts on DEV with `backfill_marts.R`:

```bash
# Sketch — set the window to the backup date range; flags are fixed.
Rscript scripts/backfill_marts.R --start_date=${DATE} --end_date=${DATE}
# Confirm DATASET/ETL_ENV point at yt_sailing_data_dev before running.
```

4. Row-count diff DEV vs prod (prod read-only):

```bash
# Sketch — row count comparison; prod is the expected-truth reference.
bq query --project_id=yt-sailing-dashboard --use_legacy_sql=false "
  SELECT 'channel_dimensions' AS t,
    (SELECT COUNT(*) FROM \`yt-sailing-dashboard.yt_sailing_data_dev.channel_dimensions\`) AS dev_n,
    (SELECT COUNT(*) FROM \`yt-sailing-dashboard.yt_sailing_data.channel_dimensions\`) AS prod_n;
"
bq query --project_id=yt-sailing-dashboard --use_legacy_sql=false "
  SELECT 'daily_metrics_history' AS t,
    (SELECT COUNT(*) FROM \`yt-sailing-dashboard.yt_sailing_data_dev.daily_metrics_history\`) AS dev_n,
    (SELECT COUNT(*) FROM \`yt-sailing-dashboard.yt_sailing_data.daily_metrics_history\`) AS prod_n;
"
```

5. Promote: only after exit criteria pass on DEV does an authorized operator
   repeat the load against prod via the normal migrate/backfill flow with
   `DATASET`/`ETL_ENV` confirmed; rehearsal itself never writes prod.

## Path C — clone-rollback (pre-migration clone)

Use when a migration/backfill corrupted the tables and a pre-migration
clone exists (`yt_sailing_data_pre_migration` dataset, clone of prod taken by
the deploy.yml migrate job).

```bash
# Sketch — clone-rollback rehearsed on DEV; replace CLONE_TS as needed.
bq cp 'yt-sailing-dashboard:yt_sailing_data_pre_migration.channel_dimensions' \
  'yt-sailing-dashboard:yt_sailing_data_dev.channel_dimensions'
bq cp 'yt-sailing-dashboard:yt_sailing_data_pre_migration.daily_metrics_history' \
  'yt-sailing-dashboard:yt_sailing_data_dev.daily_metrics_history'
Rscript scripts/backfill_marts.R --start_date=${DATE} --end_date=${DATE}
```

The pre-migration / pre_migration clone is dropped only after the new
migration is verified; never rely on it past its documented lifetime.

## Rehearsal exit criteria (acceptance)

Rehearsal passes when ALL hold on DEV (`yt_sailing_data_dev`):

1. Row-count check: dev row count for `channel_dimensions` and for
   `daily_metrics_history` matches prod within the rehearsal-day delta
   (diff explained by the backup `DATE` vs today; attach both counts).
2. `backfill_marts.R` completes on DEV with no errors for the rehearsal
   window; marts row counts are non-zero and consistent with the reloaded
   source tables.
3. Dev dashboard renders against the restored DEV dataset (spot-check
   leaderboard/cohort pages, no query errors).
4. Timings recorded: time-travel copy time, `bq load` time per table,
   backfill wall-clock time. Paste all timings into REHEARSAL-RESULTS.

## Appendix — evidence placeholders (USER fills during rehearsal)

- `REHEARSAL-RESULTS`: paste rehearsal date, chosen path (A/B/C), backup
  DATE or restore TS, dev-vs-prod row counts, backfill log tail, dashboard
  spot-check, and per-step timings here.
- `LIFECYCLE-APPLIED`: paste `docs/backup-lifecycle.json` rule verification
  (60d) output here.
- `DENY-APPLIED`: paste `docs/prod-delete-deny.md` / deletion-guard check
  output here.
