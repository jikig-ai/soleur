#!/usr/bin/env bash
# Follow-through soak for #5728 (post-deploy confirmation of the heartbeat
# DELIVERY fix).
#
# #5728: scheduled-community-monitor recorded `missed` daily 2026-06-13→06-21
# even though the digest was produced — the single terminal Sentry check-in was
# never DELIVERED (mid-eval SIGKILL / a throw before the heartbeat step / a
# dropped POST). The fix hardens delivery (final-attempt error heartbeat on the
# throw path + bounded POST retry) on top of ADR-078/#5686 (graceful cron drain,
# which removes the dominant SIGKILL cause).
#
# This soak asserts the heartbeat is now DELIVERED on every fire — i.e. ZERO
# server-generated `missed` / `timeout` check-ins in the trailing 7-day window.
# It deliberately does NOT fail on `error` check-ins: an `error` still means the
# POST was delivered (the monitor RAN and reported), which is exactly the #5728
# success condition. (A daily `error` regime is a DISTINCT problem — the
# credit/digest-generation class, tracked separately — not a delivery defect.)
#
# The directive's `earliest=<deploy+7d>` gates the first sweep to ≥7 days after
# deploy, so the rolling 7-day window below is entirely post-deploy (same pattern
# as reconcile-ff-only-sentry-4977.sh) — no deploy timestamp needs threading in.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero missed/timeout in the 7-day window; sweeper closes #5728)
#   1 = FAIL       (≥1 missed/timeout — delivery regressed; sweeper comments, leaves open)
#   * = TRANSIENT  (Sentry API unreachable, auth failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_IAC_AUTH_TOKEN). Optional: SENTRY_ORG (default jikigai-eu),
#   SENTRY_API_HOST (default de.sentry.io — the EU region host; ADR-031, and the
#   host live-verified for the checkins endpoint during #5728 Phase 0).

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="${SENTRY_ORG:-jikigai-eu}"
API_HOST="${SENTRY_API_HOST:-de.sentry.io}"
MONITOR_SLUG="scheduled-community-monitor"
WINDOW_DAYS=7

URL="https://${API_HOST}/api/0/organizations/${ORG}/monitors/${MONITOR_SLUG}/checkins/?per_page=30"

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry checkins API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

# Cutoff = now - WINDOW_DAYS. The checkins endpoint returns recent check-ins with
# a `status` string (ok|error|missed|timeout|in_progress) and a `dateAdded` ISO
# timestamp. Count missed/timeout within the window.
CUTOFF=$(date -u -d "${WINDOW_DAYS} days ago" +%s 2>/dev/null) \
  || CUTOFF=$(date -u -v-"${WINDOW_DAYS}"d +%s 2>/dev/null)
if ! [[ "$CUTOFF" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not compute the ${WINDOW_DAYS}-day cutoff timestamp" >&2
  exit 2
fi

# Validate the response parses and carries the expected shape before trusting a
# zero count (a schema drift must be TRANSIENT, never a vacuous PASS).
if ! printf '%s' "$BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "TRANSIENT: checkins response is not a JSON array (schema drift?)" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

TOTAL_IN_WINDOW=$(printf '%s' "$BODY" | jq -r --argjson cutoff "$CUTOFF" '
  [ .[]
    | select((.dateAdded // .dateCreated) != null)
    | select(((.dateAdded // .dateCreated) | fromdateiso8601) >= $cutoff)
  ] | length' 2>/dev/null)

BAD=$(printf '%s' "$BODY" | jq -r --argjson cutoff "$CUTOFF" '
  [ .[]
    | select((.dateAdded // .dateCreated) != null)
    | select(((.dateAdded // .dateCreated) | fromdateiso8601) >= $cutoff)
    | select((.status | tostring | ascii_downcase) as $s
             | ($s == "missed") or ($s == "timeout") or ($s == "timed_out"))
  ]' 2>/dev/null)

if ! [[ "$TOTAL_IN_WINDOW" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse check-in counts from response" >&2
  exit 2
fi

if [[ "$TOTAL_IN_WINDOW" -eq 0 ]]; then
  # No check-ins at all in the window means the monitor isn't firing — that is a
  # liveness problem, not a confirmed delivery PASS. Surface it as TRANSIENT.
  echo "TRANSIENT: 0 check-ins in the trailing ${WINDOW_DAYS}-day window (monitor not firing?)" >&2
  exit 2
fi

BAD_COUNT=$(printf '%s' "$BAD" | jq -r 'length' 2>/dev/null)
if [[ "$BAD_COUNT" -eq 0 ]]; then
  echo "PASS: 0 missed/timeout check-ins in ${TOTAL_IN_WINDOW} fires over the trailing ${WINDOW_DAYS}d — heartbeat delivery holds (#5728)"
  exit 0
fi

echo "FAIL: ${BAD_COUNT} missed/timeout check-in(s) of ${TOTAL_IN_WINDOW} in the trailing ${WINDOW_DAYS}d — delivery may have regressed (#5728)"
printf '%s' "$BAD" | jq -r '.[] | "  - \(.status) @ \(.dateAdded // .dateCreated)"' | head -10
exit 1
