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
# Steps (idempotent — safe to re-run; also the leak-rotation path). The two
# steps run under DIFFERENT Doppler configs:
#   1. terraform apply -target the two new resources in apps/web-platform/infra
#      (random_password.live_verify_user → doppler_secret LIVE_VERIFY_USER_PASSWORD),
#      under `-c prd_terraform` (the infra root reads its TF_VAR_* + doppler_token_tf
#      from prd_terraform, NOT prd) with `--name-transformer tf-var`, plus BARE
#      AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY exported (outside the transformer)
#      for the Cloudflare-R2 S3 backend. Mirrors apply-web-platform-infra.yml.
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

# The infra root authenticates via the prd_terraform config (NOT prd): it reads
# doppler_token_tf + betterstack/github-app TF vars (~12 TF_VAR_* inputs). Under
# -c prd the apply fails immediately with "No value for required variable". So
# Step 1 runs under prd_terraform; Step 2 (the seed) stays under prd.
#
# The Cloudflare-R2 S3 backend reads its creds during `terraform init`, BEFORE any
# provider/variable evaluates — and it wants RAW AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY. The `--name-transformer tf-var` wrapper below rewrites
# every prd_terraform secret to TF_VAR_* (so the backend would see TF_VAR_aws_*,
# ignore it, and SSO-fallback-fail). Export the bare AWS_* OUTSIDE the wrapper so
# they survive into the child env unrenamed. Mirrors apply-web-platform-infra.yml's
# "Extract backend credentials" step + variables.tf:1-13.
AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform)
AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "::error::R2 backend creds empty in Doppler prd_terraform (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)" >&2
  exit 1
fi

# -lockfile=readonly for parity with apply-web-platform-infra.yml: refuses to
# download a provider whose checksum is not already in .terraform.lock.hcl
# (defends against a malicious republish of a pinned provider version).
terraform -chdir="$INFRA" init -input=false -lockfile=readonly >/dev/null

# prd_terraform carries the ~12 TF_VAR_* inputs; --name-transformer tf-var renames
# them so terraform sees TF_VAR_*. The bare AWS_* exported above survive into this
# child env for the R2 backend.
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
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
