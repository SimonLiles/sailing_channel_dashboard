# Iteration 1 — Platform & CI/CD modernization — Delivery Plan

Status: **DRAFT — 2026-10-15**
Date: 2026-10-15
Author: Orchestrator

---

## 1. Executive Summary

Modernize the platform so all later work (I2 Auth/Users, I3 Channels,
I4 Instrumentation + Monitoring + Audit, I5 Trivy cleanup) lands on
tracked-as-code infrastructure with enforced gates. No pipeline behavior
change in this iteration.

Deliverables (from `agents/iteration_history.md`, Iteration 1):
1. U1 — Lint gates: lintr (R) + ruff (Python) configs and CI wiring
2. U2 — Terraform full-adopt of live GCP infra (data layer first)
3. U3 — Liquibase OSS adoption + SQL test strategy
4. U4 — Required PR checks + Trivy in advisory mode

Explicitly out of scope: ETL/Shiny logic changes, backfills, new analytical
marts, the Python admin service (I2), Shiny instrumentation (I4).

**Key constraint(s) honored throughout:** import-then-verify, never recreate
live infra; secret-needing jobs stay off PR runs; dataset discipline
(`DATASET`/`ETL_ENV` confirmed before anything touching BigQuery);
prod-gated applies never run unattended against the wrong dataset.

4 units, strictly serialized (U1 fast feedback → U2 infra safety →
U3 schema safety → U4 enforcement wiring).

---

## 2. Architecture-Gate Check (all units)

Reference: AGENTS.md Architecture Gate.

| Unit | Calls | Must NOT call | Verdict |
|---|---|---|---|
| U1 | R/Python sources (read-only lint), GHA workflows | Pipeline behavior changes | PASS |
| U2 | GCP APIs (read import, state backend), `*.tf` | Recreate/replace live resources; serving infra before data layer | PASS |
| U3 | Dev dataset (migrate + sandbox tests), `sql/` changelogs | Prod dataset writes; full-refresh rebuild semantics change | PASS |
| U4 | PR-triggered CI, built images (scan-only) | Live secrets on PR runs; blocking merges on Trivy (advisory until I5) | PASS |

---

## 3. Units of Work (serialized)

### U1 — Lint gates

**Goal:** Every later unit lands under lint enforcement from day one.

**Deliverables:** `.lintr.R` config (repo root); ruff config
(`pyproject.toml`, scoped to the upcoming `admin/` service); lintr + ruff
steps in CI; AGENTS.md Commands table updated with exact lint commands.

**Touchpoints:**
- New: `.lintr.R`, Python ruff config
- Modified: `.github/workflows/deploy.yml` (lint jobs), `AGENTS.md` Commands
- No changes to `etl/`, `shiny/`, `sql/` behavior
- Tests: CI itself is the test surface (see below)

**Test surface (tester writes first):**
- `lintr` is clean on all R sources; CI lint job goes red when a violation
  is introduced (demonstrated with a scratch violation, then removed)
- `ruff check` passes (no Python sources yet — validates config; first
  sources arrive under enforcement in I2)

**Verification:** lint commands green locally + CI workflow passes.

**Dependencies:** none. **Architecture gate:** PASS.

### U2 — Terraform full-adopt (data layer first)

**Goal:** Live GCP infra reproducible from git, with `plan` proving zero
drift — without touching serving traffic.

**Deliverables:** `terraform/` root (GCS backend, provider pinning);
resource-by-resource `import` of Cloud Run services/job, Scheduler,
BigQuery datasets/IAM (permission-mapper output as accelerator), GCS
buckets, Artifact Registry; CI `fmt`/`validate` on PRs, `plan`+`apply` on
main.

**Touchpoints:**
- New: `terraform/` (state backend, modules as needed)
- Modified: `.github/workflows/deploy.yml` (tf jobs)
- No changes to `etl/`, `shiny/`, `sql/`, `scripts/` behavior
- Tests: `terraform validate`, `plan` shows no unexpected diff on every
  import batch

**Test surface (tester writes first):**
- Each import batch ends with `plan` showing no diff (import-then-verify)
- Import order enforced: datasets/IAM → storage/registry → scheduling →
  serving (a serving-first plan fails review)
- A deliberately drifted sandbox value is detected by `plan` (red baseline)

**Verification:** clean `plan` on main + `apply` is a no-op after final import.

**Dependencies:** U1 (lint). **Architecture gate:** PASS.

### U3 — Liquibase OSS + SQL tests

**Goal:** Schema changes versioned, reviewable, and tested before merge.

**Deliverables:** Liquibase changelog baseline of the current schema
(`DATABASECHANGELOG` tracking); `liquibase update` in CI against the dev
dataset; sandbox-backed SQL tests in testthat; `sql/05_tests/` populated;
R runner keeps the idempotent full-refresh mart rebuilds.

**Touchpoints:**
- New: `changelog*/` (or `db/` — location decided at build), SQL tests
- Modified: `.github/workflows/deploy.yml` (migrate + SQL-test jobs),
  `tests/testthat/` additions
- Untouched semantics: mart rebuild behavior identical before/after
- Tests: migration up-to-baseline on empty dev copy; down/rollback path;
  query-result assertions on sandbox data

**Test surface (tester writes first):**
- Baseline changelog applied to an empty dataset reproduces prod schema
  (diff empty)
- A sample schema change migrates up and rolls back cleanly
- A mart query returns expected rows on fixture data (fails before fix)

**Verification:** `Rscript tests/testthat.R` green + Liquibase `update`
green on dev + prod schema untouched.

**Dependencies:** U1–U2 (lint, infra safety). **Architecture gate:** PASS.

### U4 — Required PR checks + Trivy advisory

**Goal:** Broken or vulnerable code is caught before merge, with Trivy
collecting (not blocking on) its baseline for I5.

**Deliverables:** `pull_request` trigger in `deploy.yml` with required
secret-free gates (testthat with live tests self-skipping, lintr, ruff,
`terraform fmt`/`validate`, Trivy fs + IaC-misconfig scans); Trivy image
scans on built ETL/Shiny images in advisory mode (SARIF to code scanning,
non-blocking); branch protection note (required checks) documented in the
plan/impl PR.

**Touchpoints:**
- Modified: `.github/workflows/deploy.yml` (PR jobs, secret scoping)
- No changes to `etl/`, `shiny/`, `sql/` behavior
- Tests: CI itself is the test surface (see below)

**Test surface (tester writes first):**
- A PR with a failing test / lint violation / tf misconfig goes red and
  blocks merge (demonstrated on a scratch PR or `act`/dry-run, then cleaned)
- A PR run proves no live secrets are present (job env audit)
- Trivy SARIF uploads and findings are visible while the check stays green
  (advisory)

**Verification:** required checks green on the U4 PR; advisory findings
triaged into the I5 backlog, not fixed here.

**Dependencies:** U1–U3 (everything it gates on). **Architecture gate:** PASS.

---

## 4. Dependency Order & Execution

```
U1 ─→ U2 ─→ U3 ─→ U4
```

U1 first for fast feedback on everything after; U2 before U3 so schema work
runs on adopted infra; U4 last because it gates on all prior tooling. TDD
loop per unit: tester (red baseline) → writer (green) → verifier (gate
PASS/FAIL). Fail routing: code issue → writer; test issue → tester. Two
identical failed loops → stop and surface to user.

## 5. Verification Strategy

Per-unit gate:

| Unit | Command(s) |
|---|---|
| U1 | lintr + ruff green locally; CI workflow passes |
| U2 | `terraform validate` + clean `plan`; `apply` no-op after final import |
| U3 | `Rscript tests/testthat.R` + Liquibase `update` green on dev |
| U4 | Required PR checks green; Trivy SARIF uploaded, advisory only |

Final regression (once, after last unit): full CI green on main;
`terraform plan` clean; prod schema and pipeline behavior unchanged;
Trivy baseline exported for I5.

## 6. Decisions & Open Questions

### Resolved (user-confirmed 2026-10-14/15)

| OQ | Question | Decision |
|---|---|---|
| OQ-0 | Kit scope | Scaffold in repo root; test gate `Rscript tests/testthat.R`; platform-first, 5 iterations |
| OQ-4 | Lint tooling | Confirmed: lintr (R) + ruff (Python); delivered as I1-U1 |
| OQ-5 | BQ migration tool | Liquibase OSS (free; BQ built in); delivered as I1-U3 |
| OQ-6b | Terraform scope | Full adopt, no rebuild; data-layer-first import; delivered as I1-U2 |
| OQ-7 | Trivy + PR gates | Trivy advisory-first (enforcing in I5); PR checks required, secret-free; delivered as I1-U4 |

### Open

| OQ | Question | Owner |
|---|---|---|
| OQ-6 | Split I4 (instrumentation vs views+audit)? Decide once event-taxonomy design lands | user |
