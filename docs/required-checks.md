# Required PR checks (Iteration 1, Unit U4)

Every pull request against `main` runs these required checks secret-free
(no `secrets.*`, no WIF `google-github-actions/auth`):

- `lint` — lintr for R sources, ruff for Python `admin/`
- `terraform` — `fmt -check` + `init -backend=false` + `validate`, no creds
- `test` — testthat suite; live YouTube contract tests self-skip without a key
- `trivy-fs-config` — Trivy filesystem + IaC misconfig scans, SARIF upload

Creds-needing jobs never run on PRs; each carries
`if: github.event_name != 'pull_request'`:

- `build-etl`, `build-shiny` (WIF auth, build + push images)
- `migrate` (prod `DATASET=yt_sailing_data` migration via the ETL job)
- `liquibase-dev` (dev `DATASET=yt_sailing_data_dev` update only, never prod)
- `deploy` (Cloud Run deploys after migration)
- `trivy-image` (Trivy scans of the built ETL + Shiny images, SARIF upload)

## Trivy: Advisory until I5

Trivy findings are visible via SARIF/code scanning, but no Trivy step sets a
blocking gate — Trivy is Advisory until I5, enforcing in I5 per OQ-7. The
checks stay green while findings are triaged.
