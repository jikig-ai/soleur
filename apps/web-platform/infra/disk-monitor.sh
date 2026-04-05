#!/usr/bin/env bash
set -euo pipefail

# disk-monitor.sh -- Proactive disk space monitoring with Discord alerting.
# Runs as a systemd timer every 5 minutes. Always exits 0.

readonly SCRIPT_NAME="disk-monitor"
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

if [[ -z "${DISCORD_OPS_WEBHOOK_URL:-}" ]]; then
  echo "WARNING: DISCORD_OPS_WEBHOOK_URL not set, skipping" >&2
  exit 0
fi

# --- Check Disk Usage ---
USAGE_PCT=$(df --output=pcent / 2>/dev/null | tail -1 | tr -d ' %') || {
  echo "WARNING: df command failed" >&2
  exit 0
}
AVAIL_KB=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ') || AVAIL_KB="unknown"
AVAIL_GB=$(( ${AVAIL_KB:-0} / 1048576 ))

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

# --- Build Disk Consumer Report ---
TOP_CONSUMERS=$(timeout 10 du -sh /* 2>/dev/null | sort -rh | head -5) || TOP_CONSUMERS="(timed out)"

# --- Send Alert ---
send_alert() {
  local level="$1" threshold="$2" mentions="$3"
  local server_hostname
  server_hostname=$(hostname)

  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg content "**[$level] Disk usage at ${USAGE_PCT}% on ${server_hostname}**"$'\n\n'"Available: ${AVAIL_GB}GB"$'\n'"Top consumers:"$'\n'"$TOP_CONSUMERS" \
    --arg username "Sol" \
    --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
    --argjson mentions "$mentions" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: $mentions}')

  curl -s -o /dev/null -w "" \
    --max-time 10 \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DISCORD_OPS_WEBHOOK_URL" 2>/dev/null || {
    echo "WARNING: Discord webhook POST failed" >&2
  }
}

# --- Evaluate Thresholds ---
if [[ "$USAGE_PCT" -ge "$CRIT_THRESHOLD" ]]; then
  if check_cooldown "$CRIT_THRESHOLD"; then
    send_alert "CRITICAL" "$CRIT_THRESHOLD" '{"parse":["everyone"]}'
    update_cooldown "$CRIT_THRESHOLD"
  fi
fi

if [[ "$USAGE_PCT" -ge "$WARN_THRESHOLD" ]]; then
  if check_cooldown "$WARN_THRESHOLD"; then
    send_alert "WARNING" "$WARN_THRESHOLD" '{"parse":[]}'
    update_cooldown "$WARN_THRESHOLD"
  fi
fi

exit 0
