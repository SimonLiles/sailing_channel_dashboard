#!/usr/bin/env bash
# U1 red-baseline probe (Iteration 1, Unit U1) — runnable WITHOUT R.
# Encodes the RED state: lint gates are absent.
# Exit 0 = all gates present (green); exit 1 = any gate missing (red).
# The writer re-runs this after delivering .lintr.R + pyproject.toml +
# CI lint job + AGENTS.md commands. Verifier uses it for the
# scratch-violation red-flip demo (step 5 below).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
RED=0

check() { # $1 = label, $2.. = command to test (green when exit 0)
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "GREEN: $label"; else echo "RED:   $label"; RED=1; fi
}

echo "== U1 lint-gate red baseline =="
check ".lintr.R exists" test -f .lintr.R
check ".lintr.R declares linters" grep -q "linters" .lintr.R
check "pyproject.toml exists" test -f pyproject.toml
check "pyproject.toml has [tool.ruff]" grep -q "\[tool.ruff" pyproject.toml
check "pyproject.toml scopes admin/" grep -q "admin" pyproject.toml
check "deploy.yml has lint job" grep -q -E "^[[:space:]]*lint[[:space:]]*:" .github/workflows/deploy.yml
check "deploy.yml mentions lintr" grep -q "lintr" .github/workflows/deploy.yml
check "deploy.yml mentions ruff" grep -q "ruff" .github/workflows/deploy.yml
check "AGENTS.md has lintr:: command" grep -q "lintr::" AGENTS.md
check "AGENTS.md has ruff check command" grep -q "ruff check" AGENTS.md

echo "== tool availability (writer needs this) =="
command -v Rscript >/dev/null && Rscript --version 2>&1 || echo "Rscript NOT on default PATH (try /usr/local/bin/Rscript)"
/usr/local/bin/Rscript -e "cat(as.character(packageVersion('lintr')))" 2>&1 || echo "lintr R package MISSING"
/usr/local/bin/Rscript -e "cat(as.character(packageVersion('testthat')))" 2>&1 || echo "testthat R package status unknown (see above)"
command -v ruff >/dev/null && ruff --version || echo "ruff binary MISSING"

echo "== scratch-violation red-flip demo =="
echo 'u1_scratch_flipper=1' > /tmp/u1_scratch_violation.R
echo 'import os' > /tmp/u1_scratch_violation.py
if ! test -f .lintr.R && ! test -f pyproject.toml; then
  echo "RED-DEMO: no lint configs exist, so no gate can flag the scratch files (this is the red baseline)."
  echo "POST-WRITER-DEMO: re-run this script (expect GREEN above), then run:"
  echo "  /usr/local/bin/Rscript -e \"lintr::lint('/tmp/u1_scratch_violation.R')\"   # expect lints found"
  echo "  ruff check --config pyproject.toml --no-cache /tmp/u1_scratch_violation.py  # expect exit 1 (unused import)"
  echo "  rm /tmp/u1_scratch_violation.R /tmp/u1_scratch_violation.py                # remove scratch, gates return green"
else
  echo "Configs present; run the two commands above to demo the red flip, then remove the scratch files."
fi
rm -f /tmp/u1_scratch_violation.R /tmp/u1_scratch_violation.py

if [ "$RED" -eq 0 ]; then echo "RESULT: GREEN — all lint gates present."; else echo "RESULT: RED — lint gates missing (expected pre-writer)."; fi
exit "$RED"
