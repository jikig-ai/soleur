#!/usr/bin/env bash
# One-shot bootstrap for the live-verification synthetic prod principal
# (#5452, AC12). Runs ONCE by the agent LOCALLY — NEVER wired into CI (keeps
# the prod service-role + Terraform apply out of GitHub Actions; security P0-1).
#
# Negative AC (enforced by review):
#   grep -rl "bootstrap-live-verify" .github/workflows/ → zero
# (seed-live-verify-user.sh IS legitimately wired into web-platform-release.yml
# for principal refresh — only this script's terraform-apply half must never
# reach CI)
#
# Usage:
#   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/bootstrap-live-verify.sh
#
# Steps (idempotent — safe to re-run; also the leak-rotation path). The two
# steps run under DIFFERENT Doppler configs:
#   1. terraform apply -target the two new resources in apps/web-platform/infra
#      (random_password.live_verify_user → doppler_secret LIVE_VERIFY_USER_PASSWORD),
#      under the canonical nested loader — outer `-p soleur-infra-privileged -c
#      prd` (Tier-B TF_STATE_AWS_* + doppler_token_tf) wrapping inner `-c
#      prd_terraform --preserve-env` (~12 TF_VAR_* inputs) — plus BARE
#      AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY exported from the same Tier-B
#      pair for the Cloudflare-R2 S3 backend. Mirrors apply-web-platform-infra.yml
#      (its infra-credentials action aliases TF_STATE_AWS_* onto AWS_*).
#   2. Run the seed under a FRESH `doppler run -c prd` so it picks up the
#      password Terraform just published to Doppler prd (the launching env was
#      captured before the secret existed).
#
# The seed echoes LIVE_VERIFY_EXPECTED_UID / LIVE_VERIFY_EXPECTED_REF — set those
# in Doppler prd afterwards so the harness allowlist code-gate (run.ts) binds.

set -euo pipefail

# Refuse to run under xtrace: -x prints a variable's value the moment it is bound (see #7797),
# and this script binds the Tier-B R2 state pair. There is no legitimate traced run, so the
# refusal is unconditional and sits before anything is bound (same guard as
# apps/cla-evidence/infra/bootstrap.sh).
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

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

# The infra root's ~12 TF_VAR_* inputs come from the prd_terraform config (NOT prd) — under
# -c prd alone the apply fails immediately with "No value for required variable". The provider
# write token `doppler_token_tf` lives only in Tier B post-O5b, so Step 1 runs under the nested
# loader below (outer soleur-infra-privileged/prd wrapping inner prd_terraform), not a bare
# prd_terraform read; Step 2 (the seed) stays under prd.
#
# The Cloudflare-R2 S3 backend reads its creds during `terraform init`, BEFORE any
# provider/variable evaluates — and it wants RAW AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY. The `--name-transformer tf-var` wrapper below rewrites
# every prd_terraform secret to TF_VAR_* (so the backend would see TF_VAR_aws_*,
# ignore it, and SSO-fallback-fail). Export the bare AWS_* OUTSIDE the wrapper so
# they survive into the child env unrenamed. Mirrors apply-web-platform-infra.yml's
# "Extract backend credentials" step + variables.tf:1-13.
# The `|| { … }` handles a doppler non-zero exit (secret absent / auth failure);
# the -z check below handles a present-but-empty value. Both fail closed with a
# friendly message (mirrors apply-web-platform-infra.yml:220-231).
# State-backend creds: the soleur-terraform-state R2 bucket's READ/WRITE pair
# lives in Tier B (soleur-infra-privileged/prd) as TF_STATE_AWS_* — the
# prd_terraform AWS_* pair is read-only since O5b (#8209/ADR-241) and 403s the
# apply's state PutObject mid-run. Exported bare (outside the transformer) so
# they reach the backend unrenamed.
AWS_ACCESS_KEY_ID=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID --plain -p soleur-infra-privileged -c prd) || {
  echo "::error::Failed to read TF_STATE_AWS_ACCESS_KEY_ID from Doppler soleur-infra-privileged/prd (R2 backend write cred)" >&2
  exit 1
}
AWS_SECRET_ACCESS_KEY=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY --plain -p soleur-infra-privileged -c prd) || {
  echo "::error::Failed to read TF_STATE_AWS_SECRET_ACCESS_KEY from Doppler soleur-infra-privileged/prd (R2 backend write cred)" >&2
  exit 1
}
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "::error::R2 backend creds empty in Doppler soleur-infra-privileged/prd (TF_STATE_AWS_ACCESS_KEY_ID/TF_STATE_AWS_SECRET_ACCESS_KEY)" >&2
  exit 1
fi

# -lockfile=readonly for parity with apply-web-platform-infra.yml: refuses to
# download a provider whose checksum is not already in .terraform.lock.hcl
# (defends against a malicious republish of a pinned provider version).
terraform -chdir="$INFRA" init -input=false -lockfile=readonly >/dev/null

# Canonical nested loader (runbook infra-credential-tiers-8209.md §Local
# Terraform invocation): the outer Tier-B loader injects TF_STATE_AWS_* and
# doppler_token_tf (the provider write token — absent from prd_terraform since
# O5b); the inner prd_terraform loader carries the ~12 TF_VAR_* inputs, and its
# --preserve-env is load-bearing: without it the inner loader would overwrite
# the outer Tier-B TF_VAR_* values with prd_terraform's plantable copies. The
# bare AWS_* exported above still reach the backend unrenamed.
doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- \
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
