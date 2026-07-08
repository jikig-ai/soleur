#!/usr/bin/env bash
# inngest-doublefire-probe.sh — 2.6 exactly-once cron-run enumeration for the
# Inngest dedicated-host cutover verify (#6178, P1-12, ADR-100). Runs ON A WEB HOST
# (delivered via the infra-config push, invoked through the
# /hooks/inngest-doublefire-probe GET hook).
#
# The `op=verify` workflow arm cannot reach the deny-all-public dedicated host
# (10.0.1.40) from a GitHub runner; a web host reaches :8288 over the private
# subnet (SEC-H2). This probe POSTs the top-level
# `runs(first, filter: RunsFilterV2!, orderBy)` query and REPORTS the raw cron runs
# in the window; the `op=verify` arm does the (functionID, floor(startedAt /
# cron_period)) exactly-once bucketing (no group > 1 ⇒ no double-fire).
#
# There is NO per-tick schedule field in inngest v1.19.4 (ADR-100 Decision 7) — the
# exactly-once invariant is derived downstream from startedAt, never a tick field.
# The introspected surface (phase0-empirical-spike.md): RunsFilterV2 =
# { from: Time!, until: Time, timeField (QUEUED_AT|STARTED_AT|ENDED_AT),
#   status, functionIDs: [UUID!], appIDs, query }; FunctionRunV2 node carries
# { id, functionID, status, queuedAt, startedAt, endedAt, ... }.
#
# Output (stdout): a single pure-JSON object — run metadata ONLY (functionID +
# startedAt), never reminder bodies / actors / connection strings (P2-sec-a). The
# webhook returns CombinedOutput and the workflow jq-parses the body as an OBJECT,
# so on SUCCESS this writes NOTHING non-JSON to EITHER stream (summary → journald
# via `logger` only):
#   { "runs": [ { "functionID": <uuid>, "startedAt": <iso> }, ... ] }
#
# Fail-LOUD (non-zero exit + stderr) on a non-array `.data.runs.edges` — a fetch
# failure / GraphQL error / unexpected shape must NOT read as a false-clean
# "no double-fire". Shape/purity modelled on inngest-registry-probe.sh +
# inngest-inventory.sh's paginated eventsV2 loop.
#
# Inputs (env):
#   INNGEST_DOUBLEFIRE_FUNCTION_IDS — comma-separated cron fn UUIDs (empty ⇒ all)
#   INNGEST_DOUBLEFIRE_FROM / INNGEST_DOUBLEFIRE_UNTIL — STARTED_AT window (ISO-8601)
# Test seam: INNGEST_DOUBLEFIRE_RUNS_FIXTURE (a dir with page-N.json runs
# responses) short-circuits the curl.
set -euo pipefail

readonly LOG_TAG="inngest-doublefire-probe"

# The DEDICATED host GQL over the private net (NOT loopback). Mirrors the
# registry-probe's INNGEST_REMOTE_GQL_URL parameterisation.
GQL_URL="${INNGEST_REMOTE_GQL_URL:-http://10.0.1.40:8288/v0/gql}"
PAGE_SIZE="${INNGEST_GQL_PAGE_SIZE:-100}"
FIXTURE_DIR="${INNGEST_DOUBLEFIRE_RUNS_FIXTURE:-}"

# STARTED_AT lower bound. Same 365-day clamp + BusyBox-safe fallback as the sibling
# inngest scripts (the epoch is rejected by v1.19.4 as an out-of-range Time bound).
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)
FROM_TS="${INNGEST_DOUBLEFIRE_FROM:-$_default_from}"
UNTIL_TS="${INNGEST_DOUBLEFIRE_UNTIL:-}"
FUNCTION_IDS_CSV="${INNGEST_DOUBLEFIRE_FUNCTION_IDS:-}"

# shellcheck disable=SC2016  # $first/$after/$filter/$order are GraphQL variables
readonly GQL_QUERY='query DoubleFireProbe($first: Int!, $after: String, $filter: RunsFilterV2!, $order: [RunsV2OrderBy!]!) {
  runs(first: $first, after: $after, filter: $filter, orderBy: $order) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { cursor node { id functionID status queuedAt startedAt endedAt } }
  }
}'

# Build the GraphQL request body for one page. $1 = after-cursor ("" for first).
# Injection-safe: built with jq -n, never shell string interpolation.
build_request_body() {
  local after="$1"
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  # functionIDs: JSON array from the CSV (empty CSV ⇒ [] ⇒ all functions).
  local fn_ids_json
  fn_ids_json=$(printf '%s' "$FUNCTION_IDS_CSV" | jq -Rc 'split(",") | map(select(length > 0))')
  local until_json="null"
  [[ -n "$UNTIL_TS" ]] && until_json=$(jq -nc --arg u "$UNTIL_TS" '$u')
  jq -nc \
    --arg q "$GQL_QUERY" \
    --argjson first "$PAGE_SIZE" \
    --argjson after "$after_json" \
    --arg from "$FROM_TS" \
    --argjson until "$until_json" \
    --argjson fnids "$fn_ids_json" \
    '{query:$q, variables:{first:$first, after:$after,
       filter:{from:$from, until:$until, timeField:"STARTED_AT", functionIDs:$fnids},
       order:[{field:"STARTED_AT", direction:"ASC"}]}}'
}

# Fetch one runs page. $1 = after-cursor, $2 = page number (fixture mode).
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

run_probe() {
  # Paginate to exhaustion, accumulating the projected {functionID,startedAt} runs
  # via a SPOOL FILE (file I/O, no argv size limit — same #5523-class pattern the
  # sibling inngest scripts use).
  local edges_file after="" page=1 resp has_next end_cursor all_runs
  edges_file=$(mktemp)
  # shellcheck disable=SC2064  # expand $edges_file NOW so the EXIT trap captures it
  trap "rm -f '$edges_file'" EXIT
  while :; do
    resp=$(fetch_page "$after" "$page")
    # Fail LOUD on a non-array .data.runs.edges (fetch failure / GraphQL error /
    # unexpected shape) — never a false-clean {runs:[]}. exit 1 → webhook non-200.
    if ! echo "$resp" | jq -e '.data.runs.edges | type == "array"' >/dev/null 2>&1; then
      local err_msgs data_keys gql_msg
      err_msgs=$(echo "$resp" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
      data_keys=$(echo "$resp" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
      gql_msg=$(echo "$resp" | jq -r '(.errors // [])[0].message // ""' 2>/dev/null | tr -d '\n\r' || echo "")
      logger -t "$LOG_TAG" "ERROR: malformed runs response on page $page: errors=$err_msgs data_keys=$data_keys" 2>/dev/null || true
      echo "inngest-doublefire-probe: FATAL malformed runs response on page $page (from=$FROM_TS): ${gql_msg:-runs missing; check the RunsFilterV2 bound / endpoint}"
      echo "ERROR: malformed runs response on page $page: errors=$err_msgs data_keys=$data_keys" >&2
      exit 1
    fi
    # Append this page's projected runs (functionID + startedAt ONLY — no bodies).
    echo "$resp" | jq -c '[ .data.runs.edges[].node | {functionID, startedAt} ]' >> "$edges_file"
    has_next=$(echo "$resp" | jq -r '.data.runs.pageInfo.hasNextPage // false')
    end_cursor=$(echo "$resp" | jq -r '.data.runs.pageInfo.endCursor // ""')
    # P3-b: hasNextPage=true but endCursor empty ⇒ more runs exist but we cannot page to
    # them. Breaking here would SILENTLY TRUNCATE the run set → a missed double-fire reads
    # clean. Fail LOUD (exit 1 → webhook non-200) instead of a break-clean.
    if [[ "$has_next" == "true" && -z "$end_cursor" ]]; then
      logger -t "$LOG_TAG" "ERROR: pagination truncated on page $page: hasNextPage=true but endCursor empty" 2>/dev/null || true
      echo "inngest-doublefire-probe: FATAL pagination truncated on page $page (hasNextPage=true, endCursor empty) — refusing to emit a possibly-truncated (false-clean) run set"
      echo "ERROR: pagination truncated on page $page: hasNextPage=true, endCursor empty" >&2
      exit 1
    fi
    [[ "$has_next" == "true" ]] || break
    after="$end_cursor"
    page=$((page + 1))
  done
  # Collapse all spooled per-page arrays into one flat run array via file input.
  all_runs=$(jq -s 'add // []' "$edges_file")

  # Observability summary (count ONLY, never run bodies) → journald only.
  local run_count
  run_count=$(echo "$all_runs" | jq 'length')
  logger -t "$LOG_TAG" "doublefire probe: runs=$run_count from=$FROM_TS until=${UNTIL_TS:-<open>}" 2>/dev/null || true

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  jq -nc --argjson r "$all_runs" '{runs:$r}'
}

# Run only when executed directly — sourcing (unit tests) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_probe
fi
