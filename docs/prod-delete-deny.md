# Prod Dataset Deletion Deny — `yt_sailing_data`

<!-- Purpose: procedure doc for a human-applied IAM deny that blocks deletion of the prod dataset. The writer never touches IAM; the user applies this. -->

## 1. Purpose

Protect the production BigQuery dataset against accidental or malicious
deletion with an explicit IAM deny. This doc is the procedure only — no IAM
change is made by this repo. A human operator applies the deny in the
Google Cloud console or via `gcloud`.

Related invariants: BR-001 (exactly one Owner; break-glass stays with the
human owner), NFR-010 (admin system is never the analytical data store).

## 2. Deny scope

| Field | Value |
|-------|-------|
| Project | `yt-sailing-dashboard` |
| Prod dataset | `yt_sailing_data` |
| Denied permission | `bigquery.datasets.delete` |
| Effect | `deny` — deletion of the prod dataset is blocked for the principals below |

This is a deny rule (not an allow grant): even if a principal holds an IAM
role that would otherwise permit dataset deletion, this deny wins and the
delete call is rejected.

## 3. Denied principals (role-based, no member IDs)

The deny applies to routine automation identities only. Principals are
described by ROLE — this doc contains no member emails or IDs:

- The ETL runtime service account (the identity the scheduled ETL job runs as).
- The CI deploy identity (the identity the deploy pipeline uses to ship the
  dashboard and run migrations).

Break-glass reservation: the human owner is EXCLUDED from this deny. Only
the owner holds break-glass authority to delete or restore the prod dataset
in a true emergency.

BR-001 note: exactly one Owner exists at all times. The deny must never
cover the owner, and nothing in this procedure deletes, suspends, or demotes
the owner.

## 4. Apply procedure (human operator only)

The writer of this doc never touches IAM. A human with Owner rights on
project `yt-sailing-dashboard` applies the deny.

### 4a. Console path

1. Open the Google Cloud console for project `yt-sailing-dashboard`.
2. Go to IAM & Admin > IAM Deny Policies.
3. Create a deny policy attached to the prod dataset `yt_sailing_data`.
4. Set the denied permission to `bigquery.datasets.delete`.
5. Add the two routine principals by role (ETL runtime service account and
   CI deploy identity) as the denied principals.
6. Confirm the human owner (break-glass) is NOT in the denied set.
7. Save and verify the policy lists `deny` on `bigquery.datasets.delete`
   for `yt_sailing_data`.

### 4b. gcloud sketch (placeholders only — substitute real members at apply time)

```bash
# PLACEHOLDERS ONLY: replace each <...> with the real member string in your
# own shell. Do not paste real member IDs into this doc.
gcloud iam deny-policies create <POLICY_ID> \
  --project=yt-sailing-dashboard \
  --attachment-point=bigquery.googleapis.com/projects/yt-sailing-dashboard/datasets/yt_sailing_data \
  --denied-principals=<ETL_RUNTIME_PRINCIPAL> \
  --denied-principals=<CI_DEPLOY_PRINCIPAL> \
  --denied-permissions=bigquery.datasets.delete \
  --denial-condition-title="Block prod dataset deletion" \
  --denial-condition-expression="true"
```

Notes:

- `<ETL_RUNTIME_PRINCIPAL>` = the ETL runtime service account member string.
- `<CI_DEPLOY_PRINCIPAL>` = the CI deploy identity member string.
- The owner break-glass principal is deliberately omitted from
  `--denied-principals`.

## 5. SAFE negative-test procedure (non-destructive)

Goal: prove the deny works WITHOUT deleting or risking anything. This is a
negative test: the attempt must fail with `permission-denied`.

Steps (all safe, read/metadata only — never destructive):

1. Authenticate as (or impersonate with dry-run rights) the ETL runtime
   service account — or simply inspect the effective policy as that identity.
2. Attempt a NEGATIVE probe that requires `bigquery.datasets.delete` without
   deleting anything, e.g. a dry-run permission check
   (`testIamPermissions` for `bigquery.datasets.delete` on `yt_sailing_data`)
   or an intentionally blocked delete issued with `--dry-run` semantics where
   supported.
3. Expected result: the call is rejected with `permission denied`
   (`permission-denied`, HTTP 403). That rejection IS the passing result of
   this negative test.
4. Confirm in the audit log that the denied attempt was traced, with no
   dataset modification.

WARNING: never attempt a real dataset delete to "test" this policy. Do not
attempt deletion against the prod dataset `yt_sailing_data` under any
circumstances — the negative permission check above is the only approved
test. This procedure is strictly non-destructive by design.

## 6. Rollback note

If the deny must be lifted (emergency restore performed by the owner):

- Only the human owner (break-glass) lifts the deny.
- Delete or disable the deny policy created in section 4, then re-verify
  dataset access behaves as before.
- Every lift and re-apply is traceable in the audit log per NFR-002.
