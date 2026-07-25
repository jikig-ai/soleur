#!/usr/bin/env bash
# Follow-through verification for #4977 (post-deploy confirmation of PR #4972).
#
# PR #4972 de-noised the `workspace-reconcile-on-push` `git pull --ff-only`
# dirty-tree abort: a self-healed condition no longer emits an error-level
# Sentry mirror (only a pino `info` breadcrumb). The original page was Sentry
# event 9ccf1d861b3b4c8595772bd116b931e8 (feature=pino-mirror, level=error,
# "Cannot fast-forward your working tree"), last seen 2026-06-05T14:00:58Z —
# BEFORE the PR #4972 deploy (web-v0.113.0 @ 2026-06-05T17:38:35Z).
#
# Asserts ZERO Sentry events at level=error matching the reconcile ff-only
# signature in the 24 hours preceding the check. Because the directive's
# `earliest=` gates this script to the first sweep ≥24h after the deploy, the
# rolling statsPeriod=24h window starts AFTER the deploy timestamp and so
# naturally excludes the original pre-deploy event. Any NEW error-level event
# for this signature in that window means the de-noise fix regressed.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero error-level events; sweeper closes #4977)
#   1 = FAIL       (≥1 NEW error-level event found; sweeper comments, leaves open)
#   * = TRANSIENT  (Sentry API unreachable, auth failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_IAC_AUTH_TOKEN)
#
# Close criteria (from #4977 / PR #4972):
#   - Query Sentry for the 24h window before now()
#   - Filter to feature:"pino-mirror" + level:error + the ff-only message phrase
#   - Expected: 0 matching events

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# Sentry query: the `feature:` tag is set by reportSilentFallback; the quoted
# free-text phrase pins to the reconcile ff-only signature (the message field
# contains it even though the event title is the raw git command). level:error
# excludes the expected info-level breadcrumb the de-noise fix now emits.
# statsPeriod=24h gives a rolling 24h window.
QUERY='feature:"pino-mirror" level:error "Cannot fast-forward your working tree"'

# Encode the query for the URL
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=24h&per_page=10&field=title&field=timestamp&field=level"

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
  echo "PASS: 0 reconcile ff-only error events in 24h window (de-noise fix #4972 holds)"
  exit 0
fi

echo "FAIL: $EVENT_COUNT reconcile ff-only error event(s) in 24h window — de-noise fix #4972 may have regressed"
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp) (id=\(.id))"' | head -10
exit 1
