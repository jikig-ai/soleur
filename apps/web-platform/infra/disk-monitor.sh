#!/usr/bin/env bash
set -euo pipefail

# disk-monitor.sh -- Proactive disk space monitoring with email alerting via Resend.
# Runs as a systemd timer every 5 minutes. Always exits 0.

readonly COOLDOWN_DIR="${COOLDOWN_DIR:-/var/run}"
readonly COOLDOWN_SECONDS=3600
readonly WARN_THRESHOLD=80
readonly CRIT_THRESHOLD=95

# --- Load Configuration ---
ENV_FILE="${ENV_FILE:-/etc/default/disk-monitor}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "WARNING: $ENV_FILE not found, skipping" >&2
  exit 0
fi
set -a; . "$ENV_FILE"; set +a

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "WARNING: RESEND_API_KEY not set, skipping" >&2
  exit 0
fi

# --- Check Disk Usage ---
USAGE_PCT=$(df --output=pcent / 2>/dev/null | tail -1 | tr -d ' %') || {
  echo "WARNING: df command failed" >&2
  exit 0
}
AVAIL_KB=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ') || AVAIL_KB="0"
[[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
AVAIL_GB=$(( AVAIL_KB / 1048576 ))

# --- Cooldown Check (per-threshold) ---
check_cooldown() {
  local threshold="$1"
  local cooldown_file="${COOLDOWN_DIR}/disk-monitor-alert-${threshold}"
  if [[ -f "$cooldown_file" ]]; then
    local last_alert
    last_alert=$(cat "$cooldown_file")
    local now
    now=$(date +%s)
    if [[ "$now" -lt "$((last_alert + COOLDOWN_SECONDS))" ]]; then
      return 1  # still in cooldown
    fi
  fi
  return 0  # not in cooldown
}

update_cooldown() {
  local threshold="$1"
  date +%s > "${COOLDOWN_DIR}/disk-monitor-alert-${threshold}"
}

# --- Send Alert ---
send_alert() {
  local level="$1" threshold="$2"
  local server_hostname
  server_hostname=$(hostname)

  # Build disk consumer report lazily (only when alerting)
  local TOP_CONSUMERS
  TOP_CONSUMERS=$(timeout 10 du -sh /* 2>/dev/null | sort -rh | head -5) || TOP_CONSUMERS="(timed out)"

  local SUBJECT="[${level}] Disk usage at ${USAGE_PCT}% on ${server_hostname}"
  local BODY
  BODY=$(printf 'Disk usage: %s%%\nAvailable: %sGB\n\nTop consumers:\n%s' \
    "$USAGE_PCT" "$AVAIL_GB" "$TOP_CONSUMERS")

  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "$SUBJECT" \
    --arg text "$BODY" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null) || HTTP_CODE="000"

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "WARNING: Resend API POST failed (HTTP ${HTTP_CODE})" >&2
  fi
}

# --- Evaluate Thresholds ---
# Both thresholds are evaluated independently (not elif) so a 96% disk triggers
# both CRITICAL and WARNING if neither is in cooldown. This matches standard
# monitoring practice: warning and critical are separate alert channels.
if [[ "$USAGE_PCT" -ge "$CRIT_THRESHOLD" ]]; then
  if check_cooldown "$CRIT_THRESHOLD"; then
    send_alert "CRITICAL" "$CRIT_THRESHOLD"
    update_cooldown "$CRIT_THRESHOLD"
  fi
fi

if [[ "$USAGE_PCT" -ge "$WARN_THRESHOLD" ]]; then
  if check_cooldown "$WARN_THRESHOLD"; then
    send_alert "WARNING" "$WARN_THRESHOLD"
    update_cooldown "$WARN_THRESHOLD"
  fi
fi

exit 0
