# Design Decisions & Open Questions — Sailing Channel Dashboard

<!--
  HOW TO USE THIS FILE
  - Active Design Decisions: constraints affecting current/future implementation.
    Group by theme; the categories below are universal starters — add, rename,
    or remove them as the project demands.
  - Open Questions: unresolved only. When a question is answered, move it to
    Resolved Questions with the decision (and date) — never delete history.
  - Record decisions here at the moment they are made (see methodology.md,
    "Resolving disagreement").
-->

## Active Design Decisions

These are constraints that affect current and future implementation.

### Architecture & Layering

- Application code (Shiny dashboard, Python admin panel) follows four-layer
  clean architecture: `presentation/` → `application/` only; `application/` →
  `domain/` + `infrastructure/`; `domain/` has zero framework dependencies
  (OQ-3, 2026-10-14)
- Data layer (ETL/`sql/`) follows the one-way Medallion flow:
  `YouTube API → 01_raw → 02_staging → 03_marts → 04_apps → GCS cache/Shiny`
  (authoritative: `docs/component_diagram.puml`, README §Architecture &
  Data Lineage)
- `shiny/` reads BigQuery + GCS cache; never writes BigQuery
- Admin System V1 is a new Python service on Cloud Run (OQ-1, 2026-10-14);
  R/Shiny stays the read-only dashboard and hosts no admin-panel logic
- Admin V1 invariants per `docs/architecture/comp_admin_system.puml`:
  exactly one Owner (BR-001), `channel_id` is truth (BR-006), audit immutable
  (BR-016), RBAC enforced (NFR-001), every mutation traced (NFR-002), health
  observes only (BR-019), admin is never the data store (NFR-010)
- Usage instrumentation uses a first-party BigQuery event table (locked
  2026-10-15): behavioral + query/channel-interest events enriched at ingest
  with visitor/session IDs, geo (MaxMind, raw IP dropped), device/UA parse,
  and session-first-touch acquisition; no PII (BR-018). GA4 optional later.

### Domain Conventions

- `channel_id` is the canonical channel identity; handles resolve to it via
  the YouTube API and are never stored as truth
- `is_active` on `channel_dimensions` gates channel inclusion in the product

### Testing

- Canonical gate: `Rscript tests/testthat.R` (CI test job on push to `main`)
- Live-contract tests (`test_get_yt_data`) skip without `YT_API_KEY`
- Lint gate adopted (OQ-2, 2026-10-14): lintr (R) + ruff (Python), enforced
  via CI from I1-U1 onward (OQ-4 resolved 2026-10-14)
- SQL tests (I1): sandbox-backed runs (dev dataset) + render/parse tests;
  results under `tests/testthat/` + `sql/05_tests/`

### Delivery Model

- Five iterations, platform-first: I1 Platform & CI/CD modernization →
  I2 Auth/Users → I3 Channels → I4 Instrumentation + Monitoring + Audit →
  I5 Trivy cleanup (enforcing)
- Each iteration stays independently shippable (see methodology.md, Phase 5);
  I4 may split (instrumentation vs views+audit) once taxonomy design lands

### CI/CD

- GitHub Actions `deploy.yml` on push to `main`: test → build ETL/Shiny
  images → migrate + backfill prod → deploy Cloud Run
- PR checks (required gates): testthat, lintr, ruff, `terraform fmt` /
  `validate`, Trivy fs + IaC-misconfig scans; secret-needing jobs stay on
  push-to-main / environment gates
- Trivy image scans run advisory (SARIF, non-blocking) from I1 until I5
  triages the baseline and flips them to enforcing
- Terraform: full adopt, no rebuild; GCS-backed state; `plan` in CI +
  `apply` on main; import order data-layer-first (datasets/IAM via
  permission-mapper output) before serving infra
- BigQuery migrations via Liquibase OSS (free Community tier; BQ support
  built in): versioned changelogs + `DATABASECHANGELOG` tracking; R runner
  keeps the idempotent full-refresh mart rebuilds
- `YT_API_KEY` is injected for the test job only, never passed to docker build

## Open Questions

- OQ-6 (2026-10-15): Split I4 (instrumentation vs views+audit)? Decide once
  the event-taxonomy design lands. Owner: user.

## Resolved Questions

| Question | Resolution |
|---|---|
| Kit target + project identity (2026-10-14) | Scaffold in repo root; PROJECT_NAME "Sailing Channel Dashboard", slug `sailing_channel_dashboard` |
| Gate commands (2026-10-14) | Test `Rscript tests/testthat.R` discovered from `tests/testthat.R` + CI; lint/codegen/import-check marked not configured |
| Active iteration (2026-10-14) | Iteration 1 — Admin System build, per `docs/` admin spec (superseded: platform-first map, 2026-10-15) |
| OQ-1 Admin V1 language (2026-10-14) | Python on Cloud Run, per the admin spec; R/Shiny will not host admin-panel logic |
| OQ-2 Lint gate (2026-10-14) | Adopted; tooling + CI wiring tracked in OQ-4 |
| OQ-3 Layer model (2026-10-14) | Keep four-layer clean arch for Shiny dashboard + admin panel; Medallion for ETL/data layer; Riverpod-DI section dropped |
| OQ-4 Lint tooling (2026-10-14) | Confirmed: lintr (R) + ruff (Python); delivered as I1-U1 |
| OQ-5 BQ migration tool (2026-10-15) | Liquibase OSS (free; BQ built in). Flyway rejected (Community 10GB cap, paid rollback); dbt deferred; goose/sqitch lack native BQ |
| OQ-6a Event sink (2026-10-15) | First-party BQ event table; GA4 optional later. Exact query text, joins to marts, ad-block-proof completeness |
| OQ-6b Terraform scope (2026-10-15) | Full adopt, no rebuild; data-layer-first import order |
| OQ-7 Trivy + PR gates (2026-10-15) | Trivy advisory-first, enforcing in I5; PR checks required (secret-free gates only) |
| OQ-8 Iteration map (2026-10-15) | Platform-first, 5 iterations with I5 = Trivy cleanup (enforcing) |
