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
#     the future fire-time using `raw.ts` (== `occurredAt`, the producer ts;
#     using the already-parsed epoch-ms avoids re-parsing the ISO string).
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
# receivedAt lower bound (#5492). The client-side occurredAt/raw.ts future filter
# does the real selection; this only bounds how far back we look for the INGEST
# (arm) time of a still-armed reminder. The epoch (1970) was WRONG — inngest
# v1.19.4 rejects it as an out-of-range `Time!` bound, so eventsV2 returned no
# `.data.eventsV2` → exit 1 → the opaque HTTP 500 that blocked the cutover.
# Default to a 365-day lookback: a recent, inngest-accepted bound that covers any
# realistic arm→fire horizon (the schedule-reminder route puts NO upper bound on
# fire_at, so a reminder COULD be armed >365d before firing — for that edge case
# the operator widens the window via ENUMERATE_FROM, which still wins below).
# Named-variable + BusyBox-safe fallback (mirrors inngest-wiped-volume-verify.sh):
# a bare ${VAR:-$(date -d '365 days ago')} aborts under `set -e` on non-GNU date.
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)   # BusyBox fallback: now (caller sets ENUMERATE_FROM for a wider window)
FROM_TS="${ENUMERATE_FROM:-$_default_from}"
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

# Build the GraphQL request body for one page. $1 = after-cursor ("" for first).
# Reads FROM_TS / PAGE_SIZE / GQL_QUERY from the environment. Injection-safe: built
# with `jq -n --arg/--argjson`, never shell string interpolation. Extracted so the
# default `filter.from` bound is unit-testable without a live inngest (#5492 AC6).
build_request_body() {
  local after="$1"
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  jq -nc \
    --arg q "$GQL_QUERY" \
    --argjson first "$PAGE_SIZE" \
    --argjson after "$after_json" \
    --arg from "$FROM_TS" \
    '{query:$q, variables:{first:$first, after:$after, filter:{from:$from, eventNames:["reminder.scheduled"], includeInternalEvents:false}}}'
}

# Fetch one page. $1 = after-cursor ("" for first), $2 = page number (fixture mode).
# Echoes the raw GraphQL JSON response.
fetch_page() {
  local after="$1" page_num="$2"
  if [[ -n "$FIXTURE_DIR" ]]; then
    cat "${FIXTURE_DIR}/page-${page_num}.json"
    return 0
  fi
  local body
  body=$(build_request_body "$after")
  curl -s --max-time 15 \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary "$body" \
    "$GQL_URL"
}

run_enumerate() {
  # --- Paginate to exhaustion, accumulating edges ---
  local all_edges="[]" after="" page=1 resp page_edges has_next end_cursor
  while :; do
    resp=$(fetch_page "$after" "$page")
    if ! echo "$resp" | jq -e '.data.eventsV2' >/dev/null 2>&1; then
      # P2-sec-a: webhook v2.8.2 CombinedOutput() captures BOTH streams and the
      # workflow cats the response body into the collaborator-readable run log, so
      # NEITHER stream may carry the event `.data` payload. Surface ONLY the GraphQL
      # error MESSAGES (API strings — e.g. "out-of-range Time bound") + the `.data`
      # KEY NAMES (structure, not values). Never the raw response, never the whole
      # `.errors` (its `extensions` can carry arbitrary data), never `.data` values.
      local err_msgs data_keys gql_msg
      err_msgs=$(echo "$resp" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
      data_keys=$(echo "$resp" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
      gql_msg=$(echo "$resp" | jq -r '(.errors // [])[0].message // ""' 2>/dev/null | tr -d '\n\r' || echo "")
      logger -t "$LOG_TAG" "ERROR: malformed GraphQL response on page $page: errors=$err_msgs data_keys=$data_keys" 2>/dev/null || true
      # STDOUT cause line (surfaced via the webhook response + workflow ::error::):
      # the upstream GraphQL message is a diagnosable, payload-free API string.
      echo "inngest-enumerate-reminders: FATAL malformed GraphQL response on page $page (from=$FROM_TS): ${gql_msg:-eventsV2 missing; check the inngest Time bound / endpoint}"
      echo "ERROR: malformed GraphQL response on page $page: errors=$err_msgs data_keys=$data_keys" >&2
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
  local records
  records=$(echo "$all_edges" | jq -c --argjson now "$NOW_MS" '
    [ .[]
      | (.node.raw | fromjson) as $env
      | select(($env.ts // 0) > $now)
      | select( any(.node.runs[]?; .status as $s | (["COMPLETED","CANCELLED","FAILED","SKIPPED"] | index($s)) != null) | not )
      | { reminder_id: $env.data.reminder_id, fire_at: $env.data.fire_at, actor: $env.data.actor, action: $env.data.action }
    ]')

  # --- Observability summary (P2-sec-a: counts + reminder_ids ONLY, never bodies) ---
  local count ids
  count=$(echo "$records" | jq 'length')
  ids=$(echo "$records" | jq -r '[.[].reminder_id] | join(",")')
  logger -t "$LOG_TAG" "armed reminders to re-arm: count=$count ids=[$ids]" 2>/dev/null || true
  echo "inngest-enumerate-reminders: $count armed reminder(s) to re-arm: [$ids]" >&2

  echo "$records"
}

# Run the enumeration only when executed directly — sourcing (the unit test for
# build_request_body / the clamped FROM_TS default) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_enumerate
fi
