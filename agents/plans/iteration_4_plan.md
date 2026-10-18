# Iteration 4 — Instrumentation, monitoring & audit — Delivery Plan

Status: **DRAFT — 2026-10-15**
Date: 2026-10-15
Author: Orchestrator

---

## Scope (from `agents/iteration_history.md`)

- Event taxonomy doc + Shiny instrumentation: JS collector (visitor cookie,
  referrer/UTMs, screen) + server enrichment (UA parse, MaxMind geo with raw
  IP dropped; bot + internal-traffic filtering). First-party BQ event table.
- Query logging at the `run_*_query.R` choke point (query text, params,
  `channel_id`, latency).
- Health-signal APIs: ETL job status, data freshness, dashboard availability
  (observe-only, BR-019).
- Admin views UC-3.1–UC-3.6 + audit log UC-4.1 (BR-016, NFR-002). No PII
  (BR-018).

May split into I4a (instrumentation) / I4b (views + audit) once taxonomy
design lands (OQ-6). Detailed units to be drafted before build starts (per
kit cadence). Prerequisite: Iteration 3 green.

## Open Questions

| OQ | Question | Owner |
|---|---|---|
| OQ-6 | Split I4 into I4a (instrumentation) vs I4b (views + audit)? Decide once event-taxonomy design lands (moved from I1 plan 2026-10-16 — it concerns I4 scope, not platform work) | user |
