#!/usr/bin/env bash
# Follow-through soak for #8978 (PR #9034): the dashboard cold-load incident
# was unbounded remote Supabase legs stalling 20-38s inside `GET /dashboard`
# transactions. PR #9034 bounds every leg (postgrest abortSignal -> error arm;
# GoTrue/getSession Promise.race; identity selects; helper fallbacks) so a
# healthy deploy cannot produce a >15s document transaction — the legs
# degrade onto fail-fast arms at ~8-10s each, and a single bounded leg
# cannot serialize past ~10s.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero `GET /dashboard` transactions >15s in the window; sweeper closes #8978)
#   1 = FAIL       (>=1 slow transaction found; sweeper comments, leaves open)
#   * = TRANSIENT  (Sentry API unreachable / auth failure; retry next sweep)
#
# Required env: SENTRY_ACTIONS_RO_TOKEN (already wired in
#   scheduled-followthrough-sweeper.yml — the org-level read-only
#   `actions-read-prd` integration, ADR-031)
#
# Note on the <=500ms FCP acceptance criterion: the soak threshold is the
# INCIDENT CLASS (unbounded 20-38s remote stalls), not the AC — the AC is
# verified once by the authenticated browser probe post-deploy (the
# postmerge verification step on PR #9034), which is what closes #8978's
# acceptance evidence. This soak exists so the regression class is watched
# *continuously* rather than only at that one probe run.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): tracing echoes commands after
# expansion — a credential prints the moment it is used.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

# Token-shape guard: a newline in the token would inject a curl config directive on the stdin
# channel below, and an empty one would send the request headerless. Never echoes the value.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}"; then echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN unusable" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# `GET /dashboard` document transactions slower than 15s in the rolling 24h —
# the pre-fix signature read 23-43s; post-fix every leg is bounded ~10s, so
# any hit is a regression signal, not noise.
QUERY='transaction:"GET /dashboard" transaction.duration:>15000'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=24h&per_page=10&field=title&field=timestamp&field=transaction.duration"

RESP=$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Accept: application/json" \
  --config - \
  "$URL" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_ACTIONS_RO_TOKEN"))

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

COUNT=$(printf '%s' "$BODY" | jq 'if type == "array" then length else (.data | length) end' 2>/dev/null || echo "-1")
if [[ "$COUNT" == "-1" ]]; then
  echo "TRANSIENT: unparseable Sentry response" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$COUNT" -gt 0 ]]; then
  echo "FAIL: $COUNT 'GET /dashboard' transaction(s) >15s in the last 24h — the unbounded remote-stall class may have regressed (#8978)" >&2
  printf '%s\n' "$BODY" | jq -r 'if type == "array" then . else .data end | .[] | "\(."timestamp" // "") \(."transaction.duration" // "") \(."title" // "")"' 2>/dev/null | head -10 >&2
  exit 1
fi

echo "PASS: zero 'GET /dashboard' transactions >15s in the last 24h"
exit 0
