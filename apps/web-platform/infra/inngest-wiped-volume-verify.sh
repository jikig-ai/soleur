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
# SAFETY GATES (in order; either failing aborts BEFORE any destructive action):
#   1. Emptiness gate (B1 — the REAL safety gate): run the enumeration; if ANY
#      non-throwaway armed reminder is present, ABORT LOUD. A wipe with a real
#      armed reminder present could destroy the operator's pending action. This
#      is the gate that matters — NOT the postgres-uri check, which ALWAYS passes
#      post-#5459 and protects nothing.
#   2. Durable-backend sanity (secondary): the running ExecStart must carry
#      --postgres-uri. A wipe of a SQLite-only backend destroys real state. This
#      is a belt-and-suspenders assert, not the primary gate.
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

readonly LOG_TAG="inngest-wiped-volume-verify"
readonly MARKER_PREFIX="__wiped-volume-verify-"
readonly NOOP_CHECK="__cutover-verify-noop__"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENUMERATE_CMD="${INNGEST_ENUMERATE_CMD:-${SCRIPT_DIR}/inngest-enumerate-reminders.sh}"
DATA_DIR="${INNGEST_DATA_DIR:-/var/lib/inngest}"
STATE_FILE="${INNGEST_VERIFY_STATE:-/var/lock/inngest-wiped-volume-verify.state}"
HEALTH_URL="${INNGEST_HEALTH_URL:-http://127.0.0.1:8288/health}"
FUNCTIONS_URL="${INNGEST_FUNCTIONS_URL:-http://127.0.0.1:8288/v1/functions}"
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
  if [[ "${INNGEST_REARM_SKIP_DOPPLER:-0}" != "1" ]] && command -v doppler >/dev/null 2>&1; then
    doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain 2>/dev/null || true
  fi
}

# ---- Gate 1: emptiness (the real B1 safety gate) -----------------------------
armed=$("$ENUMERATE_CMD" 2>/dev/null) || abort "enumerate_failed" "enumeration failed; refusing to wipe without confirming the armed set is empty"
echo "$armed" | jq -e 'type == "array"' >/dev/null 2>&1 || abort "enumerate_bad_output" "enumeration did not return a JSON array"
# Exclude our own throwaway markers (a prior aborted run could leave one).
real_count=$(echo "$armed" | jq --arg p "$MARKER_PREFIX" '[.[] | select((.reminder_id // "") | startswith($p) | not)] | length')
if [[ "$real_count" -ne 0 ]]; then
  ids=$(echo "$armed" | jq -r --arg p "$MARKER_PREFIX" '[.[] | select((.reminder_id // "") | startswith($p) | not) | .reminder_id] | join(",")')
  abort "real_reminders_present" "$real_count real armed reminder(s) present ([$ids]) — drain or re-arm them first; refusing to wipe"
fi

# ---- Gate 2: durable-backend sanity (secondary) ------------------------------
execstart="${INNGEST_VERIFY_EXECSTART:-$(systemctl show inngest-server.service -p ExecStart 2>/dev/null || true)}"
[[ "$execstart" == *"--postgres-uri"* ]] || abort "non_durable_backend" "inngest ExecStart has no --postgres-uri (SQLite-only) — a wipe would destroy real state"

# ---- Arm the throwaway marker (unregistered named-check → no comment) --------
SECRET="$(read_secret)"
[[ -n "$SECRET" ]] || abort "no_secret" "INNGEST_MANUAL_TRIGGER_SECRET unavailable"
MARKER_ID="${INNGEST_VERIFY_MARKER_ID:-${MARKER_PREFIX}$(date +%s%N)__}"
FIRE_AT=$(date -u -d "+90 seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
marker_body=$(jq -nc --arg id "$MARKER_ID" --arg fa "$FIRE_AT" --arg chk "$NOOP_CHECK" \
  '{reminder_id:$id, fire_at:$fa, actor:"platform", action:{type:"named-check", check:$chk, report_to_issue:1}}')
arm_code=$(curl -s --max-time 15 -o /dev/null -w '%{http_code}' \
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

# /v1/functions has >= 1 cron (crons re-registered after restart)
fn_body=$(curl -s --max-time 10 "$FUNCTIONS_URL" || echo "[]")
fn_count=$(echo "$fn_body" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo 0)
[[ "$fn_count" -ge 1 ]] || abort "no_functions" "inngest /v1/functions returned $fn_count functions after restart"

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
