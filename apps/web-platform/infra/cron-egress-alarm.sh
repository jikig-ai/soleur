#!/usr/bin/env bash
# cron-egress-alarm.sh — OnFailure= alarm for the cron-egress firewall units
# (#5046 PR-2 / cron-egress-firewall).
#
# Fires when cron-egress-firewall.service or cron-egress-resolve.service
# FAILS (a dead resolve timer freezes the allowlist set → progressive then
# total container egress loss as SaaS IPs rotate — hr-observability-as-plan-
# quality-gate). Two channels, both best-effort, mirroring disk-monitor.sh:
#   1. Sentry Crons error check-in on the cron-egress-resolve monitor slug
#      (turns the monitor RED even when the script crashed before its own
#      error check-in could post).
#   2. Resend email to ops@ (the disk-monitor alert precedent).
# Runs doppler-wrapped (prd) so SENTRY_* / RESEND_API_KEY are present;
# degrades gracefully when absent.
set -uo pipefail
# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — every credential
# here arrives from the doppler-wrapped unit's environment, so a `${VAR:+x}`
# hatch names nothing it can trust. The `logger` leg ships the halt off-box
# through Vector Source 2 (PRIORITY 0-2 from any unit); it inlines the literal
# tag because `LOG_TAG=` is itself a command Rule A forbids above this refusal
# (#7898 §2).
case "$-" in
  *x*)
    printf 'SOLEUR_CRON_EGRESS_ALARM_HALT reason=xtrace-credential-bound issue=7797\n'
    printf '[cron-egress-alarm] refusing to run under xtrace: this unit handles a live credential and -x would print it\n' >&2
    logger -p user.crit -t cron-egress-alarm 'SOLEUR_CRON_EGRESS_ALARM_HALT reason=xtrace-credential-bound issue=7797' 2>/dev/null \
      || printf '[cron-egress-alarm] logger=absent (SOLEUR_CRON_EGRESS_ALARM_HALT not shipped off-box)\n' >&2
    exit 78
    ;;
esac
# (#7873/#7898 §2) TLS-env unset — rationale in disk-monitor.sh.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT
# The pin's [a-z0-9] / [a-f0-9] classes are locale-defined; pin the locale.
export LC_ALL=C

LOG_TAG="cron-egress-alarm"
SENTRY_SLUG="cron-egress-resolve"
FAILED_UNIT="${1:-unknown-unit}"
# systemd's %n is root-controlled argv, but it is the one non-literal token any
# marker below carries — validate its charset before the first emit (#7898).
# No leading `-` (never readable as an option by a later consumer) and no `@`
# (the vector pii_scrub email rule would rewrite `unit=a@b.service`); both
# current callers pass a plain `<name>.service`, and a templated instance name
# reads `invalid-unit-name` rather than leaking through.
[[ "$FAILED_UNIT" =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || FAILED_UNIT=invalid-unit-name
# Overridable so the exec harness can redirect the stamp into a tmpdir; the
# production unit never sets it (a failed `touch` below is loud).
EMAIL_COOLDOWN_FILE="${EMAIL_COOLDOWN_FILE:-/run/cron-egress-alarm.last-email}"
EMAIL_COOLDOWN_SECS=1800

log() { echo "[$LOG_TAG] $*"; }

# Emit a refusal/failed-send marker on every channel that survives it: stdout
# (journald), stderr (humans), and the crit row Vector Source 2 ships off-box
# (#7898). Reason tokens only — never an env value, a host, a body or a
# credential. A missing `logger` must not take the alarm down with it, but must
# not be silent either.
emit_refusal() {
  printf '%s\n' "$1"
  printf '[%s] %s\n' "$LOG_TAG" "$1" >&2
  logger -p user.crit -t "$LOG_TAG" "$1" 2>/dev/null \
    || printf '[%s] logger=absent (%s not shipped off-box)\n' "$LOG_TAG" "${1%% *}" >&2
}

# --- Channel 1: Sentry Crons error check-in ---
# A function so the `sentry-dest-pin` region sits at the same indentation as
# container-restart-monitor.sh › sentry_event() and the two regions can be
# diffed verbatim. Globals on purpose (no `local`): the region must be identical
# in both files, and `SENTRY_CHANNEL_NOTE` is read by Channel 2.
SENTRY_CHANNEL_NOTE=""
sentry_checkin() {
  # (#7898 §2) Sentry ingest-triple adjudication — rationale in
  # container-restart-monitor.sh › sentry_event(); the region below is
  # byte-identical there (a parity row in cron-egress-firewall.test.sh diffs
  # the two verbatim). Here the public key sits in the URL PATH.
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
  if (( sentry_dest_ok )); then
    # (#7873) transport confinement, position load-bearing — rationale in
    # disk-monitor.sh › send_alert(). The URL interpolates the FOLDED host, never
    # the raw env value; stderr stays closed because this URL embeds the key.
    local code rc=0
    code="$(curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST \
      "https://${_si_host}/api/${SENTRY_PROJECT_ID}/cron/${SENTRY_SLUG}/${SENTRY_PUBLIC_KEY}/?status=error" 2>/dev/null)" \
      || { rc=$?; code="000"; }
    if [[ ! "$code" =~ ^2 ]]; then
      log "WARNING: Sentry error check-in failed (HTTP ${code})"
      emit_refusal "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=sentry http_code=${code} rc=${rc}"
    fi
  elif [[ -n "$sentry_refuse_reason" ]]; then
    # Reason TOKEN only: the refused value is exactly the one that is not a sane
    # hostname (a pasted DSN carries the public key). The email below carries it.
    emit_refusal "SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=${sentry_refuse_reason}"
    SENTRY_CHANNEL_NOTE="sentry channel refused: destination failed the #7898 pin"
  else
    # A deliberate skip, not a failure: SEND_SKIPPED is its own marker class so
    # a future alert rule on SEND_FAILED never pages on configuration.
    log "WARNING: Sentry env unset — skipping error check-in"
    emit_refusal "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=sentry reason=unset"
  fi
}
sentry_checkin

# --- Channel 2: Resend email (disk-monitor.sh precedent) ---
# Cooldown: a sustained failure fires OnFailure= every timer tick; Sentry
# dedupes but the inbox does not — cap emails to one per 30 min. The truest
# reason a send is skipped wins the token (an absent key beats a cooldown that
# a previous send left behind; the first of cooldown/jq wins after that); a
# suppressed send still ships a SEND_SKIPPED row below so the unit-failure
# signal is never journald-only for the whole cooldown window (#7898 P9). That
# row is per OnFailure fire — one per resolve-timer tick (1/min) for the
# duration of a sustained failure, bounded by the outage that is already
# paging through Sentry; it is a SKIPPED row, so an alert rule on SEND_FAILED
# never keys on it.
RESEND_SKIP_REASON=""
[[ -n "${RESEND_API_KEY:-}" ]] || RESEND_SKIP_REASON="unset"
if [[ -f "$EMAIL_COOLDOWN_FILE" ]]; then
  last="$(stat -c %Y "$EMAIL_COOLDOWN_FILE" 2>/dev/null || echo 0)"
  if (( $(date +%s) - last < EMAIL_COOLDOWN_SECS )); then
    log "email cooldown active — skipping Resend channel"
    RESEND_API_KEY=""
    [[ -n "$RESEND_SKIP_REASON" ]] || RESEND_SKIP_REASON="cooldown"
  fi
fi
if ! command -v jq >/dev/null; then
  log "WARNING: jq not found — skipping email channel"
  RESEND_API_KEY=""
  [[ -n "$RESEND_SKIP_REASON" ]] || RESEND_SKIP_REASON="jq"
fi
if [[ -n "${RESEND_API_KEY:-}" ]]; then
  HOSTNAME_STR="$(hostname)"
  JOURNAL_TAIL="$(journalctl -u "$FAILED_UNIT" -n 20 --no-pager 2>/dev/null | tail -c 2000 || echo '(journal unavailable)')"
  PAYLOAD="$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "[CRITICAL] cron-egress firewall unit ${FAILED_UNIT} FAILED on ${HOSTNAME_STR}" \
    --arg text "Unit ${FAILED_UNIT} failed. A dead re-resolve timer freezes the egress allowlist; as SaaS IPs rotate the container loses egress (fail-loud, but degrading). Investigate: systemctl status ${FAILED_UNIT}

Last journal lines:
${JOURNAL_TAIL}${SENTRY_CHANNEL_NOTE:+

$SENTRY_CHANNEL_NOTE}" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')"
  RESEND_RC=0
  HTTP_CODE="$(curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)" || { RESEND_RC=$?; HTTP_CODE="000"; }
  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    touch "$EMAIL_COOLDOWN_FILE" || log "WARNING: could not write the email cooldown stamp ${EMAIL_COOLDOWN_FILE} — the next fire will email again"
  else
    log "WARNING: Resend POST failed (HTTP ${HTTP_CODE})"
    emit_refusal "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=resend http_code=${HTTP_CODE} rc=${RESEND_RC}"
  fi
else
  log "WARNING: RESEND_API_KEY unset/suppressed — skipping email alarm"
  emit_refusal "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=resend reason=${RESEND_SKIP_REASON:-unset} unit=${FAILED_UNIT}"
fi

log "alarm dispatched for ${FAILED_UNIT}"
