# Iteration 1B — Prod-dataset deletion protection + daily backups — Delivery Plan

Status: **DELIVERED — 2026-10-16 (all 5 units tester→writer→verifier PASS; full gate 212 passed / 1 known pre-existing fail `test_config.R:12:3`; user-side actions pending)**
Parent: Iteration 1 (Platform & CI/CD modernization, DELIVERED 2026-10-16)
Author: Orchestrator

---

## 1. Executive Summary

Close the catastrophic-loss profile identified after I1: the 8 months of
daily history in `daily_metrics_history` are irreplaceable (the YouTube
API serves no historical stats), so a deleted prod dataset older than the
~7-day time-travel window is gone forever. Five layered protections:

1. U1 — Daily Parquet backup of the 2 source tables (ETL step 6)
2. U2 — 60-day GCS lifecycle rule on `backups/*`
3. U3 — Terraform deletion-guard contract (applied at live import)
4. U4 — IAM deny on prod dataset deletion (user-side, documented here)
5. U5 — Restore runbook + dev rehearsal

Decisions locked with user 2026-10-16: backup runs **after** mart
rebuilds (single writer step — only `etl/main.R` writes these tables, so
post-ETL state is the consistent state); **60-day** retention; backup
**inside the daily ETL** (same job/schedule/SA, zero new infra).
Steady-state cost ≈ $0.02/mo (60 × ~15 MB in Standard).

Explicitly out of scope: derived-layer backups (marts re-derive via
`backfill_marts.R`), Trivy enforcing (I5), live Terraform import itself.

**Key constraints honored throughout:** no pipeline behavior change
except the additive backup step; backup failure never fails the ETL
(BR-013 spirit — a missing backup beats a failed pipeline; next day
heals the gap, worst case < 24h loss); dataset discipline
(`DATASET`/`ETL_ENV` confirmed before anything touching BigQuery);
prod never written from the scaffold machine (rehearsal runs on dev,
by the user).

5 units; U1 first (defines the backup format everything else references),
U2–U4 independent after U1, U5 last (needs U1 format + U4 context).

---

## 2. Architecture-Gate Check (all units)

Reference: AGENTS.md Architecture Gate.

| Unit | Calls | Must NOT call | Verdict |
|---|---|---|---|
| U1 | BQ read (`EXPORT DATA` query jobs via `run_sql_file`), GCS write (`backups/` prefix, same bucket/SA as cache) | BQ writes; ETL failure on backup error; new infra/auth | PASS |
| U2 | GCS lifecycle JSON (committed doc) + one user-side bucket update | Any data-layer change | PASS |
| U3 | `terraform/` docs only (guard contract for import session) | Resource bodies; live state | PASS |
| U4 | Docs only (IAM deny procedure, user applies) | Any repo behavior change | PASS |
| U5 | Dev dataset (user-run rehearsal), `docs/` runbook | Prod dataset writes | PASS |

---

## 3. Units of Work

### U1 — Daily Parquet backup (ETL step 6)

**Goal:** Every post-ETL state of the 2 source tables lands in GCS daily.

**Deliverables:** `scripts/backup_source_tables.R` (renders + executes 2
`EXPORT DATA OPTIONS(format='PARQUET')` statements with
`{{project}}`/`{{dataset}}`/date-prefix substitution via the existing
`render_sql`/`run_sql_file` path); hook as step 6 in `etl/main.R` after
the GCS cache write, wrapped so backup failure logs but never fails the
job; prefix `backups/YYYY-MM-DD/<table>/*.parquet` in the existing
cache bucket (`gcs_bucket` + fixed `backups/` prefix — never the
`cache-*` prefixes Shiny reads).

**Touchpoints:**
- New: `scripts/backup_source_tables.R` (+ optional `sql/00_utils/export_*.sql` if the writer prefers file-based SQL over inline)
- Modified: `etl/main.R` (additive step-6 call only)
- Untouched: mart semantics, cache format, `config.yml`, Shiny
- Tests: `tests/testthat/test_backup_tables.R` (render/date-prefix/failure-isolation assertions, credential-free)

**Test surface (tester writes first):**
- EXPORT SQL renders with correct project/dataset/date-prefix (no `{{…}}` leftovers)
- Date prefix is UTC `YYYY-MM-DD` and both tables share it
- Backup step is failure-isolated (ETL continues on export error — assert the guard construct)
- Backup prefix never collides with Shiny `cache-*` prefixes

**Verification:** targeted tests green + full gate green (only known
`test_config` failure); live proof deferred to first scheduled run
(user checks `backups/<date>/` + row-count match).

**Dependencies:** none (first). **Architecture gate:** PASS.

### U2 — 60-day lifecycle rule

**Goal:** Backups self-prune; steady state ≈ 1 GB, no manual cleanup.

**Deliverables:** `docs/backup-lifecycle.json` (committed lifecycle
spec: prefix `backups/`, age 60 → Delete) + application procedure in
the U5 runbook appendix; user applies once via console/`gcloud`
(`gcloud storage buckets update gs://yt-sailing-dashboard-cache
--lifecycle-file=docs/backup-lifecycle.json`).

**Touchpoints:** New doc file only. No code, no CI.

**Test surface:** test asserts the JSON exists, parses, targets
`backups/` with a 60-day delete action (static, credential-free).

**Verification:** static test green + user confirms applied (paste
`lifecycle` get output into the rehearsal report).

**Dependencies:** U1 (references its prefix). **Architecture gate:** PASS.

### U3 — Terraform deletion-guard contract

**Goal:** The future live-import session cannot leave prod deletable.

**Deliverables:** `terraform/deletion_guards.md` checklist (applied at
import time, not now): `lifecycle { prevent_destroy = true }` +
explicit `delete_contents_on_destroy = false` on both dataset resources;
keep table `deletion_protection = true`; acceptance proof defined as
`terraform plan -destroy` proposing zero deletions / hard-failing on
the dataset. `terraform/README.md` extended with a pointer.

**Touchpoints:** New doc + README pointer. No `.tf` changes (no
resource bodies exist yet by design).

**Test surface:** doc exists with the three guard keywords +
`plan -destroy` acceptance criterion (static assertions).

**Verification:** static test green; real proof happens at the user's
import session (checklist sign-off).

**Dependencies:** U1 (ordering only). **Architecture gate:** PASS.

### U4 — IAM deny on prod dataset deletion

**Goal:** Deletion fails at the IAM layer for routine identities, even
bypassing Terraform.

**Deliverables:** `docs/prod-delete-deny.md` with the exact deny policy
(`bigquery.datasets.delete` on prod `yt_sailing_data`, denied for the
ETL + deploy SAs, break-glass stays with the user's human identity)
plus a safe negative-test procedure (attempt-as-SA → expect
permission-denied; attempt nothing destructive). User applies via
console/`gcloud`; tester/writer never touch IAM.

**Touchpoints:** New doc only.

**Test surface:** doc exists with deny scope (dataset + permission +
principals) + negative-test procedure (static assertions).

**Verification:** static test green + user confirms applied and
negative-tested (result pasted into rehearsal report).

**Dependencies:** U1 (ordering only). **Architecture gate:** PASS.

### U5 — Restore runbook + dev rehearsal

**Goal:** "We can recover in under an hour" — proven, not assumed.

**Deliverables:** `docs/restore-runbook.md`: (a) < 7d path (time-travel
restore commands), (b) > 7d path (latest `backups/<date>/` →
`bq load` both tables → `backfill_marts.R` on **dev** → row-count diff
vs prod → promote procedure), (c) clone-rollback steps, (d) appendix
with U2/U4 application evidence. Rehearsal is **user-executed**
(prod-adjacent by nature): exit criteria — dev row counts for both
tables match prod within the rehearsal day's delta, dev dashboard
renders from rebuilt marts, timings recorded.

**Touchpoints:** New doc only (+ rehearsal report pasted into it by
the user).

**Test surface:** runbook exists covering all three paths + exit
criteria + appendix placeholders (static assertions).

**Verification:** static test green; runbook COMPLETE only after the
user pastes rehearsal results (tracked as the post-build follow-up).

**Dependencies:** U1–U4 (needs backup format + guard/IAM context).
**Architecture gate:** PASS.

---

## 4. Dependency Order & Execution

```
U1 ─→ ┌→ U2 ─→ ┐
      ├→ U3 ─→ ├→ U5
      └→ U4 ─→ ┘
```

U1 first (backup format is referenced by U2/U5). U2–U4 independent,
parallelizable (docs-only, distinct files). U5 last. TDD loop per unit:
tester (red) → writer (green) → verifier (gate). Fail routing:
code → writer; test → tester. Two identical failed loops → stop, surface.

## 5. Verification Strategy

| Unit | Gate |
|---|---|
| U1 | Targeted tests green; full `Rscript tests/testthat.R` green (only known `test_config` failure); `etl/main.R` diff is additive-only |
| U2–U4 | Static doc/config tests green; full suite regression-free |
| U5 | Static test green now; runbook COMPLETE after user rehearsal |
| Final | Full CI green on main (modulo known failure); first scheduled backup verified by user (objects + row counts) |

## 6. User-side action checklist (not built by pipeline)

- [ ] Apply GCS lifecycle rule (U2 procedure)
- [ ] Apply IAM deny + negative test (U4 procedure)
- [ ] Apply deletion guards at Terraform live import (U3 checklist sign-off)
- [ ] Run dev restore rehearsal, paste results into runbook (U5 exit criteria)
- [ ] Verify first scheduled `backups/<date>/` + row-count match

## 7. Decisions & Open Questions

### Resolved (user-confirmed 2026-10-16)

| Item | Decision |
|---|---|
| Timing | Backup AFTER mart rebuilds (single writer; post-ETL = consistent state) |
| Retention | 60 days, lifecycle auto-delete (~$0.02/mo steady state) |
| Placement | Inside daily ETL as step 6 (same job/schedule/SA, zero new infra) |
| Scope | 2 source tables only (`channel_dimensions`, `daily_metrics_history`); marts re-derive |
| Failure semantics | Backup failure logs, never fails ETL (BR-013 spirit) |

### Open

None — all trade-offs closed before planning.
