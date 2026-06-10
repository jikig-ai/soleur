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

LOG_TAG="cron-egress-alarm"
SENTRY_SLUG="cron-egress-resolve"
FAILED_UNIT="${1:-unknown-unit}"
EMAIL_COOLDOWN_FILE="/run/cron-egress-alarm.last-email"
EMAIL_COOLDOWN_SECS=1800

log() { echo "[$LOG_TAG] $*"; }

# --- Channel 1: Sentry Crons error check-in ---
if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
  curl -s -o /dev/null --max-time 10 -X POST \
    "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${SENTRY_SLUG}/${SENTRY_PUBLIC_KEY}/?status=error" \
    || log "WARNING: Sentry error check-in failed"
else
  log "WARNING: Sentry env unset — skipping error check-in"
fi

# --- Channel 2: Resend email (disk-monitor.sh precedent) ---
# Cooldown: a sustained failure fires OnFailure= every timer tick; Sentry
# dedupes but the inbox does not — cap emails to one per 30 min.
if [[ -f "$EMAIL_COOLDOWN_FILE" ]]; then
  last="$(stat -c %Y "$EMAIL_COOLDOWN_FILE" 2>/dev/null || echo 0)"
  if (( $(date +%s) - last < EMAIL_COOLDOWN_SECS )); then
    log "email cooldown active — skipping Resend channel (Sentry check-in still posted)"
    RESEND_API_KEY=""
  fi
fi
if ! command -v jq >/dev/null; then
  log "WARNING: jq not found — skipping email channel"
  RESEND_API_KEY=""
fi
if [[ -n "${RESEND_API_KEY:-}" ]]; then
  HOSTNAME_STR="$(hostname)"
  JOURNAL_TAIL="$(journalctl -u "$FAILED_UNIT" -n 20 --no-pager 2>/dev/null | tail -c 2000 || echo '(journal unavailable)')"
  PAYLOAD="$(jq -n \
    --arg from "Soleur Ops <noreply@soleur.ai>" \
    --arg subject "[CRITICAL] cron-egress firewall unit ${FAILED_UNIT} FAILED on ${HOSTNAME_STR}" \
    --arg text "Unit ${FAILED_UNIT} failed. A dead re-resolve timer freezes the egress allowlist; as SaaS IPs rotate the container loses egress (fail-loud, but degrading). Investigate: systemctl status ${FAILED_UNIT}

Last journal lines:
${JOURNAL_TAIL}" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')"
  HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)" || HTTP_CODE="000"
  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    touch "$EMAIL_COOLDOWN_FILE"
  else
    log "WARNING: Resend POST failed (HTTP ${HTTP_CODE})"
  fi
else
  log "WARNING: RESEND_API_KEY unset/suppressed — skipping email alarm"
fi

log "alarm dispatched for ${FAILED_UNIT}"
