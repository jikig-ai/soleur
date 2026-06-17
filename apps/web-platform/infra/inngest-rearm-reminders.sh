#!/usr/bin/env bash
# inngest-rearm-reminders.sh — no-SSH cutover re-arm executor (#5450, AC2/B2).
#
# Runs ON THE HOST (delivered via the infra-config push, invoked through the
# /hooks/inngest-rearm-reminders POST hook). Consumes the JSON records emitted by
# inngest-enumerate-reminders.sh (stdin) and re-arms each by POSTing it back to
# the app's POST /api/internal/schedule-reminder route on host loopback. This is
# the half that actually makes a dropped reminder FIRE against the fresh
# Postgres+Redis backend after the cutover.
#
# Why route through schedule-reminder (not a raw inngest.send): the route is the
# existing, validated arming surface — it recomputes the inngest dedup keys
# `id`(=reminder_id) + `ts`(=Date.parse(fire_at)) from the body, so re-arming an
# event that ALSO survived in inngest state dedups instead of double-firing a
# non-idempotent comment (B2-i). It enforces `actor:"platform"` (B2-ii) and the
# action allowlist. Feeding back {reminder_id,fire_at,actor,action} is sufficient.
#
# ORDERING GUARD (B2-iii): the route returns 503 while INNGEST_CUTOVER_QUIESCE is
# set. Re-arm MUST run AFTER the operator clears the flag (cutover step 6). If we
# get a 503 we ABORT LOUD — never swallow it — so a too-early re-arm is a visible
# failure, not a silent reminder loss.
#
# Read path for the Bearer secret: $INNGEST_MANUAL_TRIGGER_SECRET if already in
# env (test/host), else `doppler secrets get` (prod host has the prd config).
# Fails closed if neither yields a secret.
set -euo pipefail

readonly LOG_TAG="inngest-rearm-reminders"
REARM_URL="${SCHEDULE_REMINDER_URL:-http://127.0.0.1:3000/api/internal/schedule-reminder}"

read_secret() {
  if [[ -n "${INNGEST_MANUAL_TRIGGER_SECRET:-}" ]]; then
    printf '%s' "$INNGEST_MANUAL_TRIGGER_SECRET"
    return 0
  fi
  # INNGEST_REARM_SKIP_DOPPLER lets tests assert the fail-closed path without a
  # doppler binary on PATH.
  if [[ "${INNGEST_REARM_SKIP_DOPPLER:-0}" != "1" ]] && command -v doppler >/dev/null 2>&1; then
    doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain 2>/dev/null || true
  fi
}

SECRET="$(read_secret)"
if [[ -z "$SECRET" ]]; then
  logger -t "$LOG_TAG" "FATAL: INNGEST_MANUAL_TRIGGER_SECRET unavailable — refusing to re-arm" 2>/dev/null || true
  echo "ERROR: INNGEST_MANUAL_TRIGGER_SECRET unavailable (env + doppler both empty)" >&2
  exit 1
fi

records="$(cat)"
if ! echo "$records" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: stdin is not a JSON array of re-arm records" >&2
  exit 1
fi

count=$(echo "$records" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  logger -t "$LOG_TAG" "no reminders to re-arm (empty record set)" 2>/dev/null || true
  echo "inngest-rearm-reminders: nothing to re-arm" >&2
  exit 0
fi

rearmed=0
failed=0
for i in $(seq 0 $((count - 1))); do
  rec=$(echo "$records" | jq -c ".[$i]")
  rid=$(echo "$rec" | jq -r '.reminder_id')
  # The route's body is exactly {reminder_id, fire_at, actor, action}.
  body=$(echo "$rec" | jq -c '{reminder_id, fire_at, actor, action}')
  http_code=$(curl -s --max-time 15 \
    -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SECRET}" \
    --data-binary "$body" \
    "$REARM_URL" || echo "000")

  case "$http_code" in
    202)
      rearmed=$((rearmed + 1))
      logger -t "$LOG_TAG" "re-armed reminder_id=$rid" 2>/dev/null || true
      ;;
    503)
      # Quiesce ordering guard — abort loud, do NOT continue (B2-iii).
      logger -t "$LOG_TAG" "ABORT: 503 on reminder_id=$rid — INNGEST_CUTOVER_QUIESCE still set" 2>/dev/null || true
      echo "ERROR: re-arm got 503 for reminder_id=$rid — INNGEST_CUTOVER_QUIESCE is still set." >&2
      echo "       Clear it (cutover step 6: doppler secrets set INNGEST_CUTOVER_QUIESCE= ...) THEN re-run re-arm." >&2
      echo "       $rearmed re-armed before abort; reminder_id=$rid and any after it were NOT re-armed." >&2
      exit 1
      ;;
    *)
      failed=$((failed + 1))
      logger -t "$LOG_TAG" "FAILED re-arm reminder_id=$rid http_code=$http_code" 2>/dev/null || true
      echo "ERROR: re-arm failed for reminder_id=$rid (HTTP $http_code)" >&2
      ;;
  esac
done

echo "inngest-rearm-reminders: re-armed=$rearmed failed=$failed total=$count" >&2
logger -t "$LOG_TAG" "done: re-armed=$rearmed failed=$failed total=$count" 2>/dev/null || true
[[ "$failed" -gt 0 ]] && exit 1 || exit 0
