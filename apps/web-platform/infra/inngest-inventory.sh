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
# Bounded (#6258, ADR-106): the eventsV2 pagination is bounded by a wall-clock DEADLINE
# (date +%s delta; precedent ci-deploy.sh:1524-1535 — the repo never uses SECONDS) and a
# per-run PAGE CEILING, both abandon-safe: on deadline/ceiling the loop emits a LOUD
# SOLEUR_INNGEST_PREFLIGHT_TIMEOUT marker and exit 1 (NEVER break — a break would fall
# through to the emit and produce a truncated well-formed HTTP-200 body, the #6218 false-
# clean class), releasing the inngest→Postgres connections instead of orphaning the scan.
# Each per-page curl is clamped to the REMAINING budget (--max-time = DEADLINE_S − elapsed,
# floored ≥1) so the sum bound `in_script_deadline + per_page ≤ outer_curl` holds — an
# ordering (per_page ≤ deadline < outer) is insufficient (#6258 Deepen Finding 1).
#
# Completeness by construction (#6258 Deepen Finding 3): armed_reminders is enumerated by a
# DEDICATED eventNames:["reminder.scheduled"] full-window query (small, page-ceiling-immune,
# zero receivedAt narrowing; precedent inngest-enumerate-reminders.sh:82) — the window is
# NEVER narrowed, and event_names is kept lossless via the all-events distinct scan with a
# raised PAGE_SIZE (the only cost lever). If the all-events scan does not fit the budget it
# aborts LOUD — it never truncates.
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
# the cutover's re-arm set agree. armed_reminders is derived from the dedicated
# reminder.scheduled scan; event_names is derived from the all-events scan (no eventNames
# filter, includeInternalEvents:true) so it captures cron/* internal ticks.
#
# #5509/#5503 — the webhook (adnanh/webhook v2.8.2) returns cmd.CombinedOutput()
# (stdout AND stderr) even on a 200, and the cutover workflow parses this body as a
# JSON OBJECT. So on the SUCCESS path this script must write NOTHING non-JSON to
# EITHER stream: stdout carries only the final object, and the summary + the
# SOLEUR_INNGEST_PREFLIGHT_* markers go to on-host journald via `logger` ONLY (read with
# `journalctl -t inngest-inventory`). The journald summary DOES now reach Better Stack:
# `inngest-inventory` was added to Vector's tag allowlist (vector.toml:134, #5526), so the
# `durability=<enum>` summary + the preflight markers are the load-bearing no-SSH carrier.
# Internal shell consumers use `$(...)` (stdout only), so the merge happens solely at
# the webhook boundary.
#
# Test seam: INNGEST_GQL_FIXTURE_DIR (page-N.json for the all-events eventsV2 scan),
# INNGEST_REMINDER_FIXTURE_DIR (page-N.json for the dedicated reminder.scheduled scan;
# when UNSET in fixture mode, armed_reminders is derived from the all-events edges for
# back-compat), INVENTORY_FUNCTIONS_FIXTURE (a file with the /v0/gql functions-query
# response), INVENTORY_NOW_MS (deterministic "now"), PREFLIGHT_DEADLINE_S / INNGEST_MAX_PAGES
# (the bounding seams).
set -euo pipefail

readonly LOG_TAG="inngest-inventory"

# Identity of the host that answered this read (#6425). /hooks/inngest-liveness is reached
# through the Cloudflare Tunnel, which selects a connector per edge colo — so this hook can
# answer from a host the caller never meant. That is not hypothetical: a freshly-recreated
# non-primary host has NO inngest-inventory.sh baked at all, so a read that lands there is a
# false `inngest_down` P1 against a perfectly healthy inngest. Emitting the emitter's identity
# discriminates "two origins" from "one broken origin" in ONE read.
#
# Declared empty at top level (NO network) so the BASH_SOURCE guard's invariant below holds and
# a sourced reference is `set -u`-safe; resolved inside the execution guard.
HOST_ID=""

# SOLEUR-DEBT: 3rd of 3 resolve_host_id copies (ci-deploy.sh source-of-truth,
# cat-deploy-state.sh, this). Kept in sync by test_host_id_drift_guard, NOT a shared sourced
# lib — sourcing works in infra (ci-deploy.sh sources its env file), but DISTRIBUTING a new script costs ~11
# surfaces (push-infra-config.sh, hooks.json.tmpl, infra-config-apply.sh FILE_MAP,
# infra-config-install.sh DEST_SPEC + its 2 hardcoded counts, server.tf triggers_replace,
# apply-deploy-pipeline-fix.yml paths, ship-deploy-pipeline-fix-gate.test.ts, ship/SKILL.md)
# plus the bake path. Upgrade trigger: a 4th copy OR any consumer outside infra/. Tracked: #6465.
resolve_host_id() {
  if [[ -n "${SOLEUR_HOST_ID_OVERRIDE:-}" ]]; then
    printf '%s' "$SOLEUR_HOST_ID_OVERRIDE"
    return 0
  fi
  local url="${SOLEUR_HOST_ID_METADATA_URL:-http://169.254.169.254/hetzner/v1/metadata/instance-id}"
  local id
  id=$(curl -sf --max-time 3 "$url" 2>/dev/null || true)
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    printf 'hetzner-%s' "$id"
    return 0
  fi
  id=$(tr -d '[:space:]' < /etc/machine-id 2>/dev/null || true)
  if [[ -n "$id" ]]; then
    # HASHED, never raw: machine-id(5) says the value "should be considered confidential and
    # must not be exposed in untrusted environments" — systemd's own guidance is to hash it
    # per-application (sd_id128_get_machine_app_specific). This fallback now reaches an HTTP
    # response body and journald -> Vector -> Better Stack (a third-party vendor), which the
    # ci-deploy.sh original never did. Hashing is LOSSLESS here: host_id only ever needs to be
    # STABLE and COMPARABLE (same-host vs different-host), never reversible.
    printf 'machine-%s' "$(printf '%s' "$id" | sha256sum | cut -c1-12)"
    return 0
  fi
  return 1
}

GQL_URL="${INNGEST_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
# #6407 Defect A — loopback /health endpoint used to CORROBORATE a functions-query failure
# in LIVENESS_ONLY mode before declaring a hard down. Same loopback server + same /health
# path that ci-deploy.sh verify_inngest_health gates on (ci-deploy.sh:1002).
INNGEST_HEALTH_URL="${INNGEST_HEALTH_URL:-http://127.0.0.1:8288/health}"
# Cost lever (#6258 Deepen Finding 3): raise PAGE_SIZE (lossless round-trip cut) — the ONLY
# completeness-preserving lever. Never narrow FROM_TS. Env-overridable for tests.
PAGE_SIZE="${INNGEST_GQL_PAGE_SIZE:-500}"
# receivedAt lower bound — same 365-day clamp as enumerate (#5492): the epoch is
# rejected by inngest v1.19.4 as out-of-range. ENUMERATE_FROM widens it for a deeper
# arm→fire horizon. BusyBox-safe fallback (mirrors inngest-wiped-volume-verify.sh).
# NEVER narrowed for cost — the single-user-incident completeness invariant (#6258).
_default_from=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)
FROM_TS="${ENUMERATE_FROM:-$_default_from}"
NOW_MS="${INVENTORY_NOW_MS:-$(date +%s%3N)}"
FIXTURE_DIR="${INNGEST_GQL_FIXTURE_DIR:-}"
REMINDER_FIXTURE_DIR="${INNGEST_REMINDER_FIXTURE_DIR:-}"
FUNCTIONS_FIXTURE="${INVENTORY_FUNCTIONS_FIXTURE:-}"
# --- Liveness-only mode (#6374, Defect 2) ---
# The external inngest health watchdog (.github/workflows/scheduled-inngest-health.yml)
# invokes this script through the /hooks/inngest-liveness hook with INVENTORY_LIVENESS_ONLY
# set. In that mode we run ONLY the cheap /v0/gql `functions` liveness query + the
# durability_state read and SKIP the heavy paginated eventsV2 scan (the 365-day read whose
# deadline/page-ceiling/pool/gateway faults false-positived as inngest_down while the cron
# executor kept firing — the #6374 root cause). The heavy full-inventory path is unchanged
# for the cutover-baseline caller (/hooks/inngest-inventory, no flag). functions fail-loud
# and durability purity are preserved verbatim; only the eventsV2 scans are elided
# (event_names / armed_reminders emit as empty arrays — they are cutover-baseline fields,
# not liveness signals).
LIVENESS_ONLY="${INVENTORY_LIVENESS_ONLY:-}"

# --- Bounding seams (#6258, ADR-106) ---
# In-script wall-clock deadline. Default 22s < the outer curl 30s (cutover-inngest.yml:341);
# the remaining-budget per-page clamp makes the SUM bound airtight (Finding 1).
PREFLIGHT_DEADLINE_S="${PREFLIGHT_DEADLINE_S:-22}"
# Page ceiling — secondary abandon-safe guard (the deadline is primary). Sized with ample
# headroom for the real corpus at the raised PAGE_SIZE; env-overridable for tests.
MAX_PAGES="${INNGEST_MAX_PAGES:-1000}"
# Bound a TCP-connect stall independently of the read budget.
CONNECT_TIMEOUT="${INNGEST_CONNECT_TIMEOUT:-5}"
# Marker identity.
PREFLIGHT_OP="inventory"
PREFLIGHT_HOST="${INNGEST_PREFLIGHT_HOST:-$(hostname 2>/dev/null || echo unknown)}"
PREFLIGHT_START_S=0
_pf_pages=0
_last_curl_exit=0

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

# ---------------------------------------------------------------------------
# Observability markers (#6258 Deepen Finding 8) — journald-ONLY. The hook's stdout IS
# the pure-JSON webhook body (#5503), so markers MUST NOT touch stdout: emit via
# `logger -t "$LOG_TAG" … 2>/dev/null || true` only (DROP marker()'s echo). Mirror the
# control-char + Unicode-separator sanitizer of marker() (git-lock-chardevice-sweep.sh)
# on the composed line, using ESCAPE notation for the separators (cq-regex-unicode-
# separators-escape-only — the Edit tool silently rewrites literal U+2028/U+2029). Purity
# (Finding 13): every field is an enum/count/id only — never a raw GraphQL errors[].message.
# ---------------------------------------------------------------------------
_pf_sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' \
    | sed $'s/\xc2\x85//g; s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'   # U+0085 NEL, U+2028, U+2029
}
# _pf_scrub (#6258 review P1 — credential/DSN leak on the failure path): redact
# connection strings + credentials AND strip control chars / Unicode separators
# from UNTRUSTED GraphQL errors[].message text before it reaches journald
# (→ Better Stack) or stdout (→ the Actions run log). A postgres:// DSN can appear
# in a DB errors[].message on the EMAXCONNSESSION pool-pressure path this probe
# targets; the SOLEUR_* markers enum-map it, the FATAL/ERROR diagnostics scrub it.
# Reads stdin, writes stdout.
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
# START — the LITERAL first line of run_inventory, before any network call, so an
# absence-of-START unambiguously means transport/host-down (Finding 8).
_pf_start_marker() {
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_START op=$PREFLIGHT_OP host=$PREFLIGHT_HOST window=${FROM_TS}..now page_ceiling=$MAX_PAGES deadline_s=$PREFLIGHT_DEADLINE_S"
}
_pf_done_marker() {
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_DONE op=$PREFLIGHT_OP pages=$_pf_pages elapsed_ms=$elapsed_ms"
}
# TIMEOUT — the curl-exit fields (pages_timed_out / last_curl_exit) split a pool-pressure
# STALL (curl exit 28, empty body — the HTTP 000 shape) from a slow scan (Finding 9).
_pf_timeout_marker() {  # $1=reason(enum) $2=pages $3=pages_timed_out $4=last_curl_exit
  local elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_TIMEOUT op=$PREFLIGHT_OP pages=$2 elapsed_ms=$elapsed_ms pages_timed_out=$3 last_curl_exit=$4 reason=$1"
}
# Shared loud-abort helper (#6258 Deepen Finding 6): deadline + ceiling route here. It
# emits the TIMEOUT marker then exit 1 (NEVER break). The EXIT trap fires on exit 1 →
# spool cleaned; the non-zero exit maps to a webhook non-200 (hooks.json.tmpl:140).
_pf_abort() {  # $1=reason $2=pages $3=pages_timed_out $4=last_curl_exit
  _pf_timeout_marker "$1" "$2" "$3" "$4"
  echo "inngest-inventory: FATAL host_id=$HOST_ID preflight scan aborted reason=$1 pages_scanned=$2 (deadline_s=$PREFLIGHT_DEADLINE_S page_ceiling=$MAX_PAGES from=$FROM_TS) — refusing to emit a truncated (false-clean) inventory"
  echo "ERROR: host_id=$HOST_ID preflight scan aborted reason=$1 pages_scanned=$2" >&2
  exit 1
}

# Build the GraphQL request body for one eventsV2 page. Injection-safe via jq -n.
#   $1 = after-cursor ("" for first)
#   $2 = eventNames JSON ("null" ⇒ ALL events / no filter; e.g. '["reminder.scheduled"]')
#   $3 = includeInternalEvents (true|false)
# The all-events scan uses (null,true) so event_names captures cron/* internal ticks; the
# dedicated armed scan uses (["reminder.scheduled"],false) — precedent enumerate:82. The
# filter.from is $FROM_TS in BOTH scans (never narrowed — completeness invariant).
build_request_body() {
  local after="$1" ev_names="${2:-null}" incl="${3:-true}"
  local after_json="null"
  [[ -n "$after" ]] && after_json=$(jq -nc --arg a "$after" '$a')
  jq -nc \
    --arg q "$GQL_QUERY" \
    --argjson first "$PAGE_SIZE" \
    --argjson after "$after_json" \
    --arg from "$FROM_TS" \
    --argjson evn "$ev_names" \
    --argjson incl "$incl" \
    '{query:$q, variables:{first:$first, after:$after,
       filter:({from:$from, includeInternalEvents:$incl}
               + (if $evn == null then {} else {eventNames:$evn} end))}}'
}

# Fetch one eventsV2 page INTO a file (no command-substitution subshell — so the loop can
# read $_last_curl_exit, which a $(...) subshell would discard). A curl failure is swallowed
# (never propagated) so the caller inspects the empty body + _last_curl_exit and routes
# through the loud-abort path — set -e must not kill the script before the marker fires.
#   $1=fixture_dir(may be "") $2=out_file $3=after $4=page $5=max_time $6=ev_names $7=incl
_fetch_events_page() {
  local fixture_dir="$1" out="$2" after="$3" page_num="$4" max_time="$5" ev_names="$6" incl="$7"
  if [[ -n "$fixture_dir" ]]; then
    cat "${fixture_dir}/page-${page_num}.json" > "$out"
    _last_curl_exit=0
    return 0
  fi
  local body
  body=$(build_request_body "$after" "$ev_names" "$incl")
  if curl -s --max-time "$max_time" --connect-timeout "$CONNECT_TIMEOUT" \
       -X POST -H "Content-Type: application/json" \
       --data-binary "$body" "$GQL_URL" > "$out"; then
    _last_curl_exit=0
  else
    _last_curl_exit=$?
  fi
  return 0
}

# Paginate an eventsV2 scan to exhaustion, bounded (deadline + page ceiling), collapsing
# every page's edges into $out_file via a SPOOL FILE (file I/O, no argv size limit — the
# #5523 MAX_ARG_STRLEN fix). Aborts LOUD (exit 1, never break) on deadline / ceiling /
# malformed-GraphQL / empty-endCursor. Increments the global $_pf_pages (for the DONE marker).
#   $1=fixture_dir(may be "") $2=eventNames JSON $3=includeInternalEvents $4=out_file
run_events_scan() {
  local fixture_dir="$1" ev_names="$2" incl="$3" out_file="$4"
  local spool="${out_file}.spool" resp_file="${out_file}.resp"
  local after="" page=1 resp has_next end_cursor
  local timed_out=0 last_curl_exit=0 now elapsed remaining
  : > "$spool"
  while :; do
    # --- deadline (SUM bound): abort BEFORE issuing a page that could overshoot ---
    now=$(date +%s); elapsed=$(( now - PREFLIGHT_START_S ))
    if (( elapsed >= PREFLIGHT_DEADLINE_S )); then
      _pf_abort deadline "$(( page - 1 ))" "$timed_out" "$last_curl_exit"
    fi
    # Clamp THIS page's curl to the remaining budget (floored ≥1) so no in-flight page can
    # overshoot the outer curl: script exit ≤ elapsed + remaining = DEADLINE_S < outer.
    remaining=$(( PREFLIGHT_DEADLINE_S - elapsed )); (( remaining < 1 )) && remaining=1
    _fetch_events_page "$fixture_dir" "$resp_file" "$after" "$page" "$remaining" "$ev_names" "$incl"
    last_curl_exit=$_last_curl_exit
    (( _last_curl_exit != 0 )) && timed_out=$(( timed_out + 1 ))
    resp=$(cat "$resp_file")
    if ! echo "$resp" | jq -e '.data.eventsV2' >/dev/null 2>&1; then
      # #5503 purity: surface only GraphQL error MESSAGES + .data KEY NAMES, never the raw
      # response / .errors[].extensions / .data values. A mid-scan EMAXCONNSESSION (or a
      # curl-timeout empty body — HTTP 000) surfaces here; the marker carries last_curl_exit
      # so the pressure-stall is distinguishable from a slow scan (Finding 9). exit 1 → non-200.
      local err_msgs data_keys gql_msg
      err_msgs=$(echo "$resp" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
      err_msgs=$(printf '%s' "$err_msgs" | _pf_scrub)   # #6258 P1: no DSN/creds to journald+stdout
      data_keys=$(echo "$resp" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
      gql_msg=$(echo "$resp" | jq -r '(.errors // [])[0].message // ""' 2>/dev/null | tr -d '\n\r' || echo "")
      gql_msg=$(printf '%s' "$gql_msg" | _pf_scrub)
      _pf_timeout_marker gql_error "$page" "$timed_out" "$last_curl_exit"
      logger -t "$LOG_TAG" "ERROR: malformed GraphQL response on page $page: errors=$err_msgs data_keys=$data_keys" 2>/dev/null || true
      echo "inngest-inventory: FATAL host_id=$HOST_ID malformed GraphQL response on page $page (from=$FROM_TS): ${gql_msg:-eventsV2 missing; check the inngest Time bound / endpoint}"
      echo "ERROR: host_id=$HOST_ID malformed GraphQL response on page $page: errors=$err_msgs data_keys=$data_keys" >&2
      exit 1
    fi
    # Append this page's edges array as ONE JSON value (one line) to the spool file.
    echo "$resp" | jq -c '.data.eventsV2.edges // []' >> "$spool"
    has_next=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.hasNextPage // false')
    end_cursor=$(echo "$resp" | jq -r '.data.eventsV2.pageInfo.endCursor // ""')
    if [[ "$has_next" == "true" ]]; then
      # #6218: hasNextPage=true with an EMPTY endCursor must FAIL LOUD, not break-clean — a
      # silent break truncates the inventory (undercount) and reconciliation reads clean.
      if [[ -z "$end_cursor" ]]; then
        _pf_timeout_marker gql_error "$page" "$timed_out" "$last_curl_exit"
        logger -t "$LOG_TAG" "ERROR: pagination hasNextPage=true but endCursor empty on page $page — refusing to truncate" 2>/dev/null || true
        echo "inngest-inventory: FATAL host_id=$HOST_ID hasNextPage=true but endCursor empty on page $page — would truncate the inventory"
        echo "ERROR: host_id=$HOST_ID pagination hasNextPage=true but empty endCursor on page $page" >&2
        exit 1
      fi
      # Page ceiling — gate as "about to fetch page > MAX_PAGES WHILE hasNextPage=true" so a
      # corpus that exactly fits MAX_PAGES breaks clean (never false-aborts).
      if (( page + 1 > MAX_PAGES )); then
        _pf_abort page_ceiling "$page" "$timed_out" "$last_curl_exit"
      fi
      after="$end_cursor"
      page=$(( page + 1 ))
    else
      break
    fi
  done
  # Collapse all spooled per-page arrays into one flat edge array via file input.
  jq -s 'add // []' "$spool" > "$out_file"
  _pf_pages=$(( _pf_pages + page ))
}

# armed_reminders projection (future fire `raw.ts > now` AND no terminal run) — identical
# to inngest-enumerate-reminders.sh so the inventory's armed set and the cutover's re-arm
# set agree. $1 = PATH to a file holding a flat eventsV2-edges JSON array.
#
# Takes a PATH, not the JSON text (#6736). The edge array is the output of a lossless
# all-events scan and is unbounded by construction; `cat`-ing it into a shell variable
# to pass here undid the spool the scan just wrote. jq reads the file directly.
derive_armed() {
  jq -c --argjson now "$NOW_MS" '
    [ .[]
      | select(.node.name == "reminder.scheduled")
      | (.node.raw | fromjson) as $env
      | select(($env.ts // 0) > $now)
      | select( any(.node.runs[]?; .status as $s | (["COMPLETED","CANCELLED","FAILED","SKIPPED"] | index($s)) != null) | not )
      | { reminder_id: $env.data.reminder_id, fire_at: $env.data.fire_at, actor: $env.data.actor, action: $env.data.action }
    ]' "$1"
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
  curl -s --max-time 15 --connect-timeout "$CONNECT_TIMEOUT" -X POST -H "Content-Type: application/json" \
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
  # --- START marker: the LITERAL first action, before any network call (Finding 8) ---
  PREFLIGHT_START_S=$(date +%s)
  _pf_pages=0
  _pf_start_marker

  # --- functions: names only (fall back to slug/id if the element lacks .name) ---
  local fn_body functions
  fn_body=$(fetch_functions)
  # Fail LOUD (not false-clean []) if the /v0/gql functions query failed or returned a
  # non-array .data.functions. A legitimately-empty inngest returns {data:{functions:[]}}
  # → passes this gate and yields functions=[] correctly; a fetch failure, a GraphQL
  # error envelope, or any unexpected shape (incl. a bare array — the pre-#5517 wrong
  # assumption) trips it. The guard is NOT loosened to accept any shape. (START already
  # emitted above, so a functions-query failure still self-reports off-box, Finding 8.)
  if ! echo "$fn_body" | jq -e '.data.functions | type == "array"' >/dev/null 2>&1; then
    # #5503 purity: surface only GraphQL error MESSAGES + .data KEY NAMES, never values.
    local fn_errs fn_keys
    fn_errs=$(echo "$fn_body" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
    fn_errs=$(printf '%s' "$fn_errs" | _pf_scrub)   # #6258 P1: no DSN/creds to journald+stdout
    fn_keys=$(echo "$fn_body" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
    _pf_timeout_marker gql_error 0 0 0
    logger -t "$LOG_TAG" "ERROR: /v0/gql functions unreachable or non-array: errors=$fn_errs data_keys=$fn_keys" 2>/dev/null || true
    # #6407 Defect A — /health corroboration (LIVENESS_ONLY only). The external watchdog's
    # cheap /v0/gql functions curl can transiently fail (a transport blip → the
    # __FETCH_FAILED__ envelope) while inngest-server is UP and processing events. Before
    # declaring a hard down (→ inngest_down → restart + [ci/inngest-down] P1), corroborate
    # against the SAME loopback server's /health endpoint (the one ci-deploy.sh
    # verify_inngest_health gates on):
    #   /health=200  → the HTTP server IS serving; the GQL read blipped → emit a SOFT DEGRADED
    #                  sentinel (classifier → functions_query_degraded → NO restart). #6407.
    #   /health !=200 → wedged/stopped → keep the FATAL sentinel (inngest_down → restart, which
    #                  recovers a wedge). is-active/ExecStart are NOT specificity-correct here
    #                  (both read for a wedged/stopped unit); /health is the only same-signal-
    #                  class corroborator. The full-inventory (non-liveness) caller keeps the
    #                  original fail-loud FATAL — corroboration is a liveness-verdict concern only.
    if [[ -n "$LIVENESS_ONLY" ]]; then
      local health_code durability_state_dg verdict_mode
      health_code="${INVENTORY_INNGEST_HEALTH_CODE-$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$INNGEST_HEALTH_URL" 2>/dev/null || echo 000)}"
      durability_state_dg=$(derive_durability_state)
      if [[ "$health_code" == "200" ]]; then verdict_mode="degraded"; else verdict_mode="down"; fi
      # #6407 Defect C — SOLEUR_INNGEST_LIVENESS_VERDICT marker (journald-only; tag
      # inngest-inventory → Vector Source 4 → Better Stack). Enum/count fields only (mode +
      # HTTP code + count + durability enum) — never a raw GraphQL errors[].message (#5503 purity).
      logger -t "$LOG_TAG" "SOLEUR_INNGEST_LIVENESS_VERDICT mode=$verdict_mode health_code=$health_code functions=0 durability=$durability_state_dg host_id=$HOST_ID" 2>/dev/null || true
      if [[ "$health_code" == "200" ]]; then
        echo "inngest-inventory: DEGRADED host_id=$HOST_ID /v0/gql functions query transiently unreachable but /health=200 (errors=$fn_errs) — soft, no restart"
        echo "DEGRADED: host_id=$HOST_ID /v0/gql functions transiently unreachable, /health=200 (errors=$fn_errs)" >&2
        exit 1
      fi
    fi
    echo "inngest-inventory: FATAL host_id=$HOST_ID /v0/gql functions query failed or non-array (errors=$fn_errs data_keys=$fn_keys); is inngest-server.service up? — refusing to emit a false-clean empty functions baseline"
    echo "ERROR: host_id=$HOST_ID /v0/gql functions non-array (errors=$fn_errs data_keys=$fn_keys)" >&2
    exit 1
  fi
  functions=$(echo "$fn_body" | jq -c '[ .data.functions[] | (.name // .slug // .id // empty) ] | sort')

  # --- Liveness-only short-circuit (#6374): skip the heavy eventsV2 scans entirely.
  # functions (above) + durability_state are the ONLY liveness signals; event_names /
  # armed_reminders are cutover-baseline fields, emitted empty here. This decouples the
  # liveness verdict from the 365-day read path whose faults caused the #6374 false-positive.
  if [[ -n "$LIVENESS_ONLY" ]]; then
    local durability_state_lo fn_count_lo
    durability_state_lo=$(derive_durability_state)
    fn_count_lo=$(echo "$functions" | jq 'length')
    logger -t "$LOG_TAG" "liveness: functions=$fn_count_lo durability=$durability_state_lo mode=liveness_only" 2>/dev/null || true
    _pf_done_marker
    jq -nc --argjson f "$functions" --arg d "$durability_state_lo" --arg hid "$HOST_ID" \
      '{functions:$f, event_names:[], armed_reminders:[], durability_state:$d, host_id:$hid}'
    return 0
  fi

  # --- bounded scans: spool + collapse via file I/O (no argv size limit, #5523) ---
  local pf_tmp
  pf_tmp=$(mktemp -d)
  # shellcheck disable=SC2064  # expand $pf_tmp NOW so the trap body captures this value.
  # EXIT (not RETURN): RETURN does NOT fire on `exit`, so the loud-abort `exit 1` branches
  # would leak the spool under RETURN. Registered INSIDE run_inventory, so the sourced-by-
  # test path (run_inventory is never called when sourced — BASH_SOURCE guard) never sets it.
  trap "rm -rf '$pf_tmp'" EXIT

  # event_names: the all-events distinct scan (NO eventNames filter, includeInternalEvents
  # :true → captures cron/* ticks). Lossless via the raised PAGE_SIZE; aborts LOUD if it
  # exceeds the budget (never truncates — the #6258 completeness invariant).
  #
  # ARGV CEILING (#6736). $all_edges is gone: it used to `cat` the whole spooled edge
  # array into a shell variable one line after run_events_scan wrote it to disk — the
  # #5523 spool defeated by the very next statement. Everything below is file-in /
  # file-out, and the final emit binds with `--rawfile … | fromjson`, never `--argjson`.
  # A shell variable bound via --argjson is ONE argv argument, and the kernel caps a
  # SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B — verified by bisect on this
  # host: 131,071 B passes, 131,072 B fails E2BIG. That is NOT `getconf ARG_MAX`
  # (2,097,152 B, the argv+envp total); a payload at 6% of ARG_MAX still dies.
  local event_names_file="$pf_tmp/event_names.json"
  local armed_file="$pf_tmp/armed.json"
  local functions_file="$pf_tmp/functions.json"
  printf '%s' "$functions" > "$functions_file"
  run_events_scan "$FIXTURE_DIR" "null" "true" "$pf_tmp/all_edges.json"
  jq -c '[ .[].node.name ] | unique' "$pf_tmp/all_edges.json" > "$event_names_file"

  # armed_reminders — completeness BY CONSTRUCTION (#6258 Deepen Finding 3): a DEDICATED
  # eventNames:["reminder.scheduled"] full-window scan (small, page-ceiling-immune, zero
  # receivedAt narrowing). In fixture mode WITHOUT a reminder-fixture dir we derive the armed
  # set from the all-events edges instead (back-compat with the pre-#6258 unit fixtures).
  if [[ -n "$FIXTURE_DIR" && -z "$REMINDER_FIXTURE_DIR" ]]; then
    derive_armed "$pf_tmp/all_edges.json" > "$armed_file"
  else
    run_events_scan "$REMINDER_FIXTURE_DIR" '["reminder.scheduled"]' "false" "$pf_tmp/rem_edges.json"
    derive_armed "$pf_tmp/rem_edges.json" > "$armed_file"
  fi

  # --- durability_state: no-SSH continuous-durability surface (#5553) ---
  # Enum only (durable|degraded|sqlite_only|unknown); never the ExecStart string.
  local durability_state
  durability_state=$(derive_durability_state)

  # --- Observability summary (counts + reminder_ids + durability ENUM ONLY, never
  #     bodies or connection strings) → journald only (#5503) ---
  local fn_count ev_count armed_count armed_ids
  fn_count=$(jq 'length' "$functions_file")
  ev_count=$(jq 'length' "$event_names_file")
  armed_count=$(jq 'length' "$armed_file")
  armed_ids=$(jq -r '[.[].reminder_id] | join(",")' "$armed_file")
  logger -t "$LOG_TAG" "inventory: functions=$fn_count event_names=$ev_count armed=$armed_count armed_ids=[$armed_ids] durability=$durability_state" 2>/dev/null || true
  _pf_done_marker

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  # $armed is the unbounded one — one object per armed reminder, from a dedicated
  # full-window reminder.scheduled scan with no page-ceiling narrowing. $event_names
  # and $functions are weakly bounded (distinct names / registered functions) but are
  # spooled too: they share the SAME argv argument budget, so bounding one of three
  # bounds nothing. $durability_state and $host_id are enums and stay on argv.
  jq -nc --rawfile f "$functions_file" --rawfile e "$event_names_file" \
    --rawfile r "$armed_file" --arg d "$durability_state" --arg hid "$HOST_ID" \
    '{functions:($f|fromjson), event_names:($e|fromjson), armed_reminders:($r|fromjson),
      durability_state:$d, host_id:$hid}'
}

# Run only when executed directly — sourcing (the unit test) must NOT hit the network.
# HOST_ID resolves HERE, inside the guard, for exactly that reason: a top-level assignment
# would fire resolve_host_id's `curl --max-time 3` on every source. `|| true` is load-bearing
# under `set -euo pipefail` — resolve_host_id return-1s when metadata is unreachable AND
# /etc/machine-id is unreadable, and a bare assignment would abort the hook into a non-200,
# losing the whole liveness verdict to protect one field.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  HOST_ID="$(resolve_host_id || true)"
  readonly HOST_ID
  run_inventory
fi
