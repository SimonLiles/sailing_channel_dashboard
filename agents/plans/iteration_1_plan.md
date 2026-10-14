# Iteration 1 — Admin System build — Delivery Plan

Status: **DRAFT — 2026-10-14**
Date: 2026-10-14
Author: Orchestrator

---

## 1. Executive Summary

Build the secure admin control plane specified in
`docs/Sailing Channel Dashboard — Administration System.md` and
`docs/use_cases/use_case_spec_admin.md` (23 use cases, 4 domains), without
altering the existing pipeline's data flow (Medallion flow stays one-way;
admin is never the analytical data store, NFR-010).

Implementation: new Python service on Cloud Run (OQ-1 resolved 2026-10-14 —
R/Shiny hosts no admin-panel logic). Application code follows four-layer
clean architecture; the data layer stays Medallion (OQ-3 resolved
2026-10-14).

Deliverables (from `agents/iteration_history.md`, Iteration 1):
0. U0 — CI/CD setup: lintr (R) + ruff (Python) configs and CI lint jobs
1. U1 — Authentication & user management (UC-1.1–UC-1.8)
2. U2 — Channel management (UC-2.1–UC-2.7)
3. U3 — Monitoring, observe-only (UC-3.1–UC-3.6)
4. U4 — Audit log view (UC-4.1)

Explicitly out of scope: changes to ETL/Shiny pipeline logic, backfills, and
any new analytical marts.

**Key constraint(s) honored throughout:** exactly one Owner (BR-001),
`channel_id` is truth (BR-006), audit immutable (BR-016), RBAC enforced
(NFR-001), every mutation traced (NFR-002), ETL failures never deactivate
channels (BR-013), health observes only (BR-019).

5 units, strictly serialized (U0 CI groundwork → U1 RBAC foundation → U2/U3
→ U4 audit closes the traceability loop).

---

## 2. Architecture-Gate Check (all units)

Reference: AGENTS.md Architecture Gate + `docs/architecture/comp_admin_system.puml`.

| Unit | Calls | Must NOT call | Verdict |
|---|---|---|---|
| U0 | GHA workflows, lint configs | Pipeline code behavior changes; prod datasets | PASS |
| U1 | Google IdP (verify), CloudSQL admin accounts, audit append | Auto-provision unknown identities (BR-005); analytical BigQuery writes; R/Shiny admin logic | PASS |
| U2 | YouTube API (handle→channel_id), `channel_dimensions`, audit append | Store handle as truth (BR-006); deactivate on ETL failure (BR-013) | PASS |
| U3 | ETL metadata, GA aggregates, Cloud Run health endpoints | Any control action on pipeline/dashboard (BR-019); PII (BR-018) | PASS |
| U4 | CloudSQL audit records (read) | Audit writes/updates/deletes (BR-016) | PASS |

---

## 3. Units of Work (serialized)

### U0 — CI/CD setup: lint gates

**Goal:** Every later unit lands in a repo where R and Python lint is
enforced by CI.

**Deliverables:** `.lintr.R` config (repo root); ruff config
(`pyproject.toml`, scoped to the upcoming `admin/` service); lintr + ruff
steps in CI (`deploy.yml`, ahead of the test job); AGENTS.md Commands table
updated with the exact lint commands.

**Touchpoints:**
- New: `.lintr.R`, Python ruff config
- Modified: `.github/workflows/deploy.yml` (lint jobs), `AGENTS.md` Commands
- No changes to `etl/`, `shiny/`, `sql/` behavior
- Tests: CI itself is the test surface (see below)

**Test surface (tester writes first):**
- `lintr` is clean on all R sources; CI lint job goes red when a violation
  is introduced (demonstrated with a scratch violation, then removed)
- `ruff check` passes (no Python sources yet — validates config; first
  sources arrive under enforcement in U1)

**Verification:** lint commands green locally + CI workflow passes on the
U0 branch/PR.

**Dependencies:** none. **Architecture gate:** PASS.

### U1 — Auth, authorization & user management

**Goal:** Only known Google identities get in, and every capability is
RBAC-gated with owner protection.

**Deliverables:** Sign-in (UC-1.1), authorization engine + capability matrix
(UC-1.2), provision/suspend/deprovision (UC-1.3–UC-1.5), role assign/change
(UC-1.6–UC-1.7), ownership transfer (UC-1.8).

**Touchpoints:**
- New: Python admin service on Cloud Run (auth + user management, four-layer
  layout: presentation/application/domain/infrastructure)
- Modified: none in `etl/`, `shiny/`, `sql/` (pipeline untouched)
- Tests: auth + RBAC matrix tests (pytest for Python service; testthat suite
  stays green)

**Test surface (tester writes first):**
- Unknown Google identity is denied (BR-005); no account created
- Owner cannot be deleted, suspended, or demoted (BR-001/BR-003)
- Capability matrix §2.1 enforced for every role (NFR-001)

**Verification:** `Rscript tests/testthat.R` green + Python service tests
green + U0 lint gates green + spec-traceability review.

**Dependencies:** U0 (lint enforcement). **Architecture gate:** PASS.

### U2 — Channel management

**Goal:** Curators maintain the tracked inventory with `channel_id` as truth.

**Deliverables:** Inventory view (UC-2.1), add with handle→`channel_id`
preview (UC-2.2), deactivate/reactivate (UC-2.3–UC-2.4), bulk CSV/XLSX
import with review (UC-2.5–UC-2.7).

**Touchpoints:**
- Reads/writes `channel_dimensions` (`is_active`, metadata) only
- Never touches fact/mart tables or the ETL schedule
- Tests: resolution, validation, row-independent commit, partial success

**Test surface (tester writes first):**
- Handle resolves to `channel_id` via YouTube API before write (BR-006)
- Failed row does not roll back sibling rows (BR-015)
- Every mutation appends an audit record (NFR-002)

**Verification:** `Rscript tests/testthat.R` green + Python service tests
green + U0 lint gates green + spec-traceability review.

**Dependencies:** U0–U1 (lint, RBAC). **Architecture gate:** PASS.

### U3 — Monitoring (observe-only)

**Goal:** Operational overview with zero control over pipeline or dashboard.

**Deliverables:** Admin home (UC-3.1), usage analytics (UC-3.2), ETL health
(UC-3.3), data freshness (UC-3.4), dashboard health (UC-3.5), channel
interest (UC-3.6).

**Touchpoints:**
- Reads: ETL metadata, aggregated analytics, BigQuery marts (read-only)
- No writes to pipeline state, schedules, or deployments
- Tests: read-only assertions, no-PII aggregation checks

**Test surface (tester writes first):**
- Health views issue no mutations (BR-019)
- Usage aggregates contain no PII (BR-018)

**Verification:** `Rscript tests/testthat.R` green + Python service tests
green + U0 lint gates green + spec-traceability review.

**Dependencies:** U0–U1 (lint, RBAC; Analyst role is read-only). **Architecture gate:** PASS.

### U4 — Audit log

**Goal:** Every admin mutation is traceable in an immutable log.

**Deliverables:** Audit log view with actor/action filters (UC-4.1).

**Touchpoints:**
- Reads CloudSQL audit records; UI is append-only view (no edit/delete)
- Backfills coverage for U1–U3 mutations if any gap is found
- Tests: immutability (no update/delete path), filter correctness

**Test surface (tester writes first):**
- No code path updates or deletes audit records (BR-016)
- Each U1–U3 mutation has a corresponding record (NFR-002)

**Verification:** `Rscript tests/testthat.R` green + full spec-traceability review.

**Dependencies:** U0–U3. **Architecture gate:** PASS.

---

## 4. Dependency Order & Execution

```
U0 ─→ U1 ─→ U2 ─→ U3 ─→ U4
```

U0 first so all later code lands under lint enforcement. U1 lays the RBAC
foundation everything else gates on; U4 closes the loop by verifying U1–U3
traceability. TDD loop per unit: tester (red baseline) → writer (green) →
verifier (gate PASS/FAIL). Fail routing: code issue → writer; test issue →
tester. Two identical failed loops → stop and surface to user.

## 5. Verification Strategy

Per-unit gate:

| Unit | Command(s) |
|---|---|
| U0 | lintr + ruff green locally; CI workflow passes |
| U1–U4 | `Rscript tests/testthat.R` + Python service tests + U0 lint gates + use-case traceability review vs `docs/use_cases/use_case_spec_admin.md` |

Final regression (once, after last unit): `Rscript tests/testthat.R` full
suite green; Python service tests green; lint gates green; no `etl/`,
`shiny/`, `sql/` pipeline behavior changed; all 23 use cases traced to
delivered behavior.

## 6. Decisions & Open Questions

### Resolved (user-confirmed 2026-10-14)

| OQ | Question | Decision |
|---|---|---|
| OQ-0 | Kit scope | Scaffold in repo root; test gate `Rscript tests/testthat.R`; Iteration 1 = Admin System build |
| OQ-1 | Admin V1 language/platform | Python service on Cloud Run; R/Shiny hosts no admin-panel logic |
| OQ-2 | Lint gate | Adopted; tooling + CI wiring tracked in OQ-4 |
| OQ-3 | Layer model | Four-layer clean arch for Shiny dashboard + admin panel; Medallion for ETL/data layer |
| OQ-4 | Lint tooling | Confirmed: lintr (R) + ruff (Python); delivered as U0 (CI/CD setup) in Iteration 1 |

### Open

None — U0 is approved for build.
