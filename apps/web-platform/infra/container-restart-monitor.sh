#!/usr/bin/env bash
# container-restart-monitor.sh — host-side detector for soleur-web-platform
# container restart churn (#5417). Runs as a systemd timer every 5 minutes.
# ALWAYS exits 0 (alerting-layer failures must never take down the monitor or
# its timer; a flaky `docker inspect` during the deploy stop/rm window must NOT
# read as "0 restarts healthy"). Set -e is deliberately OFF — every signal read
# is best-effort and collapses to a safe default rather than aborting.
#
# Why this exists: the container ran with no `--memory` cap (ci-deploy.sh, fixed
# in this PR's Deliverable A). When a heavy concurrent-cron memory spike drove
# HOST OOM, the kernel killed an arbitrary victim and `--restart unless-stopped`
# churned the container ~10-60x/day, killing in-flight Claude-eval crons and
# flushing the DOCKER-USER egress jump. resource-monitor.sh samples HOST RAM%
# only — it cannot see the container's RestartCount / OOMKilled. This is the
# container-level detector (extends the resource-monitor pattern; does NOT
# replace it). Two channels, both best-effort, mirroring cron-egress-alarm.sh:
#   1. Sentry error EVENT (store API) tagged feature=container-restart-monitor —
#      the no-SSH signal the sentry_issue_alert.container_restart_burst rule
#      pages on (and the host-authoritative cross-check for the "Server startup"
#      event-frequency).
#   2. Resend email to ops@ (the resource-monitor / disk-monitor precedent).
#
# Classification state machine (per AC5):
#   - deploy (container_id CHANGED) → new container; reset baseline + rolling
#     window, SUPPRESS the alert (a deploy is expected churn) UNLESS the fresh
#     container already has RestartCount>0 (immediate crash-loop → alert).
#   - same container_id, RestartCount delta>0 → crash-restart(s); append to the
#     rolling window; alert when the rolling rate ≥ RESTART_THRESHOLD.
#   - container absent (docker inspect non-zero) → exit 0, baseline untouched.
# OOM corroboration (AC5e): OOM is the OR of the cgroup memory.events `oom_kill`
# counter delta (authoritative — the ONLY signal that catches child-cgroup
# bwrap-sandbox kills, .State.OOMKilled is a cgroup-v2 false-negative there),
# exit-137, and the journald `oom-kill:` kernel ring. NOT .State.OOMKilled alone.
set -uo pipefail

readonly CONTAINER="${CONTAINER:-soleur-web-platform}"
readonly STATE_DIR="${STATE_DIR:-/var/run}"
readonly CGROUP_ROOT="${CGROUP_ROOT:-/sys/fs/cgroup}"
readonly LOG_TAG="container-restart-monitor"

# Tuning constants (AC6). 5-min timer = 288 ticks/day; ≥3 crash-restarts in a
# rolling 1h window catches a 10-60/day storm within minutes while a lone
# legitimate crash (delta 1, well under 3/h) stays quiet. 1h cooldown bounds the
# inbox to ~1 email/h during an active storm (Sentry dedupes its own channel).
readonly RESTART_THRESHOLD="${RESTART_THRESHOLD:-3}"
readonly RESTART_WINDOW_SECS="${RESTART_WINDOW_SECS:-3600}"
readonly COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-3600}"

readonly STATE_FILE="${STATE_DIR}/container-restart-monitor.state"
readonly EVENTS_FILE="${STATE_DIR}/container-restart-monitor.events"
readonly ALERTED_FILE="${STATE_DIR}/container-restart-monitor.alerted"
readonly COOLDOWN_FILE="${STATE_DIR}/container-restart-monitor.cooldown"
readonly RATE_FILE="${STATE_DIR}/container-restart-monitor.rate"

log() { echo "[$LOG_TAG] $*"; }

# --- Config (Resend key; Sentry env arrives via the doppler-wrapped service) ---
ENV_FILE="${ENV_FILE:-/etc/default/container-restart-monitor}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  set -a; . "$ENV_FILE"; set +a
fi

# --- Channel 1: Sentry error EVENT (store API; mirrors cron-egress-resolve.sh) -
sentry_event() {
  local msg="$1" op="$2" extra="$3"
  if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
    log "WARN: Sentry env unset — event not posted (op=${op})"
    return 0
  fi
  local payload
  payload="$(jq -n \
    --arg msg "$msg" \
    --arg op "$op" \
    --argjson extra "$extra" \
    '{message: $msg, level: "error", platform: "other", logger: "container-restart-monitor",
      tags: {feature: "container-restart-monitor", op: $op},
      extra: $extra}' 2>/dev/null)" || return 0
  curl -s -o /dev/null --max-time 10 -X POST \
    "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
    -H "Content-Type: application/json" \
    -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
    -d "$payload" \
    || log "WARN: Sentry event POST failed (op=${op})"
}

# --- Channel 2: Resend email (resource-monitor.sh / cron-egress-alarm.sh shape) -
resend_email() {
  local subject="$1" body="$2"
  if [[ -z "${RESEND_API_KEY:-}" ]]; then
    log "WARN: RESEND_API_KEY unset — skipping email channel (Sentry still posted)"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log "WARN: jq not found — skipping email channel"
    return 0
  fi
  local payload http
  payload="$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "$subject" \
    --arg text "$body" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')"
  http="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)" || http="000"
  if [[ ! "$http" =~ ^2 ]]; then
    # cq-silent-fallback-must-mirror-to-sentry: the Sentry event (channel 1) is
    # already posted, so a Resend failure is loud, not silent. Log it.
    log "WARN: Resend POST failed (HTTP ${http})"
  fi
}

# --- Gather current container state (best-effort; absent → exit 0) ------------
NOW=$(date +%s)
INSPECT="$(docker inspect "$CONTAINER" \
  --format '{{.Id}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.ExitCode}}' 2>/dev/null)" \
  || INSPECT=""
if [[ -z "$INSPECT" ]]; then
  log "container ${CONTAINER} not inspectable (likely deploy stop/rm window) — exit 0, baseline untouched"
  exit 0
fi
read -r ID COUNT OOMKILLED EXITCODE <<< "$INSPECT"
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
[[ "$EXITCODE" =~ ^-?[0-9]+$ ]] || EXITCODE=0

# cgroup memory.events oom_kill counter (authoritative OOM signal; catches
# child-cgroup bwrap kills that .State.OOMKilled misses under cgroup v2).
OOM_COUNTER=$(awk '/^oom_kill /{print $2; exit}' \
  "${CGROUP_ROOT}/system.slice/docker-${ID}.scope/memory.events" 2>/dev/null || echo 0)
[[ "$OOM_COUNTER" =~ ^[0-9]+$ ]] || OOM_COUNTER=0

# journald kernel-ring OOM corroboration (vector ships these to Better Stack).
JOURNAL_OOM=$(journalctl -k --since "@$((NOW - RESTART_WINDOW_SECS))" --no-pager 2>/dev/null \
  | grep -cE 'oom-kill|Killed process' || true)
[[ "$JOURNAL_OOM" =~ ^[0-9]+$ ]] || JOURNAL_OOM=0

# --- Load baseline ------------------------------------------------------------
PREV_ID="" PREV_COUNT=0 PREV_OOM=0
if [[ -f "$STATE_FILE" ]]; then
  read -r PREV_ID PREV_COUNT PREV_OOM _ < "$STATE_FILE" 2>/dev/null || true
  [[ "$PREV_COUNT" =~ ^[0-9]+$ ]] || PREV_COUNT=0
  [[ "$PREV_OOM" =~ ^[0-9]+$ ]] || PREV_OOM=0
fi

# --- Classify -----------------------------------------------------------------
IS_DEPLOY=false
DELTA=0
OOM_DELTA=0
if [[ -n "$PREV_ID" && "$ID" == "$PREV_ID" ]]; then
  # Same container instance.
  if (( COUNT > PREV_COUNT )); then DELTA=$(( COUNT - PREV_COUNT )); fi
  if (( OOM_COUNTER > PREV_OOM )); then OOM_DELTA=$(( OOM_COUNTER - PREV_OOM )); fi
else
  # New container (deploy) OR first run. A fresh container's RestartCount is its
  # own crash count; treat count>0 as immediate crash-loop.
  IS_DEPLOY=true
  DELTA=$COUNT
  OOM_DELTA=$OOM_COUNTER
  : > "$EVENTS_FILE" 2>/dev/null || true   # new instance → reset rolling window
fi

# Record crash-restart events (DELTA of them at NOW) in the rolling window.
if (( DELTA > 0 )); then
  for ((i = 0; i < DELTA; i++)); do echo "$NOW" >> "$EVENTS_FILE"; done
fi

# Prune events outside the window; RATE = remaining count.
RATE=0
if [[ -f "$EVENTS_FILE" ]]; then
  CUTOFF=$(( NOW - RESTART_WINDOW_SECS ))
  TMP_EVENTS="$(mktemp "${STATE_DIR}/cre.XXXXXX" 2>/dev/null || echo "${EVENTS_FILE}.tmp")"
  awk -v c="$CUTOFF" '$1 ~ /^[0-9]+$/ && $1 >= c {print}' "$EVENTS_FILE" > "$TMP_EVENTS" 2>/dev/null || true
  mv -f "$TMP_EVENTS" "$EVENTS_FILE" 2>/dev/null || true
  RATE=$(wc -l < "$EVENTS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  [[ "$RATE" =~ ^[0-9]+$ ]] || RATE=0
fi
echo "$RATE" > "$RATE_FILE" 2>/dev/null || true

# OOM classification (AC5e): NOT .State.OOMKilled alone.
OOM=false
if [[ "$OOMKILLED" == "true" ]] || (( EXITCODE == 137 )) || (( OOM_DELTA > 0 )) || (( JOURNAL_OOM > 0 )); then
  OOM=true
fi
CLASS="crash"; [[ "$OOM" == "true" ]] && CLASS="OOM"

log "id=${ID} count=${COUNT} prev_count=${PREV_COUNT} delta=${DELTA} rate=${RATE}/${RESTART_WINDOW_SECS}s deploy=${IS_DEPLOY} class=${CLASS} oom_delta=${OOM_DELTA} exit=${EXITCODE} journal_oom=${JOURNAL_OOM}"

# --- Alert decision -----------------------------------------------------------
# A deploy with count>0 (fresh crash-loop) alerts immediately, bypassing the
# rolling threshold; otherwise alert when the rolling rate breaches threshold.
ALERTABLE=false
ALERT_OP="restart_storm"
if [[ "$IS_DEPLOY" == "true" && "$COUNT" -gt 0 ]]; then
  ALERTABLE=true; ALERT_OP="fresh_crash_loop"
elif (( RATE >= RESTART_THRESHOLD )); then
  ALERTABLE=true; ALERT_OP="restart_storm"
fi

# Cooldown (per resource-monitor.sh): suppress repeat emails within the window.
LAST_ALERT=0
[[ -f "$COOLDOWN_FILE" ]] && LAST_ALERT=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
[[ "$LAST_ALERT" =~ ^[0-9]+$ ]] || LAST_ALERT=0
COOLDOWN_ACTIVE=false
if (( NOW - LAST_ALERT < COOLDOWN_SECONDS )); then COOLDOWN_ACTIVE=true; fi

if [[ "$ALERTABLE" == "true" ]]; then
  HOST="$(hostname 2>/dev/null || echo unknown)"
  SUBJECT="[${CLASS}] soleur-web-platform restart churn on ${HOST} (rate ${RATE}/h, ${ALERT_OP})"
  BODY="Container ${CONTAINER} restart churn detected.
class:        ${CLASS}
op:           ${ALERT_OP}
container_id: ${ID}
restart_count:${COUNT} (prev ${PREV_COUNT}, delta ${DELTA})
rolling_rate: ${RATE} in ${RESTART_WINDOW_SECS}s (threshold ${RESTART_THRESHOLD})
exit_code:    ${EXITCODE}
oom_signals:  oomkilled=${OOMKILLED} cgroup_oom_delta=${OOM_DELTA} journald_oom=${JOURNAL_OOM}

A capped container that still churns means the --memory cap (ci-deploy.sh
PROD_MEMORY_CAP) is BELOW the legitimate concurrent-cron peak (AC2 regression) —
raise it. A 'crash' class means an uncaught exception (see Sentry fatal events)."
  EXTRA="$(jq -n \
    --arg cls "$CLASS" --argjson cnt "$COUNT" --argjson rate "$RATE" \
    --argjson delta "$DELTA" --argjson exitc "$EXITCODE" \
    --argjson oomd "$OOM_DELTA" --argjson joom "$JOURNAL_OOM" \
    '{class: $cls, restart_count: $cnt, rolling_rate: $rate, delta: $delta,
      exit_code: $exitc, cgroup_oom_delta: $oomd, journald_oom: $joom}' 2>/dev/null || echo '{}')"

  if [[ "$COOLDOWN_ACTIVE" == "true" ]]; then
    log "alert suppressed by cooldown (last alert $((NOW - LAST_ALERT))s ago < ${COOLDOWN_SECONDS}s); Sentry dedupes its own channel"
  else
    sentry_event "${CLASS} restart churn: ${CONTAINER} ${RATE}/h (${ALERT_OP})" "$ALERT_OP" "$EXTRA"
    resend_email "$SUBJECT" "$BODY"
    echo "$NOW" > "$COOLDOWN_FILE" 2>/dev/null || true
  fi
  touch "$ALERTED_FILE" 2>/dev/null || true
elif [[ -f "$ALERTED_FILE" && "$RATE" -eq 0 ]]; then
  # Recovery: an alert was open and the rolling rate is back to 0 → notify ONCE
  # so the operator does not have to infer resolution from silence.
  HOST="$(hostname 2>/dev/null || echo unknown)"
  sentry_event "soleur-web-platform restart storm CLEARED on ${HOST}" "recovered" \
    "$(jq -n --argjson cnt "$COUNT" '{restart_count: $cnt, rolling_rate: 0, status: "cleared"}' 2>/dev/null || echo '{}')"
  resend_email "[RESOLVED] soleur-web-platform restart storm cleared on ${HOST}" \
    "Container ${CONTAINER} restart rate has returned to 0 over the last ${RESTART_WINDOW_SECS}s. The earlier churn alert is resolved (current RestartCount ${COUNT})."
  rm -f "$ALERTED_FILE" 2>/dev/null || true
  log "recovery: restart storm cleared, alerted flag removed"
fi

# --- Update baseline ----------------------------------------------------------
echo "${ID} ${COUNT} ${OOM_COUNTER} ${NOW}" > "$STATE_FILE" 2>/dev/null || true

exit 0
