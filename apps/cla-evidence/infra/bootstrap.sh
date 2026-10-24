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
# token, set GH secret, live-verify the Lock Rule, trigger first timestamp
# cron). Each step is mechanical and chainable — they're only "operator-only"
# because they need credentials that scoped TF tokens can't carry. This
# script collapses them into ONE operator step: paste a one-time CF admin
# token, walk away.
#
# Workflow contract codified at `hr-multi-step-post-merge-bootstrap-script`.
#
# Operator steps (one-time):
#   1. Mint a one-hour CF admin token at https://dash.cloudflare.com/profile/api-tokens
#      with permissions: Account → Cloudflare R2 → Edit, User → API Tokens → Edit
#      scoped to the jikigai account.
#   2. Create the R2 S3-compat token (separate resource type, distinct from the
#      generic API Token in step 1) at:
#        Storage & databases → R2 → Manage API Tokens → Create Account API token
#        Permission: Object Read & Write
#        Buckets: Apply to specific buckets only → soleur-cla-evidence
#        TTL: Forever
#      The dashboard shows the resulting Access Key ID + Secret Access Key ONCE
#      on creation. Cloudflare R2's S3 surface only accepts credentials minted
#      via this flow — generic cloudflare_api_token Bearer values do NOT work
#      as SigV4 HMAC pairs (confirmed via SignatureDoesNotMatch on every run
#      from 2026-05-16 onward; learning file 2026-05-18-cla-evidence-r2-s3-creds-not-derived.md).
#   3. Run this script with all three values exported:
#        CF_ADMIN_TOKEN_BOOTSTRAP=<paste from step 1> \
#        R2_S3_ACCESS_KEY_ID=<paste from step 2, 32-char hex> \
#        R2_S3_SECRET_ACCESS_KEY=<paste from step 2, 64-char hex> \
#          bash apps/cla-evidence/infra/bootstrap.sh
#   4. The script self-revokes the CF admin token via the CF API at the end of
#      a successful run. If that step fails (network blip, etc.), the script
#      warns and the operator must revoke manually in the dashboard. The R2 S3
#      token is long-lived and is rotated only on leak signal.
#
# Optional opt-in (closes #3908): set SENTINEL_PR_AUTOMATION=1 to run the
# Phase 8 sentinel-PR driver (human signer + allowlist-bypass) at the end
# of the bootstrap. Default OFF.
#
# Idempotent: every step checks current state before mutating. Re-run is
# safe.
#
# Cost: ~$0 (R2 bucket + 2 tokens are well within the free tier).

set -euo pipefail

# Refuse to run under xtrace: -x prints a variable's value the moment it is bound (see #7797), and
# this script handles a live Cloudflare admin token and the R2 SigV4 pair. There is no legitimate
# traced run, so the refusal is unconditional and sits before anything is bound.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; NC='\033[0m'
red()    { printf '%b%s%b\n' "$RED"    "$*" "$NC" >&2; }
green()  { printf '%b%s%b\n' "$GREEN"  "$*" "$NC"; }
yellow() { printf '%b%s%b\n' "$YELLOW" "$*" "$NC"; }
step()   { printf '\n→ %s\n' "$*"; }

# Shared CF-admin-token helpers (verify + self-revoke). Sourced AFTER the
# red/green/yellow helpers above (sourcing precondition) and via a self-
# contained script-dir anchor so it does NOT depend on INFRA_DIR (computed
# later, after the verify block that now calls cf_token_verify).
# shellcheck source=../scripts/_cf-admin-token.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/_cf-admin-token.sh"
# shellcheck source=../scripts/_r2-endpoint.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/_r2-endpoint.sh"
# The ONE curl that carries the R2 SigV4 pair: the key id and secret ride curl's stdin config, never argv.
# shellcheck source=../scripts/_r2-sigv4-curl.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/_r2-sigv4-curl.sh"

# ─────────────────────────────────────────────────────────────────────────
# Pre-flight: deps + auth + admin token
# ─────────────────────────────────────────────────────────────────────────

for bin in terraform doppler gh jq curl openssl; do
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
# Shared helper hard-fails on verify error / non-active / empty id. The empty-id
# hard-fail is the defensive upgrade (issue #3950 item 3): the prior inline form
# captured the id with `// ""` and continued on empty, silently disabling the
# post-run self-revoke. Now an un-capturable id aborts bootstrap up front.
CF_ADMIN_TOKEN_ID=$(cf_token_verify "$CF_ADMIN_TOKEN_BOOTSTRAP") \
  || { red "CF_ADMIN_TOKEN_BOOTSTRAP failed verify (or token id not captured); rotate and retry"; exit 1; }

# Compute total step count once so the step counter is consistent end-to-end.
if [[ "${SENTINEL_PR_AUTOMATION:-0}" == "1" ]]; then
  TOTAL_STEPS=6
else
  TOTAL_STEPS=5
fi

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

# ─────────────────────────────────────────────────────────────────────────
# Step 1 — terraform apply (creates bucket + Lock Rules + 2 scoped tokens)
# ─────────────────────────────────────────────────────────────────────────
step "[1/${TOTAL_STEPS}] terraform apply (R2 bucket + CF Lock Rules + 2 scoped tokens)"

# Pull supporting values from prd_terraform (existing config — no admin scope
# needed for these specific values).
CF_ACCOUNT_ID=$(doppler secrets get CF_ACCOUNT_ID -p soleur -c prd_terraform --plain)
# State-backend creds: the soleur-terraform-state R2 bucket's READ/WRITE pair
# lives in Tier B (soleur-infra-privileged/prd) as TF_STATE_AWS_* — the
# prd_terraform AWS_* pair is read-only since O5b (#8209/ADR-241) and 403s the
# apply's state PutObject. All-or-none: a half-set pair authenticates as nobody.
STATE_KEY=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID    -p soleur-infra-privileged -c prd --plain) \
  || { echo "::error::TF_STATE_AWS_ACCESS_KEY_ID unreadable in soleur-infra-privileged/prd" >&2; exit 1; }
STATE_SEC=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain) \
  || { echo "::error::TF_STATE_AWS_SECRET_ACCESS_KEY unreadable in soleur-infra-privileged/prd" >&2; exit 1; }

# Common TF env (reused across init/apply/output calls).
tf_env() {
  TF_VAR_cf_account_id="$CF_ACCOUNT_ID" \
  TF_VAR_cf_api_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  TF_VAR_cf_admin_token="$CF_ADMIN_TOKEN_BOOTSTRAP" \
  AWS_ACCESS_KEY_ID="$STATE_KEY" \
  AWS_SECRET_ACCESS_KEY="$STATE_SEC" \
    "$@"
}

tf_env terraform init -input=false -no-color >/dev/null
tf_env terraform apply -auto-approve -input=false -no-color

# Capture outputs (sensitive — never echo).
OBJECT_WRITE_TOKEN_VALUE=$(tf_env terraform output -raw object_write_token_value)
OBJECT_WRITE_TOKEN_ID=$(tf_env terraform output -raw object_write_token_id)
STATE_WRITE_TOKEN=$(tf_env terraform output -raw state_write_token_value)
BUCKET_NAME=$(tf_env terraform output -raw bucket_name)
BUCKET_ENDPOINT=$(tf_env terraform output -raw bucket_endpoint)
[[ -n "$OBJECT_WRITE_TOKEN_VALUE" ]] || { red "object_write_token_value missing"; exit 1; }
[[ -n "$OBJECT_WRITE_TOKEN_ID"    ]] || { red "object_write_token_id missing — older TF state may need a re-apply"; exit 1; }
[[ -n "$STATE_WRITE_TOKEN"        ]] || { red "state_write_token_value missing";  exit 1; }
green "  bucket=$BUCKET_NAME endpoint=$BUCKET_ENDPOINT (tokens captured, not logged)"

# R2 S3-compat HMAC pair — REQUIRED from the caller, NOT derived.
#
# Prior revisions of this script tried to derive the pair from the
# `cloudflare_api_token` TF resource via:
#   access_key_id = token.id          (32-char hex)
#   secret_access_key = sha256(token.value)
# That derivation is wrong: Cloudflare's S3-compat surface does not accept
# generic-API-token-derived HMAC values. R2 issues real S3 credentials only
# when you create an "R2 API Token" (a distinct resource type) via the
# dashboard route /:account/r2/api-tokens/create — that flow returns a
# 32-char accessKeyId + 64-char secretAccessKey directly, shown ONCE on
# creation. The Terraform `cloudflare_api_token` resource here remains
# load-bearing for the CF Lock Rules and GDPR-override REST calls below
# (those use Bearer auth, not SigV4), but its value cannot be reused as
# the R2 S3 secret. Confirmed empirically: pushing the derived pair to
# Doppler produced `<Code>SignatureDoesNotMatch</Code>` on every workflow
# run from 2026-05-16 onward.
#
# Operator workflow:
#   1. Create the R2 token in the Cloudflare dashboard:
#        Storage & databases → R2 → Manage API Tokens → Create Account API token
#        Permission: Object Read & Write
#        Buckets: Apply to specific buckets only → soleur-cla-evidence
#        TTL: Forever (rotate manually if needed)
#   2. Copy the displayed Access Key ID + Secret Access Key.
#   3. Re-run this script with both env vars set:
#        R2_S3_ACCESS_KEY_ID=<32-char> \
#        R2_S3_SECRET_ACCESS_KEY=<64-char> \
#        CF_ADMIN_TOKEN_BOOTSTRAP=<paste> \
#          bash apps/cla-evidence/infra/bootstrap.sh
#
# Length assertions below surface a typo before any Doppler write.
if [[ -z "${R2_S3_ACCESS_KEY_ID:-}" || -z "${R2_S3_SECRET_ACCESS_KEY:-}" ]]; then
  red "R2_S3_ACCESS_KEY_ID and R2_S3_SECRET_ACCESS_KEY must be set."
  red "Create the R2 token in the CF dashboard (see header comment above this block for the exact path), then re-run with both env vars exported."
  exit 64
fi
R2_ACCESS_KEY="$R2_S3_ACCESS_KEY_ID"
R2_SECRET="$R2_S3_SECRET_ACCESS_KEY"
[[ ${#R2_ACCESS_KEY} -eq 32 ]] \
  || { red "R2_S3_ACCESS_KEY_ID length=${#R2_ACCESS_KEY}, expected 32 (hex)"; exit 1; }
[[ ${#R2_SECRET} -eq 64 ]] \
  || { red "R2_S3_SECRET_ACCESS_KEY length=${#R2_SECRET}, expected 64 (hex)"; exit 1; }

# Probe-PUT: verify the supplied creds actually sign correctly against R2
# BEFORE writing them to Doppler. Without this, a typo or wrong-token-type
# silently lands in prd_cla and surfaces only when the first PR's
# cla-evidence workflow runs — the 2026-05-16 outage class. The probe key
# is content-addressed under bootstrap-probe/ so it's idempotent across
# re-runs and easy to identify+delete in the bucket inspector.
# The pair is judged here, before anything else: a malformed value exits 2 with the marker and the
# variable name the operator actually set. The request itself goes through r2_sigv4_curl, which pins
# the destination and passes the pair on curl's stdin config instead of argv. It also confines the
# transport (--disable --noproxy '*', no inherited CA bundle), so this one-shot needs direct egress to
# R2 with the system trust store; a proxy or a TLS-inspecting CA reads as status 000 below.
# Pin the canonical R2 endpoint base (guards a malformed CF_ACCOUNT_ID) BEFORE
# this credentialed probe PUT — without it, a bad account id would send the R2
# HMAC secret to a non-canonical host (item 1 of #3950). Reused for the Doppler
# push below.
R2_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
assert_r2_endpoint "$R2_ENDPOINT"
probe_endpoint="${R2_ENDPOINT}/${BUCKET_NAME}/bootstrap-probe/$(date -u +%Y%m%dT%H%M%SZ).json"
probe_body='{"probe":"bootstrap","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'
probe_body_file=$(mktemp)
trap 'rm -f "$probe_body_file"' EXIT
r2_sigv4_judge "bootstrap" "$R2_ACCESS_KEY" "$R2_SECRET" R2_S3_ACCESS_KEY_ID R2_S3_SECRET_ACCESS_KEY || exit 2
probe_code=$(r2_sigv4_curl "bootstrap" "$R2_ACCESS_KEY" "$R2_SECRET" "$probe_endpoint" \
  -sS -o "$probe_body_file" -w "%{http_code}" --max-time 30 \
  -X PUT \
  -H "If-None-Match: *" \
  -H "Content-Type: application/json" \
  --data-binary "$probe_body" || true)
probe_code="${probe_code:-000}"
if [[ "$probe_code" != "200" && "$probe_code" != "201" && "$probe_code" != "412" ]]; then
  red "R2 probe PUT failed: status=$probe_code body=$(tr '\n' ' ' < "$probe_body_file" | head -c 400)"
  red "Refusing to push known-broken creds to Doppler. Verify R2_S3_ACCESS_KEY_ID/SECRET match a freshly-minted R2 dashboard token (see header)."
  # The helper refusing the destination or an argument (return 64) cannot happen here: assert_r2_endpoint above already
  # exits 64 on a non-canonical host, and this call's arguments are fixed. So 000 means curl itself got no response.
  if [[ "$probe_code" == "000" ]]; then
    red "status=000 also means curl never got a response: this probe needs direct egress to R2 with the system trust store (no proxy, no TLS-inspecting CA)."
  fi
  exit 1
fi
green "  R2 probe PUT ok (status=$probe_code); creds verified before Doppler push"

# ─────────────────────────────────────────────────────────────────────────
# Step 2 — Doppler prd_cla config + secrets
# ─────────────────────────────────────────────────────────────────────────
step "[2/${TOTAL_STEPS}] Doppler prd_cla config + secrets"

if ! doppler configs --project soleur --json | jq -e '.[] | select(.name == "prd_cla")' >/dev/null 2>&1; then
  doppler configs create prd_cla --project soleur --environment prd
  green "  created prd_cla config"
else
  yellow "  prd_cla already exists; will update secrets in place"
fi

# Endpoint is derivable but stored for sidecar simplicity. R2_ENDPOINT was
# computed AND validated (assert_r2_endpoint) above, before the probe PUT.

# The two non-secret values go as NAME=value arguments. The HMAC pair goes on the CLI's STDIN, one name per
# call (printf is a builtin, so the value never reaches an exec argv): an argument would put the pair in
# /proc/<pid>/cmdline for the life of the doppler process, which is the exposure this script's curl
# probe no longer has. The two pair writes are NOT one atomic call. If the second fails, prd_cla holds
# the new key id with the OLD secret, and the required cla-evidence check fails on every PR until this
# is re-run, so that case says so loudly. Recovery needs the SAME R2_S3_* pair (the dashboard shows the
# secret once) and a live CF_ADMIN_TOKEN_BOOTSTRAP (valid for one hour); re-running is idempotent. A
# read-back then compares each stored length with the expected 32/64 (the values are never printed), because
# nothing else would notice a CLI that stored an empty or trimmed value from stdin.
doppler secrets set \
  --project soleur --config prd_cla \
  --no-interactive \
  R2_CLA_EVIDENCE_ENDPOINT="$R2_ENDPOINT" \
  R2_CLA_EVIDENCE_BUCKET="$BUCKET_NAME" \
  >/dev/null
pair_write_failed() {
  red "R2 pair write to prd_cla FAILED part-way: prd_cla may now hold a MIXED pair and the required cla-evidence check will fail until this is fixed."
  red "Re-run with the SAME R2_S3_ACCESS_KEY_ID / R2_S3_SECRET_ACCESS_KEY and a live CF_ADMIN_TOKEN_BOOTSTRAP (or restore prd_cla in the Doppler UI)."
  exit 1
}
printf '%s' "$R2_ACCESS_KEY" | doppler secrets set R2_CLA_EVIDENCE_ACCESS_KEY_ID \
  --project soleur --config prd_cla --no-interactive >/dev/null || pair_write_failed
printf '%s' "$R2_SECRET" | doppler secrets set R2_CLA_EVIDENCE_SECRET \
  --project soleur --config prd_cla --no-interactive >/dev/null || pair_write_failed
stored_id=$(doppler secrets get R2_CLA_EVIDENCE_ACCESS_KEY_ID --project soleur --config prd_cla --plain 2>/dev/null) || stored_id=""
stored_secret=$(doppler secrets get R2_CLA_EVIDENCE_SECRET --project soleur --config prd_cla --plain 2>/dev/null) || stored_secret=""
if [[ "${#stored_id}" -ne 32 || "${#stored_secret}" -ne 64 || "$stored_id" != "$R2_ACCESS_KEY" || "$stored_secret" != "$R2_SECRET" ]]; then
  red "R2 pair read-back from prd_cla does not match what was written (stored lengths: id=${#stored_id}, secret=${#stored_secret}; expected 32 and 64)."
  pair_write_failed
fi
green "  pushed 4 secrets to prd_cla (S3-compat HMAC pair on stdin + endpoint + bucket)"

# ─────────────────────────────────────────────────────────────────────────
# Step 3 — Doppler service token + GH repo secret
# ─────────────────────────────────────────────────────────────────────────
step "[3/${TOTAL_STEPS}] Doppler service token + DOPPLER_TOKEN_CLA repo secret"

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
# Step 4 — live CF Lock Rules verification
# ─────────────────────────────────────────────────────────────────────────
step "[4/${TOTAL_STEPS}] live CF Lock Rules verification (age-based, maxAgeSeconds >= 315360000)"

CF_ADMIN_TOKEN_BOOTSTRAP="$CF_ADMIN_TOKEN_BOOTSTRAP" \
CF_ACCOUNT_ID="$CF_ACCOUNT_ID" \
R2_CLA_EVIDENCE_BUCKET="$BUCKET_NAME" \
  bash "$INFRA_DIR/main.test.sh" --live

# ─────────────────────────────────────────────────────────────────────────
# Step 5 — trigger cla-evidence-timestamp.yml first run
# ─────────────────────────────────────────────────────────────────────────
step "[5/${TOTAL_STEPS}] trigger cla-evidence-timestamp.yml first run"

gh workflow run cla-evidence-timestamp.yml --repo jikig-ai/soleur 2>&1 \
  | tail -n 1
green "  workflow dispatched — watch the run at \`gh run list --workflow cla-evidence-timestamp.yml\`"

# ─────────────────────────────────────────────────────────────────────────
# Step 6 — Phase 8 sentinel PRs (opt-in via SENTINEL_PR_AUTOMATION=1)
# ─────────────────────────────────────────────────────────────────────────
if [[ "${SENTINEL_PR_AUTOMATION:-0}" == "1" ]]; then
  step "[6/${TOTAL_STEPS}] Phase 8 sentinel PRs (closes #3908)"
  bash "$INFRA_DIR/../scripts/sentinel-pr.sh" both
else
  yellow "Sentinel-PR automation skipped (set SENTINEL_PR_AUTOMATION=1 to enable; closes #3908)."
fi

# ─────────────────────────────────────────────────────────────────────────
# Self-revoke the bootstrap admin token. The admin token carries
# `User → API Tokens → Edit` scope (required to create the two scoped
# tokens earlier), which by definition includes the right to revoke
# itself. Operator no longer needs to remember to do this in the
# dashboard — closes the residual window between bootstrap exit and
# manual revocation.
# ─────────────────────────────────────────────────────────────────────────
# Shared best-effort self-revoke (warns, never hard-fails). CF_ADMIN_TOKEN_ID
# is guaranteed non-empty here — cf_token_verify aborts up front on empty id.
green ""
cf_token_self_revoke "$CF_ADMIN_TOKEN_BOOTSTRAP" "$CF_ADMIN_TOKEN_ID"

# ─────────────────────────────────────────────────────────────────────────
# Done — closing reminders
# ─────────────────────────────────────────────────────────────────────────
green ""
green "BOOTSTRAP COMPLETE."
green "Operator follow-ups:"
green "  1. Verify the dispatched cla-evidence-timestamp.yml run reached green."
if [[ "${SENTINEL_PR_AUTOMATION:-0}" != "1" ]]; then
  green "  2. (Optional) Re-run with SENTINEL_PR_AUTOMATION=1 to exercise the sentinel-PR path (closes #3908)."
fi
