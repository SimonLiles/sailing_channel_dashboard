#!/bin/sh
# U2 terraform scaffold red-baseline probe (read-only, no creds, no live I/O).
# Runs `fmt -check` and `init -backend=false` + `validate` with the pinned
# binary. Never runs import/plan/apply (scaffold-only scope: the user runs
# live import elsewhere). Exits non-zero while terraform/ is absent (RED).
set -eu
TF_BIN="/Users/simon/.local/bin/terraform"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"

if [ ! -x "$TF_BIN" ]; then
  echo "RED U2: terraform binary missing at $TF_BIN (expected v1.16.6)."
  exit 1
fi
if [ ! -d "$TF_DIR" ]; then
  echo "RED U2: terraform/ scaffold missing at $TF_DIR."
  exit 1
fi

echo "== terraform fmt -check =="
"$TF_BIN" fmt -check -recursive "$TF_DIR"
echo "== terraform init -backend=false (provider download only, no auth) =="
"$TF_BIN" -chdir="$TF_DIR" init -backend=false -input=false
echo "== terraform validate =="
"$TF_BIN" -chdir="$TF_DIR" validate -no-color
echo "GREEN U2 baseline probe: fmt + init + validate all exited 0."
