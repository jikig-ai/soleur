#!/usr/bin/env bash
# inngest-enumerate-reminders.sh — no-SSH cutover step-2 enumeration (#5450).
#
# Runs ON THE HOST (delivered via the infra-config push, invoked through the
# /hooks/inngest-enumerate-reminders GET hook). Queries the self-hosted inngest
# GraphQL (`127.0.0.1:8288/v0/gql`, no auth on loopback in `start` mode) for
# `reminder.scheduled` events that are STILL ARMED — future-dated AND not yet
# fired — and emits a JSON array of FULL re-armable records to stdout so the
# cutover can re-arm them against the fresh Postgres+Redis backend without
# silently dropping the operator's pending reminders.
#
# Schema pinned (verified vs inngest v1.19.4):
#   knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md
# Load-bearing facts the runbook's old `id name receivedAt` query got wrong:
#   - The payload lives in `raw: String!` — a JSON-string envelope that MUST be
#     parsed; there is NO `data` field. `JSON.parse(raw).data` = producer payload,
#     `.ts` = future fire epoch-ms.
#   - `eventsV2(filter:{from,until})` bounds `receivedAt` (ingest time), NOT
#     `occurredAt`/fire-time — so a future reminder cannot be selected
#     server-side. We fetch a WIDE receivedAt window then filter client-side on
#     `occurredAt > now`.
#   - `node.runs[].status` terminal set {COMPLETED,CANCELLED,FAILED,SKIPPED} = the
#     reminder already fired → drop. Empty `runs` = armed, never picked up → keep.
#
# Output (stdout): JSON array of `{reminder_id, fire_at, actor, action}` — exactly
# the POST /api/internal/schedule-reminder body. The route recomputes the inngest
# dedup keys `id`(=reminder_id) + `ts`(=Date.parse(fire_at)) on re-arm, so feeding
# these records back through the route preserves idempotency (no double-fire).
#
# Read-only: no writes, no service restart. Safe to call anytime.
#
# Test seam: when INNGEST_GQL_FIXTURE_DIR is set, page N is read from
# "${INNGEST_GQL_FIXTURE_DIR}/page-N.json" instead of curling; ENUMERATE_NOW_MS
# overrides "now" for deterministic future/past filtering.
set -euo pipefail

readonly LOG_TAG="inngest-enumerate-reminders"

GQL_URL="${INNGEST_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
PAGE_SIZE="${INNGEST_GQL_PAGE_SIZE:-50}"
# receivedAt lower bound. A reminder armed long ago but firing in the future must
# still be in-window, so default to the unix epoch — the client-side occurredAt
# filter does the real future/past selection. Overridable for a tighter window.
FROM_TS="${ENUMERATE_FROM:-1970-01-01T00:00:00Z}"
# "now" in epoch-ms; the future/past cutoff. Overridable for tests.
NOW_MS="${ENUMERATE_NOW_MS:-$(date +%s%3N)}"
FIXTURE_DIR="${INNGEST_GQL_FIXTURE_DIR:-}"

# shellcheck disable=SC2016  # $first/$after/$filter are GraphQL variables, not shell expansions
readonly GQL_QUERY='query EnumReminders($first: Int!, $after: String, $filter: EventsFilter!) {
  eventsV2(first: $first, after: $after, filter: $filter) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { cursor node { id name occurredAt receivedAt idempotencyKey raw runs { id status startedAt endedAt } } }
  }
}'

# Fetch one page. $1 = after-cursor ("" for first), $2 = page number (fixture mode).
# Echoes the raw GraphQL JSON response. Injection-safe: the request body is built
# with `jq -n --arg/--argjson`, never shell string interpolation.
fetch_page() {
  local after="$1" page_num="$2"
  if [[ -n "$FIXTURE_DIR" ]]; then
    cat "${FIXTURE_DIR}/page-${page_num}.json"
    return 0
  fi
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  local body
  body=$(jq -nc \
    --arg q "$GQL_QUERY" \
    --argjson first "$PAGE_SIZE" \
    --argjson after "$after_json" \
    --arg from "$FROM_TS" \
    '{query:$q, variables:{first:$first, after:$after, filter:{from:$from, eventNames:["reminder.scheduled"], includeInternalEvents:false}}}')
  curl -s --max-time 15 \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary "$body" \
    "$GQL_URL"
}

# --- Paginate to exhaustion, accumulating edges ---
all_edges="[]"
after=""
page=1
while :; do
  resp=$(fetch_page "$after" "$page")
  if ! echo "$resp" | jq -e '.data.eventsV2' >/dev/null 2>&1; then
    logger -t "$LOG_TAG" "ERROR: malformed GraphQL response on page $page" 2>/dev/null || true
    echo "ERROR: malformed GraphQL response on page $page" >&2
    echo "$resp" >&2
    exit 1
  fi
  page_edges=$(echo "$resp" | jq -c '.data.eventsV2.edges // []')
  all_edges=$(jq -nc --argjson a "$all_edges" --argjson b "$page_edges" '$a + $b')
  has_next=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.hasNextPage // false')
  end_cursor=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.endCursor // ""')
  [[ "$has_next" == "true" && -n "$end_cursor" ]] || break
  after="$end_cursor"
  page=$((page + 1))
done

# --- Filter to STILL-ARMED + project the re-armable record ---
# Keep iff: future fire (raw.ts > now) AND no run in the terminal set.
records=$(echo "$all_edges" | jq -c --argjson now "$NOW_MS" '
  [ .[]
    | (.node.raw | fromjson) as $env
    | select(($env.ts // 0) > $now)
    | select( any(.node.runs[]?; .status as $s | (["COMPLETED","CANCELLED","FAILED","SKIPPED"] | index($s)) != null) | not )
    | { reminder_id: $env.data.reminder_id, fire_at: $env.data.fire_at, actor: $env.data.actor, action: $env.data.action }
  ]')

# --- Observability summary (P2-sec-a: counts + reminder_ids ONLY, never bodies) ---
count=$(echo "$records" | jq 'length')
ids=$(echo "$records" | jq -r '[.[].reminder_id] | join(",")')
logger -t "$LOG_TAG" "armed reminders to re-arm: count=$count ids=[$ids]" 2>/dev/null || true
echo "inngest-enumerate-reminders: $count armed reminder(s) to re-arm: [$ids]" >&2

echo "$records"
