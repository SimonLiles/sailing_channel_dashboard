# AGENTS.md — Sailing Channel Dashboard

<!--
  HOW TO USE THIS FILE
  - Rules and gates belong here; narratives belong in docs/ or agents/.
  - Keep entries terse: an agent re-reads this file at the start of every
    session.
-->

## Architecture Gate

Before touching data-layer or admin-system code, read the authoritative
diagrams. Existing pipeline: `docs/component_diagram.puml` (repo components)
plus README §Architecture & Data Lineage (Medallion flow). Admin System
(Iteration 1): `docs/architecture/comp_admin_system.puml` plus
`docs/use_cases/use_case_spec_admin.md`. Violations of the invariants below
are architecture errors.

Hard invariants (from `comp_admin_system.puml` legend + admin spec):

- BR-001: exactly one Owner exists at all times; the Owner cannot be deleted,
  suspended, or demoted.
- BR-006: `channel_id` is truth for channel identity (handles resolve to it
  via the YouTube API; never stored as truth).
- BR-016: audit records are immutable and append-only. NFR-002: every
  mutation is traceable in the audit log.
- BR-005: no auto-provisioning — unknown Google identities are denied.
  NFR-001: RBAC enforced on every admin capability (capability matrix in
  `docs/use_cases/use_case_spec_admin.md` §2.1).
- BR-003: owner protection on user management. BR-013: ETL failures never
  deactivate channels.
- BR-019: health monitoring observes only — it never controls the pipeline or
  dashboard. NFR-010: the admin system is never the analytical data store.
- Medallion flow is one-way:
  `YouTube API → 01_raw → 02_staging → 03_marts → 04_apps → GCS cache/Shiny`.
  Never skip layers; downstream never writes upstream.

## Commands

| Action | Command |
|--------|---------|
| Test (CI gate) | `Rscript tests/testthat.R` |
| Shiny, local (needs GCP creds) | `R -e "shiny::runApp('shiny')"` from repo root |
| ETL, local (needs GCP creds + `YT_API_KEY`) | `Rscript etl/main.R` from repo root |
| Schema migrate (**prod-gated**: confirm `DATASET`/`ETL_ENV` first) | `Rscript scripts/migrate_schema.R` |
| Backfill marts (**prod-gated**) | `Rscript scripts/backfill_marts.R --start_date=YYYY-MM-DD --end_date=YYYY-MM-DD` |
| Deploy | CI on push to `main` (test → build → migrate → deploy); manual `./deploy.sh` is legacy |
| Lint (adopted OQ-2; tooling TBD) | Proposed: lintr (R), ruff (Python admin) — configure, then gate |
| Codegen / Import-check | Not configured — no generators, no import verifier |

## Layer Rules

Four-layer clean architecture for application code (Shiny dashboard, Python
admin panel — OQ-3); Medallion one-way flow for the data layer (ETL/`sql/`):

- Application: `presentation/` depends on `application/` only;
  `application/` depends on `domain/` + `infrastructure/`; `domain/` has zero
  framework dependencies; `infrastructure/` depends on `domain/` or external
  SDKs.
- Data: `sql/00_utils -> 01_raw -> 02_staging -> 03_marts -> 04_apps`
  (one-way; downstream never writes upstream).
- `scripts/*.R` helpers are `source()`d by `etl/main.R` and `shiny/global.R` —
  never run standalone against prod except via the Cloud Run Job.
- `shiny/` reads BigQuery (parameterized queries) + GCS RDS cache; never
  writes BigQuery.
- Admin V1 (Python, Cloud Run) must never become the analytical data store
  (NFR-010).

## Config & Secrets

- `config.yml` is canonical (`project`, `dataset`, `window_days`, `gcs_*`);
  env vars override file values via `config_get()` in `scripts/config.R`.
- Secrets live in `app/secrets/*.json` plus `YT_API_KEY` /
  `ETL_SERVICE_ACCOUNT_PATH` env vars — gitignored (`*.json`, `secrets/`,
  `.Renviron`). Never commit keys; never bake them into images (CI injects
  `YT_API_KEY` for tests only).
- Dataset discipline: `config.yml` points at the dev dataset; prod is
  `yt_sailing_data`. Confirm `DATASET`/`ETL_ENV` before any migrate/backfill.

## Code Generation

None configured — SQL is hand-written per medallion layer under `sql/`, R has
no generators. Nothing to rerun.

## Testing

- Canonical gate: `Rscript tests/testthat.R` (also the CI test job on push to
  `main`; exits non-zero on failure).
- Existing suite in `tests/testthat/`: `test_config`, `test_get_yt_data`
  (live-contract, skipped without `YT_API_KEY`), `test_run_sql`,
  `test_sql_orchestration`.
- New SQL logic gets coverage under `tests/testthat/` + `sql/05_tests/`.
- Lint gate adopted (OQ-2); wire tooling (proposed lintr/ruff) into the
  Commands table once configured.

## Project Constraints

- Package slug `sailing_channel_dashboard`; app title `Sailing Channel Dashboard`
- All comments use format from `class_comment_specification.md`
- Admin V1 is Python on Cloud Run (spec + OQ-1); R/Shiny stays the read-only
  dashboard — R/Shiny will not host admin-panel logic
- `channel_id` is the canonical channel identity (BR-006)
- Exactly one Owner; owner protection enforced (BR-001/BR-003);
  no auto-provisioning of admin accounts (BR-005)
- Audit log append-only and immutable; every mutation traced (BR-016/NFR-002)
- ETL failures never deactivate channels (BR-013)
- Confirm `DATASET`/`ETL_ENV` before migrate/backfill — never run prod-gated
  scripts unattended against the wrong dataset

## Domain Model

- Channel — curated YouTube channel; `channel_dimensions` row keyed by
  `channel_id`; `is_active` gates inclusion; metadata comes from ingestion,
  never manual entry
- DailyMetrics — per-channel per-day fact (`daily_metrics_history` →
  `fct_daily_performance` with lags/velocities)
- ChannelCohort — subscriber-bucket assignment (`mart_channel_cohorts`)
- ChannelRanking — leaderboard position derived from marts
  (`mart_channel_rankings`)
- AdminAccount (Iteration 1, planned) — Google-identity-linked admin with an
  RBAC role; exactly one Owner
- AuditRecord (Iteration 1, planned) — immutable append-only trace of every
  admin mutation
- BulkImport (Iteration 1, planned) — CSV/XLSX batch with row-level
  independent commit; partial success OK

## Current Iteration

**Iteration 1**: Platform & CI/CD modernization

Terraform full-adopt of live GCP infra (data layer first), Liquibase OSS for
BigQuery versioning, lintr + ruff gates, SQL test strategy, required PR
checks with Trivy in advisory mode — no pipeline behavior change. Sets the
foundation for I2 Auth/Users, I3 Channels, I4 Instrumentation + Monitoring
+ Audit, I5 Trivy cleanup (enforcing).

Full plan: `agents/plans/iteration_1_plan.md`

## Reference Archives

- `agents/methodology.md` — design process, UML conventions, design patterns, working agreements
- `agents/decisions.md` — design decisions log, open questions
- `agents/iteration_history.md` — per-iteration build history and delivery plan
