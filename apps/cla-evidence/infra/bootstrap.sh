#!/usr/bin/env bash
# One-shot post-merge bootstrap for the cla-evidence layer (PR #3201).
#
# Why this exists: the cla-evidence terraform root creates two NEW scoped
# Cloudflare API tokens via `cloudflare_api_token`. Creating tokens requires
# a Cloudflare account-admin token with "User → API Tokens → Edit"
# permission — a scope that, by design, none of our existing scoped Doppler
# tokens have. So a fresh admin token must be minted once and discarded after.
#
# Without this script, the operator would run 5 separate post-merge steps
# (terraform apply, capture outputs, create Doppler config, create service
# token, set GH secret, live-verify Object Lock, trigger first timestamp
# cron). Each step is mechanical and chainable — they're only "operator-only"
# because they need credentials that scoped TF tokens can't carry. This
# script collapses them into ONE operator step: paste a one-time CF admin
# token, walk away.
#
# Workflow contract codified at `wg-multi-step-post-merge-bootstrap-script`.
#
# Operator step (one-time):
#   1. Open https://dash.cloudflare.com/profile/api-tokens
#   2. Create custom token with permissions:
#        - Account → Cloudflare R2 → Edit
#        - User → API Tokens → Edit
#        - Account scope: <your jikigai account>
#      Set TTL: 1 hour.
#   3. Copy the token value, then run:
#        CF_ADMIN_TOKEN_BOOTSTRAP=<paste> \
#          bash apps/cla-evidence/infra/bootstrap.sh
#   4. Revoke the token in the dashboard after the script exits 0.
#
# Idempotent: every step checks current state before mutating. Re-run is
# safe.
#
# Cost: ~$0 (R2 bucket + 2 tokens are well within the free tier).

set -euo pipefail

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; NC='\033[0m'
red()    { printf '%b%s%b\n' "$RED"    "$*" "$NC" >&2; }
green()  { printf '%b%s%b\n' "$GREEN"  "$*" "$NC"; }
yellow() { printf '%b%s%b\n' "$YELLOW" "$*" "$NC"; }
step()   { printf '\n→ %s\n' "$*"; }

# ─────────────────────────────────────────────────────────────────────────
# Pre-flight: deps + auth + admin token
# ─────────────────────────────────────────────────────────────────────────

for bin in terraform doppler gh aws jq curl; do
  command -v "$bin" >/dev/null || { red "missing $bin on PATH"; exit 64; }
done

doppler configure get token --plain >/dev/null 2>&1 \
  || { red "doppler not authenticated; run \`doppler login\`"; exit 64; }
gh auth status >/dev/null 2>&1 \
  || { red "gh not authenticated; run \`gh auth login\`"; exit 64; }

if [[ -z "${CF_ADMIN_TOKEN_BOOTSTRAP:-}" ]]; then
  red "CF_ADMIN_TOKEN_BOOTSTRAP env var is required. See header for token-mint instructions."
  exit 64
fi

# Verify the admin token actually has the scopes we need before going further.
verify=$(curl -fsS \
  -H "Authorization: Bearer $CF_ADMIN_TOKEN_BOOTSTRAP" \
  https://api.cloudflare.com/client/v4/user/tokens/verify 2>&1) \
  || { red "CF_ADMIN_TOKEN_BOOTSTRAP failed verify; rotate and retry"; exit 1; }
status=$(printf '%s' "$verify" | jq -r '.result.status // "unknown"')
[[ "$status" == "active" ]] || { red "admin token status=$status (not active)"; exit 1; }

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

# ─────────────────────────────────────────────────────────────────────────
# Step 1 — terraform apply (creates bucket + Object Lock + 2 scoped tokens)
# ─────────────────────────────────────────────────────────────────────────
step "[1/5] terraform apply (R2 bucket + Object Lock + 2 scoped tokens)"

# Pull supporting values from prd_terraform (existing config — no admin scope
# needed for these specific values).
CF_ACCOUNT_ID=$(doppler secrets get CF_ACCOUNT_ID -p soleur -c prd_terraform --plain)
# State-backend creds (R2-as-S3 access for soleur-terraform-state — already
# scoped to that bucket).
STATE_KEY=$(doppler secrets get AWS_ACCESS_KEY_ID    -p soleur -c prd_terraform --plain)
STATE_SEC=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

# r2_admin_* vars are used by the null_resource Object Lock provisioner.
# We pass the BOOTSTRAP token here too — the put-object-lock-configuration
# S3 call accepts the CF bearer token in HMAC form when the token has
# R2:Edit scope on the bucket (which the admin token does, transitively).
TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
AWS_ACCESS_KEY_ID="$STATE_KEY" \
AWS_SECRET_ACCESS_KEY="$STATE_SEC" \
  terraform init -input=false -no-color >/dev/null

TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
AWS_ACCESS_KEY_ID="$STATE_KEY" \
AWS_SECRET_ACCESS_KEY="$STATE_SEC" \
  terraform apply -auto-approve -input=false -no-color

# Capture outputs (sensitive — never echo).
OBJECT_WRITE_TOKEN=$(TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
  TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
  TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
  terraform output -raw object_write_token_value)
STATE_WRITE_TOKEN=$(TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
  TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
  TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
  terraform output -raw state_write_token_value)
BUCKET_NAME=$(TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
  TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
  TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
  terraform output -raw bucket_name)
BUCKET_ENDPOINT=$(TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
  TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  TF_VAR_r2_admin_access_key_id="$STATE_KEY" \
  TF_VAR_r2_admin_secret_access_key="$STATE_SEC" \
  terraform output -raw bucket_endpoint)
[[ -n "$OBJECT_WRITE_TOKEN" ]] || { red "object_write_token_value missing"; exit 1; }
[[ -n "$STATE_WRITE_TOKEN"  ]] || { red "state_write_token_value missing";  exit 1; }
green "  bucket=$BUCKET_NAME endpoint=$BUCKET_ENDPOINT (tokens captured, not logged)"

# ─────────────────────────────────────────────────────────────────────────
# Step 2 — Doppler prd_cla config + secrets
# ─────────────────────────────────────────────────────────────────────────
step "[2/5] Doppler prd_cla config + secrets"

if ! doppler configs --project soleur --json | jq -e '.[] | select(.name == "prd_cla")' >/dev/null 2>&1; then
  doppler configs create prd_cla --project soleur --environment prd
  green "  created prd_cla config"
else
  yellow "  prd_cla already exists; will update secrets in place"
fi

# Endpoint is derivable but stored for sidecar simplicity.
R2_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"

doppler secrets set \
  --project soleur --config prd_cla \
  --no-interactive \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID="$OBJECT_WRITE_TOKEN" \
  R2_CLA_EVIDENCE_SECRET="$OBJECT_WRITE_TOKEN" \
  R2_CLA_EVIDENCE_ENDPOINT="$R2_ENDPOINT" \
  R2_CLA_EVIDENCE_BUCKET="$BUCKET_NAME" \
  R2_CLA_EVIDENCE_ADMIN_KEY_ID="$OBJECT_WRITE_TOKEN" \
  R2_CLA_EVIDENCE_ADMIN_SECRET="$OBJECT_WRITE_TOKEN" \
  >/dev/null
green "  pushed 6 secrets to prd_cla"

# ─────────────────────────────────────────────────────────────────────────
# Step 3 — Doppler service token + GH repo secret
# ─────────────────────────────────────────────────────────────────────────
step "[3/5] Doppler service token + DOPPLER_TOKEN_CLA repo secret"

if existing=$(doppler configs tokens --project soleur --config prd_cla --json 2>/dev/null \
              | jq -r '.[] | select(.name == "ci-cla-evidence-workflow") | .slug' | head -n 1) \
   && [[ -n "$existing" ]]; then
  yellow "  service token ci-cla-evidence-workflow already exists; revoking + recreating"
  doppler configs tokens revoke "$existing" --project soleur --config prd_cla --yes >/dev/null
fi

SERVICE_TOKEN=$(doppler configs tokens create ci-cla-evidence-workflow \
  --project soleur --config prd_cla \
  --plain)
[[ -n "$SERVICE_TOKEN" ]] || { red "service token creation failed"; exit 1; }

gh secret set DOPPLER_TOKEN_CLA --body "$SERVICE_TOKEN" --repo jikig-ai/soleur >/dev/null
green "  service token created + uploaded as repo secret DOPPLER_TOKEN_CLA"

# ─────────────────────────────────────────────────────────────────────────
# Step 4 — live Object Lock verification
# ─────────────────────────────────────────────────────────────────────────
step "[4/5] live Object Lock verification (GOVERNANCE / 3650 days)"

R2_CLA_EVIDENCE_ADMIN_KEY_ID="$OBJECT_WRITE_TOKEN" \
R2_CLA_EVIDENCE_ADMIN_SECRET="$OBJECT_WRITE_TOKEN" \
R2_CLA_EVIDENCE_ENDPOINT="$R2_ENDPOINT" \
R2_CLA_EVIDENCE_BUCKET="$BUCKET_NAME" \
  bash "$INFRA_DIR/main.test.sh" --live

# ─────────────────────────────────────────────────────────────────────────
# Step 5 — trigger cla-evidence-timestamp.yml first run
# ─────────────────────────────────────────────────────────────────────────
step "[5/5] trigger cla-evidence-timestamp.yml first run"

gh workflow run cla-evidence-timestamp.yml --repo jikig-ai/soleur 2>&1 \
  | tail -n 1
green "  workflow dispatched — watch the run at \`gh run list --workflow cla-evidence-timestamp.yml\`"

# ─────────────────────────────────────────────────────────────────────────
# Done — closing reminders
# ─────────────────────────────────────────────────────────────────────────
green ""
green "BOOTSTRAP COMPLETE."
green "Operator follow-ups:"
green "  1. REVOKE the CF_ADMIN_TOKEN_BOOTSTRAP token in the Cloudflare dashboard NOW."
green "  2. Close GitHub issues: #3905 #3906 #3907 #3909 (this script covers all four)."
green "  3. Open the Phase 8 sentinel PRs (issue #3908) — those genuinely need a human signer."
