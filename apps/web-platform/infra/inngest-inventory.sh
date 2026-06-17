#!/usr/bin/env bash
# inngest-inventory.sh — no-SSH full-state inventory for the durable-backend
# cutover (#5509). Runs ON THE HOST (delivered via the infra-config push, invoked
# through the /hooks/inngest-inventory GET hook). Captures a single JSON baseline
# of everything the cutover could lose moving off the volume-based SQLite store, so
# an operator can diff BEFORE vs AFTER and prove nothing was dropped:
#
#   { "functions":      [<registered function name/slug>, ...],   # /v1/functions
#     "event_names":    [<distinct event name>, ...],             # eventsV2 (ALL)
#     "armed_reminders": [{reminder_id,fire_at,actor,action}, ...] }  # enumerate proj.
#
# Read-only: no writes, no service restart. Safe to call anytime.
#
# Schema pinned (verified vs inngest v1.19.4):
#   knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md
# Loopback (127.0.0.1:8288, no auth in `start` mode): GET /v1/functions returns a
# JSON array of registered functions; /v0/gql eventsV2 carries the event envelope in
# `raw: String!` (parse with fromjson; `.ts` = future fire epoch-ms; `from`/`until`
# bound receivedAt NOT fire-time → wide window + client-side future filter).
#
# armed_reminders mirrors inngest-enumerate-reminders.sh's projection EXACTLY
# (future fire `raw.ts > now` AND no terminal run) so the inventory's armed set and
# the cutover's re-arm set agree. We run ONE eventsV2 query over ALL events
# (no eventNames filter, includeInternalEvents:true) and derive both event_names and
# armed_reminders from the same edge set.
#
# #5509/#5503 — the webhook (adnanh/webhook v2.8.2) returns cmd.CombinedOutput()
# (stdout AND stderr) even on a 200, and the cutover workflow parses this body as a
# JSON OBJECT. So on the SUCCESS path this script must write NOTHING non-JSON to
# EITHER stream: stdout carries only the final object, and the summary goes to
# on-host journald via `logger` ONLY (read with `journalctl -t inngest-inventory`;
# it does NOT reach Better Stack — see #5495). Internal shell consumers use `$(...)`
# (stdout only), so the merge happens solely at the webhook boundary.
#
# Test seam: INNGEST_GQL_FIXTURE_DIR (page-N.json for eventsV2), INVENTORY_FUNCTIONS_FIXTURE
# (a file with the /v1/functions JSON), INVENTORY_NOW_MS (deterministic "now").
set -euo pipefail

readonly LOG_TAG="inngest-inventory"

GQL_URL="${INNGEST_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
FUNCTIONS_URL="${INNGEST_FUNCTIONS_URL:-http://127.0.0.1:8288/v1/functions}"
PAGE_SIZE="${INNGEST_GQL_PAGE_SIZE:-50}"
# receivedAt lower bound — same 365-day clamp as enumerate (#5492): the epoch is
# rejected by inngest v1.19.4 as out-of-range. ENUMERATE_FROM widens it for a deeper
# arm→fire horizon. BusyBox-safe fallback (mirrors inngest-wiped-volume-verify.sh).
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)
FROM_TS="${ENUMERATE_FROM:-$_default_from}"
NOW_MS="${INVENTORY_NOW_MS:-$(date +%s%3N)}"
FIXTURE_DIR="${INNGEST_GQL_FIXTURE_DIR:-}"
FUNCTIONS_FIXTURE="${INVENTORY_FUNCTIONS_FIXTURE:-}"

# shellcheck disable=SC2016  # $first/$after/$filter are GraphQL variables, not shell expansions
readonly GQL_QUERY='query InvEvents($first: Int!, $after: String, $filter: EventsFilter!) {
  eventsV2(first: $first, after: $after, filter: $filter) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { cursor node { id name occurredAt receivedAt idempotencyKey raw runs { id status startedAt endedAt } } }
  }
}'

# Build the GraphQL request body for one page (ALL events — NO eventNames filter, so
# event_names captures cron/* etc.). $1 = after-cursor ("" for first). Injection-safe
# via jq -n. Extracted so the default filter.from is unit-testable (#5492 AC6 pattern).
build_request_body() {
  local after="$1"
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  jq -nc \
    --arg q "$GQL_QUERY" \
    --argjson first "$PAGE_SIZE" \
    --argjson after "$after_json" \
    --arg from "$FROM_TS" \
    '{query:$q, variables:{first:$first, after:$after, filter:{from:$from, includeInternalEvents:true}}}'
}

# Fetch one eventsV2 page. $1 = after-cursor, $2 = page number (fixture mode).
fetch_page() {
  local after="$1" page_num="$2"
  if [[ -n "$FIXTURE_DIR" ]]; then
    cat "${FIXTURE_DIR}/page-${page_num}.json"
    return 0
  fi
  local body
  body=$(build_request_body "$after")
  curl -s --max-time 15 -X POST -H "Content-Type: application/json" \
    --data-binary "$body" "$GQL_URL"
}

# Fetch the registered-function list (fixture or loopback). Echoes the raw JSON array.
fetch_functions() {
  if [[ -n "$FUNCTIONS_FIXTURE" ]]; then
    cat "$FUNCTIONS_FIXTURE"
    return 0
  fi
  curl -s --max-time 15 "$FUNCTIONS_URL" || echo "[]"
}

run_inventory() {
  # --- functions: names only (fall back to slug/id if the element lacks .name) ---
  local fn_body functions
  fn_body=$(fetch_functions)
  functions=$(echo "$fn_body" | jq -c '
    if type=="array"
    then [ .[] | (.name // .slug // .id // empty) ] | sort
    else [] end' 2>/dev/null || echo '[]')

  # --- eventsV2: paginate ALL events to exhaustion ---
  local all_edges="[]" after="" page=1 resp page_edges has_next end_cursor
  while :; do
    resp=$(fetch_page "$after" "$page")
    if ! echo "$resp" | jq -e '.data.eventsV2' >/dev/null 2>&1; then
      # #5503 purity: surface only GraphQL error MESSAGES + .data KEY NAMES, never
      # the raw response / .errors[].extensions / .data values. exit 1 → webhook non-200.
      local err_msgs data_keys gql_msg
      err_msgs=$(echo "$resp" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
      data_keys=$(echo "$resp" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
      gql_msg=$(echo "$resp" | jq -r '(.errors // [])[0].message // ""' 2>/dev/null | tr -d '\n\r' || echo "")
      logger -t "$LOG_TAG" "ERROR: malformed GraphQL response on page $page: errors=$err_msgs data_keys=$data_keys" 2>/dev/null || true
      echo "inngest-inventory: FATAL malformed GraphQL response on page $page (from=$FROM_TS): ${gql_msg:-eventsV2 missing; check the inngest Time bound / endpoint}"
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

  # --- event_names: distinct sorted set across ALL events ---
  local event_names
  event_names=$(echo "$all_edges" | jq -c '[ .[].node.name ] | unique')

  # --- armed_reminders: enumerate's projection (future fire AND no terminal run) ---
  local armed
  armed=$(echo "$all_edges" | jq -c --argjson now "$NOW_MS" '
    [ .[]
      | select(.node.name == "reminder.scheduled")
      | (.node.raw | fromjson) as $env
      | select(($env.ts // 0) > $now)
      | select( any(.node.runs[]?; .status as $s | (["COMPLETED","CANCELLED","FAILED","SKIPPED"] | index($s)) != null) | not )
      | { reminder_id: $env.data.reminder_id, fire_at: $env.data.fire_at, actor: $env.data.actor, action: $env.data.action }
    ]')

  # --- Observability summary (counts + reminder_ids ONLY, never bodies) → journald only (#5503) ---
  local fn_count ev_count armed_count armed_ids
  fn_count=$(echo "$functions" | jq 'length')
  ev_count=$(echo "$event_names" | jq 'length')
  armed_count=$(echo "$armed" | jq 'length')
  armed_ids=$(echo "$armed" | jq -r '[.[].reminder_id] | join(",")')
  logger -t "$LOG_TAG" "inventory: functions=$fn_count event_names=$ev_count armed=$armed_count armed_ids=[$armed_ids]" 2>/dev/null || true

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  jq -nc --argjson f "$functions" --argjson e "$event_names" --argjson r "$armed" \
    '{functions:$f, event_names:$e, armed_reminders:$r}'
}

# Run only when executed directly — sourcing (the unit test) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_inventory
fi
