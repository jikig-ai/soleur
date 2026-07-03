#!/usr/bin/env bash
# Push infra-config files to the production host via the /hooks/infra-config
# webhook endpoint through the Cloudflare Tunnel. Invoked by the local-exec
# provisioner in terraform_data.deploy_pipeline_fix (#3756).
#
# Environment variables (set by the provisioner's environment {} block):
#   WEBHOOK_SECRET   — HMAC-SHA256 shared secret
#   CF_ACCESS_ID     — Cloudflare Access service-token client ID
#   CF_ACCESS_SECRET — Cloudflare Access service-token client secret
#   APP_DOMAIN_BASE  — Base domain (e.g., soleur.ai)
#   INFRA_DIR        — Path to the infra directory (path.module)
#   HOOKS_JSON_B64   — Pre-rendered hooks.json (base64-encoded by Terraform
#                      from local.hooks_json — the template has secrets
#                      interpolated at plan time, so the on-disk .tmpl file
#                      is NOT the right source)
set -euo pipefail

for var in WEBHOOK_SECRET CF_ACCESS_ID CF_ACCESS_SECRET APP_DOMAIN_BASE INFRA_DIR HOOKS_JSON_B64; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required env var $var is missing or empty" >&2
    exit 1
  fi
done

PAYLOAD_FILE=$(mktemp /tmp/infra-config-payload.XXXXXX)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

# Build JSON payload with base64-encoded file contents.
# hooks.json is passed pre-encoded via HOOKS_JSON_B64 because it is rendered
# from a Terraform template (hooks.json.tmpl) with secrets interpolated —
# the on-disk file is the template, not the rendered output.
#
# #5450/#5492 — the four inngest cutover scripts (inngest-enumerate-reminders.sh,
# inngest-rearm-reminders.sh, inngest-wiped-volume-verify.sh,
# cat-inngest-verify-state.sh) are delivered by this push (payload below +
# infra-config-apply FILE_MAP + infra-config-install DEST_SPEC). They ARE
# registered in deploy_pipeline_fix's per-file triggers_replace hash (server.tf)
# + the ship DEPLOY_PIPELINE_FIX_TRIGGERS array/regex + the gate test, so a
# body-only edit to any one re-fires the apply and reaches /usr/local/bin
# (#5492: an earlier "transient, don't register" decision blocked the enumerate
# fix from deploying — no hashed file had changed).
cat > "$PAYLOAD_FILE" <<PAYLOAD
{
  "ci_deploy_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/ci-deploy.sh")",
  "ci_deploy_wrapper_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/ci-deploy-wrapper.sh")",
  "webhook_service_b64": "$(base64 -w0 < "${INFRA_DIR}/webhook.service")",
  "cat_deploy_state_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/cat-deploy-state.sh")",
  "canary_bundle_claim_check_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/canary-bundle-claim-check.sh")",
  "hooks_json_b64": "${HOOKS_JSON_B64}",
  "cat_infra_config_state_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/cat-infra-config-state.sh")",
  "inngest_enumerate_reminders_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/inngest-enumerate-reminders.sh")",
  "inngest_rearm_reminders_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/inngest-rearm-reminders.sh")",
  "inngest_wiped_volume_verify_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/inngest-wiped-volume-verify.sh")",
  "cat_inngest_verify_state_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/cat-inngest-verify-state.sh")",
  "inngest_inventory_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/inngest-inventory.sh")",
  "git_lock_chardevice_sweep_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/git-lock-chardevice-sweep.sh")"
}
PAYLOAD

# Compute HMAC-SHA256 over the raw payload file (same pattern as web-platform-release.yml).
HMAC=$(openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" < "$PAYLOAD_FILE" | sed 's/.*= //')

# --data-binary preserves the exact payload bytes (including newlines from
# the heredoc). curl's -d strips newlines, creating an HMAC mismatch between
# what openssl hashed and what the server receives.
HTTP_CODE=$(curl -s -o /tmp/infra-config-response.txt -w '%{http_code}' \
  --max-time 30 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Signature-256: sha256=${HMAC}" \
  -H "CF-Access-Client-Id: ${CF_ACCESS_ID}" \
  -H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}" \
  --data-binary @"$PAYLOAD_FILE" \
  "https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config")

if [[ "$HTTP_CODE" != "202" ]]; then
  echo "ERROR: webhook returned HTTP ${HTTP_CODE} (expected 202)" >&2
  cat /tmp/infra-config-response.txt >&2 2>/dev/null || true
  exit 1
fi

echo "infra-config push succeeded (HTTP 202)"
