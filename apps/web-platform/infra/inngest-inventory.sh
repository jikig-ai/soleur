#!/usr/bin/env bash
# inngest-inventory.sh — no-SSH full-state inventory for the durable-backend
# cutover (#5509). Runs ON THE HOST (delivered via the infra-config push, invoked
# through the /hooks/inngest-inventory GET hook). Captures a single JSON baseline
# of everything the cutover could lose moving off the volume-based SQLite store, so
# an operator can diff BEFORE vs AFTER and prove nothing was dropped:
#
#   { "functions":      [<registered function name/slug>, ...],   # /v0/gql functions
#     "event_names":    [<distinct event name>, ...],             # eventsV2 (ALL)
#     "armed_reminders": [{reminder_id,fire_at,actor,action}, ...],   # enumerate proj.
#     "durability_state": "durable"|"degraded"|"sqlite_only"|"unknown" }  # #5553
#
# durability_state (#5553) is the no-SSH continuous-durability surface: a between-deploy
# detector (.github/workflows/scheduled-inngest-health.yml) reads it every 15 min and
# files an advisory issue when the host runs non-durable (sqlite_only/degraded) between
# deploys — the deploy-time ci-deploy.sh signal fires only at deploy time. Derived
# on-host from `systemctl show -p ExecStart inngest-server.service` + `systemctl is-active
# inngest-redis.service`, mirroring the canonical ci-deploy.sh:277-287 verdict (pinned by
# a cross-file drift-guard test). Only the ENUM is emitted — never the ExecStart string
# (the $VAR-form connection refs stay on-host; #5503 purity). Test seams:
# INVENTORY_EXECSTART, INVENTORY_REDIS_ACTIVE (CI has no systemd).
#
# Read-only: no writes, no service restart. Safe to call anytime.
#
# Schema pinned (verified vs inngest v1.19.4):
#   knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md
# Loopback (127.0.0.1:8288, no auth in `start` mode): the /v0/gql `functions` query
# returns {data:{functions:[{id,name,slug,triggers,...}]}}  # verified: 2026-06-18
# (GET /v1/functions is an UNREGISTERED 404 in v1.19.4 → the old bare-number `shape`
# was the "404 page not found" body's leading token, #5517); /v0/gql eventsV2 carries
# the event envelope in `raw: String!` (parse with fromjson; `.ts` = future fire
# epoch-ms; `from`/`until` bound receivedAt NOT fire-time → wide window + client-side
# future filter).
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
# on-host journald via `logger` ONLY (read with `journalctl -t inngest-inventory`).
# The journald summary DOES now reach Better Stack: `inngest-inventory` was added to
# Vector's tag allowlist (vector.toml:132, #5526), so the `durability=<enum>` summary
# is the load-bearing no-SSH carrier for the between-deploy degraded state (#5553).
# Internal shell consumers use `$(...)` (stdout only), so the merge happens solely at
# the webhook boundary.
#
# Test seam: INNGEST_GQL_FIXTURE_DIR (page-N.json for eventsV2), INVENTORY_FUNCTIONS_FIXTURE
# (a file with the /v0/gql functions-query response), INVENTORY_NOW_MS (deterministic "now").
set -euo pipefail

readonly LOG_TAG="inngest-inventory"

GQL_URL="${INNGEST_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
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

# Registered-function query (#5517). GET /v1/functions is an UNREGISTERED 404 in
# v1.19.4; the top-level GraphQL `functions` field (same /v0/gql endpoint eventsV2
# uses, no auth on loopback) returns the rich object array the devserver UI shows.
# We project names only, so id/name/slug suffice (no appName discovery needed).
readonly FUNCTIONS_GQL_QUERY='query InvFunctions { functions { id name slug } }'

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

# Fetch the registered-function list via /v0/gql (fixture or loopback). Echoes the raw
# GraphQL response {data:{functions:[...]}}. Injection-safe body via jq -n.
fetch_functions() {
  if [[ -n "$FUNCTIONS_FIXTURE" ]]; then
    cat "$FUNCTIONS_FIXTURE"
    return 0
  fi
  local body
  body=$(jq -nc --arg q "$FUNCTIONS_GQL_QUERY" '{query:$q}')
  # On a real curl failure emit a GraphQL error envelope (no .data.functions) so
  # run_inventory fails LOUD below. A silent "[]" would record a false-clean empty
  # `functions` baseline that the cutover before/after diff cannot distinguish from a
  # real loss (#5509 review P3 — false-confidence on a degraded read).
  curl -s --max-time 15 -X POST -H "Content-Type: application/json" \
    --data-binary "$body" "$GQL_URL" || echo '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}'
}

# Derive a no-SSH durability verdict from the live inngest-server unit (#5553),
# mirroring the canonical ci-deploy.sh:277-287 rule EXACTLY (the deploy-time verdict
# source of truth; kept token-identical in intent and pinned by the cross-file
# drift-guard test). Reads only the CONFIGURED ExecStart ($VAR form — NEVER the
# resolved connection string, #5503 purity / AC3) + inngest-redis activeness, and
# emits ONE enum on stdout:
#   durable     — durable sentinel (--postgres-max-open-conns) present AND inngest-redis active
#   degraded    — durable sentinel present but redis inactive
#                 (the #5542 incident state: durable backend, broken durability
#                 invariant — ci-deploy treats this as a hard FAIL)
#   sqlite_only — no durable sentinel (the SQLite-only fail-safe ExecStart, #5547)
#   unknown     — ExecStart unreadable (empty); the server-down case is already
#                 caught upstream by the .data.functions array guard
# Detection sentinel (#5560): durability is keyed on the NON-SECRET
# --postgres-max-open-conns flag, NOT --postgres-uri/--redis-uri — those URIs are now
# delivered via the doppler-run ENVIRONMENT (never argv) so they no longer appear in
# the ExecStart. inngest-bootstrap.sh writes --postgres-max-open-conns ONLY in the
# durable branch (present iff durable). This keeps the parser reading the $VAR-form
# ExecStart only (NEVER a resolved connection string, #5503 purity / AC3).
# Test seams: INVENTORY_EXECSTART / INVENTORY_REDIS_ACTIVE (CI has no systemd).
# Unset-only (`${VAR-…}`, not `:-`) so an explicitly-empty seam deterministically
# means "unit read came back empty → unknown" regardless of any systemd on the runner.
# SOLEUR-DEBT: 3rd of 3 ExecStart-durability parsers (ci-deploy.sh source-of-truth,
# inngest-wiped-volume-verify.sh subset, this). Kept in sync by test_durability_drift_guard,
# NOT a shared sourced lib (infra has no source-lib precedent). Upgrade trigger: a 4th
# durable-sentinel ExecStart parser appears -> extract inngest-durability-lib.sh. Tracked: #5450.
derive_durability_state() {
  local exec_start redis_active
  exec_start="${INVENTORY_EXECSTART-$(systemctl show -p ExecStart inngest-server.service 2>/dev/null || true)}"
  redis_active="${INVENTORY_REDIS_ACTIVE-$(systemctl is-active inngest-redis.service 2>/dev/null || echo inactive)}"
  if [[ -z "$exec_start" ]]; then
    echo "unknown"; return 0
  fi
  if [[ "$exec_start" == *'--postgres-max-open-conns'* ]]; then
    if [[ "$redis_active" != "active" ]]; then
      echo "degraded"; return 0
    fi
    echo "durable"; return 0
  fi
  echo "sqlite_only"
}

run_inventory() {
  # --- functions: names only (fall back to slug/id if the element lacks .name) ---
  local fn_body functions
  fn_body=$(fetch_functions)
  # Fail LOUD (not false-clean []) if the /v0/gql functions query failed or returned a
  # non-array .data.functions. A legitimately-empty inngest returns {data:{functions:[]}}
  # → passes this gate and yields functions=[] correctly; a fetch failure, a GraphQL
  # error envelope, or any unexpected shape (incl. a bare array — the pre-#5517 wrong
  # assumption) trips it. The guard is NOT loosened to accept any shape.
  if ! echo "$fn_body" | jq -e '.data.functions | type == "array"' >/dev/null 2>&1; then
    # #5503 purity: surface only GraphQL error MESSAGES + .data KEY NAMES, never values.
    local fn_errs fn_keys
    fn_errs=$(echo "$fn_body" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
    fn_keys=$(echo "$fn_body" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
    logger -t "$LOG_TAG" "ERROR: /v0/gql functions unreachable or non-array: errors=$fn_errs data_keys=$fn_keys" 2>/dev/null || true
    echo "inngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=$fn_errs data_keys=$fn_keys); is inngest-server.service up? — refusing to emit a false-clean empty functions baseline"
    echo "ERROR: /v0/gql functions non-array (errors=$fn_errs data_keys=$fn_keys)" >&2
    exit 1
  fi
  functions=$(echo "$fn_body" | jq -c '[ .data.functions[] | (.name // .slug // .id // empty) ] | sort')

  # --- eventsV2: paginate ALL events to exhaustion ---
  # #5523: accumulate page edges via a SPOOL FILE, not argv. The old form passed the
  # entire running accumulator to jq as a single command-line argument every page
  # (via --argjson); once it crossed the
  # kernel per-arg ceiling (MAX_ARG_STRLEN, ~128 KB) the execve(2) of jq failed with
  # "Argument list too long" (the live HTTP 500). Appending each page's edges array to
  # a temp file and collapsing once with `jq -s 'add // []'` reads via file I/O — no
  # argv size limit. Pattern precedent: github-community.sh:294 (the same #5523-class
  # learning's fix). `// []` keeps a zero-page run well-formed.
  local edges_file after="" page=1 resp has_next end_cursor all_edges
  edges_file=$(mktemp)
  # shellcheck disable=SC2064  # expand $edges_file NOW so the trap body captures this
  # value, not whatever the name resolves to at fire time. EXIT (not RETURN): RETURN
  # does NOT fire on `exit`, so the two `exit 1` FATAL branches below would leak the
  # spool file under RETURN. Registered INSIDE run_inventory, so the sourced-by-test
  # path (run_inventory is never called when sourced — BASH_SOURCE guard) never sets it.
  trap "rm -f '$edges_file'" EXIT
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
    # Append this page's edges array as ONE JSON value (one line) to the spool file;
    # file I/O has no argv size limit (unlike the old per-page --argjson accumulation).
    echo "$resp" | jq -c '.data.eventsV2.edges // []' >> "$edges_file"
    has_next=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.hasNextPage // false')
    end_cursor=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.endCursor // ""')
    [[ "$has_next" == "true" && -n "$end_cursor" ]] || break
    after="$end_cursor"
    page=$((page + 1))
  done
  # Collapse all spooled per-page arrays into one flat edge array via file input.
  all_edges=$(jq -s 'add // []' "$edges_file")

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

  # --- durability_state: no-SSH continuous-durability surface (#5553) ---
  # Enum only (durable|degraded|sqlite_only|unknown); never the ExecStart string.
  local durability_state
  durability_state=$(derive_durability_state)

  # --- Observability summary (counts + reminder_ids + durability ENUM ONLY, never
  #     bodies or connection strings) → journald only (#5503) ---
  local fn_count ev_count armed_count armed_ids
  fn_count=$(echo "$functions" | jq 'length')
  ev_count=$(echo "$event_names" | jq 'length')
  armed_count=$(echo "$armed" | jq 'length')
  armed_ids=$(echo "$armed" | jq -r '[.[].reminder_id] | join(",")')
  logger -t "$LOG_TAG" "inventory: functions=$fn_count event_names=$ev_count armed=$armed_count armed_ids=[$armed_ids] durability=$durability_state" 2>/dev/null || true

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  jq -nc --argjson f "$functions" --argjson e "$event_names" --argjson r "$armed" --arg d "$durability_state" \
    '{functions:$f, event_names:$e, armed_reminders:$r, durability_state:$d}'
}

# Run only when executed directly — sourcing (the unit test) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_inventory
fi
