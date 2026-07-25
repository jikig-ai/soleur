#!/usr/bin/env bash
# Follow-through verification for #5673 (AC8 post-deploy soak of PR #5671).
#
# PR #5671 added the connect-time duplicate-solo guard (ADR-044 Amendment
# 2026-06-29). The webhook founder resolver's `soloRows.length > 1` ambiguous
# branch is RETAINED as the backstop canary; it pages as `op:founder-ambiguous`
# (Sentry issue WEB-PLATFORM-3M) whenever a duplicate-solo pair is hit at
# webhook time. AC8 requires that signal to hold at ~0 over a 7-day post-deploy
# soak — proving the connect-time block keeps new duplicates from forming AND
# no pre-existing pair remains. When it holds, this issue closes and ADR-044
# Amendment 2026-06-29 is considered accepted (adopting → accepted).
#
# Asserts ZERO Sentry events at level=error for `op:founder-ambiguous` in the
# window from just-after the PR #5671 deploy (2026-06-29T16:00:00Z, after the
# 14:49Z merge + web-platform-release live-verify success) to now. The directive's
# `earliest=2026-07-06T18:00:00Z` gates the first real check to ≥7 days post-deploy,
# and the explicit `start=` pins the window strictly after deploy so the morning
# 2026-06-29 pre-deploy burst (last seen ~10:44Z) is naturally excluded.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero error-level op:founder-ambiguous events; sweeper closes #5673)
#   1 = FAIL       (>=1 event in window; a duplicate slipped past the block — leave open, investigate)
#   * = TRANSIENT  (Sentry API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_IAC_AUTH_TOKEN). Mirrors reconcile-ff-only-sentry-4977.sh.

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# `op:` tag is set by the webhook founder resolver's reportSilentFallback; the
# retained `soloRows.length > 1` branch fingerprints as op:founder-ambiguous.
# level:error excludes any info-level breadcrumb.
QUERY='op:founder-ambiguous level:error'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

# Absolute window start pinned just after the #5671 deploy so pre-deploy events
# (incl. the 2026-06-29 morning burst) cannot contaminate the soak verdict.
START="2026-06-29T16:00:00"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&start=${START}&end=${END}&per_page=10&field=title&field=timestamp&field=level"

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
  echo "PASS: 0 op:founder-ambiguous error events since deploy ($START..$END) — AC8 soak holds; ADR-044 Amendment 2026-06-29 accepted."
  exit 0
fi

echo "FAIL: $EVENT_COUNT op:founder-ambiguous error event(s) since $START — a duplicate-solo pair was hit at webhook time; run the duplicate-solo-repo-detection runbook and re-point before this can close."
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp) (id=\(.id))"' | head -10
exit 1
