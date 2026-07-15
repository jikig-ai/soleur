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
# DEST_PATH values are interpolated unescaped into the state JSON ("file":"...");
# keep them JSON-safe (no '"' or '\') so /hooks/infra-config-status stays parseable.
# NOTE (#4827): /etc/sudoers.d/deploy-inngest-bootstrap is intentionally NOT in
# this map. Prod-mode writes now escalate through the pinned infra-config-install
# helper (the deploy user cannot write root:root dirs directly), and letting that
# helper write a sudoers file would be an unbounded privilege escalation (a deploy
# user invoking it directly could install `NOPASSWD: ALL`; visudo validates syntax
# only, not policy). The sudoers grant is therefore managed root-only — delivered
# by terraform_data.infra_config_handler_bootstrap (root SSH) + cloud-init
# write_files — never via this webhook handler. See the security review on #4827.
FILE_MAP=(
  "CI_DEPLOY_SH_B64|/usr/local/bin/ci-deploy.sh|755|root:root"
  "CI_DEPLOY_WRAPPER_SH_B64|/usr/local/bin/ci-deploy-wrapper.sh|755|root:root"
  "WEBHOOK_SERVICE_B64|/etc/systemd/system/webhook.service|644|root:root"
  "CAT_DEPLOY_STATE_SH_B64|/usr/local/bin/cat-deploy-state.sh|755|root:root"
  "CANARY_BUNDLE_CLAIM_CHECK_SH_B64|/usr/local/bin/canary-bundle-claim-check.sh|755|root:root"
  "HOOKS_JSON_B64|/etc/webhook/hooks.json|640|root:deploy"
  "CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root"
  "INNGEST_ENUMERATE_REMINDERS_SH_B64|/usr/local/bin/inngest-enumerate-reminders.sh|755|root:root"
  "INNGEST_REARM_REMINDERS_SH_B64|/usr/local/bin/inngest-rearm-reminders.sh|755|root:root"
  "INNGEST_WIPED_VOLUME_VERIFY_SH_B64|/usr/local/bin/inngest-wiped-volume-verify.sh|755|root:root"
  "CAT_INNGEST_VERIFY_STATE_SH_B64|/usr/local/bin/cat-inngest-verify-state.sh|755|root:root"
  "INNGEST_INVENTORY_SH_B64|/usr/local/bin/inngest-inventory.sh|755|root:root"
  "GIT_LOCK_CHARDEVICE_SWEEP_SH_B64|/usr/local/bin/git-lock-chardevice-sweep.sh|755|root:root"
  "INNGEST_REGISTRY_PROBE_SH_B64|/usr/local/bin/inngest-registry-probe.sh|755|root:root"
  "INNGEST_DOUBLEFIRE_PROBE_SH_B64|/usr/local/bin/inngest-doublefire-probe.sh|755|root:root"
)

# TEST_DESTDIR allows tests to redirect writes to a sandbox
DESTDIR="${TEST_DESTDIR:-}"

# Prod-mode escalation (#4827): the handler runs as User=deploy but the 15 managed
# files live in root:root 0755 dirs the deploy user cannot mktemp into (EACCES).
# In prod mode (DESTDIR empty) we stage each decoded payload in a deploy-writable
# dir, then escalate the atomic install to root via the pinned sudoers helper
# (Cmnd_Alias INFRA_CONFIG_INSTALL). In test mode (DESTDIR set) the sandbox dest
# dirs ARE writable, so the legacy in-dest mktemp + mv path runs unchanged.
#   STAGING_DIR  — deploy-writable, in webhook.service ReadWritePaths (/var/lock).
#   INSTALL_HELPER — the root-run escalation helper (delivered via cloud-init +
#                    the SSH handler-bootstrap bridge; NOT in the webhook FILE_MAP
#                    to avoid the helper-can't-deliver-itself paradox + count churn).
STAGING_DIR="${INFRA_CONFIG_STAGING_DIR:-/var/lock}"
INSTALL_HELPER="${INFRA_CONFIG_INSTALL_HELPER:-/usr/local/bin/infra-config-install}"

# State file for observability (#4554). Queryable via /hooks/infra-config-status.
STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"
START_TS=$(date +%s)

# Clear stale sentinel from prior run (same pattern as ci-deploy.sh:105)
rm -f "${STATE_FILE}.final"

# EXIT trap: on non-zero exit without a .final sentinel, write "unhandled" state.
# Also cleans up temp files and the sentinel. files_total:0 is a "no-accounting"
# sentinel (the trap fires before/independent of the write loop and before
# TOTAL_COUNT is set); it pairs with files_written:0/files_failed:0 and is
# harmless to the CI gate, which fails on the non-zero exit_code first.
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
# mapping. Per-file accounting lets the 15 good files (crucially the new
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

  logger -t "$LOG_TAG" "writing: $dest_path"

  # Stage the payload.
  #  - test mode (DESTDIR set): stage IN the sandbox dest dir; same-fs mv is atomic
  #    and the sandbox dirs are writable (legacy path, unchanged).
  #  - prod mode (DESTDIR empty): stage in the deploy-writable STAGING_DIR; the
  #    root helper re-stages into the (root-owned) dest dir and does the atomic
  #    rename there, so the deploy user never has to write a root-owned dir (#4827).
  if [[ -n "$DESTDIR" ]]; then
    stage_dir=$(dirname "$dest")
  else
    stage_dir="$STAGING_DIR"
  fi

  # #6178: the payload arrives as a FILE (pass-file-to-command + base64decode in
  # hooks.json.tmpl), NOT a base64 string in the environment — the exec env has a
  # 128KB per-var ceiling (MAX_ARG_STRLEN) that ci-deploy.sh's ~140KB base64 blew,
  # killing fork/exec with E2BIG. So ${!env_var} now holds the PATH to the already-
  # DECODED payload that webhook wrote; copy it into our own mktemp temp (so the
  # atomic-install + cleanup contract below is unchanged and we never install the
  # webhook temp directly). A missing/unreadable source is a per-file failure.
  tmpfile=$(mktemp "${stage_dir}/tmp.infra-config.XXXXXX")
  TMPFILES+=("$tmpfile")

  if ! cp "${!env_var}" "$tmpfile" 2>/dev/null; then
    logger -t "$LOG_TAG" "FAILED: $dest_path reason=payload_file_unreadable path=${!env_var}"
    echo "ERROR: could not read webhook payload file for $dest_path (env $env_var=${!env_var})" >&2
    [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
    FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"payload_file_unreadable\"}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -f "$tmpfile"
    continue
  fi

  # NOTE (#4827): the former visudo-validation arm for /etc/sudoers.d/* was
  # removed with the sudoers entry — that file is no longer in FILE_MAP (it is
  # root-managed, not webhook-writable; see the FILE_MAP comment above).

  chmod "$mode" "$tmpfile"
  # SHA is computed from the staged temp (content-identical to the installed
  # file) BEFORE the move, so it is available in both modes without re-reading a
  # root-owned dest the deploy user may not be able to stat.
  local_sha=$(sha256sum "$tmpfile" | awk '{print $1}')

  if [[ -n "$DESTDIR" ]]; then
    # Test/sandbox mode: chown skipped (not root), atomic same-fs rename.
    mv -f "$tmpfile" "$dest"
  else
    # Prod mode: escalate the atomic install to root via the pinned helper. The
    # helper validates dest ∈ allowlist + mode/owner against its authoritative
    # table, then mktemps-in-dest + chmod + chown + atomic mv (it runs as root, so
    # no EACCES). The payload is piped over STDIN — NOT passed as a file path — so
    # the deploy-writable staging temp cannot be symlink-swapped between check and
    # use (#4827 security review P1). The `< "$tmpfile"` redirect is opened by THIS
    # (deploy) process before sudo elevates.
    install_rc=0
    sudo "$INSTALL_HELPER" "$dest_path" "$mode" "$owner" < "$tmpfile" 2>/dev/null || install_rc=$?
    rm -f "$tmpfile"
    if [[ "$install_rc" -ne 0 ]]; then
      # rc=3 from the helper means the dest/TOCTOU guard rejected the install;
      # any other non-zero is an install failure (mktemp/cp/chmod/chown/mv/sudo).
      if [[ "$install_rc" -eq 3 ]]; then
        reason="install_rejected"
      else
        reason="install_failed"
      fi
      logger -t "$LOG_TAG" "FAILED: $dest_path reason=$reason rc=$install_rc"
      echo "ERROR: escalated install failed ($reason) for $dest_path" >&2
      [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
      FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"$reason\"}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
  fi

  logger -t "$LOG_TAG" "wrote: $dest_path sha256=$local_sha"
  [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
  FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"$local_sha\",\"status\":\"ok\"}"
  WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
done

logger -t "$LOG_TAG" "complete: $WRITTEN_COUNT/$TOTAL_COUNT files written, $FAIL_COUNT failed"

# --- Orphan-hook self-check (#6178) ---
# A hooks.json execute-command that points at a /usr/local/bin script NOT present on
# disk after this push is a DANGLING HOOK: the webhook (adnanh/webhook) fork/exec's a
# missing file and returns an EMPTY HTTP 500 — silent, fast, and undiagnosable without
# SSH. This exact drift (hooks.json advertised inngest-registry-probe but the script
# was never delivered) fast-500'd the cutover op=verify / op=execute empty-registry
# gate. Cross-check the JUST-WRITTEN hooks.json against on-disk scripts and fail LOUD +
# emit a monitored marker so the drift self-reports at DELIVERY time (before it can
# 500) instead of silently. Only /usr/local/bin/* commands are guarded — the handler
# itself (/usr/local/bin/infra-config-apply.sh) is cloud-init/SSH-bridge delivered, not
# FILE_MAP, but it exists on disk in prod so it passes the on-disk existence check.
hooks_dest="${DESTDIR}/etc/webhook/hooks.json"
if [[ -f "$hooks_dest" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r cmd_path; do
    [[ -n "$cmd_path" ]] || continue
    case "$cmd_path" in /usr/local/bin/*) : ;; *) continue ;; esac
    if [[ ! -e "${DESTDIR}${cmd_path}" ]]; then
      logger -t "$LOG_TAG" "SOLEUR_INFRA_CONFIG_HOOK_ORPHAN dangling_hook_command=$cmd_path reason=script_not_on_disk_after_push"
      echo "ERROR: hooks.json advertises $cmd_path but no script is on disk after this push — webhook exec of this hook would fast-500 (dangling hook)" >&2
      [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
      FILES_JSON+="{\"file\":\"$cmd_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"orphan_hook_command\"}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done < <(jq -r '.[]."execute-command" // empty' "$hooks_dest" 2>/dev/null || true)
fi

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
# Intentionally UNCONDITIONAL on FAIL_COUNT: a partial apply must still
# daemon-reload + self-restart so a freshly-written hooks.json (the chicken-and-egg
# self-heal, #4804) activates and re-aligns the host env-mapping for the next
# apply. A missing_env on a NON-hooks.json file can transiently leave the router
# pointing at a stale/absent target until the next clean apply; the CI verify gate
# catches the partial (files_written != files_total) and the next apply self-heals.
if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]; then
  sync
  systemctl daemon-reload
  logger -t "$LOG_TAG" "scheduling self-restart in 3s"
  # Self-restart: schedule a delayed restart so the HTTP 202 response
  # completes before the webhook binary is killed.
  sudo /usr/bin/systemd-run --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook
fi

exit "$EXIT_CODE"
