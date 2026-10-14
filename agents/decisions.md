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

### Domain Conventions

- `channel_id` is the canonical channel identity; handles resolve to it via
  the YouTube API and are never stored as truth
- `is_active` on `channel_dimensions` gates channel inclusion in the product

### Testing

- Canonical gate: `Rscript tests/testthat.R` (CI test job on push to `main`)
- Live-contract tests (`test_get_yt_data`) skip without `YT_API_KEY`
- Lint gate adopted (OQ-2, 2026-10-14): lintr (R) + ruff (Python), enforced
  via CI from U0 onward (OQ-4 resolved 2026-10-14)

### Delivery Model

- Work is sliced per admin-spec domain (auth, channels, monitoring, audit);
  each planned iteration stays independently shippable (see methodology.md,
  Phase 5)
- Iteration 1 opens with U0 (CI/CD + lint setup) so all later units land
  under enforcement

### CI/CD

- GitHub Actions `deploy.yml` on push to `main`: test → build ETL/Shiny
  images → migrate + backfill prod → deploy Cloud Run
- U0 adds lint jobs (lintr, ruff) ahead of the test job
- `YT_API_KEY` is injected for the test job only, never passed to docker build

## Open Questions

- None currently.

## Resolved Questions

| Question | Resolution |
|---|---|
| Kit target + project identity (2026-10-14) | Scaffold in repo root; PROJECT_NAME "Sailing Channel Dashboard", slug `sailing_channel_dashboard` |
| Gate commands (2026-10-14) | Test `Rscript tests/testthat.R` discovered from `tests/testthat.R` + CI; lint/codegen/import-check marked not configured |
| Active iteration (2026-10-14) | Iteration 1 — Admin System build, per `docs/` admin spec |
| OQ-1 Admin V1 language (2026-10-14) | Python on Cloud Run, per the admin spec; R/Shiny will not host admin-panel logic |
| OQ-2 Lint gate (2026-10-14) | Adopted; tooling + CI wiring tracked in OQ-4 |
| OQ-3 Layer model (2026-10-14) | Keep four-layer clean arch for Shiny dashboard + admin panel; Medallion for ETL/data layer; Riverpod-DI section dropped |
| OQ-4 Lint tooling (2026-10-14) | Confirmed: lintr (R) + ruff (Python); delivered as U0 (CI/CD setup) in Iteration 1 |
