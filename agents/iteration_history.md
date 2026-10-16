# Iteration History & Delivery Plan — Sailing Channel Dashboard

<!--
  HOW TO USE THIS FILE
  - Delivery Plan table: one row per iteration, updated when an iteration is
    planned and again when its status changes.
  - "What Has Been Built": append a concrete deliverables list at the END of
    each completed iteration (files, classes, screens, test counts).
  - Planned Iterations: expand upcoming iterations here; detailed per-track /
    per-unit plans live in agents/plans/.
-->

## Iterative Delivery Plan

<!-- Status vocabulary: Not started | In progress | Completed -->

| It | Goal | Key Deliverables | Status |
|---|---|---|---|
| 1 | Platform & CI/CD modernization | Lint gates (lintr+ruff), Terraform full-adopt, Liquibase + SQL tests, required PR checks + Trivy advisory | Not started |
| 2 | Auth & user management (UC-1.x) | Python service: Google-OAuth sign-in, RBAC engine, provision/suspend/deprovision, roles, ownership transfer | Not started |
| 3 | Channel management (UC-2.x) | Inventory, add (handle→`channel_id`), deactivate/reactivate, bulk import | Not started |
| 4 | Instrumentation, monitoring & audit (UC-3.x + UC-4.1) | Event taxonomy + Shiny logging, health-signal APIs, admin monitoring views, audit log | Not started |
| 5 | Trivy cleanup (enforcing) | Baseline triaged, image findings remediated, Trivy gates flipped to blocking | Not started |

---

## What Has Been Built Per Iteration

### OOB — Creator Explorer cold-start fix (2026-10-16)

- Crash on newly added channels (`if (NA)` in the negative-average
  footnote) fixed via NA-safe helpers + graceful-partial UI.
- New: `shiny/utils/coldstart_helpers.R` (`safe_tail1`,
  `show_negative_note`, `coalesce_profile_field`, `format_count_safe`,
  `has_series`, `flows_pending`); 1-line `source()` in `shiny/global.R`.
- Modified: `shiny/pages/creator_explorer.R` only (empty-history branch,
  pending-notice banner, placeholder sparklines, `N/A` value boxes).
- Tests: `tests/testthat/test_coldstart_helpers.R` (48 tests green;
  full gate has one pre-existing unrelated failure:
  `test_config.R` prod-dataset expectation vs dev working config).
- Plan: `agents/plans/iteration_oob_creator_explorer_coldstart_plan.md`.
  Prod verification left to the user (no prod access granted).

### Iteration 1

<!-- Append at iteration end. -->

---

## Planned Iterations

<!-- Detailed scope for upcoming iterations goes here, newest first. Keep each
     planned iteration independently shippable (methodology.md, Phase 5). -->

### Iteration 5 — Trivy cleanup (enforcing)

- Triage the advisory-mode baseline accumulated since I1 (image + fs/IaC
  findings for ETL/Shiny images and Terraform).
- Remediate or formally accept each finding; upgrade/rebuild base images as
  needed.
- Flip Trivy gates from advisory to enforcing (build fails on policy;
  policy: HIGH+ or CRITICAL per baseline review).
- Exit criteria: `deploy.yml` green with enforcing gates; no open
  unaccepted findings.

### Iteration 4 — Instrumentation, monitoring & audit

- Event taxonomy doc + Shiny instrumentation (JS collector: visitor cookie,
  referrer/UTMs, screen; server enrichment: UA parse, MaxMind geo with raw
  IP dropped; bot + internal-traffic filtering).
- Query logging at the `run_*_query.R` choke point (query text, params,
  `channel_id`, latency).
- Health-signal APIs: ETL job status, data freshness, dashboard availability
  (observe-only, BR-019).
- Admin views UC-3.1–UC-3.6 + audit log UC-4.1 (BR-016, NFR-002).
- May split into I4a (instrumentation) / I4b (views + audit) once taxonomy
  design lands (OQ-6).

### Iteration 3 — Channel management

- UC-2.1–UC-2.7 on the Python service: inventory, add with handle→
  `channel_id` preview, deactivate/reactivate, bulk CSV/XLSX import with
  review and row-independent commit (BR-015).
- Every mutation appends an audit record (NFR-002); `channel_id` truth
  enforced (BR-006).

### Iteration 2 — Auth & user management

- UC-1.1–UC-1.8 on the Python service: Google-OAuth sign-in with no
  auto-provisioning (BR-005), RBAC engine + capability matrix (NFR-001),
  provision/suspend/deprovision, role assign/change, ownership transfer
  (BR-001/BR-003).

### Iteration 1 — Platform & CI/CD modernization

New Python service on Cloud Run (OQ-1); four-layer clean arch for app code,
Medallion for the data layer (OQ-3).

- U1 — Lint gates: lintr (R) + ruff (Python) configs, CI wiring, AGENTS.md
  Commands updated.
- U2 — Terraform full-adopt (data layer first): GCS-backed state,
  resource-by-resource import with `plan` showing no diff; `fmt`/`validate`
  on PRs, `plan`+`apply` on main.
- U3 — Liquibase OSS + SQL tests: baseline changelog of current schema,
  `migrate` in CI (dev), sandbox-backed SQL tests, `sql/05_tests/`
  populated. R runner keeps idempotent mart rebuilds.
- U4 — PR checks + Trivy advisory: `pull_request` trigger with required
  secret-free gates; Trivy fs + IaC-misconfig scans required, image scans
  advisory (SARIF, non-blocking) until I5.

Full unit plan: `agents/plans/iteration_1_plan.md`. Spec:
`docs/use_cases/use_case_spec_admin.md`. Component diagram:
`docs/architecture/comp_admin_system.puml`.
