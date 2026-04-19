#!/usr/bin/env bash
set -euo pipefail

# resource-monitor.sh -- Host CPU/RAM + concurrent-session monitoring (#1052).
# Runs as a systemd timer every 5 minutes. Always exits 0 (alerting-layer
# failures must never take down the monitor; the timer keeps firing).
#
# Pairs with disk-monitor.sh: same cooldown/alert/envfile shape, different
# signal. Keep pattern changes in sync between both scripts.

readonly COOLDOWN_DIR="${COOLDOWN_DIR:-/var/run}"
readonly COOLDOWN_SECONDS=3600
readonly WARN_MEM_PCT="${WARN_MEM_PCT:-80}"
readonly CRIT_MEM_PCT="${CRIT_MEM_PCT:-95}"
readonly WARN_CPU_PCT="${WARN_CPU_PCT:-85}"
readonly PROC_ROOT="${PROC_ROOT:-/proc}"
readonly METRICS_URL="${METRICS_URL:-http://127.0.0.1:3000/internal/metrics}"

# --- Load Configuration ---
ENV_FILE="${ENV_FILE:-/etc/default/resource-monitor}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "WARNING: $ENV_FILE not found, skipping" >&2
  exit 0
fi
set -a; . "$ENV_FILE"; set +a

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "WARNING: RESEND_API_KEY not set, skipping" >&2
  exit 0
fi

# --- Samplers ---
# Memory: use MemAvailable (reclaimable buffers/cache included) — this is the
# number that actually predicts OOM, not MemTotal-MemFree.
sample_mem_pct() {
  local total available
  total=$(awk '/^MemTotal:/ {print $2; exit}' "$PROC_ROOT/meminfo" 2>/dev/null || echo 0)
  available=$(awk '/^MemAvailable:/ {print $2; exit}' "$PROC_ROOT/meminfo" 2>/dev/null || echo 0)
  [[ -n "$total" && -n "$available" && "$total" -gt 0 ]] || { echo 0; return 0; }
  echo $(( ((total - available) * 100) / total ))
}

# CPU: /proc/stat delta over 1 second. Measures true utilization rather than
# loadavg (which reflects run-queue depth including iowait). The 1s sleep is
# acceptable here because the monitor runs on a 5-min systemd timer.
sample_cpu_pct() {
  local user1 nice1 sys1 idle1 iowait1 total1 idle_all1
  local user2 nice2 sys2 idle2 iowait2 total2 idle_all2
  read -r _ user1 nice1 sys1 idle1 iowait1 _ < <(head -1 "$PROC_ROOT/stat")
  idle_all1=$(( idle1 + iowait1 ))
  total1=$(( user1 + nice1 + sys1 + idle1 + iowait1 ))
  sleep 1
  read -r _ user2 nice2 sys2 idle2 iowait2 _ < <(head -1 "$PROC_ROOT/stat")
  idle_all2=$(( idle2 + iowait2 ))
  total2=$(( user2 + nice2 + sys2 + idle2 + iowait2 ))
  local delta_total=$(( total2 - total1 ))
  [[ "$delta_total" -gt 0 ]] || { echo 0; return 0; }
  echo $(( ((delta_total - (idle_all2 - idle_all1)) * 100) / delta_total ))
}

# Active session count: reach into the container via the host-published port
# (ci-deploy.sh publishes 0.0.0.0:3000:3000). The /internal/metrics endpoint
# is gated to loopback Host headers and exposes capacity + session counts that
# /health intentionally does NOT (defense-in-depth). If the server is down,
# curl fails fast and we fall back to 0 — the alert still fires on CPU/RAM.
sample_active_sessions() {
  local body
  body=$(curl -s --max-time 2 "$METRICS_URL" 2>/dev/null || echo "{}")
  echo "$body" | jq -r '.active_sessions // 0' 2>/dev/null || echo 0
}

# --- Cooldown (per-threshold, mirrors disk-monitor.sh) ---
check_cooldown() {
  local threshold="$1"
  local cooldown_file="${COOLDOWN_DIR}/resource-monitor-alert-${threshold}"
  if [[ -f "$cooldown_file" ]]; then
    local last_alert now
    last_alert=$(cat "$cooldown_file")
    now=$(date +%s)
    if [[ "$now" -lt "$((last_alert + COOLDOWN_SECONDS))" ]]; then
      return 1
    fi
  fi
  return 0
}

update_cooldown() {
  local threshold="$1"
  date +%s > "${COOLDOWN_DIR}/resource-monitor-alert-${threshold}"
}

# --- Send Alert (same Resend HTTP shape as disk-monitor.sh) ---
send_alert() {
  local level="$1" body="$2"
  local server_hostname
  server_hostname=$(hostname)

  local SUBJECT="[${level}] Resource pressure on ${server_hostname}"
  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "$SUBJECT" \
    --arg text "$body" \
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

# --- Main ---
MEM_PCT=$(sample_mem_pct)
CPU_PCT=$(sample_cpu_pct)
SESSIONS=$(sample_active_sessions)

echo "[resource-monitor] mem=${MEM_PCT}% cpu=${CPU_PCT}% sessions=${SESSIONS}"

# Memory (thresholds evaluated independently; crit and warn have separate
# cooldowns so a sustained incident escalates cleanly).
if [[ "$MEM_PCT" -ge "$CRIT_MEM_PCT" ]] && check_cooldown "mem-crit"; then
  send_alert "CRIT" "Memory ${MEM_PCT}% (CPU ${CPU_PCT}%, sessions ${SESSIONS})"
  update_cooldown "mem-crit"
fi

if [[ "$MEM_PCT" -ge "$WARN_MEM_PCT" ]] && check_cooldown "mem-warn"; then
  send_alert "WARN" "Memory ${MEM_PCT}% (CPU ${CPU_PCT}%, sessions ${SESSIONS})"
  update_cooldown "mem-warn"
fi

if [[ "$CPU_PCT" -ge "$WARN_CPU_PCT" ]] && check_cooldown "cpu-warn"; then
  send_alert "WARN" "CPU ${CPU_PCT}% (memory ${MEM_PCT}%, sessions ${SESSIONS})"
  update_cooldown "cpu-warn"
fi

exit 0
