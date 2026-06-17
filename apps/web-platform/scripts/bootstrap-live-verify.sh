#!/usr/bin/env bash
# One-shot bootstrap for the live-verification synthetic prod principal
# (#5452, AC12). Runs ONCE by the agent LOCALLY — NEVER wired into CI (keeps
# the prod service-role + Terraform apply out of GitHub Actions; security P0-1).
#
# Negative AC (enforced by review):
#   grep -rl "bootstrap-live-verify\|seed-live-verify" .github/workflows/ → zero
#
# Usage:
#   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/bootstrap-live-verify.sh
#
# Steps (idempotent — safe to re-run; also the leak-rotation path):
#   1. terraform apply -target the two new resources in apps/web-platform/infra
#      (random_password.live_verify_user → doppler_secret LIVE_VERIFY_USER_PASSWORD).
#   2. Run the seed under a FRESH `doppler run -c prd` so it picks up the
#      password Terraform just published to Doppler prd (the launching env was
#      captured before the secret existed).
#
# The seed echoes LIVE_VERIFY_EXPECTED_UID / LIVE_VERIFY_EXPECTED_REF — set those
# in Doppler prd afterwards so the harness allowlist code-gate (run.ts) binds.

set -euo pipefail

if [[ "${DOPPLER_CONFIG:-}" != "prd" ]]; then
  echo "::error::DOPPLER_CONFIG=\"${DOPPLER_CONFIG:-<unset>}\" — run via:" >&2
  echo "::error::  doppler run -p soleur -c prd -- bash $0" >&2
  exit 1
fi

command -v terraform >/dev/null 2>&1 || { echo "::error::terraform not on PATH" >&2; exit 1; }
command -v doppler   >/dev/null 2>&1 || { echo "::error::doppler not on PATH" >&2; exit 1; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
INFRA="$REPO_ROOT/apps/web-platform/infra"
SEED="$REPO_ROOT/apps/web-platform/scripts/seed-live-verify-user.sh"

[[ -f "$INFRA/live-verify.tf" ]] || { echo "::error::$INFRA/live-verify.tf not found" >&2; exit 1; }
[[ -f "$SEED" ]] || { echo "::error::$SEED not found" >&2; exit 1; }

echo "==> Step 1: terraform apply (-target the two live-verify resources)"
terraform -chdir="$INFRA" init -input=false >/dev/null
terraform -chdir="$INFRA" apply -input=false -auto-approve \
  -target=random_password.live_verify_user \
  -target=doppler_secret.live_verify_user_password

echo "==> Step 2: seed the synthetic prod principal (fresh doppler run picks up the new secret)"
doppler run -p soleur -c prd -- bash "$SEED"

echo ""
echo "::notice::Bootstrap complete. Now set the harness allowlist vars in Doppler prd"
echo "::notice::from the LIVE_VERIFY_EXPECTED_UID / LIVE_VERIFY_EXPECTED_REF lines above:"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_UID=<uid> -p soleur -c prd"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_REF=<ref> -p soleur -c prd"
