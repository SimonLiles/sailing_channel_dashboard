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
| 1 | Platform & CI/CD modernization | Lint gates (lintr+ruff), Terraform full-adopt, Liquibase + SQL tests, required PR checks + Trivy advisory | Completed |
| 1B | Prod-dataset deletion protection + daily backups | Daily Parquet backup (ETL step 6), 60-day lifecycle, tf deletion-guard contract, IAM deny, restore runbook + rehearsal | Completed |
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

### Iteration 1 — Platform & CI/CD modernization (2026-10-16)

Built via tester → writer → verifier pipeline per unit (plan:
`agents/plans/iteration_1_plan.md`). Full gate: 138 passed / 1 failed
(pre-existing `test_config.R:12:3` dev-vs-prod dataset expectation,
untouched by I1). No pipeline behavior change; `etl/`, `shiny/`,
`sql/00-04`, `scripts/` untouched.

- U1 Lint gates: `.lintr.R` (defaults), `pyproject.toml` (ruff F-rules,
  scoped `admin/`), `lint:` CI job, AGENTS.md Commands row.
  Tests: `tests/testthat/test_lint_gates.R` (12) + `tests/lint_red_baseline.sh`.
- U2 Terraform scaffold-only (user decision — no live import from this
  machine): `terraform/` (`versions.tf` tf>=1.16 + google~>6.0,
  `backend.tf` GCS `yt-sailing-dashboard-cache`/`terraform/state`,
  8 `import` blocks BQ-first/Cloud-Run-last, README with
  import-then-verify), `terraform:` CI job (fmt/validate, secret-free),
  `.gitignore` covers `.terraform/`. Tests:
  `tests/testthat/test_terraform_adopt.R` (24) + `tests/terraform_baseline.sh`.
  Live `import`/`plan`/`apply` deferred to the user (key
  `app/secrets/…1a37e4c18a27.json` referenced by path only).
- U3 Liquibase + SQL tests: `db/changelog/db.changelog-master.xml`
  (4 changeSets, rollback each, dev-pinned, offline `validate` clean),
  `sql/05_tests/` (cohort 16 rows + rankings 5 rows, SQLite sandbox),
  `liquibase-dev` CI job (WIF, `DATASET=yt_sailing_data_dev`, prod path
  Liquibase-free). Tests: `tests/testthat/test_liquibase_sql.R` (12).
- U4 PR checks + Trivy advisory: `pull_request: [main]` trigger;
  6 creds jobs gated off PR (`if: github.event_name != 'pull_request'`);
  PR path secret-free (note: `YT_API_KEY` removed from CI entirely —
  live contract tests now self-skip on main too); `trivy-fs-config`
  (fs+config, SARIF, required) + `trivy-image` (ETL+Shiny, advisory,
  off-PR); `docs/required-checks.md` (advisory-until-I5 per OQ-7).
  Tests: `tests/testthat/test_pr_trivy_gates.R` (19).
- Deferred: live tf import (user), `test_config` dev-dataset fix,
  Trivy enforcing in I5, liquibase-bigquery CI coordinate confirmation.

### Iteration 1B — Deletion protection + daily backups (2026-10-16)

Built via tester → writer → verifier per unit (plan:
`agents/plans/iteration_1b_plan.md`). Full gate: 212 passed / 1 failed
(pre-existing `test_config.R:12:3`, untouched). Backup after marts,
60-day retention, inside daily ETL as step 6, 2 source tables only,
backup failure never fails ETL (~$0.02/mo steady state).

- U1: `scripts/backup_source_tables.R` (`backup_prefix()` UTC date,
  `EXPORT DATA … PARQUET` via `render_sql`/`run_sql_file`, caller's
  connection) + 9-line failure-isolated step-6 hook in `etl/main.R`.
  Tests: `test_backup_tables.R` (28). Mid-build conflict resolved:
  I1-U4 guard re-scoped to allowlist the hook (still rejects other
  `etl/|shiny/|sql/|scripts/` diffs — negative control proven).
- U2: `docs/backup-lifecycle.json` (single Delete rule, age 60,
  `backups/`). Tests: `test_backup_lifecycle.R` (7). Gitignore exception
  `!docs/backup-lifecycle.json` wired (secrets `*.json` guard intact).
- U3: `terraform/deletion_guards.md` (prevent_destroy,
  delete_contents_on_destroy=false, deletion_protection,
  `plan -destroy` zero-deletion acceptance, sign-off) + README pointer.
  Tests: `test_deletion_guards.R` (12). Applied at live import, not now.
- U4: `docs/prod-delete-deny.md` (scope, role-based principals,
  break-glass to owner, apply + safe negative-test + rollback; zero
  secret material). Tests: `test_prod_delete_deny.R` (11). User applies.
- U5: `docs/restore-runbook.md` (time-travel <7d, parquet-reload >7d,
  clone-rollback, exit criteria, DEV-ONLY guard, evidence placeholders).
  Tests: `test_restore_runbook.R` (15). Rehearsal user-executed.
- User-side checklist (open): apply lifecycle rule; apply IAM deny +
  negative test; guards at tf import (`plan -destroy` + sign-off); dev
  restore rehearsal; first-scheduled-backup check.

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

Security backlog triaged 2026-10-18 (from Trivy IaC scan of PR #22,
`terraform/main.tf`, 8 findings → 4 issues, grouped by rule):
- #23 GCP-0002 MED — uniform bucket-level access on both GCS buckets
  (cache bucket already UBA-enabled live = config drift; tf_state genuine).
- #24 GCP-0077 MED — bucket logging not configured (both buckets).
- #25 GCP-0078 MED — bucket versioning disabled (both buckets).
- #26 GCP-0066 LOW — no customer-managed encryption key (both buckets;
  needs Cloud KMS key + GCS SA grant).
Labels `security`, `iteration-5`, `severity:medium`, `severity:low`
created and applied.

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
