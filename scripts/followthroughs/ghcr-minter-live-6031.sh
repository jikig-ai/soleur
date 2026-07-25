#!/usr/bin/env bash
# Follow-through: GHCR installation-token minter live-and-writing (#6031 / ADR-088).
#
# #6031's full "done" is post-merge + operator-gated: org-owner re-consent to the
# App's new packages:read grant (AC10) → apply the prd-scoped write-token IaC → the minter's first
# successful mint+write (AC11) → a real deploy +
# fresh-host boot authenticating with the minted token (AC12) → interim PAT revoked
# (AC13). This follow-through automates the closure so it is NOT memory-gated.
#
# Close criterion (the honest live signal): the Sentry cron monitor
# `scheduled-ghcr-token-minter` has a recent `ok` check-in. Because the handler's
# heartbeat is OUTPUT-AWARE — it only checks in `ok` when the Doppler write returned
# 2xx — a recent `ok` proves the minter is live AND writing valid tokens to prd.
# A missed/errored check-in means the minter is not yet live (pre-cutover) or is
# failing, so the tracker stays open.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS      (monitor's latest check-in is `ok` within the freshness window → close #6031)
#   1 = FAIL      (monitor exists but latest check-in is not a fresh `ok` — pre-cutover or failing)
#   * = TRANSIENT (Sentry API unreachable/auth failure, or monitor not created yet → retry)
#
# Required env: SENTRY_AUTH_TOKEN
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
set -uo pipefail

# soleur:followthrough-stub v1

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"
MONITOR_SLUG="scheduled-ghcr-token-minter"
# The minter runs every 20 min; a fresh `ok` within 40 min proves liveness (survives
# one missed tick), matching the <=40 < 60-min token-TTL staleness floor.
FRESH_WINDOW_SECS=$((40 * 60))

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "${API}/organizations/${ORG}/monitors/${MONITOR_SLUG}/checkins/?per_page=1") || {
  echo "TRANSIENT: Sentry API unreachable for monitor ${MONITOR_SLUG}" >&2
  exit 2
}

STATUS_CODE="${RESP##*HTTP_STATUS:}"
BODY="${RESP%$'\n'HTTP_STATUS:*}"

if [[ "$STATUS_CODE" == "404" ]]; then
  echo "TRANSIENT: monitor ${MONITOR_SLUG} not created yet (pre-apply / pre-cutover)" >&2
  exit 2
fi
if [[ "$STATUS_CODE" != "200" ]]; then
  echo "TRANSIENT: Sentry returned HTTP ${STATUS_CODE} for ${MONITOR_SLUG}" >&2
  exit 2
fi

# Latest check-in status + timestamp.
LATEST_STATUS=$(printf '%s' "$BODY" | jq -r '.[0].status // empty')
LATEST_TS=$(printf '%s' "$BODY" | jq -r '.[0].dateCreated // empty')

if [[ -z "$LATEST_STATUS" || -z "$LATEST_TS" ]]; then
  echo "FAIL: no check-ins recorded for ${MONITOR_SLUG} yet (minter not live)." >&2
  exit 1
fi

# Age of the latest check-in.
NOW_EPOCH=$(date -u +%s)
TS_EPOCH=$(date -u -d "$LATEST_TS" +%s 2>/dev/null || echo 0)
AGE=$((NOW_EPOCH - TS_EPOCH))

if [[ "$LATEST_STATUS" == "ok" && "$TS_EPOCH" -gt 0 && "$AGE" -le "$FRESH_WINDOW_SECS" ]]; then
  echo "PASS: ${MONITOR_SLUG} latest check-in is 'ok' ${AGE}s ago (<= ${FRESH_WINDOW_SECS}s) — minter live and writing. Close #6031 after confirming the interim PAT is revoked (AC13)."
  exit 0
fi

echo "FAIL: ${MONITOR_SLUG} latest check-in is '${LATEST_STATUS}' (age ${AGE}s) — not a fresh 'ok'; minter not yet live/healthy." >&2
exit 1
