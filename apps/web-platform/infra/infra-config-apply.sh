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

# --- No-SSH fatal-error channel (#7220) -----------------------------------------------------
# HOISTED TO THE TOP, deliberately. #7220 measured what the old placement cost: START_TS, the
# state-file resets and the EXIT trap all sat BELOW the RESTART_SETTLE_SECS guard, so an
# `exit 64` there left the PREVIOUS run's frame on disk and the gate certified a stale green for
# an apply that had delivered nothing. Everything required for the handler to REPORT ITS OWN
# DEATH is therefore established before the first line that can die.
#
# What #7220 actually was: `systemctl daemon-reload` (below) runs as User=deploy with no sudoers
# grant. It returned "Interactive authentication required", `set -e` aborted AFTER all 19 files
# were written, and the EXIT trap published a frame of hardcoded zeros. The gate then reported
# `files_total=0` — the exact opposite of what happened — with no line, no command and no rc.
# The handler could fail; it could not say how.
#
# Logger seam (AC14b), adopting the CUTOVER_LOGGER_CMD idiom the inngest cutover-flip script
# already uses for its own no-SSH state channel (grep CUTOVER_LOGGER_CMD). The suite installs a
# PATH shim globally; this seam lets a single arm intercept the fatal channel specifically.
#
# The precedent is cited by MECHANISM, not by filename, on purpose: cutover-inngest-workflow.
# test.sh pins a topology invariant — the cutover-flip assets must appear on OCI/cloud-init
# surfaces and NEVER on a webhook surface like this file — using a bare `grep -qF <filename>`,
# which cannot tell a delivery from a comment. Naming the file here would false-trip it.
LOGGER_CMD="${INFRA_CONFIG_LOGGER_CMD:-logger}"

# State file for observability (#4554). Queryable via /hooks/infra-config-status.
STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"
START_TS=$(date +%s)
# The ERR->EXIT handoff slot. A FILE, not a variable (AC9): a failure inside `$( )` assigns in
# the child, so the parent's EXIT trap would otherwise publish a frame with no attribution —
# while the frame is precisely the transport-independent arm of this channel. Measured on the
# target image's bash 5.2.21: the variable is UNSET in the parent, the file crosses.
FATAL_FILE="${STATE_FILE}.fatal"

# Clear stale sentinels from the prior run (same pattern as ci-deploy.sh:105).
# #7103 R2 3.3 — and the STATE FILE itself, so an apply that dies before writing one reads as
# "no_prior_apply" rather than serving the PREVIOUS apply's frame as if it were current.
#
# Not cosmetic. The gate's poll window is ~18s while two synchronous try-restarts can exceed it,
# and on a handler-only apply (the handler is not in FILE_MAP) no payload byte changes — so a
# stale frame would satisfy both the count and the content invariants and certify a `restarts`
# array produced by an earlier run. That is #6594's latched false-green reproduced inside the
# very mechanism built to end it.
rm -f "${STATE_FILE}.final" "$FATAL_FILE"
rm -f "$STATE_FILE"

TMPFILES=()

# errtrace propagates ERR into functions, command substitutions and subshells. Without it a
# fatal inside `$( )` — where most of this script's probes live — leaves no trace at all.
set -o errtrace

# ERR trap: PURE ASSIGNMENT plus one redirect. No logger, no subshell, no sanitizer, no
# branching. All emission happens in on_exit, which runs only once and only on the real exit.
# That makes a FALSE `SOLEUR_INFRA_CONFIG_FATAL` structurally impossible rather than
# test-verified.
#
# THE SINGLE QUOTES ARE LOAD-BEARING. Double quotes would expand $LINENO and $BASH_COMMAND at
# trap-DEFINITION time, permanently pinning the trap to its own line and its own text — the
# instrument reporting itself as the fault, forever.
#
# Verified on bash 5.2.21 (the ubuntu-24.04 target image, not just the dev box): this does NOT
# fire for `[[ cond ]] && x=y` with a false test, for `v=$(cmd) || v=""`, or for anything under
# `if`/`!` — the idioms this script is built from. Only a genuine unhandled non-zero fires it.
trap 'FATAL_RC=$?; FATAL_LINE=$LINENO; FATAL_CMD=$BASH_COMMAND; printf "%s\n%s\n%s\n" "$FATAL_RC" "$FATAL_LINE" "$FATAL_CMD" > "$FATAL_FILE" 2>/dev/null || true' ERR

# EXIT trap: on non-zero exit without a .final sentinel, publish the "unhandled" frame — now
# carrying WHERE it died, WHAT died, and how much had already landed.
#
# #7103 R2 3.3 — the payload carries schema_version:2 and an EMPTY restarts array. An unhandled
# abort must report itself as UNHANDLED, not trip the gate's restarts contract check; exit_code
# is non-zero here, which is what the gate adjudicates on first.
on_exit() {
  # rc FIRST — every command below overwrites $?.
  local rc=$?
  # DISARM ERR IMMEDIATELY, as the first statement after the capture.
  #
  # MEASURED (bash 5.2.21 and 5.3.9, #7220 AC10): a failing command inside an ARMED EXIT trap
  # both fires ERR and turns `exit 0` into rc=1 — and `trap - ERR` alone suppresses the marker
  # but NOT the status flip. Enriching this trap without the full shape below would turn a
  # GREEN apply RED on the one host that has no SSH runbook: the instrument becoming the
  # outage. Hence all three of: capture-first, disarm here, every statement `|| true`, and the
  # explicit `exit "$rc"` re-pin at the end.
  trap - ERR

  local f_rc=0 f_line=0 f_cmd="" f_cmd_safe=""
  if [[ -f "$FATAL_FILE" ]]; then
    { IFS= read -r f_rc || true; IFS= read -r f_line || true; IFS= read -r f_cmd || true; } < "$FATAL_FILE" || true
  fi
  [[ "$f_rc"   =~ ^[0-9]+$ ]] || f_rc=0
  [[ "$f_line" =~ ^[0-9]+$ ]] || f_line=0
  # An explicit `exit N` (the RESTART_SETTLE_SECS guard below) is not an ERR, but it IS a death
  # the operator must see attributed. Carry the process status when no ERR fired; a clean exit
  # leaves this 0, so the field is still "zeroed when ERR never fired" (AC12).
  [[ "$f_rc" -ne 0 ]] || f_rc="$rc"

  # Same sanitizer as the restart-stderr path below. The charset EXCLUDES '"' and '\', which is
  # what keeps the frame valid JSON BY CONSTRUCTION rather than by escaping — load-bearing,
  # because this string is the only free-form upstream text that reaches the frame.
  f_cmd_safe=$(printf '%s' "$f_cmd" | tr -d '\000-\037' | tr -c 'A-Za-z0-9 ._:/=-' '?' | cut -c1-200) || f_cmd_safe=""

  if [[ "$rc" -ne 0 ]] && [[ ! -f "${STATE_FILE}.final" ]]; then
    # ONE branchless printf: fatal_* are emitted UNCONDITIONALLY (zeroed when ERR never fired),
    # so "valid JSON in both cases" is true by construction rather than by a branch that can rot.
    #
    # The `:-0` defaults are MANDATORY, not defensive. This trap is installed above
    # WRITTEN_COUNT=0, and measured on the target bash: a bare `$WRITTEN_COUNT` under `set -u`
    # makes an abort in that window write NO FRAME AT ALL — which cat-infra-config-state.sh
    # reports as `no_prior_apply`, i.e. "the handler never ran". The instrument would erase
    # exactly the death it exists to report.
    printf '{"schema_version":2,"start_ts":%d,"end_ts":%d,"exit_code":%d,"reason":"unhandled","files_written":%d,"files_failed":%d,"files_total":%d,"fatal_rc":%d,"fatal_line":%d,"fatal_cmd":"%s","files":[],"restarts":[]}\n' \
      "$START_TS" "$(date +%s)" "$rc" \
      "${WRITTEN_COUNT:-0}" "${FAIL_COUNT:-0}" "${TOTAL_COUNT:-0}" \
      "$f_rc" "$f_line" "$f_cmd_safe" > "$STATE_FILE" 2>/dev/null || true
  fi

  # The journald arm of the same fact. Dual-channel on purpose: the frame needs the status
  # endpoint to be reachable, journald->Vector->Better Stack does not.
  if [[ "$rc" -ne 0 ]]; then
    "$LOGGER_CMD" -t "$LOG_TAG" "SOLEUR_INFRA_CONFIG_FATAL: line=$f_line rc=$f_rc files_written=${WRITTEN_COUNT:-0} files_total=${TOTAL_COUNT:-0} cmd=$f_cmd_safe" 2>/dev/null || true
  fi

  rm -f "${TMPFILES[@]}" "${STATE_FILE}.final" "$FATAL_FILE" 2>/dev/null || true
  # Re-pin the ORIGINAL status. Without this the trap's own work decides the exit code.
  exit "$rc"
}
trap on_exit EXIT

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
  # #7095 — 640 root:deploy, DELIBERATELY different from the existing
  # /etc/default/webhook-deploy (600 deploy:deploy). webhook.service runs as User=deploy and
  # vector.service reads the same file, so the credential needs GROUP read; root ownership
  # keeps the deploy user from rewriting its own credential source. Not a copy-paste slip.
  "SOLEUR_DOPPLER_TOKEN_B64|/etc/default/soleur-doppler-token|640|root:deploy"
  # #7095 — systemd drop-ins re-pointing the two GENERATED units (vector.service from
  # soleur-host-bootstrap.sh:721-738, inngest-heartbeat.service from inngest-bootstrap.sh:315)
  # at the re-deliverable credential. Their unit bodies are heredocs baked into the image, so
  # nothing re-renders them on a running host; a drop-in is the only delivery path, and systemd
  # merges drop-ins AFTER the main unit so EnvironmentFile later-wins applies. Distinct basenames
  # are REQUIRED: infra_config_classify_files keys the repo lookup on basename(dest), so two
  # drop-ins both named 10-doppler-token.conf would collide on one repo file.
  "VECTOR_DOPPLER_TOKEN_CONF_B64|/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf|644|root:root"
  "INNGEST_HEARTBEAT_DOPPLER_TOKEN_CONF_B64|/etc/systemd/system/inngest-heartbeat.service.d/10-inngest-heartbeat-doppler-token.conf|644|root:root"
  # #7095 review — inngest-server runs `doppler run` UNCONDITIONALLY (no [ -n $DOPPLER_TOKEN ]
  # gate) with Restart=on-failure, and inngest-bootstrap.sh restarts it on EVERY co-located
  # ci-deploy. Without this it crash-loops on the next deploy after the fix lands.
  "INNGEST_SERVER_DOPPLER_TOKEN_CONF_B64|/etc/systemd/system/inngest-server.service.d/10-inngest-server-doppler-token.conf|644|root:root"
)

# TEST_DESTDIR allows tests to redirect writes to a sandbox
DESTDIR="${TEST_DESTDIR:-}"

# Prod-mode escalation (#4827): the handler runs as User=deploy but the managed
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

# --- Unit reconciliation (#7103 R2) -------------------------------------------------------
# DELIVERY IS NOT ACTIVATION. The drop-ins below re-point their units at the re-deliverable
# credential, but systemd only reads a drop-in when the unit is (re)started. Before this, the
# handler wrote them, reported ok, and the running processes kept the environment they were
# started with — a channel reporting a state it had not established.
#
# Ordering is load-bearing: vector.service is LAST because restarting it blinks the log stream
# every post-apply assertion is read through.
#
# inngest-server.service also carries a drop-in but is deliberately ABSENT here: inngest-bootstrap
# restarts it on every co-located ci-deploy, so it already re-reads its environment on a schedule
# this handler does not need to duplicate. Its omission is a decision, not an oversight — and the
# sudoers grant covers exactly the unit below, so adding a second here without widening the
# grant would produce denied restarts rather than coverage.
#
# inngest-heartbeat.service is ALSO absent, and that is a correction rather than an omission.
# It was in this map when the contract first shipped. It is a `Type=oneshot` with NO
# `RemainAfterExit` anywhere in inngest-bootstrap.sh, driven by a 60s timer around a sub-second
# ExecStart — so it reads `inactive` on essentially every apply. Three consequences, all bad and
# none hypothetical: the entry graded `skipped/unit_inactive` forever, making the gate's warning
# arm the STEADY STATE on a correct host rather than an edge case (the alert fatigue #7103 B3
# names); the grant bought nothing, because a timer-driven oneshot re-reads its drop-in on its
# next tick after the `daemon-reload` this handler already performs; and an apply landing inside
# the heartbeat's brief active window could try-restart it, find it exited two seconds later, and
# grade `noop_not_active` — a spurious HARD RED on the sole no-SSH remediation path.
# Dropping it also retires one root-restart grant on the host that cannot be replaced, which is
# the direction ADR-159 argues for: do not widen the surface to buy nothing.
RESTART_MAP=(
  "vector.service|/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf"
)

# The credential every unit above depends on. A rotation of THIS file makes a unit stale just as
# surely as a change to its own drop-in, which is why the predicate takes the max of both — it
# also heals a rotation that predates this code.
CRED_FILE="/etc/default/soleur-doppler-token"

# Test seams (#7103 R2 3.10). Two, not one, because they are different privilege domains:
#   READ  — `systemctl show` needs no root, and routing it through sudo would be DENIED (the
#           DROPIN_TRY_RESTART grant pins `try-restart` only), turning every read into a failure.
#   WRITE — must expand to the exact argv the sudoers alias grants. sudo matches the full
#           resolved command, so a stray flag here is a denial, not a widening.
# The seam exists so the predicate, the grading and the ordering all run UNGUARDED in sandbox
# mode. Gating them behind INFRA_CONFIG_TEST_MODE instead would mean the assertions covering
# this logic assert behaviour that never executes in the test run.
SYSTEMCTL_SHOW="${INFRA_CONFIG_SYSTEMCTL_SHOW:-/usr/bin/systemctl}"
SYSTEMCTL_RESTART="${INFRA_CONFIG_SYSTEMCTL:-sudo /usr/bin/systemctl}"

# Seconds to wait before grading a restart by effect. try-restart returns as soon as the unit is
# forked, so reading ActiveState immediately would grade a process that has not yet lived long
# enough to fail. Overridable so the suite does not pay it.
RESTART_SETTLE_SECS="${INFRA_CONFIG_RESTART_SETTLE_SECS:-2}"
# VALIDATED, because an unvalidated value here is a deterministic prod freeze, not a footgun.
# `sleep abc` exits 1; under this script's `set -euo pipefail` that kills the handler MID-LOOP,
# the EXIT trap overwrites the state with files_total:0/"unhandled", and the post-write
# daemon-reload + webhook self-restart never run — freshly-delivered hooks.json written but never
# activated. Measured on the unmodified script with INFRA_CONFIG_RESTART_SETTLE_SECS=abc: 19 of 19
# files on disk, frame reported "files_total":0 "reason":"unhandled", webhook restart NEVER RAN.
# That is the #4804 chicken-and-egg freeze, deterministic, on the host with no SSH runbook.
# Reachable in practice: webhook.service carries EnvironmentFile=/etc/default/webhook-deploy and
# the handler inherits it wholesale, so any render or operator write of a non-numeric value bricks
# the delivery channel. Fail LOUD and early here rather than mid-loop.
if [[ ! "$RESTART_SETTLE_SECS" =~ ^[0-9]+$ ]]; then
  logger -t "$LOG_TAG" "SOLEUR_INFRA_CONFIG_CONFIG_INVALID: var=INFRA_CONFIG_RESTART_SETTLE_SECS reason=not_a_non_negative_integer"
  echo "FATAL: INFRA_CONFIG_RESTART_SETTLE_SECS must be a non-negative integer" >&2
  exit 64
fi

# mtime in epoch seconds, or 0. GUARDED: `stat` on an absent dest exits 1, and under this
# script's `set -euo pipefail` that would kill the handler MID-LOOP — the EXIT trap would then
# overwrite the state with files_total:0/"unhandled" and the post-write daemon-reload and webhook
# self-restart would never run, freshly-delivered hooks.json written but never activated. That is
# the #4804 chicken-and-egg freeze re-entered, and it would be deterministic rather than rare.
dest_mtime() {
  local p="$1" m=""
  m=$(stat -c %Y "$p" 2>/dev/null) || m=""
  [[ "$m" =~ ^[0-9]+$ ]] || m=0
  printf '%s' "$m"
}

# One systemd property. Prints the value and returns 0 when the PROBE ITSELF succeeded;
# returns 1 when it did not.
#
# The distinction is the whole point. This previously returned "" on any failure, and the caller
# mapped "" to `unit_inactive` — so a missing systemctl, an unreachable D-Bus, or EPERM inside
# webhook.service's namespace all rendered as "the unit is not running", which the gate treats as
# a WARNING and passes. That is an instrument failure being graded as a measurement: the run then
# certifies activation having reconciled nothing, which is the exact false-green this contract
# exists to end. `systemctl show` exits 0 and prints empty for an ABSENT unit, so rc is a genuine
# discriminator between "I asked and the answer is nothing" and "I could not ask".
unit_prop() {
  local unit="$1" prop="$2" v=""
  v=$($SYSTEMCTL_SHOW show "$unit" -p "$prop" --value 2>/dev/null) || return 1
  printf '%s' "$v"
}

# ExecMainStartTimestamp -> epoch seconds.
#   ""          -> ""   (no timestamp; an inactive unit has none — the caller has already
#                        short-circuited on ActiveState, so this is belt-and-braces)
#   unparseable -> "x"  (a NON-EMPTY value date cannot read; a distinct, reportable fault)
# Treating empty as "unparseable ⇒ stale" would build a loop that never self-disarms while
# reporting success, which is why the two are kept apart.
ts_epoch() {
  local raw="$1" e=""
  [[ -n "$raw" ]] || { printf ''; return 0; }
  e=$(date -d "$raw" +%s 2>/dev/null) || e=""
  [[ "$e" =~ ^[0-9]+$ ]] || { printf 'x'; return 0; }
  printf '%s' "$e"
}

# NOTE: env vars are validated PER FILE inside the write loop below (missing_env
# arm), NOT upfront. The former upfront all-or-nothing `exit 1` caused the
# chicken-and-egg freeze (#4804): when a new file was added to FILE_MAP +
# hooks.json env-passing atomically, the host's stale hooks.json could not pass
# the new key, leaving its env var empty — and the upfront gate then aborted the
# ENTIRE write, including the new hooks.json that would have re-aligned the
# mapping. Per-file accounting lets the remaining good files (crucially the new
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
    # #7095 — sandbox mode stages directly INTO the dest dir, so a dest whose parent does not
    # exist yet (a systemd drop-in .d/ directory) fails at mktemp below. Prod mode does not need
    # this: it stages in $STAGING_DIR (which exists) and the root helper creates the real dest
    # dir itself. Mirroring it here keeps the sandbox path faithful to prod rather than making
    # drop-in dests untestable.
    mkdir -p "$stage_dir" 2>/dev/null || true
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

  # #7103 R2 3.4 — derive `changed`; the WRITE ITSELF STAYS UNCONDITIONAL.
  #
  # Making the write content-conditional would silently drop the per-apply re-assertion of
  # 640 root:deploy on the credential: a dest whose DAC drifted (world-readable, or root:root
  # breaking vector's group read) still matches on CONTENT, so it would be skipped, reported
  # changed:false — and the state JSON would still say ok. The one channel able to repair it
  # would have stopped repairing it. So every entry is installed on every apply exactly as
  # before, and `changed` is a derived observation, never a gate.
  #
  # Its one behavioural use is the mtime preservation below: a content-identical rewrite that
  # bumped mtime would make the staleness predicate fire on every apply forever, restarting
  # units that are not stale — clause-equivalent over-firing.
  #
  # sha256sum ONLY. Never diff/cmp -l/od on a FILE_MAP dest: a diff of
  # /etc/default/soleur-doppler-token prints the prd token into journald, which vector ships to
  # Better Stack. The comparison must not be able to echo the bytes it compares.
  changed="true"
  if [[ -L "$dest" ]]; then
    # lstat guard: a symlinked dest is treated as changed and never followed or read through.
    changed="true"
  elif [[ -f "$dest" ]]; then
    existing_sha=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}') || existing_sha=""
    if [[ -n "$existing_sha" && "$existing_sha" == "$local_sha" ]]; then
      changed="false"
      touch -r "$dest" "$tmpfile" 2>/dev/null || true
    fi
  fi

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
  FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"$local_sha\",\"status\":\"ok\",\"changed\":$changed}"
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

# --- Activate what was delivered (#7103 R2 3.3/3.5/3.6/3.7) --------------------------------
# ORDER: this whole block runs BEFORE the state write, because reconciliation must happen after
# daemon-reload but be REPORTED in the state JSON. Previously the state was written first and
# sync/daemon-reload ran afterwards; a restart decided after the frame was published could never
# appear in it.
#
# sync + daemon-reload stay behind INFRA_CONFIG_TEST_MODE (they need a real host). The
# reconciliation loop does NOT — it runs through the seams in sandbox mode so the predicate,
# the grading and the ordering are actually exercised by the suite rather than gated out of it.
if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]; then
  sync
  systemctl daemon-reload
fi

RESTARTS_JSON=""
for restart_entry in "${RESTART_MAP[@]}"; do
  IFS='|' read -r r_unit r_dropin <<< "$restart_entry"
  r_action="skipped"; r_reason=""; r_rc=0
  r_ts_before=0; r_ts_after=0; r_nrestarts=0; r_active=""

  # --- ActiveState FIRST. An inactive unit is skipped with NO attempt made. ---
  # ExecMainStartTimestamp is empty for an inactive unit, so treating empty as
  # "unparseable ⇒ stale" would build a loop that restarts forever while reporting success.
  # try-restart is also a deliberate no-op on an inactive unit, so attempting it would produce
  # rc=0 and grade as a successful restart that never happened.
  #
  # Every unit_prop call is rc-guarded: it now returns 1 when the PROBE failed, and an unguarded
  # `x=$(unit_prop …)` under `set -euo pipefail` would abort the handler mid-loop — the same
  # class as the RESTART_SETTLE_SECS freeze guarded above.
  r_probe_ok=1
  r_active=$(unit_prop "$r_unit" ActiveState) || r_probe_ok=0
  if [[ "$r_probe_ok" -eq 0 ]]; then
    # COULD NOT MEASURE is its own outcome, and it fails the gate. Folding it into
    # `unit_inactive` is what let an instrument failure certify an apply as green.
    r_action="failed"; r_reason="probe_unavailable"; r_active=""
  elif [[ "$r_active" != "active" ]]; then
    # rc=0 with an empty value means systemd has no such unit loaded; rc=0 with a non-active
    # state means it is loaded and not running. Both are legitimate on a co-location-dependent
    # host, but they are different facts and the frame now carries which one.
    r_action="skipped"
    if [[ -z "$r_active" ]]; then r_reason="unit_absent"; else r_reason="unit_inactive"; fi
  else
    r_probe_ok=1
    r_raw_before=$(unit_prop "$r_unit" ExecMainStartTimestamp) || r_probe_ok=0
    r_e_before=$(ts_epoch "$r_raw_before")
    if [[ "$r_probe_ok" -eq 0 ]]; then
      r_action="failed"; r_reason="probe_unavailable"
    elif [[ -z "$r_e_before" ]]; then
      # ACTIVE but carrying no start timestamp — a Type=oneshot in `active (exited)`, or a unit
      # whose main process is gone. ts_epoch deliberately separates this from unparseable, and
      # the caller used to discard that separation one line later. Kept apart, and both fail:
      # neither is a state in which a staleness comparison means anything.
      r_action="failed"; r_reason="timestamp_absent"
    elif [[ "$r_e_before" == "x" ]]; then
      # Reserved for a NON-EMPTY value date could not read. Reported, never guessed at.
      r_action="failed"; r_reason="timestamp_unparseable"
    else
      r_ts_before="$r_e_before"
      # --- The single staleness predicate ---
      #   stale := the running process started BEFORE the newest input it depends on.
      # One clause subsuming what were three OR'd ones, and strictly more correct: it also
      # heals a credential rotation that predates this code.
      r_m_dropin=$(dest_mtime "${DESTDIR}${r_dropin}")
      r_m_cred=$(dest_mtime "${DESTDIR}${CRED_FILE}")
      r_newest="$r_m_dropin"
      [[ "$r_m_cred" -gt "$r_newest" ]] && r_newest="$r_m_cred"

      if [[ "$r_ts_before" -ge "$r_newest" ]]; then
        r_action="skipped"; r_reason="not_stale"; r_ts_after="$r_ts_before"
      else
        r_reason="stale_config"
        # Capture stderr instead of discarding it. `>/dev/null 2>&1` here destroyed the one datum
        # that says WHICH failure this is, at the source — the same mistake this codebase already
        # documents as why WEB-PLATFORM-5B was undiagnosable. Without it, every non-zero rc was
        # reported as `sudo_denied`, so the derived remediation ("repair DROPIN_TRY_RESTART") sent
        # an agent at a grant that server.tf already asserts is present, leaving no next lever
        # short of SSH.
        r_err=$($SYSTEMCTL_RESTART try-restart "$r_unit" 2>&1 >/dev/null) || r_rc=$?
        if [[ "$r_rc" -ne 0 ]]; then
          # try-restart returns non-zero when the restart JOB fails (start error, dependency
          # failure, timeout), not only when sudo refuses. Those are different defects with
          # different owners: a denial is a PROVISIONING defect, a failed job is a state of the
          # unit. #5934: a swallowed sudo denial is how a remediation becomes a silent no-op.
          r_action="failed"
          case "$r_err" in
            *"a password is required"*|*"not allowed to execute"*|*"may not run"*|*"is not in the sudoers file"*)
              r_reason="sudo_denied" ;;
            *)
              r_reason="restart_invocation_failed" ;;
          esac
          # Sanitized separately from the closed-vocabulary marker below, which must stay a fixed
          # alphabet: this line carries free upstream text and so is scrubbed to a safe charset
          # and truncated before it reaches journald and the off-box sink.
          r_err_safe=$(printf '%s' "$r_err" | tr -d '\000-\037' | tr -c 'A-Za-z0-9 ._:/=-' '?' | cut -c1-200)
          logger -t "$LOG_TAG" "SOLEUR_INFRA_CONFIG_RESTART_STDERR: unit=$r_unit rc=$r_rc detail=$r_err_safe"
          r_active=$(unit_prop "$r_unit" ActiveState) || r_active=""
        else
          # --- GRADE ON EFFECT, NOT ON EXIT CODE ---
          # try-restart exits 0 on a FAILED unit (it is defined as a no-op there), and on a
          # Type=simple unit a 0 means "forked", not "running". So re-read and require both
          # active AND an advanced start timestamp before calling this a restart.
          # DropInPaths is deliberately NOT an input: daemon-reload refreshes systemd's
          # in-memory view, so it lists the new drop-in even though the process never re-exec'd.
          [[ "$RESTART_SETTLE_SECS" == "0" ]] || sleep "$RESTART_SETTLE_SECS"
          # Each probe rc-guarded, and each `[[ … ]] && x=y` given an explicit `|| true`: a
          # non-matching test is the LAST command of that compound, so it returns 1 and `set -e`
          # would abort the handler here — after the restart fired but before the frame records
          # it, which is the worst possible point to die.
          r_post_ok=1
          r_active=$(unit_prop "$r_unit" ActiveState) || r_post_ok=0
          r_raw_after=$(unit_prop "$r_unit" ExecMainStartTimestamp) || r_post_ok=0
          r_e_after=$(ts_epoch "$r_raw_after")
          [[ "$r_e_after" =~ ^[0-9]+$ ]] && r_ts_after="$r_e_after" || true
          r_n=$(unit_prop "$r_unit" NRestarts) || r_post_ok=0
          [[ "$r_n" =~ ^[0-9]+$ ]] && r_nrestarts="$r_n" || true

          if [[ "$r_post_ok" -eq 0 ]]; then
            # The restart was ISSUED and we cannot read whether it took. That is not success.
            r_action="failed"; r_reason="probe_unavailable"
          elif [[ "$r_active" != "active" ]]; then
            r_action="failed"; r_reason="noop_not_active"
          elif [[ "$r_ts_after" -le "$r_ts_before" ]]; then
            r_action="failed"; r_reason="restart_did_not_advance"
          else
            r_action="restarted"; r_reason="stale_config"
          fi
        fi
      fi
    fi
  fi

  # Closed vocabulary, epoch seconds, no host paths. exec_main_start_ts_* is both what the
  # grading above needs and what the post-apply follow-through probe reads.
  logger -t "$LOG_TAG" "SOLEUR_INFRA_CONFIG_RESTART: unit=$r_unit action=$r_action reason=$r_reason rc=$r_rc active=$r_active"
  [[ -n "$RESTARTS_JSON" ]] && RESTARTS_JSON+=","
  RESTARTS_JSON+="{\"unit\":\"$r_unit\",\"action\":\"$r_action\",\"reason\":\"$r_reason\",\"rc\":$r_rc,\"active\":\"$r_active\",\"nrestarts\":$r_nrestarts,\"exec_main_start_ts_before\":$r_ts_before,\"exec_main_start_ts_after\":$r_ts_after}"
done

# --- Write state file (before self-restart) ---
END_TS=$(date +%s)
EXIT_CODE=0
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  EXIT_CODE=1
fi

# NOTE (#7220 A5): the `.final` sentinel is touched AFTER a successful `mv`, not here. It is the
# EXIT trap's "a real frame was published, do not overwrite it" flag, so touching it before the
# publish made "completed, but the frame never landed" indistinguishable from "never ran" —
# the trap saw the sentinel and stayed silent about a failure it could have described.
state_tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || {
  logger -t "$LOG_TAG" "write_state: mktemp failed for STATE_FILE=$STATE_FILE"
  state_tmp=""
}
if [[ -n "${state_tmp:-}" ]]; then
  # #7220 AC12 — fatal_rc/fatal_line/fatal_cmd are emitted UNCONDITIONALLY, by BOTH frame
  # writers, zeroed here because reaching this line means no ERR fired. Schema parity between
  # the success path and the EXIT-trap path is the point: a consumer that has to ask WHICH
  # writer produced a frame before it knows which keys exist is a second source of truth, and
  # the gate's fatal-mode branch keys on exactly these fields.
  printf '{"schema_version":2,"start_ts":%d,"end_ts":%d,"exit_code":%d,"files_written":%d,"files_failed":%d,"files_total":%d,"fatal_rc":0,"fatal_line":0,"fatal_cmd":"","files":[%s],"restarts":[%s]}\n' \
    "$START_TS" "$END_TS" "$EXIT_CODE" "$WRITTEN_COUNT" "$FAIL_COUNT" "$TOTAL_COUNT" "$FILES_JSON" "$RESTARTS_JSON" \
    > "$state_tmp" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: printf/redirect failed"
    rm -f "$state_tmp"
    state_tmp=""
  }
fi
if [[ -n "${state_tmp:-}" ]]; then
  if mv "$state_tmp" "$STATE_FILE" 2>/dev/null; then
    # #7220 A5 — the publish SUCCEEDED, so now the frame on disk is authoritative and the EXIT
    # trap must not clobber it. Any earlier and the sentinel is a claim about a write that had
    # not happened yet.
    touch "${STATE_FILE}.final"
  else
    logger -t "$LOG_TAG" "write_state: mv failed"
    rm -f "$state_tmp"
  fi
fi

# --- Post-write self-restart (skip in test mode) ---
# Only the DELAYED webhook self-restart lives after the state write now; sync, daemon-reload and
# unit reconciliation moved above it (#7103 R2 3.3) so their outcome can appear in the frame.
#
# Intentionally UNCONDITIONAL on FAIL_COUNT: a partial apply must still self-restart so a
# freshly-written hooks.json (the chicken-and-egg self-heal, #4804) activates and re-aligns the
# host env-mapping for the next apply. A missing_env on a NON-hooks.json file can transiently
# leave the router pointing at a stale/absent target until the next clean apply; the CI verify
# gate catches the partial (files_written != files_total) and the next apply self-heals.
#
# It stays LAST because it kills the process serving this request: anything sequenced after it
# is not guaranteed to run.
if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]; then
  logger -t "$LOG_TAG" "scheduling self-restart in 3s"
  # Self-restart: schedule a delayed restart so the HTTP 202 response
  # completes before the webhook binary is killed.
  sudo /usr/bin/systemd-run --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook
fi

exit "$EXIT_CODE"
