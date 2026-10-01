#!/usr/bin/env bash
set -euo pipefail
# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — the credential this
# unit handles is bound BELOW this line (sourced from ENV_FILE), so a `${VAR:+x}`
# hatch would test an empty variable, open, and trace the bind itself. The
# `logger` leg ships the halt off-box through Vector Source 2 (PRIORITY 0-2 from
# any unit); it inlines the literal tag because a `readonly LOG_TAG=` is itself
# a command Rule A forbids above this refusal (#7898 §2).
case "$-" in
  *x*)
    printf 'SOLEUR_DISK_MONITOR_HALT reason=xtrace-credential-bound issue=7797\n'
    printf '[disk-monitor] refusing to run under xtrace: this unit handles a live credential and -x would print it\n' >&2
    logger -p user.crit -t disk-monitor 'SOLEUR_DISK_MONITOR_HALT reason=xtrace-credential-bound issue=7797' 2>/dev/null \
      || printf '[disk-monitor] logger=absent (SOLEUR_DISK_MONITOR_HALT not shipped off-box)\n' >&2
    exit 78
    ;;
esac

# disk-monitor.sh -- Proactive disk space monitoring with email alerting via Resend.
# Runs as a systemd timer every 5 minutes. Always exits 0.

readonly LOG_TAG="disk-monitor"
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
# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS itself: SSLKEYLOGFILE writes the
# session keys, the CA vars substitute the trust store, OPENSSL_CONF loads an
# arbitrary provider .so, LD_PRELOAD applies to the curl child. Unset AFTER the
# env-file source so nothing sourced can re-arm them (#7898 §2).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT

# Emit a refusal/failed-send marker on every channel that survives it: stdout
# (journald), stderr (humans), and the crit row Vector Source 2 ships off-box
# (#7898). Reason tokens only — never an env value, a body or a credential. A
# missing `logger` must not take the alert down with it, but must not be silent.
emit_refusal() {
  printf '%s\n' "$1"
  printf '[%s] %s\n' "$LOG_TAG" "$1" >&2
  logger -p user.crit -t "$LOG_TAG" "$1" 2>/dev/null \
    || printf '[%s] logger=absent (%s not shipped off-box)\n' "$LOG_TAG" "${1%% *}" >&2
}

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

  # (#7873) transport confinement, position load-bearing: `--disable` aborts
  # ~/.curlrc parsing only when FIRST; `--noproxy '*'` ignores every proxy var;
  # `--proto '=https'` refuses a scheme downgrade; `-g` disables URL globbing.
  local HTTP_CODE rc=0
  HTTP_CODE=$(curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null) || { rc=$?; HTTP_CODE="000"; }

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "WARNING: Resend API POST failed (HTTP ${HTTP_CODE})" >&2
    emit_refusal "SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=${HTTP_CODE} rc=${rc}"
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
