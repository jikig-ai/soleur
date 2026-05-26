#!/usr/bin/env bash
# Webhook handler for /hooks/infra-config — replaces the SSH provisioner in
# terraform_data.deploy_pipeline_fix with an HTTPS-only code path (#3756).
#
# Self-restart state machine: this script is exec'd by the webhook binary
# (adnanh/webhook) which is itself managed by webhook.service. When this
# script writes a new webhook.service unit, it must restart the webhook
# binary to pick up the change — but the restart kills the process that is
# currently serving the HTTP response. The fix: schedule a delayed restart
# via systemd-run --on-active=3s so the 202 response flushes before the
# binary is replaced. The 3s delay > typical TCP FIN handshake (~200ms).
#
# Chicken-and-egg bootstrap: on the FIRST apply after this code lands,
# the host does not yet have this script or the /hooks/infra-config hook.
# That first apply runs from the operator's local machine via the old SSH
# path (operator IP is in admin_ips). All subsequent applies use webhook.
set -euo pipefail

# --- File map (hardcoded — no generic JSON, no jq) ---
# Each entry: ENV_VAR_NAME | DEST_PATH | MODE | OWNER
FILE_MAP=(
  "CI_DEPLOY_SH_B64|/usr/local/bin/ci-deploy.sh|755|root:root"
  "CI_DEPLOY_WRAPPER_SH_B64|/usr/local/bin/ci-deploy-wrapper.sh|755|root:root"
  "WEBHOOK_SERVICE_B64|/etc/systemd/system/webhook.service|644|root:root"
  "CAT_DEPLOY_STATE_SH_B64|/usr/local/bin/cat-deploy-state.sh|755|root:root"
  "CANARY_BUNDLE_CLAIM_CHECK_SH_B64|/usr/local/bin/canary-bundle-claim-check.sh|755|root:root"
  "DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64|/etc/sudoers.d/deploy-inngest-bootstrap|440|root:root"
  "HOOKS_JSON_B64|/etc/webhook/hooks.json|640|root:deploy"
)

# TEST_DESTDIR allows tests to redirect writes to a sandbox
DESTDIR="${TEST_DESTDIR:-}"

# --- Validate all required env vars upfront ---
for entry in "${FILE_MAP[@]}"; do
  IFS='|' read -r env_var _ _ _ <<< "$entry"
  if [[ -z "${!env_var:-}" ]]; then
    echo "ERROR: required env var $env_var is missing or empty" >&2
    exit 1
  fi
done

# --- Write each file atomically ---
for entry in "${FILE_MAP[@]}"; do
  IFS='|' read -r env_var dest_path mode owner <<< "$entry"
  dest="${DESTDIR}${dest_path}"
  dest_dir=$(dirname "$dest")

  # Decode to a temp file in the same directory (same filesystem for mv atomicity)
  tmpfile=$(mktemp "${dest_dir}/tmp.infra-config.XXXXXX")
  trap "rm -f '$tmpfile'" EXIT

  echo "${!env_var}" | base64 -d > "$tmpfile"

  # Sudoers files get visudo validation before install
  if [[ "$dest_path" == /etc/sudoers.d/* ]]; then
    if ! visudo -cf "$tmpfile" 2>/dev/null; then
      echo "WARNING: visudo validation failed for $dest_path — skipping install" >&2
      rm -f "$tmpfile"
      continue
    fi
  fi

  chmod "$mode" "$tmpfile"
  # chown only works as root; skip in test mode
  if [[ -z "$DESTDIR" ]]; then
    chown "$owner" "$tmpfile"
  fi
  mv -f "$tmpfile" "$dest"
done

# --- Post-write commands (skip in test mode) ---
if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]; then
  systemctl daemon-reload
  # Self-restart: schedule a delayed restart so the HTTP 202 response
  # completes before the webhook binary is killed.
  sudo systemd-run --on-active=3s --unit=webhook-self-restart systemctl restart webhook
fi

exit 0
