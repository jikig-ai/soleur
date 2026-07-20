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
# so on SUCCESS this writes NOTHING non-JSON to EITHER stream (summary + the
# SOLEUR_INNGEST_PREFLIGHT_* markers → journald via `logger` only):
#   { "runs": [ { "functionID": <uuid>, "startedAt": <iso> }, ... ] }
#
# Fail-LOUD (non-zero exit + stderr) on a non-array `.data.runs.edges` — a fetch
# failure / GraphQL error / unexpected shape must NOT read as a false-clean
# "no double-fire". Shape/purity modelled on inngest-registry-probe.sh +
# inngest-inventory.sh's paginated eventsV2 loop.
#
# Bounded (#6258, ADR-106): like the inventory scan, the runs pagination is bounded by a
# wall-clock DEADLINE (date +%s delta; NEVER SECONDS) and a per-run PAGE CEILING, both
# abandon-safe (deadline/ceiling → LOUD SOLEUR_INNGEST_PREFLIGHT_TIMEOUT marker + exit 1,
# NEVER break — a break would emit a truncated HTTP-200 body). Each per-page curl is
# clamped to the REMAINING budget (--max-time = DEADLINE_S − elapsed, floored ≥1) so the
# sum bound `deadline + per_page ≤ outer_curl` holds (Deepen Finding 1). The scan cost is
# cut via a `functionIDs` filter + the page ceiling — the time WINDOW is NEVER narrowed
# (Finding 5): a probe window narrower than the operator's cutover window would surface
# false "missed ticks" at cutover-inngest.yml:704-743 → operator re-fire → DOUBLE-FIRE
# (the exact harm the cutover prevents). Invariant: window ⊇ cutover-relevant period
# (FROM ≤ cutover_instant − 2×max_cron_period).
#
# Inputs (env):
#   INNGEST_DOUBLEFIRE_FUNCTION_IDS — comma-separated cron fn UUIDs (empty ⇒ all)
#   INNGEST_DOUBLEFIRE_FROM / INNGEST_DOUBLEFIRE_UNTIL — STARTED_AT window (ISO-8601)
#   PREFLIGHT_DEADLINE_S / INNGEST_MAX_PAGES — the bounding seams (defaults 50 / 1000)
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
# NEVER narrowed for cost (Finding 5) — keep the window ⊇ the operator cutover window.
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)
FROM_TS="${INNGEST_DOUBLEFIRE_FROM:-$_default_from}"
UNTIL_TS="${INNGEST_DOUBLEFIRE_UNTIL:-}"
FUNCTION_IDS_CSV="${INNGEST_DOUBLEFIRE_FUNCTION_IDS:-}"

# --- Bounding seams (#6258, ADR-106) ---
# In-script wall-clock deadline. Default 50s < the outer curl 60s (cutover-inngest.yml:673);
# the remaining-budget per-page clamp makes the SUM bound airtight (Finding 1).
PREFLIGHT_DEADLINE_S="${PREFLIGHT_DEADLINE_S:-50}"
MAX_PAGES="${INNGEST_MAX_PAGES:-1000}"
CONNECT_TIMEOUT="${INNGEST_CONNECT_TIMEOUT:-5}"
PREFLIGHT_OP="verify-doublefire"
PREFLIGHT_HOST="${INNGEST_PREFLIGHT_HOST:-$(hostname 2>/dev/null || echo unknown)}"
PREFLIGHT_START_S=0
_pf_pages=0
_last_curl_exit=0

# shellcheck disable=SC2016  # $first/$after/$filter/$order are GraphQL variables
readonly GQL_QUERY='query DoubleFireProbe($first: Int!, $after: String, $filter: RunsFilterV2!, $order: [RunsV2OrderBy!]!) {
  runs(first: $first, after: $after, filter: $filter, orderBy: $order) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { cursor node { id functionID status queuedAt startedAt endedAt } }
  }
}'

# ---------------------------------------------------------------------------
# Observability markers (#6258 Deepen Finding 8) — journald-ONLY (stdout IS the pure-JSON
# webhook body). Escape-notation Unicode-separator sanitizer (cq-regex-unicode-separators-
# escape-only). Purity (Finding 13): enum/count/id only — never a raw GraphQL message.
# ---------------------------------------------------------------------------
_pf_sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' \
    | sed $'s/\xc2\x85//g; s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'   # U+0085 NEL, U+2028, U+2029
}
# _pf_scrub (#6258 review P1): redact connection strings/credentials + strip control
# chars / Unicode separators from UNTRUSTED GraphQL errors[].message text before it
# reaches journald (→ Better Stack) or stdout (→ the Actions run log). A postgres://
# DSN can appear in a DB errors[].message on the pool-pressure path this probe targets;
# the SOLEUR_* markers enum-map it, the FATAL/ERROR diagnostics scrub it. stdin→stdout.
_pf_scrub() {
  # Control chars are translated to SPACE, not deleted. Deleting them WELDS
  # adjacent tokens (`host=db.X` + newline + `password=Y` -> one token), which
  # defeats every separator-based rule below. Translating preserves the
  # log-injection guarantee (no raw newline reaches journald) AND keeps tokens
  # separated. (#6617)
  LC_ALL=C tr '\000-\037\177' '[ *]' \
    | sed $'s/\xc2\x85/ /g; s/\xe2\x80\xa8/ /g; s/\xe2\x80\xa9/ /g' \
    | sed -E -e 's#[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]"]*#<uri-redacted>#g' \
             -e 's#[A-Za-z0-9._%+-]+:[^[:space:]"@/]*@[A-Za-z0-9.-]+#<cred-redacted>#g' \
             -e 's#[A-Za-z0-9-]*\.?[a-z0-9]{16,}\.supabase\.co#<db-host-redacted>#g' \
             -e 's#(password|pgpassword)[[:space:]]*=[[:space:]]*\\*"[^"\\]*\\*"#\1=<redacted>#gI' \
             -e 's#(password|pgpassword)[[:space:]]*=[[:space:]]*'"'"'[^'"'"']*'"'"'#\1=<redacted>#gI' \
             -e 's#(password|pgpassword)[[:space:]]*=[^[:space:]",;\\]*#\1=<redacted>#gI' \
             -e 's#(^|[[:space:]])(host|hostaddr|port|dbname|user|password|sslmode|sslrootcert|connect_timeout|application_name|target_session_attrs)=[^[:space:]"]*(([[:space:]]|\\[nrt])+(host|hostaddr|port|dbname|user|password|sslmode|sslrootcert|connect_timeout|application_name|target_session_attrs)=[^[:space:]"]*)+#\1<dsn-redacted>#g'
}
_pf_marker() {
  logger -t "$LOG_TAG" "$(_pf_sanitize "$1")" 2>/dev/null || true
}
_pf_start_marker() {
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_START op=$PREFLIGHT_OP host=$PREFLIGHT_HOST window=${FROM_TS}..${UNTIL_TS:-open} page_ceiling=$MAX_PAGES deadline_s=$PREFLIGHT_DEADLINE_S"
}
_pf_done_marker() {
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_DONE op=$PREFLIGHT_OP pages=$_pf_pages elapsed_ms=$elapsed_ms"
}
_pf_timeout_marker() {  # $1=reason(enum) $2=pages $3=pages_timed_out $4=last_curl_exit
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_TIMEOUT op=$PREFLIGHT_OP pages=$2 elapsed_ms=$elapsed_ms pages_timed_out=$3 last_curl_exit=$4 reason=$1"
}
# Shared loud-abort helper (Finding 6): deadline + ceiling route here → TIMEOUT marker +
# exit 1 (NEVER break). The EXIT trap fires on exit 1 → spool cleaned; exit 1 → webhook non-200.
_pf_abort() {  # $1=reason $2=pages $3=pages_timed_out $4=last_curl_exit
  _pf_timeout_marker "$1" "$2" "$3" "$4"
  echo "inngest-doublefire-probe: FATAL preflight scan aborted reason=$1 pages_scanned=$2 (deadline_s=$PREFLIGHT_DEADLINE_S page_ceiling=$MAX_PAGES from=$FROM_TS) — refusing to emit a truncated (false-clean) run set"
  echo "ERROR: preflight scan aborted reason=$1 pages_scanned=$2" >&2
  exit 1
}

# Build the GraphQL request body for one page. $1 = after-cursor ("" for first).
# Injection-safe: built with jq -n, never shell string interpolation.
build_request_body() {
  local after="$1"
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  # functionIDs: JSON array from the CSV (empty CSV ⇒ [] ⇒ all functions).
  # `printf '%s\n'` (NOT '%s') is load-bearing: with an empty CSV, '%s' emits
  # ZERO BYTES, so `jq -R` has no line to read and emits NOTHING — fn_ids_json
  # becomes "" and the --argjson below aborts with "invalid JSON text passed to
  # --argjson". That is the DEFAULT path (op=verify 2.6 passes no FUNCTION_IDS),
  # so the exactly-once check returned HTTP 500 rather than a verdict. The
  # trailing newline gives jq -R an empty line to split into []. (#6617)
  local fn_ids_json
  fn_ids_json=$(printf '%s\n' "$FUNCTION_IDS_CSV" | jq -Rc 'split(",") | map(select(length > 0))')
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

# Fetch one runs page INTO a file (no command-substitution subshell — so the loop can read
# $_last_curl_exit). A curl failure is swallowed so the caller routes through the loud-abort
# path (set -e must not kill the script before the marker fires).
#   $1=out_file $2=after $3=page $4=max_time
_fetch_runs_page() {
  local out="$1" after="$2" page_num="$3" max_time="$4"
  # Build the body BEFORE the fixture short-circuit (#6617). The seam used to
  # return above this line, so every fixture-driven test bypassed request
  # construction entirely — which is exactly how the empty-CSV --argjson abort
  # shipped green and only surfaced as a live HTTP 500. Constructing first costs
  # one jq call per fixture page and puts ~15 existing tests on the real path.
  local body
  body=$(build_request_body "$after")
  if [[ -n "$FIXTURE_DIR" ]]; then
    cat "${FIXTURE_DIR}/page-${page_num}.json" > "$out"
    _last_curl_exit=0
    return 0
  fi
  if curl -s --max-time "$max_time" --connect-timeout "$CONNECT_TIMEOUT" \
       -X POST -H "Content-Type: application/json" \
       --data-binary "$body" "$GQL_URL" > "$out"; then
    _last_curl_exit=0
  else
    _last_curl_exit=$?
  fi
  return 0
}

run_probe() {
  # --- START marker: the LITERAL first action, before any network call (Finding 8) ---
  PREFLIGHT_START_S=$(date +%s)
  _pf_pages=0
  _pf_start_marker

  # Paginate to exhaustion (bounded), accumulating the projected {functionID,startedAt}
  # runs via a SPOOL FILE (file I/O, no argv size limit — the #5523 pattern).
  local pf_tmp
  pf_tmp=$(mktemp -d)
  # shellcheck disable=SC2064  # expand $pf_tmp NOW so the EXIT trap captures it. EXIT (not
  # RETURN) so the loud-abort `exit 1` branches still clean the spool.
  trap "rm -rf '$pf_tmp'" EXIT
  local spool="$pf_tmp/runs.spool" resp_file="$pf_tmp/runs.resp"
  local after="" page=1 resp has_next end_cursor
  local timed_out=0 last_curl_exit=0 now elapsed remaining
  : > "$spool"
  while :; do
    # --- deadline (SUM bound): abort BEFORE issuing a page that could overshoot ---
    now=$(date +%s); elapsed=$(( now - PREFLIGHT_START_S ))
    if (( elapsed >= PREFLIGHT_DEADLINE_S )); then
      _pf_abort deadline "$(( page - 1 ))" "$timed_out" "$last_curl_exit"
    fi
    remaining=$(( PREFLIGHT_DEADLINE_S - elapsed )); (( remaining < 1 )) && remaining=1
    _fetch_runs_page "$resp_file" "$after" "$page" "$remaining"
    last_curl_exit=$_last_curl_exit
    (( _last_curl_exit != 0 )) && timed_out=$(( timed_out + 1 ))
    resp=$(cat "$resp_file")
    # Fail LOUD on a non-array .data.runs.edges (fetch failure / GraphQL error / unexpected
    # shape) — never a false-clean {runs:[]}. A curl-timeout empty body surfaces here; the
    # marker carries last_curl_exit (splits pool-stall from slow scan). exit 1 → webhook non-200.
    if ! echo "$resp" | jq -e '.data.runs.edges | type == "array"' >/dev/null 2>&1; then
      local err_msgs data_keys gql_msg
      err_msgs=$(echo "$resp" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
      err_msgs=$(printf '%s' "$err_msgs" | _pf_scrub)   # #6258 P1: no DSN/creds to journald+stdout
      data_keys=$(echo "$resp" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
      gql_msg=$(echo "$resp" | jq -r '(.errors // [])[0].message // ""' 2>/dev/null | tr -d '\n\r' || echo "")
      gql_msg=$(printf '%s' "$gql_msg" | _pf_scrub)
      _pf_timeout_marker gql_error "$page" "$timed_out" "$last_curl_exit"
      logger -t "$LOG_TAG" "ERROR: malformed runs response on page $page: errors=$err_msgs data_keys=$data_keys" 2>/dev/null || true
      echo "inngest-doublefire-probe: FATAL malformed runs response on page $page (from=$FROM_TS): ${gql_msg:-runs missing; check the RunsFilterV2 bound / endpoint}"
      echo "ERROR: malformed runs response on page $page: errors=$err_msgs data_keys=$data_keys" >&2
      exit 1
    fi
    # Append this page's projected runs (functionID + startedAt ONLY — no bodies).
    echo "$resp" | jq -c '[ .data.runs.edges[].node | {functionID, startedAt} ]' >> "$spool"
    has_next=$(echo "$resp" | jq -r '.data.runs.pageInfo.hasNextPage // false')
    end_cursor=$(echo "$resp" | jq -r '.data.runs.pageInfo.endCursor // ""')
    if [[ "$has_next" == "true" ]]; then
      # P3-b: hasNextPage=true but endCursor empty ⇒ more runs exist but we cannot page to
      # them. Breaking here would SILENTLY TRUNCATE the run set → a missed double-fire reads
      # clean. Fail LOUD (exit 1 → webhook non-200) instead of a break-clean.
      if [[ -z "$end_cursor" ]]; then
        _pf_timeout_marker gql_error "$page" "$timed_out" "$last_curl_exit"
        logger -t "$LOG_TAG" "ERROR: pagination truncated on page $page: hasNextPage=true but endCursor empty" 2>/dev/null || true
        echo "inngest-doublefire-probe: FATAL pagination truncated on page $page (hasNextPage=true, endCursor empty) — refusing to emit a possibly-truncated (false-clean) run set"
        echo "ERROR: pagination truncated on page $page: hasNextPage=true, endCursor empty" >&2
        exit 1
      fi
      # Page ceiling — "about to fetch page > MAX_PAGES WHILE hasNextPage=true" (exact-fit breaks clean).
      if (( page + 1 > MAX_PAGES )); then
        _pf_abort page_ceiling "$page" "$timed_out" "$last_curl_exit"
      fi
      after="$end_cursor"
      page=$(( page + 1 ))
    else
      break
    fi
  done
  # Collapse all spooled per-page arrays into one flat run array — file IN, file OUT.
  #
  # ARGV CEILING (#6736). The collapsed set stays in a FILE and is never round-tripped
  # through a shell variable on its way to jq. It used to land in $all_runs and be bound
  # as `--argjson r "$all_runs"` on the final emit, which made the entire paginated run
  # set ONE argv argument; the kernel caps a SINGLE argv argument at
  # MAX_ARG_STRLEN = 131,072 B — verified by bisect on this host: 131,071 B passes,
  # 131,072 B fails E2BIG. That is NOT `getconf ARG_MAX` (2,097,152 B, the argv+envp
  # total); a payload at 6% of ARG_MAX still dies.
  #
  # This was the #5523 defect re-introduced ONE LINE AFTER its own fix: the loop above
  # spools every page to disk precisely to avoid an argv-sized accumulator (see the
  # "no argv size limit — the #5523 pattern" comment on the spool), and then the final
  # emit handed the whole thing back to execve. The spool bought nothing.
  #
  # The bound is the page ceiling ($MAX_PAGES × $PAGE_SIZE runs), not anything about
  # bytes, so it was never safe: at the default page budget the run set can exceed
  # 131,072 B long before MAX_PAGES is reached, and the failure lands on the LOUD path
  # (exit non-zero → webhook non-200) only by luck — `jq` dying on E2BIG here would
  # surface as a probe crash, not as the deliberate TIMEOUT marker.
  local runs_file="$pf_tmp/runs.json"
  jq -s 'add // []' "$spool" > "$runs_file"
  _pf_pages=$(( _pf_pages + page ))

  # Observability summary (count ONLY, never run bodies) → journald only.
  local run_count
  run_count=$(jq 'length' "$runs_file")
  logger -t "$LOG_TAG" "doublefire probe: runs=$run_count from=$FROM_TS until=${UNTIL_TS:-<open>}" 2>/dev/null || true
  _pf_done_marker

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  # File input, so the run array never crosses execve.
  jq -c '{runs: .}' "$runs_file"
}

# Run only when executed directly — sourcing (unit tests) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_probe
fi
