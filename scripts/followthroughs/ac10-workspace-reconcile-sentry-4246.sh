#!/usr/bin/env bash
# Follow-through verification for #4246 (AC10 of PR #4226).
#
# Asserts ZERO Sentry events at level=error with tag feature:"workspace-reconcile-push"
# in the 24 hours preceding the check. Warning-level events for non-default-branch
# pushes / workspace_not_ready skips / unmapped installs are expected and tolerated.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero error-level events; sweeper closes #4246)
#   1 = FAIL       (≥1 error-level event found; sweeper comments, leaves open)
#   * = TRANSIENT  (Sentry API unreachable, auth failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN
#
# Close criteria (from #4246 / PR #4226 AC10):
#   - Query Sentry for the 24h window before now()
#   - Filter to feature:"workspace-reconcile-push" + level:error
#   - Expected: 0 matching events

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# Sentry query: filter by feature tag (set via reportSilentFallback's `feature:`
# arg) AND level=error. statsPeriod=24h gives a rolling 24h window.
QUERY='feature:"workspace-reconcile-push" level:error'

# Encode the query for the URL
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=24h&per_page=10"

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

EVENT_COUNT=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)

if ! [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse event count from response" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  echo "PASS: 0 workspace-reconcile-push error events in 24h window"
  exit 0
fi

echo "FAIL: $EVENT_COUNT workspace-reconcile-push error event(s) in 24h window"
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) (id=\(.id))"' | head -10
exit 1
