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

readonly LOG_TAG="infra-config-apply"

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
  "CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root"
)

# TEST_DESTDIR allows tests to redirect writes to a sandbox
DESTDIR="${TEST_DESTDIR:-}"

# State file for observability (#4554). Queryable via /hooks/infra-config-status.
STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"
START_TS=$(date +%s)

# Clear stale sentinel from prior run (same pattern as ci-deploy.sh:105)
rm -f "${STATE_FILE}.final"

# EXIT trap: on non-zero exit without a .final sentinel, write "unhandled" state.
# Also cleans up temp files and the sentinel.
TMPFILES=()
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ ! -f "${STATE_FILE}.final" ]; then
  printf "{\"start_ts\":%d,\"end_ts\":%d,\"exit_code\":%d,\"reason\":\"unhandled\",\"files_written\":0,\"files_failed\":0,\"files_total\":0,\"files\":[]}\n" \
    "$START_TS" "$(date +%s)" "$rc" > "$STATE_FILE" 2>/dev/null || true
fi; rm -f "${TMPFILES[@]}" "${STATE_FILE}.final"' EXIT

# NOTE: env vars are validated PER FILE inside the write loop below (missing_env
# arm), NOT upfront. The former upfront all-or-nothing `exit 1` caused the
# chicken-and-egg freeze (#4804): when a new file was added to FILE_MAP +
# hooks.json env-passing atomically, the host's stale hooks.json could not pass
# the new key, leaving its env var empty — and the upfront gate then aborted the
# ENTIRE write, including the new hooks.json that would have re-aligned the
# mapping. Per-file accounting lets the 7 good files (crucially the new
# hooks.json) land while the absent one is recorded as a failure and surfaces a
# loud exit_code=1 to the CI verify gate.

TOTAL_COUNT=${#FILE_MAP[@]}
logger -t "$LOG_TAG" "starting: $TOTAL_COUNT files to write"

# --- Write each file atomically ---
WRITTEN_COUNT=0
FAIL_COUNT=0
FILES_JSON=""

for entry in "${FILE_MAP[@]}"; do
  IFS='|' read -r env_var dest_path mode owner <<< "$entry"

  # Missing-env arm: record a per-file failure and continue so the OTHER files
  # still land (chicken-and-egg self-heal, #4804). Placed before mktemp so no
  # orphan temp file is created for the absent file.
  if [[ -z "${!env_var:-}" ]]; then
    logger -t "$LOG_TAG" "FAILED: $dest_path reason=missing_env env=$env_var"
    echo "ERROR: missing payload for $dest_path (env $env_var empty)" >&2
    [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
    FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"missing_env\"}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  dest="${DESTDIR}${dest_path}"
  dest_dir=$(dirname "$dest")

  logger -t "$LOG_TAG" "writing: $dest_path"

  # Decode to a temp file in the same directory (same filesystem for mv atomicity)
  tmpfile=$(mktemp "${dest_dir}/tmp.infra-config.XXXXXX")
  TMPFILES+=("$tmpfile")

  if ! echo "${!env_var}" | base64 -d > "$tmpfile" 2>/dev/null; then
    logger -t "$LOG_TAG" "FAILED: $dest_path reason=base64_decode"
    echo "ERROR: base64 decode failed for $dest_path" >&2
    [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
    FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"base64_decode\"}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -f "$tmpfile"
    continue
  fi

  # Sudoers files get visudo validation before install
  if [[ "$dest_path" == /etc/sudoers.d/* ]]; then
    if ! visudo -cf "$tmpfile" 2>/dev/null; then
      logger -t "$LOG_TAG" "SKIPPED: $dest_path reason=visudo_validation_failed"
      echo "WARNING: visudo validation failed for $dest_path — skipping install" >&2
      [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
      FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"skipped\",\"reason\":\"visudo_validation_failed\"}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
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

  local_sha=$(sha256sum "$dest" | awk '{print $1}')
  logger -t "$LOG_TAG" "wrote: $dest_path sha256=$local_sha"
  [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
  FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"$local_sha\",\"status\":\"ok\"}"
  WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
done

logger -t "$LOG_TAG" "complete: $WRITTEN_COUNT/$TOTAL_COUNT files written, $FAIL_COUNT failed"

# --- Write state file (before self-restart) ---
END_TS=$(date +%s)
EXIT_CODE=0
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  EXIT_CODE=1
fi

touch "${STATE_FILE}.final"
state_tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || {
  logger -t "$LOG_TAG" "write_state: mktemp failed for STATE_FILE=$STATE_FILE"
  state_tmp=""
}
if [[ -n "${state_tmp:-}" ]]; then
  printf '{"start_ts":%d,"end_ts":%d,"exit_code":%d,"files_written":%d,"files_failed":%d,"files_total":%d,"files":[%s]}\n' \
    "$START_TS" "$END_TS" "$EXIT_CODE" "$WRITTEN_COUNT" "$FAIL_COUNT" "$TOTAL_COUNT" "$FILES_JSON" \
    > "$state_tmp" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: printf/redirect failed"
    rm -f "$state_tmp"
    state_tmp=""
  }
fi
if [[ -n "${state_tmp:-}" ]]; then
  mv "$state_tmp" "$STATE_FILE" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: mv failed"
    rm -f "$state_tmp"
  }
fi

# --- Post-write commands (skip in test mode) ---
if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]; then
  sync
  systemctl daemon-reload
  logger -t "$LOG_TAG" "scheduling self-restart in 3s"
  # Self-restart: schedule a delayed restart so the HTTP 202 response
  # completes before the webhook binary is killed.
  sudo /usr/bin/systemd-run --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook
fi

exit "$EXIT_CODE"
