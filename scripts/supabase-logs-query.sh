#!/usr/bin/env bash
# Query Supabase project logs via the Management API's REPLACEMENT analytics
# endpoint, and NEVER hand back a row count without the coverage verdict that
# tells you whether the count means anything.
#
#   GET /v1/projects/{ref}/analytics/endpoints/logs
#
# replacing the deprecated `analytics/endpoints/logs.all` (removal announced for
# 2026-09-23). Contract measured live; every number, quirk and refuted claim
# cited below lives in ONE place — do not restate it here:
#   knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md
#
# WHY THIS SCRIPT EXISTS
# ======================
# On 2026-06-29 an ad-hoc curl against this API answered a GDPR access question
# with a bare `0`. The zero was not "no access occurred" — it was an
# uninstrumented source over a window that partly predated retention, returned
# with HTTP 200 and `error: null`. Nothing in the response distinguished it from
# a real zero. This helper exists so that shape cannot be produced again: every
# answer is an inseparable evidence block, and the verdict is bound to the exit
# code so it survives `$?`.
#
# USAGE
#   doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh \
#       --source postgres_logs --since 24h
#
# See --help for flags and the exit-code table.
#
# HOST PIN — NO ENV OVERRIDE
# ==========================
# This process holds a Supabase cloud-admin PAT. An overridable host is a
# PAT-exfil-via-redirect seam, and the literal below is additionally enumerated
# by the deprecation-assembly guard. Testability comes from stubbing the curl
# BINARY on PATH (see tests/scripts/test-supabase-logs-query.sh), which costs
# production nothing. Same reasoning, same shape as scripts/supabase-advisor-scan.sh.
#
# CLICKHOUSE DIALECT — DO NOT INVENT THE IDIOMS
# =============================================
# The endpoint's own OpenAPI description states the SQL must be ClickHouse
# dialect. scripts/betterstack-query.sh already writes ClickHouse against a
# different warehouse; its forms are adopted here rather than translating
# BigQuery habits. In particular newest-N-presented-oldest-first is a NESTED
# subquery (see build_rows_sql).
#
# `count(*)` IS ACCEPTED. Secondary sources claim otherwise; that claim is
# REFUTED by direct measurement (evidence file, §Confirmed from the plan). Do
# not "fix" it.
#
# DATA MINIMISATION
# =================
# Bounded --limit default, no artifact, no output file, no `tee`. Note honestly:
# in an agent session stdout lands in a transcript, so the BOUNDED LIMIT — not
# "stdout only" — is the real control. The absence of write sites here is
# mechanically checked by the suite's write-boundary sweep.
# shellcheck disable=SC2034
# SC2034 is disabled file-wide on purpose. The V_* globals below are the
# renderer's INPUT PROTOCOL: they are read by emit_evidence_block /
# emit_evidence_json in scripts/lib/supabase-logs-verdict.sh, which
# ShellCheck cannot see from this file alone. Suppressing per-assignment
# would need a dozen inline directives and would make a genuinely dead V_*
# indistinguishable from a live one; the lib's own suite covers that side.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/supabase-logs-verdict.sh
. "${SCRIPT_DIR}/lib/supabase-logs-verdict.sh"

API="https://api.supabase.com" # pinned — NO env override (see header)

# Finding F: a format-valid WRONG ref passes every other check in this script
# and prints COVERED over another project's data — the one failure nothing else
# catches. Defaulting to the pinned prd literal makes the common case a
# guard-covered constant, and the resolved ref + project NAME are echoed on
# every output path so a wrong ref is visible in the evidence itself.
DEFAULT_REF="pigsfuxruiopinouvjwy"

# Pinned instrumentation span. MUST stay pinned and cited: an unbounded "full
# retained span" enumeration is exactly the wide window that returns 0 for every
# source (evidence file, finding C row), so the naive version marks everything
# UNINSTRUMENTED and trains agents to ignore the verdict. 30 days is the widest
# span in the measured table that still returns a populated, plausible per-source
# breakdown.
INSTRUMENTATION_SPAN_DAYS=30

# Above this width the monotonicity self-check fires. Chosen because the
# measured curve is already non-monotone by 30d.
MONOTONICITY_TRIGGER_DAYS=7

# Log ingestion lags and windows rarely align to a row exactly; an hour of slack
# at each edge keeps "covered" from being unachievable in practice.
COVERAGE_EDGE_TOLERANCE_SEC=3600

BISECT_MAX_STEPS=5
MAX_SLICES=32
DEFAULT_LIMIT=100

# The vendor's documented `source` enumeration. Used ONLY to tell a TYPO
# (finding B — `postgres_logsss`) apart from a real source that is
# UNINSTRUMENTED on this project (finding E — `edge_logs`), because those two
# have different next actions. It is NOT the authority on what exists: the
# runtime enumeration is, since this list can drift.
DOCUMENTED_SOURCES="auth_logs auth_audit_logs edge_logs function_edge_logs function_logs postgrest_logs pgbouncer_logs postgres_logs realtime_logs storage_logs supavisor_logs database_version_upgrade_logs multigres_logs"

# --- V_* globals consumed by the renderer in scripts/lib/supabase-logs-verdict.sh
V_REASON=""; V_REF=""; V_PROJECT=""; V_REQ_START=""; V_REQ_END=""
V_COV_START=""; V_COV_END=""; V_COV_CLASS="NONE"; V_ROWS=""
V_SOURCES_REQ=""; V_SPAN_DAYS="$INSTRUMENTATION_SPAN_DAYS"
V_INSTR_LINE=""; V_WINDOW_LINE=""; V_MONO="not-run"; V_SLICES="none"; V_NEXT=""
V_SOURCES_JSON="[]"; V_SAMPLE_JSON="[]"
JSON_MODE=0

usage() {
  cat <<'HELP'
supabase-logs-query.sh — Supabase project logs with an inseparable coverage verdict.

  scripts/supabase-logs-query.sh [--ref REF] [--source NAME]... [--since W]
                                 [--until W] [--limit N] [--json] [--help]

  --ref REF       project ref, 20 lowercase alnum chars (default: pinned prd ref)
  --source NAME   log source, repeatable; omit for all sources
  --since W       Nm|Nh|Nd relative, or an ISO timestamp (default 24h)
  --until W       Nm|Nh|Nd relative, or an ISO timestamp (default now)
  --limit N       max log lines returned; 0 to skip the tail (default 100)
  --json          emit ONE JSON object on stdout instead of the human block
  --help          this text

EXIT CODES — the verdict is bound to $?, not merely printed
  0  COVERED                    window covered, count trustworthy
  1  INCONCLUSIVE / transient   a 5xx that SURVIVED narrowing; retry is rational
  2  INCONCLUSIVE / auth+config creds, bad ref, stale SQL; retry is NOT rational
  3  INCONCLUSIVE / data        uninstrumented source, partial coverage, window
                                outside retention, or an unresolved width cap
  64 usage error

  DIVERGENCE, deliberate: scripts/betterstack-query.sh uses exit 3 for MISSING
  CREDENTIALS. Here missing credentials are exit 2 and exit 3 is the DATA
  verdict. Documented rather than silently inherited — an agent carrying "3 ==
  no creds" over from the sibling would read this helper's headline verdict as
  a config problem and go hunting in Doppler.

OUTPUT
  Human mode: log lines on stdout (pipeable), the evidence block on stderr.
  --json:     ONE object {verdict, reason, ref, project, coverage, sources,
              rows, next_action, exit_code, sample} on stdout. Never a bare
              array — the machine path carries the verdict or "no bare zero"
              would be true only where a human was reading.
HELP
}

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
REF=""; SINCE="24h"; UNTIL=""; LIMIT="$DEFAULT_LIMIT"
SOURCES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)    REF="${2:-}"; shift 2 ;;
    --source) SOURCES+=("${2:-}"); shift 2 ;;
    --since)  SINCE="${2:-}"; shift 2 ;;
    --until)  UNTIL="${2:-}"; shift 2 ;;
    --limit)  LIMIT="${2:-}"; shift 2 ;;
    --json)   JSON_MODE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'supabase-logs-query.sh: unknown flag: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

REF="${REF:-$DEFAULT_REF}"
V_REF="$REF"
V_PROJECT="(unresolved)"
if (( ${#SOURCES[@]} > 0 )); then
  V_SOURCES_REQ="${SOURCES[*]}"
else
  V_SOURCES_REQ="(all sources)"
fi

fail_now() { V_REASON="$1"; V_NEXT="$2"; emit_and_exit; }

[[ "$REF" =~ ^[a-z0-9]{20}$ ]] || fail_now CONFIG_ERROR \
  "--ref '${REF}' is not a project ref (expected 20 lowercase alphanumerics). A malformed ref cannot be resolved to a project name, and an UNVERIFIED ref is how a COVERED verdict gets printed over the wrong project's data."

[[ "$LIMIT" =~ ^[0-9]+$ ]] || fail_now CONFIG_ERROR \
  "--limit '${LIMIT}' is not a non-negative integer."

for s in ${SOURCES[@]+"${SOURCES[@]}"}; do
  [[ "$s" =~ ^[a-z0-9_]+$ ]] || fail_now CONFIG_ERROR \
    "--source '${s}' is not a source name (expected [a-z0-9_]+). Source names are interpolated into SQL; anything else is rejected outright rather than escaped."
done

# ---------------------------------------------------------------------------
# Credentials. Mirrors scripts/betterstack-query.sh's message deliberately: the
# misdiagnosis it prevents ("this session has no Supabase access, I cannot
# verify") collides head-on with hr-no-dashboard-eyeball-pull-data-yourself.
# ---------------------------------------------------------------------------
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  cat >&2 <<'CREDS'
supabase-logs-query.sh: SUPABASE_ACCESS_TOKEN is not set.

You are NOT missing Supabase access — this PAT lives in Doppler and this script
needs it INJECTED. Re-run wrapped in `doppler run`:

  doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh <args>

e.g.  doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --source postgres_logs --since 24h

Do NOT conclude "no access / can't verify" from this message — the correct next
step is the doppler-wrapped re-run above.
CREDS
  fail_now CONFIG_ERROR "Re-run wrapped in: doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh <args>. Do NOT conclude 'no access / can't verify'."
fi

# ---------------------------------------------------------------------------
# Time window. Both bounds are resolved to absolute ISO here and BOTH are always
# sent — see api_logs.
# ---------------------------------------------------------------------------
to_epoch() {
  local w="$1"
  if [[ "$w" =~ ^([0-9]+)([mhd])$ ]]; then
    local n="${BASH_REMATCH[1]}" u="${BASH_REMATCH[2]}" secs
    case "$u" in m) secs=$((n * 60)) ;; h) secs=$((n * 3600)) ;; d) secs=$((n * 86400)) ;; esac
    printf '%s' "$(( NOW_EPOCH - secs ))"
    return 0
  fi
  date -u -d "$w" +%s 2>/dev/null
}
to_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null; }

NOW_EPOCH="$(date -u +%s)"
START_EPOCH="$(to_epoch "$SINCE")"
if [[ -n "$UNTIL" ]]; then END_EPOCH="$(to_epoch "$UNTIL")"; else END_EPOCH="$NOW_EPOCH"; fi

[[ -n "$START_EPOCH" ]] || fail_now CONFIG_ERROR "--since '${SINCE}' is not Nm|Nh|Nd or an ISO timestamp."
[[ -n "$END_EPOCH" ]]   || fail_now CONFIG_ERROR "--until '${UNTIL}' is not Nm|Nh|Nd or an ISO timestamp."
(( END_EPOCH > START_EPOCH )) || fail_now CONFIG_ERROR "--until must be after --since (got ${SINCE}..${UNTIL:-now})."

START_ISO="$(to_iso "$START_EPOCH")"; END_ISO="$(to_iso "$END_EPOCH")"
V_REQ_START="$START_ISO"; V_REQ_END="$END_ISO"
WIDTH_SEC=$(( END_EPOCH - START_EPOCH ))

# ---------------------------------------------------------------------------
# HTTP. The PAT is piped to curl on STDIN via `--header @-`, never interpolated
# into an argument: the shell expands an inline `-H "Authorization: Bearer $TOK"`
# BEFORE exec, so a cloud-admin token would land in curl's argv and be
# world-readable at /proc/<pid>/cmdline for the life of the request.
# ---------------------------------------------------------------------------
api_get() {
  printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" |
    curl --silent --show-error --max-time 30 \
      --header @- \
      --write-out $'\n%{http_code}' --url "$1" 2>/dev/null
}

# FINDING G — BOTH BOUNDS, ALWAYS.
#
# Both endpoints' OpenAPI descriptions carry the identical sentence "If both are
# not provided, only the last 1 minute of logs will be queried." The DEPRECATED
# endpoint honours it. The REPLACEMENT does not: it returns HTTP 200 with
# {"result":null,"error":"Backend error!..."} instead, reproducibly. So the
# divergence is from the VENDOR'S OWN SPEC, not merely from our plan — which is
# why a reader who checks the docs and concludes the bounds are optional will be
# wrong. Never construct a request without both. (Evidence file, finding G.)
api_logs() {
  local sql="$1" start_iso="$2" end_iso="$3"
  if [[ -z "$start_iso" || -z "$end_iso" ]]; then
    fail_now CONFIG_ERROR "internal: a logs request was constructed without both iso bounds — see finding G in the evidence file; the replacement endpoint answers that with a deterministic 200 Backend error."
  fi
  printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" |
    curl --silent --show-error --max-time 60 --get \
      --header @- \
      --data-urlencode "sql=${sql}" \
      --data-urlencode "iso_timestamp_start=${start_iso}" \
      --data-urlencode "iso_timestamp_end=${end_iso}" \
      --write-out $'\n%{http_code}' \
      --url "${API}/v1/projects/${REF}/analytics/endpoints/logs" 2>/dev/null
}

http_code() { printf '%s' "$1" | tail -1; }
http_body() { printf '%s' "$1" | sed '$d'; }
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

source_predicate() {
  (( ${#SOURCES[@]} == 0 )) && return 0
  local parts="" s
  for s in "${SOURCES[@]}"; do parts="${parts}${parts:+, }$(sql_lit "$s")"; done
  printf ' where source in (%s)' "$parts"
}

# ---------------------------------------------------------------------------
# The one query entry point. FAIL CLOSED: non-2xx, a non-null `.error`, or a
# null `result` all terminate. A row count is NEVER printed for a failed query.
#
# HTTP 500 / "Backend error!" IS NOT CLASSIFIED TRANSIENT ON SIGHT. Finding D is
# deterministic and WINDOW-DEPENDENT, and the instrumentation enumeration is the
# mandatory first call — so a wide window 500s immediately, and a "transient,
# retry" verdict would send an agent into a loop against a deterministically
# failing request. Re-issue ONCE at half width:
#   survives narrowing -> genuinely transient           (exit 1)
#   clears on narrowing -> a WIDTH failure, named as such, slices offered (exit 3)
# Sets Q_RESULT (the parsed `.result` array) on success.
# ---------------------------------------------------------------------------
Q_RESULT=""
run_query() {
  local label="$1" sql="$2" s_iso="$3" e_iso="$4" s_epoch="$5" e_epoch="$6"
  local raw code body err result
  raw="$(api_logs "$sql" "$s_iso" "$e_iso")"
  code="$(http_code "$raw")"; body="$(http_body "$raw")"

  if [[ "$code" =~ ^5 ]] || printf '%s' "$body" | grep -qF 'Backend error!'; then
    local half_start half_start_iso raw2 code2 body2
    half_start=$(( e_epoch - (e_epoch - s_epoch) / 2 ))
    half_start_iso="$(to_iso "$half_start")"
    raw2="$(api_logs "$sql" "$half_start_iso" "$e_iso")"
    code2="$(http_code "$raw2")"; body2="$(http_body "$raw2")"
    if [[ "$code2" == "200" ]] && ! printf '%s' "$body2" | grep -qF 'Backend error!'; then
      V_MONO="half-width retry of '${label}' CLEARED — the failure is window-size, not transient"
      fail_now WINDOW_SIZE_FAILURE \
        "The '${label}' query failed at ${WIDTH_SEC}s wide and SUCCEEDED at half that width, so this is a width failure, not a transient one — retrying the same request will keep failing. Re-run over halves: --since ${START_ISO} --until ${half_start_iso}, then --since ${half_start_iso} --until ${END_ISO}."
    fi
    fail_now TRANSIENT_5XX \
      "The '${label}' query returned HTTP ${code} and STILL failed at half width (HTTP ${code2}), so narrowing does not fix it — this one is genuinely transient. Retry the identical invocation; if it persists past a few minutes it is a vendor incident, not a bad query."
  fi

  if [[ ! "$code" =~ ^2 ]]; then
    if [[ "$code" == "401" || "$code" == "403" ]]; then
      fail_now AUTH_ERROR "The PAT was rejected (HTTP ${code}) on the '${label}' query. Re-run wrapped in \`doppler run -p soleur -c prd --\`; if that is already the case the PAT needs rotating. This is NOT evidence about the logs."
    fi
    fail_now CONFIG_ERROR "The '${label}' query returned HTTP ${code} for ref ${REF}. A 404 here means the ref does not resolve to a project you can read — check the ref before trusting anything else."
  fi

  err="$(printf '%s' "$body" | jq -r 'if type == "object" then (.error // "null") else "MALFORMED" end' 2>/dev/null)"
  if [[ -z "$err" || "$err" == "MALFORMED" ]]; then
    fail_now MALFORMED_RESULT "The '${label}' query returned HTTP ${code} with a body that is not the {result, error} envelope. Treat this as an endpoint contract change, not as zero rows."
  fi
  if [[ "$err" != "null" ]]; then
    # Mode A. The dialect is OURS to get right — the helper builds every query.
    fail_now DIALECT_ERROR \
      "The endpoint rejected the '${label}' query: ${err}. Do NOT hand-write a replacement query — this helper builds the SQL, so a dialect error means THE HELPER IS STALE. File an issue against scripts/supabase-logs-query.sh with this block attached. Hand-writing curl here is how the 2026-06-29 bare zero happened."
  fi

  result="$(printf '%s' "$body" | jq -c '.result' 2>/dev/null)"
  if [[ -z "$result" || "$result" == "null" ]]; then
    fail_now MALFORMED_RESULT "The '${label}' query returned \`result: null\` with \`error: null\` — a shape with no meaning. It is NOT zero rows."
  fi
  Q_RESULT="$result"
}

# ---------------------------------------------------------------------------
# SQL builders. Every aggregate below is deliberately NOT --limit-bound: a
# coverage window computed from a limited row set describes the rows that
# survived the limit, not the window that was asked about.
#
# The range comes from iso_timestamp_start/end, not from a WHERE clause, which
# is the endpoint's documented mechanism. Where a comparison IS written in SQL,
# use parseDateTime64BestEffort('<iso>', 6) — never a bare string literal.
#
# The per-query alias (instrumentation_c / window_source_c / probe_c / bisect_c /
# slice_c / row_ts) is load-bearing beyond readability: it is what lets the test
# harness's fake curl tell the requests apart, so a helper that queries the
# WRONG thing is detectable instead of being answered identically.
# ---------------------------------------------------------------------------
build_instrumentation_sql() {
  printf 'select source, count(*) as instrumentation_c from logs group by source order by instrumentation_c desc'
}
build_window_agg_sql() {
  printf 'select source, count(*) as window_source_c, min(timestamp) as window_lo, max(timestamp) as window_hi from logs group by source order by window_source_c desc'
}
build_probe_sql()  { printf 'select count(*) as probe_c from logs%s' "$(source_predicate)"; }
build_bisect_sql() { printf 'select count(*) as bisect_c from logs%s' "$(source_predicate)"; }
build_slice_sql()  { printf 'select source, count(*) as slice_c, min(timestamp) as slice_lo, max(timestamp) as slice_hi from logs group by source'; }

# Newest-N presented oldest-first is a NESTED subquery. The INNER
# `order by ... desc limit n` selects WHICH rows survive; the OUTER reorders
# them for reading. Flatten it and --limit silently changes which window the
# rows describe.
build_rows_sql() {
  printf 'select row_ts, id, event_message from (select timestamp as row_ts, id, event_message from logs%s order by row_ts desc limit %s) order by row_ts asc' \
    "$(source_predicate)" "$LIMIT"
}

# ---------------------------------------------------------------------------
# Normalisation: every per-source aggregate becomes [{source, c, lo, hi}] so the
# window response and the unioned slice responses are computed identically.
# ---------------------------------------------------------------------------
normalize_agg() {
  printf '%s' "$1" | jq -c --arg c "$2" --arg lo "$3" --arg hi "$4" \
    '[ .[] | { source: (.source // "(unknown)"), c: ((.[$c] // 0) | tonumber?) // 0,
               lo: (.[$lo] // null), hi: (.[$hi] // null) } ]' 2>/dev/null
}
merge_agg() {
  printf '%s\n%s' "$1" "$2" | jq -sc \
    '[ (.[0] + .[1]) | group_by(.source)[] |
       { source: .[0].source, c: (map(.c) | add),
         lo: ([ .[] | .lo | select(. != null) ] | min),
         hi: ([ .[] | .hi | select(. != null) ] | max) } ]' 2>/dev/null
}
agg_sum()  { printf '%s' "$1" | jq -r 'map(.c) | add // 0'; }
agg_lo()   { printf '%s' "$1" | jq -r '[ .[] | .lo | select(. != null) ] | min // ""'; }
agg_hi()   { printf '%s' "$1" | jq -r '[ .[] | .hi | select(. != null) ] | max // ""'; }
agg_subset() {
  printf '%s' "$1" | jq -c --argjson want "$2" 'if ($want | length) == 0 then . else map(select(.source as $s | $want | index($s))) end'
}
sources_json_array() {
  local list="" s
  for s in ${SOURCES[@]+"${SOURCES[@]}"}; do list="${list}${list:+ }${s}"; done
  printf '%s' "$list" | jq -Rc 'if . == "" then [] else split(" ") end'
}

# ---------------------------------------------------------------------------
# Rung 1 — project identity (finding F).
# ---------------------------------------------------------------------------
ID_RAW="$(api_get "${API}/v1/projects/${REF}")"
ID_CODE="$(http_code "$ID_RAW")"; ID_BODY="$(http_body "$ID_RAW")"
if [[ "$ID_CODE" == "401" || "$ID_CODE" == "403" ]]; then
  fail_now AUTH_ERROR "The PAT was rejected (HTTP ${ID_CODE}) resolving ref ${REF}. Re-run wrapped in \`doppler run -p soleur -c prd --\`; if it already was, rotate the PAT. This says NOTHING about the logs."
fi
if [[ ! "$ID_CODE" =~ ^2 ]]; then
  fail_now CONFIG_ERROR "Ref ${REF} did not resolve to a readable project (HTTP ${ID_CODE}). Every count below would have been about an unknown project, so none was taken."
fi
V_PROJECT="$(printf '%s' "$ID_BODY" | jq -r '.name // ""' 2>/dev/null)"
[[ -n "$V_PROJECT" ]] || fail_now MALFORMED_RESULT \
  "Ref ${REF} resolved with HTTP ${ID_CODE} but no project name. Without the project NAME a format-valid WRONG ref is indistinguishable from the right one, so no count is reported."

# ---------------------------------------------------------------------------
# Rung 2 — instrumentation enumeration over the PINNED span. ONE call that both
# validates --source against the observed set (kills finding B) and supplies the
# full-span counts that distinguish UNINSTRUMENTED from empty (kills finding E).
# ---------------------------------------------------------------------------
INSTR_START_EPOCH=$(( NOW_EPOCH - INSTRUMENTATION_SPAN_DAYS * 86400 ))
run_query "instrumentation" "$(build_instrumentation_sql)" \
  "$(to_iso "$INSTR_START_EPOCH")" "$(to_iso "$NOW_EPOCH")" "$INSTR_START_EPOCH" "$NOW_EPOCH"
INSTR_AGG="$(normalize_agg "$Q_RESULT" instrumentation_c _none_ _none_)"
V_INSTR_LINE="$(printf '%s' "$INSTR_AGG" | jq -r 'if length == 0 then "(no source returned any row over the pinned span)" else ([ .[] | "\(.source)=\(.c)=INSTRUMENTED" ] | join(" ")) end')"
OBSERVED="$(printf '%s' "$INSTR_AGG" | jq -r '[ .[] | .source ] | join(" ")')"

# ---------------------------------------------------------------------------
# Rung 3 — the requested window, grouped by source, with min/max. NOT
# --limit-bound. One response serves three purposes:
#   - per-source counts over THIS window (routing, mode E)
#   - the requested sources' count and covered span (the answer)
#   - the PROJECT-WIDE span, which is the retention probe: if no source has any
#     row in the window, the window is outside retention and nothing about it
#     can be concluded — as opposed to the requested source simply being quiet.
# ---------------------------------------------------------------------------
run_query "window" "$(build_window_agg_sql)" "$START_ISO" "$END_ISO" "$START_EPOCH" "$END_EPOCH"
WINDOW_AGG="$(normalize_agg "$Q_RESULT" window_source_c window_lo window_hi)"

WANT_JSON="$(sources_json_array)"

recompute() {
  ALL_LO_ISO="$(agg_lo "$WINDOW_AGG")"; ALL_HI_ISO="$(agg_hi "$WINDOW_AGG")"
  local subset; subset="$(agg_subset "$WINDOW_AGG" "$WANT_JSON")"
  REQ_COUNT="$(agg_sum "$subset")"
  REQ_LO_ISO="$(agg_lo "$subset")"; REQ_HI_ISO="$(agg_hi "$subset")"
  V_WINDOW_LINE="$(printf '%s' "$WINDOW_AGG" | jq -r 'if length == 0 then "(no rows for ANY source in this window)" else ([ .[] | "\(.source)=\(.c)" ] | join(" ")) end')"
}
recompute

# ---------------------------------------------------------------------------
# Rung 4 — source validation, now that both the pinned-span set and the
# in-window set are known. Two distinct next actions, so two distinct reasons.
# ---------------------------------------------------------------------------
routing_hint() {
  local instrumented
  instrumented="$(printf '%s' "$WINDOW_AGG" | jq -r '[ .[] | select(.c > 0) | "\(.source) (\(.c))" ] | join(", ")')"
  if [[ -n "$instrumented" ]]; then
    printf 'Sources that ARE carrying rows over THIS window: %s — one of those may answer the question.' "$instrumented"
  else
    printf 'No source carries any row over this window, so re-routing to another source will not help; the window itself is the problem.'
  fi
}

for s in ${SOURCES[@]+"${SOURCES[@]}"}; do
  if [[ " $DOCUMENTED_SOURCES " != *" $s "* ]]; then
    fail_now UNKNOWN_SOURCE \
      "'${s}' is not a known log source, so it matched nothing and would have returned a clean zero. Sources observed on ${V_PROJECT} over the pinned ${INSTRUMENTATION_SPAN_DAYS}d span: ${OBSERVED:-(none)}. Documented sources: ${DOCUMENTED_SOURCES}. Re-run with one of those."
  fi
  if [[ " $OBSERVED " != *" $s "* ]]; then
    # Mode E, the sharpest one: the per-source counts are already computed, so
    # say UNINSTRUMENTED *and* route. Without the routing half the next
    # investigation repeats the 2026-06-29 source choice.
    fail_now UNINSTRUMENTED \
      "'${s}' is a real source but is UNINSTRUMENTED on ${V_PROJECT}: it returned no row over the pinned ${INSTRUMENTATION_SPAN_DAYS}d span, so a zero from it is evidence about INSTRUMENTATION, not about traffic. $(routing_hint)"
  fi
done

# ---------------------------------------------------------------------------
# Rung 5 — monotonicity self-check, then AUTO-NARROW.
#
# WHY THIS IS CLIENT-SIDE AT ALL: both endpoint descriptions state that a range
# over 24 hours throws a validation error. It does not — measured, a 25-hour
# range and a 61-DAY range both return HTTP 200 with data (evidence file, §The
# documented 24-hour cap is NOT enforced). The vendor's documented guard cannot
# be relied on to reject a too-wide window, so the probe and the coverage
# verdict have to exist here. A reader who finds the vendor's cap in the docs
# and assumes it covers them is exactly the reader this comment is for.
#
# A strictly narrower sub-window cannot legitimately contain MORE rows than the
# window enclosing it. If it does, the wider call was truncated.
#
# THREE KNOWN FALSE-PASS MODES, all real, none papered over:
#   1. The measured curve is non-monotone in BOTH directions, so two samples can
#      land anywhere on it and compare either way.
#   2. If --limit bound both calls they compare equal. It does not here — every
#      aggregate above is unlimited — but a future edit that limits them
#      silently disables this probe.
#   3. WHEN THE WHOLE WINDOW PREDATES RETENTION BOTH CALLS RETURN 0, `0 >= 0`
#      HOLDS, AND THE PROBE DOES NOT FIRE AT ALL. It therefore does NOT close
#      finding C and must never be described as doing so. That case is caught by
#      the coverage verdict below, not by this probe.
# ---------------------------------------------------------------------------
TRUNCATED=0
if (( WIDTH_SEC > MONOTONICITY_TRIGGER_DAYS * 86400 )); then
  SUB_START_EPOCH=$(( END_EPOCH - MONOTONICITY_TRIGGER_DAYS * 86400 ))
  run_query "probe" "$(build_probe_sql)" "$(to_iso "$SUB_START_EPOCH")" "$END_ISO" "$SUB_START_EPOCH" "$END_EPOCH"
  PROBE_COUNT="$(printf '%s' "$Q_RESULT" | jq -r '(.[0].probe_c // 0) | tonumber? // 0')"
  if (( REQ_COUNT < PROBE_COUNT )); then
    TRUNCATED=1
    V_MONO="TRUNCATION DETECTED: the ${WIDTH_SEC}s window returned ${REQ_COUNT} rows but its own last-${MONOTONICITY_TRIGGER_DAYS}d sub-window returned ${PROBE_COUNT}; auto-narrowing"
  else
    V_MONO="probe fired and PASSED: window=${REQ_COUNT} >= last-${MONOTONICITY_TRIGGER_DAYS}d sub-window=${PROBE_COUNT} (note: 0>=0 also passes — this probe does NOT close finding C)"
  fi
else
  V_MONO="not fired (window <= ${MONOTONICITY_TRIGGER_DAYS}d, so there is no strictly narrower sub-window to compare)"
fi

# AUTO-NARROW. Detection without a remedy is a dead end: a helper that exits
# saying "the cap has moved" leaves an agent two rational recoveries — abandon
# the question, or hand-write curl, which is exactly the behaviour this helper
# exists to retire. So bisect the cap the probe just located, re-issue beneath
# it, and UNION the per-slice coverage into ONE verdict.
if (( TRUNCATED == 1 )); then
  lo_h=$(( MONOTONICITY_TRIGGER_DAYS * 24 ))
  hi_h=$(( WIDTH_SEC / 3600 ))
  # Captured BEFORE the bisection, which mutates hi_h. Slicing off the post-loop
  # hi_h would cover only the bisection's final probe width, silently answering
  # a 60-day question with a few days of slices — the truncated short answer
  # this whole arm exists to replace.
  width_h=$hi_h
  step=0
  # Heuristic, and honestly so: the curve is non-monotone, so this locates *a*
  # width that still returns at least the known-good count, not necessarily the
  # exact cap. That is sufficient — every slice is then narrower than a width
  # measured to work.
  while (( step < BISECT_MAX_STEPS && hi_h - lo_h > 1 )); do
    mid_h=$(( (lo_h + hi_h) / 2 ))
    mid_start=$(( END_EPOCH - mid_h * 3600 ))
    run_query "bisect" "$(build_bisect_sql)" "$(to_iso "$mid_start")" "$END_ISO" "$mid_start" "$END_EPOCH"
    mid_c="$(printf '%s' "$Q_RESULT" | jq -r '(.[0].bisect_c // 0) | tonumber? // 0')"
    if (( mid_c >= PROBE_COUNT )); then lo_h=$mid_h; else hi_h=$mid_h; fi
    step=$(( step + 1 ))
  done
  cap_h=$lo_h
  n_slices=$(( (width_h + cap_h - 1) / cap_h ))
  (( n_slices < 1 )) && n_slices=1

  if (( n_slices > MAX_SLICES )); then
    # Auto-narrowing refused (it would take more calls than is reasonable).
    # Print the EXACT slice invocations rather than a bare failure.
    slice_cmds=""; c_start=$START_EPOCH
    while (( c_start < END_EPOCH )); do
      c_end=$(( c_start + cap_h * 3600 )); (( c_end > END_EPOCH )) && c_end=$END_EPOCH
      slice_cmds="${slice_cmds}${slice_cmds:+ ; }--since $(to_iso "$c_start") --until $(to_iso "$c_end")"
      c_start=$c_end
    done
    fail_now TRUNCATION_UNRESOLVED \
      "The window truncates and would need ${n_slices} slices (> ${MAX_SLICES}) to cover at the measured ${cap_h}h cap, so it was not auto-narrowed. Re-run these exact slices and sum them: ${slice_cmds}"
  fi

  SLICE_AGG='[]'
  slice_desc=""; c_start=$START_EPOCH
  while (( c_start < END_EPOCH )); do
    c_end=$(( c_start + cap_h * 3600 )); (( c_end > END_EPOCH )) && c_end=$END_EPOCH
    run_query "slice" "$(build_slice_sql)" "$(to_iso "$c_start")" "$(to_iso "$c_end")" "$c_start" "$c_end"
    SLICE_AGG="$(merge_agg "$SLICE_AGG" "$(normalize_agg "$Q_RESULT" slice_c slice_lo slice_hi)")"
    slice_desc="${slice_desc}${slice_desc:+ + }$(to_iso "$c_start")..$(to_iso "$c_end")"
    c_start=$c_end
  done
  # The union REPLACES the truncated single-shot answer. Both are shown, so the
  # discrepancy is on the record rather than quietly corrected.
  V_SLICES="${n_slices} slice(s) at a measured ${cap_h}h cap: ${slice_desc}"
  WINDOW_AGG="$SLICE_AGG"
  truncated_count="$REQ_COUNT"
  recompute
  V_MONO="${V_MONO}; single-shot returned ${truncated_count}, unioned slices return ${REQ_COUNT}"
fi

# ---------------------------------------------------------------------------
# Rung 6 — the coverage verdict. THIS, not the monotonicity probe, is what
# catches a window that predates retention.
# ---------------------------------------------------------------------------
all_lo_epoch=""; all_hi_epoch=""
[[ -n "$ALL_LO_ISO" ]] && all_lo_epoch="$(date -u -d "$ALL_LO_ISO" +%s 2>/dev/null)"
[[ -n "$ALL_HI_ISO" ]] && all_hi_epoch="$(date -u -d "$ALL_HI_ISO" +%s 2>/dev/null)"
V_COV_CLASS="$(coverage_classify "$all_lo_epoch" "$all_hi_epoch" "$START_EPOCH" "$END_EPOCH" "$COVERAGE_EDGE_TOLERANCE_SEC")"
V_COV_START="${REQ_LO_ISO:-$ALL_LO_ISO}"; V_COV_END="${REQ_HI_ISO:-$ALL_HI_ISO}"

V_SOURCES_JSON="$(printf '%s\n%s\n%s' "$INSTR_AGG" "$WINDOW_AGG" "$WANT_JSON" | jq -sc '
  . as [$instr, $win, $want] |
  ([ $instr[].source ] + [ $win[].source ] + $want | unique) |
  [ .[] as $s |
    { source: $s,
      instrumentation_count: (([ $instr[] | select(.source == $s) | .c ] | add) // 0),
      window_count: (([ $win[] | select(.source == $s) | .c ] | add) // 0),
      status: (if (([ $instr[] | select(.source == $s) | .c ] | add) // 0) > 0
               then "INSTRUMENTED" else "UNINSTRUMENTED" end),
      requested: (($want | length) == 0 or ($want | index($s)) != null) } ]')"

case "$V_COV_CLASS" in
  NONE)
    V_ROWS="$REQ_COUNT"
    fail_now WINDOW_PREDATES_RETENTION \
      "No source on ${V_PROJECT} has a single row anywhere in ${START_ISO}..${END_ISO}, so this window is outside what the project retains. The ${REQ_COUNT} above is what the endpoint said, NOT what happened — a zero here is the absence of RECORDS, not the absence of events, and it cannot support a determination either way. Next: narrow to a window inside the retained span (the pinned ${INSTRUMENTATION_SPAN_DAYS}d enumeration shows what is retained), or source the answer from a system that keeps records this old."
    ;;
  PARTIAL)
    V_ROWS="$REQ_COUNT"
    gap=""
    if [[ -n "$all_lo_epoch" ]] && (( all_lo_epoch > START_EPOCH + COVERAGE_EDGE_TOLERANCE_SEC )); then
      gap="head ${START_ISO}..${ALL_LO_ISO}"
    fi
    if [[ -n "$all_hi_epoch" ]] && (( all_hi_epoch < END_EPOCH - COVERAGE_EDGE_TOLERANCE_SEC )); then
      gap="${gap}${gap:+ and }tail ${ALL_HI_ISO}..${END_ISO}"
    fi
    fail_now PARTIAL_COVERAGE \
      "The project has rows for only part of the requested window; UNCOVERED: ${gap:-(edges)}. The count of ${REQ_COUNT} describes ${ALL_LO_ISO}..${ALL_HI_ISO}, not what was asked for, so it cannot be quoted against the requested window. Next: re-run with --since ${ALL_LO_ISO} --until ${ALL_HI_ISO} to get a count that matches its window, and treat the uncovered part as unknown."
    ;;
esac

# ---------------------------------------------------------------------------
# Rung 7 — the tail. Fetched only on a covered window, and never used for the
# coverage math (see build_rows_sql).
# ---------------------------------------------------------------------------
if (( TRUNCATED == 1 )); then
  V_SAMPLE_JSON='[]'
elif (( LIMIT > 0 && REQ_COUNT > 0 )); then
  run_query "rows" "$(build_rows_sql)" "$START_ISO" "$END_ISO" "$START_EPOCH" "$END_EPOCH"
  V_SAMPLE_JSON="$Q_RESULT"
  if (( JSON_MODE == 0 )); then
    # scrub_pat only, NOT strip_log_injection: the latter deletes newlines by
    # design, which would fuse every log line into one. jq -c has already
    # JSON-escaped any control byte inside these rows, so they are inert.
    printf '%s' "$Q_RESULT" | jq -c '.[]' | scrub_pat
  fi
fi

V_ROWS="$REQ_COUNT"
if (( TRUNCATED == 1 )); then
  V_REASON="TRUNCATED_AUTONARROWED"
  V_NEXT="The single-shot query over this window was TRUNCATED by the endpoint's undocumented width cap; the count above is the UNION of the slices listed in slices=, which is the trustworthy one. The vendor's documented 24h validation error does not fire (see the evidence file), so nothing server-side would have told you. No row tail is returned on this path — re-run one slice to read lines."
elif (( REQ_COUNT == 0 )); then
  V_REASON="ZERO_WITH_FULL_COVERAGE"
  V_NEXT="This is a REAL zero: the requested source is instrumented (see instrumentation=) and the project has rows spanning the whole window (see covered_window=), so the absence is the absence of events, not of records. Safe to quote — quote it WITH this block."
else
  V_REASON="FULLY_COVERED"
  V_NEXT="Count and window agree; the requested source is instrumented and the window is inside the retained span. Quote the count WITH this block, never on its own."
fi
emit_and_exit
