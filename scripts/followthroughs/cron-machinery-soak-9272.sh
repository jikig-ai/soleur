#!/usr/bin/env bash
# Follow-through soak for #9272/#9273/#9274 (post-deploy confirmation of the
# cron-machinery PR).
#
# Asserts, over the trailing soak window:
#   (a) ZERO Sentry error events with op `scheduled-output-missing` for
#       feature:cron-community-monitor (the #9272 verify-race signature) AND at
#       least one `scheduled-community-monitor` issue landed in the window —
#       the pair proves the producer is both producing AND being credited.
#   (b) ZERO `missed`/`timeout` check-ins on the scheduled-actions-queue-health
#       monitor (#9273 — dispatch-primary should deliver ~2/h; a missed now
#       means BOTH triggers failed or real starvation — still pageable).
#   (c) ZERO open soleur-ai[bot] PRs with mergeable_state=behind older than
#       24 h (#9274 — the reaper sweep at 17 */2 * * * should keep the armed
#       set moving).
#
# The directive's `earliest=<deploy+3d>` gates the first sweep to ≥3 days after
# deploy, so the window below is entirely post-deploy (same pattern as
# reconcile-ff-only-sentry-4977.sh).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (all three assertions hold; sweeper closes the tracker)
#   1 = FAIL       (any assertion fails; sweeper comments, leaves open)
#   * = TRANSIENT  (API unreachable / auth failure; retry next sweep)
#
# Required env: SENTRY_ACTIONS_RO_TOKEN (org-level read-only `actions-read-prd`
#   integration, ADR-031) and GH_TOKEN (repo read for open bot PRs — the `gh`
#   CLI's ambient auth also satisfies it).
#   The org and API host are PINNED literals (Rule D, ADR-202): `jikigai-eu` on
#   `de.sentry.io`. An env override that does not equal the pin is refused
#   (TRANSIENT), never followed.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so a credential is printed the moment it is used. The test below
# covers EVERY credential this file references and uses `${VAR:+x}`, which is
# non-emptiness WITHOUT expanding the value -- `${VAR:-}` would print it here.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ] || [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN/GH_TOKEN). Unset them to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN not set" >&2; exit 2; fi
if ! command -v gh >/dev/null 2>&1; then echo "TRANSIENT: gh CLI not installed" >&2; exit 2; fi

readonly ORG_PINNED="jikigai-eu"
readonly API_HOST_PINNED="de.sentry.io"
ORG="${SENTRY_ORG:-$ORG_PINNED}"
API_HOST="${SENTRY_API_HOST:-$API_HOST_PINNED}"
if [[ "$ORG" != "$ORG_PINNED" || "$API_HOST" != "$API_HOST_PINNED" ]]; then
  echo "TRANSIENT: refusing an unpinned Sentry destination (org=${ORG} host=${API_HOST}; pinned to ${ORG_PINNED} / ${API_HOST_PINNED})" >&2
  exit 2
fi

WINDOW_DAYS=3
CUTOFF=$(date -u -d "${WINDOW_DAYS} days ago" +%s 2>/dev/null) \
  || CUTOFF=$(date -u -v-"${WINDOW_DAYS}"d +%s 2>/dev/null)
if ! [[ "$CUTOFF" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not compute the ${WINDOW_DAYS}-day cutoff timestamp" >&2
  exit 2
fi
CUTOFF_ISO=$(date -u -d "@${CUTOFF}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || CUTOFF_ISO=$(date -u -r "${CUTOFF}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

FAILURES=0

# --- (a1) zero scheduled-output-missing events for cron-community-monitor ---
QUERY='feature:"cron-community-monitor" "scheduled-output-missing"'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="https://${API_HOST}/api/0/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=${WINDOW_DAYS}d&per_page=10&field=title&field=timestamp"
RESP=$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN" \
  -H "Accept: application/json" \
  "$URL")
HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')
if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry events API returned $HTTP_STATUS" >&2
  exit 2
fi
EVENT_COUNT=$(printf '%s' "$BODY" | jq -r '.data | if type=="array" then length else -1 end' 2>/dev/null)
if ! [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse events response" >&2
  exit 2
fi
if [[ "$EVENT_COUNT" -gt 0 ]]; then
  echo "FAIL(a): $EVENT_COUNT scheduled-output-missing event(s) for cron-community-monitor in ${WINDOW_DAYS}d — #9272 retry may not be live"
  printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp)"' | head -5
  FAILURES=$((FAILURES + 1))
else
  echo "ok(a1): 0 scheduled-output-missing events for cron-community-monitor in ${WINDOW_DAYS}d"
fi

# --- (a2) ≥1 scheduled-community-monitor issue landed in the window ---
DIGESTS=$(gh issue list --repo jikig-ai/soleur --label scheduled-community-monitor \
  --state all --search "created:>=${CUTOFF_ISO}" --json number --limit 10 2>/dev/null \
  | jq 'length' 2>/dev/null)
if ! [[ "$DIGESTS" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: gh issue list failed" >&2
  exit 2
fi
if [[ "$DIGESTS" -lt 1 ]]; then
  echo "FAIL(a2): 0 scheduled-community-monitor issues in ${WINDOW_DAYS}d — digests are not landing"
  FAILURES=$((FAILURES + 1))
else
  echo "ok(a2): ${DIGESTS} scheduled-community-monitor issue(s) created in ${WINDOW_DAYS}d"
fi

# --- (b) zero missed/timeout check-ins on scheduled-actions-queue-health ---
URL="https://${API_HOST}/api/0/organizations/${ORG}/monitors/scheduled-actions-queue-health/checkins/?per_page=100"
RESP=$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN" \
  -H "Accept: application/json" \
  "$URL")
HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')
if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry checkins API returned $HTTP_STATUS" >&2
  exit 2
fi
if ! printf '%s' "$BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "TRANSIENT: checkins response is not a JSON array (schema drift?)" >&2
  exit 2
fi
COUNTS=$(printf '%s' "$BODY" | jq -r --argjson cutoff "$CUTOFF" '
  [ .[]
    | select((.dateAdded // .dateCreated) != null)
    | select(((.dateAdded // .dateCreated) | fromdateiso8601) >= $cutoff)
  ] as $w
  | "\($w | length) \([$w[] | select((.status | tostring | ascii_downcase) as $s | ($s == "missed") or ($s == "timeout") or ($s == "timed_out"))] | length)"' 2>/dev/null)
TOTAL_IN_WINDOW=$(printf '%s' "$COUNTS" | awk '{print $1}')
MISSED_IN_WINDOW=$(printf '%s' "$COUNTS" | awk '{print $2}')
if ! [[ "$TOTAL_IN_WINDOW" =~ ^[0-9]+$ && "$MISSED_IN_WINDOW" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse check-in counts" >&2
  exit 2
fi
if [[ "$TOTAL_IN_WINDOW" -eq 0 ]]; then
  echo "FAIL(b): zero check-ins at all in ${WINDOW_DAYS}d — neither the dispatch nor the schedule fallback is delivering"
  FAILURES=$((FAILURES + 1))
elif [[ "$MISSED_IN_WINDOW" -gt 0 ]]; then
  echo "FAIL(b): $MISSED_IN_WINDOW missed/timeout check-in(s) in ${WINDOW_DAYS}d — #9273 dispatch-primary may not be live"
  FAILURES=$((FAILURES + 1))
else
  echo "ok(b): ${TOTAL_IN_WINDOW} check-ins in ${WINDOW_DAYS}d, 0 missed/timeout"
fi

# --- (c) no armed soleur-ai[bot] PR behind >24h ---
# gh's `mergeable` field reports MERGEABLE/CONFLICTING/UNKNOWN — the `behind`
# distinction needs the REST `mergeable_state`; use the API directly. A PR is
# stale when it is behind AND has been untouched (no update-branch run) for
# >24h — a fresh `behind` is expected between merges.
STALE=0
NOW_S=$(date -u +%s)
while IFS=$'\t' read -r num; do
  [[ -n "$num" ]] || continue
  mstate=$(gh api "repos/jikig-ai/soleur/pulls/${num}" --jq '.mergeable_state' 2>/dev/null) || continue
  updated=$(gh api "repos/jikig-ai/soleur/pulls/${num}" --jq '.updated_at' 2>/dev/null) || continue
  updated_s=$(date -u -d "$updated" +%s 2>/dev/null) || updated_s=$(date -u -jf '%Y-%m-%dT%H:%M:%SZ' "$updated" +%s 2>/dev/null) || continue
  if [[ "$mstate" == "behind" ]] && (( updated_s < NOW_S - 86400 )); then
    echo "FAIL(c): PR #${num} mergeable_state=behind and untouched >24h"
    STALE=$((STALE + 1))
  fi
done < <(gh pr list --repo jikig-ai/soleur --state open --limit 100 \
  --json number,author,autoMergeRequest \
  --jq '.[] | select(.author.login == "soleur-ai" or .author.login == "app/soleur-ai" or .author.login == "soleur-ai[bot]") | select(.autoMergeRequest != null) | .number' 2>/dev/null)
if [[ "$STALE" -gt 0 ]]; then
  FAILURES=$((FAILURES + 1))
else
  echo "ok(c): no armed soleur-ai[bot] PR has sat behind >24h"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  echo "exit: PASS"
  exit 0
fi
echo "exit: FAIL (${FAILURES} assertion group(s) failed)"
exit 1
