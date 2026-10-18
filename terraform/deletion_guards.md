# Terraform deletion-guard checklist (Iteration 1B, Unit U3 — DOCS ONLY)

This checklist is docs-only. It is applied by the user at the future
live-import session when the `resource` bodies are written. No `.tf`
changes are made by this unit.

## Guards (required on both dataset resources)

- `google_bigquery_dataset.dev_dataset` MUST declare a `lifecycle` block
  with `prevent_destroy = true`.
- `google_bigquery_dataset.prod_dataset` MUST declare a `lifecycle` block
  with `prevent_destroy = true`.
- Both dataset resources MUST set `delete_contents_on_destroy = false`
  explicitly (never `true`).
- Table resources MUST keep `deletion_protection = true`.

Example (applied at import, not in this scaffold):

```hcl
lifecycle {
  prevent_destroy = true
}
```

## Acceptance

At the live-import session, `terraform plan -destroy` on the imported
state proposes zero deletions on the datasets, and the apply hard-fails
on the dataset resources while the `prevent_destroy` lifecycle guard is
present (proposes zero deletions / hard-fails on the dataset).

## Import-session sign-off

Sign-off: date __________ signature __________
