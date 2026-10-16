# Iteration 5 — Trivy cleanup (enforcing) — Delivery Plan

Status: **DRAFT — 2026-10-15**
Date: 2026-10-15
Author: Orchestrator

---

## Scope (from `agents/iteration_history.md`)

- Triage the advisory-mode baseline accumulated since I1 (image + fs/IaC
  findings for ETL/Shiny images and Terraform).
- Remediate or formally accept each finding; upgrade/rebuild base images as
  needed.
- Flip Trivy gates from advisory to enforcing (build fails on policy;
  severity threshold confirmed against the baseline at build time).
- Exit criteria: `deploy.yml` green with enforcing gates; no open
  unaccepted findings.

Detailed units to be drafted before build starts (per kit cadence).
Prerequisite: Iteration 4 green (all images/containers final).
