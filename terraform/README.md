# Terraform full-adopt scaffold (Iteration 1, Unit U2 — SCAFFOLD ONLY)

This directory holds the Terraform scaffold for adopting the live GCP
infrastructure. It declares versions, the GCS backend, variables, and
data-layer-first `import` blocks only. No live `import`, `plan`, or `apply`
is ever run from this scaffold machine.

## Import-then-verify procedure

1. The user (with live-import authorization and `gcloud` credentials) copies
   this scaffold to a machine that may touch live infrastructure.
2. Fill each `TODO(import)` placeholder `id` in `main.tf` with the real live
   resource ID, then write the corresponding `resource` bodies at
   live-import time (never guessed here).
3. Run `terraform init` (with backend), then `terraform import` per block in
   batch order, then `terraform plan` (must show no unexpected changes) and
   `terraform validate`.
4. Verify with `terraform fmt -check` and `tests/terraform_baseline.sh`.

Live `import`/`plan`/`apply` runs elsewhere by the user, NOT from this
scaffold machine. This scaffold only ever runs credential-free checks:
`terraform fmt -check` and `terraform init -backend=false` + `terraform validate`.

## Batch order (data layer first, serving last)

- Batch 1 — BigQuery datasets + IAM FIRST.
- Batch 2 — GCS buckets + Artifact Registry.
- Batch 3 — Cloud Scheduler (scheduling).
- Batch 4 — Cloud Run services/job LAST.

Downstream never precedes upstream; serving resources import last.

## Backend and authentication

- Backend: `gcs` bucket `yt-sailing-dashboard-cache`, prefix `terraform/state`.
- Scaffold checks use `init -backend=false` (provider download only, no auth).
- The service-account key at `app/secrets/yt-sailing-dashboard-1a37e4c18a27.json`
  is referenced by path only and is never read or used by scaffold checks.

## Deletion guards

Before the live-import session, read the docs-only acceptance checklist in
`deletion_guards.md` (lifecycle `prevent_destroy`, `delete_contents_on_destroy`,
table `deletion_protection`, `plan -destroy` acceptance, import sign-off).
