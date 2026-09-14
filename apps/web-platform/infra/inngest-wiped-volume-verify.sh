#!/usr/bin/env bash
# inngest-wiped-volume-verify.sh — OPT-IN, emptiness-gated, destructive
# end-to-end durability proof for the cutover (#5450, AC3/B1/F2/P2-sec-b).
#
# NOT a default cutover step. The DEFAULT verify is the existing non-destructive
# verify_inngest_health HARD gate that runs on every deploy (ci-deploy.sh) plus
# the Phase-0 spike-0.2 evidence (durable Redis survived a wiped-volume restart).
# This script is the explicit opt-in proof for an operator who wants the
# end-to-end durability invariant exercised in prod shape: arm a throwaway future
# reminder, WIPE the local inngest volume, restart, and confirm the reminder
# still fires (durability is in Postgres+Redis, not the wiped /var/lib/inngest).
#
# Runs ON THE HOST (delivered via the infra-config push, invoked through the
# /hooks/inngest-wiped-volume-verify POST hook, async 202 + the
# /hooks/inngest-verify-status responder).
#
# SAFETY GATES (in order; any failing aborts BEFORE any destructive action):
#   1. Emptiness gate (B1 — the REAL safety gate): run the enumeration; if ANY
#      non-throwaway armed reminder is present, ABORT LOUD. A wipe with a real
#      armed reminder present could destroy the operator's pending action. This
#      is the gate that matters — NOT the durable-sentinel check, which ALWAYS passes
#      post-#5459 and protects nothing.
#   2. Durable-backend sanity (secondary): the running ExecStart must carry the
#      non-secret --postgres-max-open-conns durable sentinel (#5560 — postgres/redis
#      URIs are env-delivered now, never argv). A wipe of a SQLite-only backend
#      destroys real state. This is a belt-and-suspenders assert, not the primary gate.
#   3. Not quiesced (#6921/#8077): a unit stopped+disabled by op=quiesce-web is refused
#      (reason quiesced_refused) — this script's `start` would re-arm the stopped scheduler.
#
# THROWAWAY MARKER (P2-sec-b): an UNREGISTERED `named-check` (check name
# `__cutover-verify-noop__`). The handler accepts it (route validates only that
# `check` is a non-empty string) but rejects it at CHECK_REGISTRY lookup BEFORE
# any octokit call — so it produces a terminal run (proving post-wipe delivery)
# while posting ZERO comments to ANY real issue. report_to_issue is a sentinel
# that is never reached (the unregistered-check reject returns first).
#
# Test seams: INNGEST_ENUMERATE_CMD, INNGEST_DATA_DIR, INNGEST_VERIFY_EXECSTART,
# INNGEST_VERIFY_MARKER_ID, INNGEST_VERIFY_STATE, INNGEST_VERIFY_SETTLE_SECS,
# INNGEST_MANUAL_TRIGGER_SECRET; mock curl/systemctl/sudo on PATH.
set -euo pipefail
# xtrace refusal (#7797): this script binds a live credential (the Doppler token and the
# INNGEST_MANUAL_TRIGGER_SECRET Bearer) and -x would print it to the webhook's journald stream.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

readonly LOG_TAG="inngest-wiped-volume-verify"

# --- #7095 re-read for a webhook-executed script -------------------------------------------
# webhook.service still exports the /etc/default/webhook-deploy DOPPLER_TOKEN, revoked
# 2026-07-30T11:19:30Z; the fresh credential is re-delivered by terraform apply at
# /etc/default/soleur-doppler-token (server.tf "WHY THIS FILE EXISTS"). #7095 re-pointed
# ci-deploy.sh (the only other doppler-reading hook target, via its parsed CRED_FILE_STATE
# block) and four long-running units via EnvironmentFile=- drop-ins; infra-config-apply.sh
# DELIVERS the file and never reads Doppler. This script kept reading Doppler on the dead
# token, so every read failed 401 into `2>/dev/null` and the fail-closed branch fired with no
# reason logged (found live 2026-09-13: op=execute cleared 2.0 for the first time and died
# at 2.1 capture).
#
# PARSED, NOT SOURCED — the file's values are terraform-interpolated and this runs as `deploy`,
# which holds NOPASSWD sudo on the installers; `. file` would hand `$(...)` to bash. Four keys
# are taken (the token plus the three baked Sentry DSN components the same file carries, so a
# read failure can page), later-wins over the unit's export, and an EMPTY value is skipped so a
# bare `KEY=` (which the installer's shape check accepts) cannot blank a working one. The
# `|| [[ -n "$k" ]]` keeps a final line without a trailing newline (ci-deploy.sh drops it).
# Every function in this block MUST stay byte-identical to the copy in the sibling webhook
# script — webhook-doppler-token-reread.test.sh pins that, because a helper re-derived per
# file drifts. `SOLEUR_CRED_FILE_STATE` records present|unreadable|absent for the log line.
SOLEUR_CRED_FILE_STATE=absent
SOLEUR_CRED_TOKEN_APPLIED=0
soleur_refresh_doppler_token() {
  local f="${SOLEUR_DOPPLER_TOKEN_FILE:-/etc/default/soleur-doppler-token}" k v
  if [[ -r "$f" ]]; then SOLEUR_CRED_FILE_STATE=present; elif [[ -e "$f" ]]; then SOLEUR_CRED_FILE_STATE=unreadable; return 0; else SOLEUR_CRED_FILE_STATE=absent; return 0; fi
  # `|| return 0` on the loop: a redirect that fails AFTER -r passed (LSM denial, race) must not
  # abort the enclosing `$(read_secret)` before the reason line is emitted.
  while IFS='=' read -r k v || [[ -n "$k" ]]; do
    v="${v%$'\r'}"
    case "$k" in
      DOPPLER_TOKEN)
        # Applied only when it has the shape server.tf's plan-time gate admits (dp.<family>.<body>);
        # a quoted value, an `export `-prefixed line or a CRLF-only `KEY=` leaves the unit's export
        # standing and is reported as token_file=present token_applied=0 — a file-shape defect.
        if [[ "$v" =~ ^dp\.[a-z]{2,}\.[A-Za-z0-9._-]+$ ]]; then export DOPPLER_TOKEN="$v"; SOLEUR_CRED_TOKEN_APPLIED=1; fi ;;
      SENTRY_INGEST_DOMAIN|SENTRY_PROJECT_ID|SENTRY_PUBLIC_KEY)
        # Whitespace-only counts as EMPTY (a CRLF-terminated `KEY=` yields $'\r', which `-n` accepts).
        if [[ -n "${v//[[:space:]]/}" ]]; then printf -v "$k" '%s' "$v"; export "${k?}"; fi ;;
    esac
  done < "$f" 2>/dev/null || return 0
  return 0
}

# Classify a failed/empty Doppler read into a closed vocabulary. The real CLI prints its cause
# LAST (`Unable to fetch secrets` then `Doppler Error: …`, coloured, behind two `Using
# DOPPLER_* from the environment` notices under this unit), so the head line is a constant.
soleur_doppler_read_class() {
  local rc="$1" errfile="$2" out="$3"
  if [[ "$rc" == 127 ]]; then printf 'binary_absent'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qa 'Invalid Auth token' "$errfile"; then printf 'invalid_auth'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qa 'Could not find requested secret' "$errfile"; then printf 'secret_not_found'; return 0; fi
  if [[ -r "$errfile" ]] && LC_ALL=C grep -qaE 'dial tcp|no such host|i/o timeout|TLS handshake|connection refused|Get "https' "$errfile"; then printf 'transport'; return 0; fi
  if [[ "$rc" == 0 && -z "$out" ]]; then printf 'empty_value'; return 0; fi
  printf 'other'
}

# One line to journald (-> Better Stack) AND to stderr (-> the hook's response body -> the
# cutover run log) saying WHY a Doppler read came back empty, so the next reader does not need
# SSH to tell a revoked token from a missing binary. The `Doppler Error:` line if present, else
# the LAST stderr line; control/ANSI bytes stripped in the C locale; credential-shaped tokens
# scrubbed with ci-deploy.sh's `dp\.[a-z]{2,}\.` shape; 160 bytes — never the value. Then a
# Sentry event (class enum only, never stderr) when the three DSN components were read. This
# runs INSIDE `$(read_secret)`, whose stdout IS the secret — so nothing here may write stdout
# (the beacon's curl is `>/dev/null`; a mock curl that printed its status code proved the point).
soleur_log_doppler_read_failure() {
  local rc="$1" errfile="$2" out="${3-}" class why="" payload
  class="$(soleur_doppler_read_class "$rc" "$errfile" "$out")"
  if [[ -r "$errfile" ]]; then
    why="$( { LC_ALL=C grep -a -m1 'Doppler Error:' "$errfile" || tail -n 1 "$errfile"; } 2>/dev/null \
      | LC_ALL=C sed -E 's/\x1b\[[0-9;]*m//g' \
      | LC_ALL=C tr -c '[:print:]' ' ' \
      | LC_ALL=C tr '"' "'" \
      | LC_ALL=C sed -E 's/dp\.[a-z]{2,}\.[A-Za-z0-9._-]+/dp.**.REDACTED/g' \
      | LC_ALL=C cut -c1-160 )" || why=""
  fi
  # token_applied=0 with token_file=present means the file was read but carried no usable
  # DOPPLER_TOKEN (quoted value, `export ` prefix, empty) — a different fix from a revoked one.
  local line="SOLEUR_DEPLOY_CRED_FAIL secret=INNGEST_MANUAL_TRIGGER_SECRET rc=${rc} class=${class} token_file=${SOLEUR_CRED_FILE_STATE} token_applied=${SOLEUR_CRED_TOKEN_APPLIED} err=\"${why:-<empty>}\""
  logger -t "${LOG_TAG:-webhook-script}" "$line" 2>/dev/null || true
  printf 'ERROR: %s\n' "$line" >&2
  # Destination pinned by SHAPE (#7873): the three values are parsed from a root-owned file, but a
  # credentialed request must refuse any host that is not a Sentry ingest domain regardless.
  local dom="${SENTRY_INGEST_DOMAIN:-}" pid="${SENTRY_PROJECT_ID:-}"
  if [[ "$dom" =~ ^[a-z0-9]+\.ingest\.([a-z]{2}\.)?sentry\.io$ && "$pid" =~ ^[0-9]+$ && -n "${SENTRY_PUBLIC_KEY:-}" ]] && command -v jq >/dev/null 2>&1; then
    payload="$(jq -nc --arg logger "${LOG_TAG:-webhook-script}" --arg class "$class" --arg rc "$rc" --arg tf "$SOLEUR_CRED_FILE_STATE" --arg ta "$SOLEUR_CRED_TOKEN_APPLIED" \
      '{message: ("doppler read failed for INNGEST_MANUAL_TRIGGER_SECRET (" + $class + ")"), level: "error", platform: "other", logger: $logger,
        tags: {feature: "inngest-cutover", op: "doppler-read-failed", class: $class},
        extra: {rc: $rc, token_file: $tf, token_applied: $ta}}')" || payload=""
    if [[ -n "$payload" ]]; then
      curl --disable --noproxy '*' -s -o /dev/null --max-time 10 -X POST \
        "https://${dom}/api/${pid}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
        -d "$payload" >/dev/null 2>&1 || true
    fi
  fi
}
readonly MARKER_PREFIX="__wiped-volume-verify-"
readonly NOOP_CHECK="__cutover-verify-noop__"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENUMERATE_CMD="${INNGEST_ENUMERATE_CMD:-${SCRIPT_DIR}/inngest-enumerate-reminders.sh}"
DATA_DIR="${INNGEST_DATA_DIR:-/var/lib/inngest}"
STATE_FILE="${INNGEST_VERIFY_STATE:-/var/lock/inngest-wiped-volume-verify.state}"
HEALTH_URL="${INNGEST_HEALTH_URL:-http://127.0.0.1:8288/health}"
GQL_URL="${INNGEST_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
REARM_URL="${SCHEDULE_REMINDER_URL:-http://127.0.0.1:3000/api/internal/schedule-reminder}"
SETTLE_SECS="${INNGEST_VERIFY_SETTLE_SECS:-120}"
START_TS=$(date +%s)

write_state() {
  local exit_code="$1" reason="$2" marker_fired="${3:-false}"
  jq -nc \
    --argjson ec "$exit_code" --arg r "$reason" \
    --argjson st "$START_TS" --argjson et "$(date +%s)" \
    --argjson mf "$marker_fired" --arg comp "inngest-wiped-volume-verify" \
    '{exit_code:$ec, reason:$r, component:$comp, start_ts:$st, end_ts:$et, marker_fired:$mf}' \
    > "$STATE_FILE" 2>/dev/null || true
}

abort() {
  local reason="$1" msg="$2"
  logger -t "$LOG_TAG" "ABORT: $reason" 2>/dev/null || true
  echo "::error::inngest-wiped-volume-verify aborted: $msg" >&2
  echo "ERROR: $msg" >&2
  write_state 1 "$reason"
  exit 1
}

read_secret() {
  if [[ -n "${INNGEST_MANUAL_TRIGGER_SECRET:-}" ]]; then printf '%s' "$INNGEST_MANUAL_TRIGGER_SECRET"; return 0; fi
  if [[ "${INNGEST_REARM_SKIP_DOPPLER:-0}" != "1" ]]; then
    soleur_refresh_doppler_token
    if ! command -v doppler >/dev/null 2>&1; then soleur_log_doppler_read_failure 127 /dev/null ""; return 0; fi
    local out="" err rc=0
    # A bare `mktemp` is an abort vector under `set -e` on a full /tmp (ci-deploy.sh notes the
    # same); degrade to /dev/null so a missing scratch file loses the stderr, never the read.
    err="$(mktemp 2>/dev/null)" || err=/dev/null
    # The RETURN trap owns the scratch file (lint-trap-tempfile-ownership rule c): it is removed
    # on every exit from this function, including an abort between allocation and the rm below.
    # shellcheck disable=SC2064  # $err is expanded at trap-registration time on purpose
    if [[ "$err" != /dev/null ]]; then
      trap "rm -f -- '$err'" RETURN
    fi
    out="$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain 2>"$err")" || rc=$?
    if [[ "$rc" -ne 0 || -z "$out" ]]; then soleur_log_doppler_read_failure "$rc" "$err" "$out"; out=""; fi
    # Only an rc-0 value is the secret: partial stdout from a failed CLI must never be returned.
    printf '%s' "$out"
  fi
}

# ---- Gate 1: emptiness (the real B1 safety gate) -----------------------------
armed=$("$ENUMERATE_CMD" 2>/dev/null) || abort "enumerate_failed" "enumeration failed; refusing to wipe without confirming the armed set is empty"
echo "$armed" | jq -e 'type == "array"' >/dev/null 2>&1 || abort "enumerate_bad_output" "enumeration did not return a JSON array"
# Classify our own throwaway markers by the UNFORGEABLE signal: action.check ==
# NOOP_CHECK. A real named-check must resolve in CHECK_REGISTRY, so a real
# reminder can never carry the noop check; and a reminder that DOES carry it is
# itself harmless (unregistered → no-op at fire, posts nothing). The reminder_id
# prefix is NOT used here — it is operator-suppliable and a prefix-only match
# would let a spoofed id dodge the gate (security review P3).
# shellcheck disable=SC2016  # $c is a jq --arg variable, not a shell expansion
is_throwaway='(.action.check? == $c)'
real_count=$(echo "$armed" | jq --arg c "$NOOP_CHECK" "[.[] | select(($is_throwaway) | not)] | length")
if [[ "$real_count" -ne 0 ]]; then
  ids=$(echo "$armed" | jq -r --arg c "$NOOP_CHECK" "[.[] | select(($is_throwaway) | not) | .reminder_id] | join(\",\")")
  abort "real_reminders_present" "$real_count real armed reminder(s) present ([$ids]) — drain or re-arm them first; refusing to wipe"
fi

# ---- Gate 2: durable-backend sanity (secondary) ------------------------------
execstart="${INNGEST_VERIFY_EXECSTART:-$(systemctl show inngest-server.service -p ExecStart 2>/dev/null || true)}"
[[ "$execstart" == *"--postgres-max-open-conns"* ]] || abort "non_durable_backend" "inngest ExecStart has no --postgres-max-open-conns durable sentinel (SQLite-only) — a wipe would destroy real state"

# ---- Gate 3: the web scheduler is not QUIESCED (#6921/#8077) ------------------
# op=quiesce-web leaves inngest-server.service `is-active ∈ {inactive, failed}` AND `is-enabled ==
# disabled` — the shape ONLY its `quiesce` handler writes and only op=rollback's `enable` clears
# (`failed` = a stop that ended in SIGKILL at TimeoutStopSec). The `start` below would re-arm the
# scheduler the cutover deliberately stopped (a start runs a disabled unit), so refuse BEFORE
# arming the marker or touching the unit. Read-only queries, no sudo; stdout is the verdict, the
# non-zero rc (is-active 3, is-enabled 1) is tolerated. Same two-state predicate as ci-deploy.sh
# inngest_unit_quiesced() and inngest-inventory.sh unit_quiesced() (separate scripts, no shared lib).
unit_active="$(systemctl is-active inngest-server.service 2>/dev/null || true)"
unit_enabled="$(systemctl is-enabled inngest-server.service 2>/dev/null || true)"
if [[ ( "$unit_active" == inactive || "$unit_active" == failed ) && "$unit_enabled" == disabled ]]; then
  abort "quiesced_refused" "inngest-server.service is quiesced (unit=$unit_active enabled=disabled — op=quiesce-web); refusing to stop/wipe/start a deliberately stopped scheduler — only op=rollback re-arms it"
fi

# ---- Arm the throwaway marker (unregistered named-check → no comment) --------
SECRET="$(read_secret)"
[[ -n "$SECRET" ]] || abort "no_secret" "INNGEST_MANUAL_TRIGGER_SECRET unavailable"
MARKER_ID="${INNGEST_VERIFY_MARKER_ID:-${MARKER_PREFIX}$(date +%s%N)__}"
FIRE_AT=$(date -u -d "+90 seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
marker_body=$(jq -nc --arg id "$MARKER_ID" --arg fa "$FIRE_AT" --arg chk "$NOOP_CHECK" \
  '{reminder_id:$id, fire_at:$fa, actor:"platform", action:{type:"named-check", check:$chk, report_to_issue:1}}')
arm_code=$(curl --disable --noproxy '*' -s --max-time 15 -o /dev/null -w '%{http_code}' \
  -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${SECRET}" \
  --data-binary "$marker_body" "$REARM_URL" || echo "000")
[[ "$arm_code" == "202" ]] || abort "marker_arm_failed" "could not arm throwaway marker (HTTP $arm_code)"
logger -t "$LOG_TAG" "armed throwaway marker_id=$MARKER_ID fire_at=$FIRE_AT" 2>/dev/null || true

# ---- Destructive: stop → wipe /var/lib/inngest → start -----------------------
# The wipe needs no root (the dir is deploy:deploy 0750); stop/start use the
# pinned sudoers aliases (B3). Stop must complete before the wipe so the running
# server is not writing into the dir mid-wipe.
sudo systemctl stop inngest-server.service || abort "stop_failed" "systemctl stop inngest-server.service failed"
# Wipe contents (not the dir itself — preserve ownership/mode).
find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
logger -t "$LOG_TAG" "wiped $DATA_DIR" 2>/dev/null || true
sudo systemctl start inngest-server.service || abort "start_failed" "systemctl start inngest-server.service failed"

# ---- Wait for the marker to fire, then assert durability ---------------------
# Settle: let the server come up and the marker's fire time pass. 0 in tests.
[[ "$SETTLE_SECS" -gt 0 ]] && sleep "$SETTLE_SECS"

# /health 200
health_code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$HEALTH_URL" || echo "000")
[[ "$health_code" == "200" ]] || abort "health_not_200" "inngest /health returned $health_code after wipe+restart"

# >= 1 cron re-registered after restart. Query /v0/gql `functions` — GET /v1/functions
# is an UNREGISTERED 404 route in v1.19.4 (#5517): the old `if type=="array" else 0`
# tolerated the 404 body as 0, so this assert would FALSELY fire `no_functions` on a
# healthy restart. >= 1 proves the SDK re-synced (durability is in Postgres+Redis,
# not the wiped /var/lib/inngest volume).
fn_body=$(curl -s --max-time 10 -X POST -H "Content-Type: application/json" \
  --data-binary '{"query":"query { functions { slug } }"}' "$GQL_URL" || echo '{"data":{"functions":[]}}')
fn_count=$(echo "$fn_body" | jq '(.data.functions // []) | length' 2>/dev/null || echo 0)
[[ "$fn_count" -ge 1 ]] || abort "no_functions" "inngest /v0/gql functions returned $fn_count functions after restart"

# Marker fired: it is no longer in the still-armed set (its run reached terminal,
# OR its fire-time passed). enumerate excludes terminal-run + past events, so a
# fired marker drops out. (Belt-and-suspenders; the durability claim is the
# health + functions survival of the wipe.)
post=$("$ENUMERATE_CMD" 2>/dev/null || echo "[]")
marker_still_armed=$(echo "$post" | jq --arg id "$MARKER_ID" '[.[] | select(.reminder_id == $id)] | length')
marker_fired=true
[[ "$marker_still_armed" == "0" ]] || marker_fired=false

logger -t "$LOG_TAG" "verify passed: health=200 functions=$fn_count marker_fired=$marker_fired" 2>/dev/null || true
echo "inngest-wiped-volume-verify: PASS (health=200 functions=$fn_count marker_fired=$marker_fired)" >&2
write_state 0 "verify_passed" "$marker_fired"
exit 0
