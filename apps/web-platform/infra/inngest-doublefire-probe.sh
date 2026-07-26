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
# NEVER break — a break would emit a truncated HTTP-200 body).
#
# PER-PAGE BUDGET (#6919 — the op=verify HTTP 500 fix). The per-page curl --max-time is the
# REMAINING wall-clock budget (`remaining = DEADLINE_S − elapsed`) FLOORED to
# PREFLIGHT_PAGE_MIN_S and CAPPED at PREFLIGHT_PAGE_MAX_S. The floor is load-bearing: the
# earlier code clamped purely to `remaining`, so once slow early pages had drained the
# budget every LATE page got ~0s → curl timed out → EMPTY body → the fail-loud guard
# mis-read the empty body as a "malformed runs response" and 500'd (deterministic
# starvation, reproduced on run 29729623865 page 6). The floor guarantees each page a
# viable timeout; the cap keeps one slow page from hogging the whole budget. SUM bound
# (Deepen Finding 1): a page is only ISSUED while `elapsed < DEADLINE`, and the near-
# deadline retry is blocked by a fresh deadline re-check, so the worst-case wall overshoot
# past DEADLINE is one PAGE_MIN → the airtight bound is `DEADLINE + PAGE_MIN ≤ outer_curl`
# (default 90 + 8 = 98 < the 120s outer curl at cutover-inngest.yml).
#
# TRANSIENT vs MALFORMED (#6919). A curl NON-ZERO exit OR an EMPTY/whitespace body is a
# TRANSIENT transport failure (timeout / truncation), NOT a GraphQL error: the page is
# retried ONCE with a fresh per-page budget; a second transient → LOUD `reason=transport`
# abort (accurate remediation: narrow the anchor, or scope functionIDs — NOT the deadline,
# which the SUM bound caps at 112 s), NEVER the
# "malformed" verdict. A NON-EMPTY body whose `.data.runs.edges` is not an array is
# GENUINELY malformed → the fail-loud `reason=gql_error` path (never masked as clean).
#
# WINDOW POLICY (#6178 — CHANGED; this paragraph used to assert the opposite).
#
# It previously read "the time WINDOW is NEVER narrowed", and the caller honoured that with
# a fixed cutover − 200d. Measurement retired it: the dedicated host executes ~728 cron runs
# per DAY (Phase 0, run 30121678305), so a 200-day window holds ~145,600 runs ≈ 1,456 pages
# against a ~18-page budget. The scan could not exhaust its window, and this probe is
# fail-loud on non-exhaustion (`_pf_abort` exits 1 and emits NOTHING) — so op=verify died
# on `reason=deadline` with no verdict, every time, and the exactly-once gate never ran.
# A comment asserting the opposite of what the code must do is how that survived.
#
# The invariant was never "182 days"; that number was the FUNCTION-DISCOVERY term (a window
# wide enough that even a quarterly cron appears at least once for the missed-tick loop).
# The DOUBLE-FIRE invariant is only:
#
#     window ⊇ [coexistence_start − 2×cron_period , now]
#
# where coexistence_start is the instant the dedicated host's scheduler went live. The
# caller (cutover-inngest.yml `doublefire_from`) now derives that instant from the on-host
# flip-FSM transition row and passes it as ?from=, so the window is exactly as wide as the
# invariant needs and no wider. Function discovery is deferred (ADR-146); until it lands,
# slow-cron missed-tick recall is reduced — a recorded trade, not a silent one.
#
# The window stays OPEN-TOPPED (no `until`): the post-repoint and post-rollback coexistence
# regions lie AFTER the recorded cutover window, so bounding the top would cut out the
# highest-risk region while looking like a symmetric tidy-up.
#
# RESIDUAL LIMITATION: the window is anchored on an instant but open-topped, so its cost
# grows with wall-clock as the cutover ages. That is bounded by the PAGE-1 FEASIBILITY GATE
# below, which reads the server's own `totalCount` on the first page and aborts in ~2 s with
# a COMPUTED latest-viable anchor rather than burning the full deadline to say nothing.
# `INNGEST_DOUBLEFIRE_FUNCTION_IDS` remains available as a hard cost cut.
#
# Inputs (env):
#   INNGEST_DOUBLEFIRE_FUNCTION_IDS — comma-separated cron fn UUIDs (empty ⇒ all)
#   INNGEST_DOUBLEFIRE_FROM / INNGEST_DOUBLEFIRE_UNTIL — STARTED_AT window (ISO-8601)
#   PREFLIGHT_DEADLINE_S / INNGEST_MAX_PAGES — the bounding seams (defaults 90 / 1000)
#   PREFLIGHT_PAGE_MIN_S / PREFLIGHT_PAGE_MAX_S — per-page curl floor/cap (defaults 8 / 15)
#   PREFLIGHT_SEC_PER_PAGE — measured s/page, the page-1 feasibility divisor (default 5)
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
# This is only the DEFAULT used when no caller supplies ?from=; the cutover workflow always
# supplies an anchored bound (see WINDOW POLICY above, which retired the former
# "never narrowed" rule for this scan).
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)
FROM_TS="${INNGEST_DOUBLEFIRE_FROM:-$_default_from}"
UNTIL_TS="${INNGEST_DOUBLEFIRE_UNTIL:-}"
FUNCTION_IDS_CSV="${INNGEST_DOUBLEFIRE_FUNCTION_IDS:-}"

# --- Bounding seams (#6258, ADR-106; #6919 per-page floor) ---
# In-script wall-clock deadline. Default 90s < the outer curl 120s (cutover-inngest.yml); the
# per-page floor/cap keeps the SUM bound `DEADLINE + PAGE_MIN ≤ outer_curl` airtight (Finding 1).
PREFLIGHT_DEADLINE_S="${PREFLIGHT_DEADLINE_S:-90}"
# Per-page curl budget window (#6919). PAGE_MIN is the anti-starvation FLOOR — every page gets
# at least this many seconds so late pages never get ~0s → empty body → false "malformed".
# PAGE_MAX caps a single page so it cannot hog the whole deadline. Invariant for the SUM bound:
# DEADLINE + PAGE_MIN ≤ outer_curl (90 + 8 = 98 < 120). PAGE_MAX < DEADLINE (no single-page hog).
PREFLIGHT_PAGE_MIN_S="${PREFLIGHT_PAGE_MIN_S:-8}"
PREFLIGHT_PAGE_MAX_S="${PREFLIGHT_PAGE_MAX_S:-15}"
MAX_PAGES="${INNGEST_MAX_PAGES:-1000}"
CONNECT_TIMEOUT="${INNGEST_CONNECT_TIMEOUT:-5}"
# Page-1 feasibility divisor (#6178). MEASURED, not guessed: Phase 0 run 30121678305 scanned
# 728 runs (8 pages at PAGE_SIZE=100) in 34 s wall-clock => ~4.2 s/page. Rounded UP to 5 so the
# affordability estimate is conservative (a too-LOW estimate would let an unexhaustible window
# through, which is the failure this gate exists to stop; a too-HIGH one only costs a needlessly
# early abort that names a viable anchor). Override only with a fresh measurement.
PREFLIGHT_SEC_PER_PAGE="${PREFLIGHT_SEC_PER_PAGE:-5}"
PREFLIGHT_OP="verify-doublefire"
PREFLIGHT_HOST="${INNGEST_PREFLIGHT_HOST:-$(hostname 2>/dev/null || echo unknown)}"
PREFLIGHT_START_S=0
_pf_pages=0
_last_curl_exit=0
# The server's count of runs matching the filter across ALL pages, read from page 1.
# The enum `unknown` — never `0` — is the pre-page-1 value: a `0` here is indistinguishable
# from "the window genuinely holds no runs", which is the exact false-clean shape this probe
# exists to refuse. The query has always requested totalCount; until #6178 nothing parsed it.
_pf_total_count="unknown"

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
_pf_done_marker() {  # $1=scanned run count
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_DONE op=$PREFLIGHT_OP pages=$_pf_pages elapsed_ms=$elapsed_ms total_count=$_pf_total_count scanned=${1:-unknown}"
}
_pf_timeout_marker() {  # $1=reason(enum) $2=pages $3=pages_timed_out $4=last_curl_exit
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  # total_count discriminates the three ways this scan fails: "window too wide" (a large
  # measured count), "budget too small" (a small count that still timed out), and "we never
  # got far enough to know" (unknown). Without it every abort looks identical off-box.
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_TIMEOUT op=$PREFLIGHT_OP pages=$2 elapsed_ms=$elapsed_ms pages_timed_out=$3 last_curl_exit=$4 total_count=$_pf_total_count reason=$1"
}
# Shared loud-abort helper (Finding 6): deadline + ceiling route here → TIMEOUT marker +
# exit 1 (NEVER break). The EXIT trap fires on exit 1 → spool cleaned; exit 1 → webhook non-200.
_pf_abort() {  # $1=reason $2=pages $3=pages_timed_out $4=last_curl_exit
  _pf_timeout_marker "$1" "$2" "$3" "$4"
  # REMEDIATION (#6178): this used to advise enlarging the in-script deadline, which was DEAD
  # advice — the SUM bound `DEADLINE + PAGE_MIN <= outer_curl` caps it at 112 s, buying ~14
  # pages against a window that needed ~1,456. An operator following it burned a dispatch to
  # fail identically. The live lever is the WINDOW.
  # (Phrased WITHOUT the imperative+token literal on purpose: the AC3 guard greps this file's
  # body, comments included, so quoting the dead advice here would keep the guard red forever —
  # the comment-vs-assertion collision in cq-assert-anchor-not-bare-token.)
  echo "inngest-doublefire-probe: FATAL preflight scan aborted reason=$1 pages_scanned=$2 (deadline_s=$PREFLIGHT_DEADLINE_S page_ceiling=$MAX_PAGES from=$FROM_TS total_count=$_pf_total_count) — narrow the window (set the CUTOVER_ANCHOR_FROM repo variable, which overrides the flip-FSM anchor) or scope the population or scope INNGEST_DOUBLEFIRE_FUNCTION_IDS; refusing to emit a truncated (false-clean) run set"
  echo "ERROR: preflight scan aborted reason=$1 pages_scanned=$2" >&2
  exit 1
}
# Page-1 feasibility abort (#6178). The scan is REFUSED before it starts, with the arithmetic
# inline and a COMPUTED latest-viable anchor derived from the observed density — so the next
# narrowing is measured rather than extrapolated (v1 of this plan extrapolated "~540 pages"
# from counting cron schedules in source and understated reality by ~2.7x).
#   $1=total_count $2=affordable_runs $3=latest_viable_from(ISO) $4=sec_per_page(as applied)
_pf_abort_window_too_wide() {
  _pf_timeout_marker window_too_wide 1 0 "$_last_curl_exit"
  echo "inngest-doublefire-probe: FATAL window too wide to exhaust — the server reports total_count=$1 run(s) matching from=$FROM_TS, but this budget can scan at most ~$2 (deadline_s=$PREFLIGHT_DEADLINE_S / ~$4s per page x page_size=$PAGE_SIZE). Scanning would burn the full deadline and emit NOTHING. Remediation: set the CUTOVER_ANCHOR_FROM repo variable to $3 or later (computed from the observed density; it OVERRIDES the flip-FSM anchor, unlike CUTOVER_WINDOW_FROM which is consulted only when no anchor is derivable). NOTE: narrowing yields a WINDOW-LIMITED verdict, not a full exactly-once proof — to keep the full window instead, scope the population via CUTOVER_DOUBLEFIRE_FUNCTION_IDS, or scope INNGEST_DOUBLEFIRE_FUNCTION_IDS; refusing to emit a truncated (false-clean) run set"
  echo "ERROR: window too wide: total_count=$1 affordable=$2 latest_viable_from=$3" >&2
  exit 1
}
# Transient-transport loud abort (#6919): a page that is STILL empty / curl-failed after one
# retry with a fresh per-page budget. This is a truncation / timeout / budget exhaustion — an
# ACCURATE, non-"malformed" verdict — so it never masks a real double-fire as clean and never
# mislabels a transient empty body as a malformed GraphQL response. exit 1 → webhook non-200.
_pf_abort_transport() {  # $1=page $2=pages_timed_out $3=last_curl_exit
  _pf_timeout_marker transport "$1" "$2" "$3"
  logger -t "$LOG_TAG" "ERROR: transport exhaustion on page $1 after retry: empty/failed body (last_curl_exit=$3)" 2>/dev/null || true
  echo "inngest-doublefire-probe: FATAL empty/truncated runs response on page $1 after 1 retry (last_curl_exit=$3, from=$FROM_TS, total_count=$_pf_total_count) — transient transport failure or preflight budget exhaustion, NOT a malformed GraphQL response; narrow the window (set the CUTOVER_ANCHOR_FROM repo variable, which overrides the flip-FSM anchor) or scope the population or scope INNGEST_DOUBLEFIRE_FUNCTION_IDS — refusing to emit a truncated (false-clean) run set"
  echo "ERROR: transport/budget exhaustion on page $1 after retry (last_curl_exit=$3)" >&2
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
#   $1=out_file $2=after $3=page $4=max_time $5=attempt(1|2, default 1)
_fetch_runs_page() {
  local out="$1" after="$2" page_num="$3" max_time="$4" attempt="${5:-1}"
  # Build the body BEFORE the fixture short-circuit (#6617). The seam used to
  # return above this line, so every fixture-driven test bypassed request
  # construction entirely — which is exactly how the empty-CSV --argjson abort
  # shipped green and only surfaced as a live HTTP 500. Constructing first costs
  # one jq call per fixture page and puts ~15 existing tests on the real path.
  local body
  body=$(build_request_body "$after")
  if [[ -n "$FIXTURE_DIR" ]]; then
    # Retry seam (#6919): on a RETRY (attempt >= 2) prefer page-N.retry.json when present, so a
    # test can model a page that returns a transient EMPTY body on attempt 1 and RECOVERS on 2.
    local fixture_file="${FIXTURE_DIR}/page-${page_num}.json"
    if (( attempt >= 2 )) && [[ -f "${FIXTURE_DIR}/page-${page_num}.retry.json" ]]; then
      fixture_file="${FIXTURE_DIR}/page-${page_num}.retry.json"
    fi
    cat "$fixture_file" > "$out"
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
  local timed_out=0 last_curl_exit=0 now elapsed remaining max_time
  : > "$spool"
  while :; do
    # --- deadline (SUM bound): abort BEFORE issuing a page that could overshoot ---
    now=$(date +%s); elapsed=$(( now - PREFLIGHT_START_S ))
    if (( elapsed >= PREFLIGHT_DEADLINE_S )); then
      _pf_abort deadline "$(( page - 1 ))" "$timed_out" "$last_curl_exit"
    fi
    # Per-page curl budget: the REMAINING wall-clock, FLOORED to PAGE_MIN (anti-starvation —
    # #6919: never hand a late page ~0s → empty body → false "malformed") and CAPPED at PAGE_MAX
    # (no single page hogs the deadline). The near-deadline floor overshoots DEADLINE by at most
    # one PAGE_MIN, which the SUM bound `DEADLINE + PAGE_MIN ≤ outer_curl` absorbs.
    remaining=$(( PREFLIGHT_DEADLINE_S - elapsed )); (( remaining < 1 )) && remaining=1
    max_time=$remaining
    (( max_time > PREFLIGHT_PAGE_MAX_S )) && max_time=$PREFLIGHT_PAGE_MAX_S
    (( max_time < PREFLIGHT_PAGE_MIN_S )) && max_time=$PREFLIGHT_PAGE_MIN_S
    _fetch_runs_page "$resp_file" "$after" "$page" "$max_time" 1
    last_curl_exit=$_last_curl_exit
    resp=$(cat "$resp_file")
    # --- TRANSIENT classification (#6919): a curl NON-ZERO exit OR an EMPTY/whitespace body is a
    # transport timeout/truncation, NOT a malformed GraphQL response. Retry the page ONCE with a
    # FRESH per-page budget (if the deadline still allows one); a second transient → LOUD
    # reason=transport abort. This is what stops budget-starvation from reading as "malformed". ---
    if (( last_curl_exit != 0 )) || [[ -z "${resp//[[:space:]]/}" ]]; then
      timed_out=$(( timed_out + 1 ))
      now=$(date +%s); elapsed=$(( now - PREFLIGHT_START_S ))
      if (( elapsed >= PREFLIGHT_DEADLINE_S )); then
        _pf_abort deadline "$(( page - 1 ))" "$timed_out" "$last_curl_exit"
      fi
      remaining=$(( PREFLIGHT_DEADLINE_S - elapsed )); (( remaining < 1 )) && remaining=1
      max_time=$remaining
      (( max_time > PREFLIGHT_PAGE_MAX_S )) && max_time=$PREFLIGHT_PAGE_MAX_S
      (( max_time < PREFLIGHT_PAGE_MIN_S )) && max_time=$PREFLIGHT_PAGE_MIN_S
      _fetch_runs_page "$resp_file" "$after" "$page" "$max_time" 2
      last_curl_exit=$_last_curl_exit
      resp=$(cat "$resp_file")
      if (( last_curl_exit != 0 )) || [[ -z "${resp//[[:space:]]/}" ]]; then
        timed_out=$(( timed_out + 1 ))
        _pf_abort_transport "$page" "$timed_out" "$last_curl_exit"
      fi
    fi
    # Fail LOUD on a non-array .data.runs.edges (GraphQL error / unexpected shape) — never a
    # false-clean {runs:[]}. Reached ONLY with a NON-EMPTY body (transient empties handled
    # above), so this is a GENUINE malformed response, not a transport timeout. exit 1 → non-200.
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
    # --- PAGE-1 FEASIBILITY GATE (#6178) --------------------------------------------
    # The query has always asked for `totalCount`; nothing ever parsed it, so the scan
    # fetched its own scale on every page and discarded it. That is why "how many runs are
    # in this window" read as an inherent unknown rather than a one-line omission, and why
    # eleven op=verify dispatches burned ~112 s each to emit NOTHING.
    #
    # Reached only AFTER the edges-array validation above, so the body is known well-formed.
    if (( page == 1 )); then
      local tc afford_pages affordable_runs
      tc=$(echo "$resp" | jq -r '.data.runs.totalCount // empty' 2>/dev/null || echo "")
      if ! [[ "$tc" =~ ^[0-9]+$ ]]; then
        # The gate cannot run without a usable count. Skipping is fail-closed on its own (the
        # scan then burns the deadline and aborts), but "the gate did not run" must be visible
        # off-box rather than inferred from a later abort.
        _pf_marker "SOLEUR_INNGEST_PREFLIGHT_GATE op=$PREFLIGHT_OP feasibility_gate=skipped reason=totalcount_unparseable"
      fi
      if [[ "$tc" =~ ^[0-9]+$ ]]; then
        _pf_total_count="$tc"
        # Affordability in RUNS, from the measured per-page rate. Both operands are clamped
        # so a hostile/degenerate override cannot divide by zero or yield a zero budget that
        # would abort every window (a gate that always fires is as useless as one that never does).
        local sec_per_page="$PREFLIGHT_SEC_PER_PAGE"
        [[ "$sec_per_page" =~ ^[1-9][0-9]*$ ]] || sec_per_page=5
        afford_pages=$(( PREFLIGHT_DEADLINE_S / sec_per_page ))
        (( afford_pages < 1 )) && afford_pages=1
        affordable_runs=$(( afford_pages * PAGE_SIZE ))
        if (( tc > affordable_runs )); then
          # COMPUTED remediation. The window is [FROM_TS, now); if tc runs occupy that span,
          # the span that would hold `affordable_runs` is proportional. Take 80% of that
          # boundary so the recommendation actually FITS rather than landing exactly on the
          # edge — density is not uniform, and an anchor that fails again teaches nothing.
          local now_e from_e span viable_span latest_viable
          now_e=$(date -u +%s)
          from_e=$(date -u -d "$FROM_TS" +%s 2>/dev/null || echo "")
          latest_viable="<unknown — supply a later CUTOVER_WINDOW_FROM>"
          if [[ "$from_e" =~ ^[0-9]+$ ]]; then
            span=$(( now_e - from_e ))
            if (( span > 0 )); then
              viable_span=$(( span * affordable_runs * 8 / (tc * 10) ))
              (( viable_span < 60 )) && viable_span=60
              latest_viable=$(date -u -d "@$(( now_e - viable_span ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || echo "<unknown — supply a later CUTOVER_WINDOW_FROM>")
            fi
          fi
          _pf_abort_window_too_wide "$tc" "$affordable_runs" "$latest_viable" "$sec_per_page"
        fi
      fi
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
  logger -t "$LOG_TAG" "doublefire probe: runs=$run_count total_count=$_pf_total_count from=$FROM_TS until=${UNTIL_TS:-<open>}" 2>/dev/null || true
  _pf_done_marker "$run_count"

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  # File input, so the run array never crosses execve.
  #
  # total_count is ADDITIVE (#6178) — the workflow's shape guard reads `.runs | type ==
  # "array"`, which is unaffected. It lets the caller distinguish a clean verdict over a
  # REAL population from one over an empty scan: "no duplicates found" and "nothing was
  # looked at" are the same string and opposite facts. Emitted as the enum string
  # `unknown` when page 1 never parsed, never as a 0 that reads as a measured empty.
  jq -c --arg tc "$_pf_total_count" \
    '{runs: ., total_count: (if $tc == "unknown" then $tc else ($tc | tonumber) end)}' "$runs_file"
}

# Run only when executed directly — sourcing (unit tests) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_probe
fi
