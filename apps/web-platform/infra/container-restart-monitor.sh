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
# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — the Resend key is
# bound BELOW this line (sourced from ENV_FILE) and the Sentry triple arrives
# from the doppler-wrapped unit, so a `${VAR:+x}` hatch would test an empty
# variable, open, and trace the bind itself. The `logger` leg ships the halt
# off-box through Vector Source 2 (PRIORITY 0-2 from any unit); it inlines the
# literal tag because `readonly LOG_TAG=` is itself a command Rule A forbids
# above this refusal (#7898 §2).
case "$-" in
  *x*)
    printf 'SOLEUR_CONTAINER_RESTART_MONITOR_HALT reason=xtrace-credential-bound issue=7797\n'
    printf '[container-restart-monitor] refusing to run under xtrace: this unit handles a live credential and -x would print it\n' >&2
    logger -p user.crit -t container-restart-monitor 'SOLEUR_CONTAINER_RESTART_MONITOR_HALT reason=xtrace-credential-bound issue=7797' 2>/dev/null \
      || printf '[container-restart-monitor] logger=absent (SOLEUR_CONTAINER_RESTART_MONITOR_HALT not shipped off-box)\n' >&2
    exit 78
    ;;
esac

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

# Emit a refusal/failed-send marker on every channel that survives it: stdout
# (journald), stderr (humans), and the crit row Vector Source 2 ships off-box
# (#7898). Reason tokens only — never an env value, a host, a body or a
# credential. A missing `logger` must not take the alert down with it, but must
# not be silent either.
emit_refusal() {
  printf '%s\n' "$1"
  printf '[%s] %s\n' "$LOG_TAG" "$1" >&2
  logger -p user.crit -t "$LOG_TAG" "$1" 2>/dev/null \
    || printf '[%s] logger=absent (%s not shipped off-box)\n' "$LOG_TAG" "${1%% *}" >&2
}

# --- Config (Resend key; Sentry env arrives via the doppler-wrapped service) ---
ENV_FILE="${ENV_FILE:-/etc/default/container-restart-monitor}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  set -a; . "$ENV_FILE"; set +a
fi
# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS itself: SSLKEYLOGFILE writes the
# session keys, the CA vars substitute the trust store, OPENSSL_CONF loads an
# arbitrary provider .so, LD_PRELOAD applies to the curl child. Unset AFTER the
# env-file source so nothing sourced can re-arm them (#7898 §2).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT
# The pin's [a-z0-9] / [a-f0-9] classes are locale-defined; pin the locale.
export LC_ALL=C
# Set by sentry_event() when the destination pin refuses; resend_email() appends
# it to the email body so the refusal rides the surviving channel.
SENTRY_CHANNEL_NOTE=""

# --- Channel 1: Sentry error EVENT (store API; mirrors cron-egress-resolve.sh) -
sentry_event() {
  local msg="$1" op="$2" extra="$3"
  # (#7898 §2) The Sentry ingest triple arrives from the doppler-wrapped
  # environment and is interpolated into the request URL, so each part is
  # adjudicated before a credentialed byte moves. Host: case-fold and strip ONE
  # trailing dot (DNS is case-insensitive and `host.` is a valid absolute FQDN),
  # then a POSITIVE DNS-label grammar ending in ADR-031's two ingest apexes
  # (`.ingest.de.sentry.io` / `.ingest.us.sentry.io` — the region is mandatory;
  # the glossary lists no region-less apex) — it refuses `@ / ? # :`, `%2F`,
  # an empty label and every non-DNS byte on its own. Project id / key regexes
  # are `_cron-shared.ts`'s SENTRY_PROJECT_RE / SENTRY_PUBLIC_KEY_RE verbatim
  # (one repo-wide definition of a valid triple). Residual (ADR-052):
  # `*.ingest.de.sentry.io` admits every Sentry EU tenant's org host, not ours.
  # All three vars are initialised BEFORE the `if` so the triple-unset path
  # reads nothing unbound under set -u. The region is kept byte-identical to
  # cron-egress-alarm.sh › sentry_checkin() at the same indentation (a parity
  # row in cron-egress-firewall.test.sh diffs the two regions verbatim).
  # BEGIN sentry-dest-pin (#7898)
  sentry_dest_ok=0; sentry_refuse_reason=""; _si_host=""
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    _si_host="${SENTRY_INGEST_DOMAIN%.}"
    _si_host="${_si_host,,}"
    if [[ "$_si_host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.ingest\.(de|us)\.sentry\.io$ ]]; then
      sentry_dest_ok=1
    else
      sentry_refuse_reason=host-shape
    fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PROJECT_ID" =~ ^[0-9]+$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=project-shape; fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PUBLIC_KEY" =~ ^[a-f0-9]{32}$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=key-shape; fi
  fi
  # END sentry-dest-pin (#7898)
  if (( ! sentry_dest_ok )); then
    if [[ -n "$sentry_refuse_reason" ]]; then
      # Reason TOKEN only: the refused value is exactly the one that is not a
      # sane hostname (a pasted DSN carries the public key).
      emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=${sentry_refuse_reason}"
      SENTRY_CHANNEL_NOTE="sentry channel refused: destination failed the #7898 pin"
    else
      # A deliberate skip, not a failure: SEND_SKIPPED is its own marker class
      # so a future alert rule on SEND_FAILED never pages on configuration.
      log "WARN: Sentry env unset — event not posted (op=${op})"
      emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_SKIPPED channel=sentry reason=unset"
    fi
    return 0
  fi
  local payload
  payload="$(jq -n \
    --arg msg "$msg" \
    --arg op "$op" \
    --argjson extra "$extra" \
    '{message: $msg, level: "error", platform: "other", logger: "container-restart-monitor",
      tags: {feature: "container-restart-monitor", op: $op},
      extra: $extra}' 2>/dev/null)" || {
    emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=sentry reason=jq"
    return 0
  }
  # (#7873) transport confinement, position load-bearing (see resend_email).
  # The URL interpolates the FOLDED host, never the raw env value.
  local code rc=0
  code="$(curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST \
    "https://${_si_host}/api/${SENTRY_PROJECT_ID}/store/" \
    -H "Content-Type: application/json" \
    -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
    -d "$payload" 2>/dev/null)" || { rc=$?; code="000"; }
  if [[ ! "$code" =~ ^2 ]]; then
    # A shape-valid but REJECTED key (401/403) was previously indistinguishable
    # from success; the HTTP code and curl's exit status are the reason tokens.
    log "WARN: Sentry event POST failed (HTTP ${code}, op=${op})"
    emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=sentry http_code=${code} rc=${rc}"
  fi
}

# --- Channel 2: Resend email (resource-monitor.sh / cron-egress-alarm.sh shape) -
resend_email() {
  # The refusal note is appended HERE, to the body this function RECEIVES: the
  # alert BODY is built before sentry_event() runs, so an append at build time
  # would always see an empty note.
  local subject="$1" body="${2}${SENTRY_CHANNEL_NOTE:+$'\n\n'$SENTRY_CHANNEL_NOTE}"
  local sentry_state="(Sentry still posted)"
  [[ -z "${SENTRY_CHANNEL_NOTE:-}" ]] || sentry_state="(Sentry channel refused too)"
  if [[ -z "${RESEND_API_KEY:-}" ]]; then
    log "WARN: RESEND_API_KEY unset — skipping email channel ${sentry_state}"
    emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_SKIPPED channel=resend reason=unset"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log "WARN: jq not found — skipping email channel"
    emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=resend reason=jq"
    return 0
  fi
  local payload http rc=0
  payload="$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "$subject" \
    --arg text "$body" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')"
  # (#7873) transport confinement, position load-bearing: `--disable` aborts
  # ~/.curlrc parsing only when FIRST; `--noproxy '*'` ignores every proxy var;
  # `--proto '=https'` refuses a scheme downgrade; `-g` disables URL globbing.
  http="$(curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)" || { rc=$?; http="000"; }
  if [[ ! "$http" =~ ^2 ]]; then
    # cq-silent-fallback-must-mirror-to-sentry: the Sentry event (channel 1) is
    # already posted, so a Resend failure is loud, not silent. Log it, and ship
    # the failure off-box as a crit row (#7898 P9) — the code and curl's exit
    # status are reason tokens, never a body.
    log "WARN: Resend POST failed (HTTP ${http})"
    emit_refusal "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=resend http_code=${http} rc=${rc}"
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
# NOTE: this is a fixed 1h lookback, NOT a delta — a single OOM keeps it >0 for
# the window AND the kernel logs both an `oom-kill:` and a `Killed process` line
# per event, so the value is a CORROBORATION boolean, not a true event count
# (it only feeds the OOM=true OR below; the alert body labels it journald_oom).
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
elif [[ -f "$ALERTED_FILE" && "$RATE" -eq 0 && "$IS_DEPLOY" == "false" ]]; then
  # Recovery: an alert was open and the rolling rate is back to 0 → notify ONCE
  # so the operator does not have to infer resolution from silence. The
  # IS_DEPLOY==false guard is load-bearing: a deploy truncates the rolling
  # window (RATE→0) for an unrelated reason, so without it a routine deploy
  # landing DURING an active storm would emit a false "CLEARED" (#5417 review).
  # A genuine recovery is only observable on the SAME container with no new
  # restarts; the next non-deploy tick after the storm subsides fires it.
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
