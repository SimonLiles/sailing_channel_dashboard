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
| 1 | Admin System build (auth, channels, monitoring, audit) | U1 auth/authz + user mgmt (UC-1.x), U2 channel mgmt (UC-2.x), U3 monitoring (UC-3.x), U4 audit log (UC-4.1) | Not started |

---

## What Has Been Built Per Iteration

### Iteration 1

<!-- Append at iteration end. -->

---

## Planned Iterations

<!-- Detailed scope for upcoming iterations goes here, newest first. Keep each
     planned iteration independently shippable (methodology.md, Phase 5). -->

### Iteration 1 — Admin System build

New Python service on Cloud Run (OQ-1 resolved 2026-10-14); four-layer clean
arch for app code, Medallion for the data layer (OQ-3).

- U0 — CI/CD setup: lintr (R) + ruff (Python) configs, lint jobs in
  `deploy.yml`, AGENTS.md Commands updated. No pipeline behavior change.

- U1 — Authentication & user management (UC-1.1–UC-1.8): Google-OAuth
  sign-in, RBAC authorization, provision/suspend/deprovision, role
  assign/change, ownership transfer. Python service.
- U2 — Channel management (UC-2.1–UC-2.7): inventory, add (handle →
  `channel_id` resolution), deactivate/reactivate, bulk CSV/XLSX import with
  row-independent commit.
- U3 — Monitoring (UC-3.1–UC-3.6): admin home, usage analytics, ETL health,
  data freshness, dashboard health, channel interest (observe-only, BR-019).
- U4 — Audit log (UC-4.1): append-only immutable view, filterable by
  actor/action (BR-016, NFR-002).

Full unit plan: `agents/plans/iteration_1_plan.md`. Spec:
`docs/use_cases/use_case_spec_admin.md`. Component diagram:
`docs/architecture/comp_admin_system.puml`.
