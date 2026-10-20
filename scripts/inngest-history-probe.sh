#!/usr/bin/env bash
# inngest-history-probe.sh -- an aggregate-only, read-only measurement of the Inngest Postgres
# history (#9927 item C1). It answers ONE question without reading a row: after a total loss of the
# Inngest Redis store, could the surviving Postgres half (config and run history, a dedicated
# Supabase project) hold a usable list of affected users, and where? Shape and estimates only.
#
# SOLEUR-DEBT: a standing credentialed measurement tool is not wanted. Delete this script and its
# suite once the C1 finding is recorded in the runbook and ADR-282 and no follow-up probe is
# scheduled; any new query (a "round 2") is added as one literal, with its own suite row and its
# own green CI, BEFORE it is ever sent.
#
# WHAT IS STRUCTURAL HERE (the claim is "cannot", not "does not"):
#   * ONE transport. Every request is made by `_send`, through bc_curl, to the Management API's
#     DEDICATED read-only endpoint (POST /v1/projects/<ref>/database/query/read-only, which runs the
#     SQL as the database role `supabase_read_only_user`). The role, not our string, blocks writes
#     (CTO ruling 2026-10-20, decision-challenges.md). A second curl call site is a RED in the suite.
#   * ONE project. The Inngest project ref is a literal below; any other `--ref` is refused before a
#     request is made. The same account-wide access token also reaches the production app project.
#   * A CLOSED allowlist of committed queries (`Q_*`), each ONE statement, a leading `select`, no `;`,
#     catalog metadata only, schema-qualified, no function outside a short allowlist. No SQL is ever
#     assembled from an argument, a response or the environment. `_sql_ok` re-checks every literal
#     before it is sent and the suite lints every literal.
#   * Identity before everything. The `identity` query runs first in EVERY invocation. Nothing else is
#     sent unless it proved: the role is exactly `supabase_read_only_user`, the transaction is
#     read-only, the statement timeout is bounded, the Inngest sentinel tables exist and no
#     web-platform app table does.
#   * Output is numbers, booleans and identifiers that match a strict shape. The response body never
#     reaches stdout, stderr, a file or a log; an unexpected shape is `could-not-measure(<reason>)`
#     and a missing, failed or unparseable read is NEVER a zero.
#
# WHAT IT DOES NOT DO: select a row, an identifier, an event name, an email, a payload or a per-user
# count. The Inngest event tables carry event bodies that hold user identifiers; this probe never
# opens them. Whether a surviving record identifies WHICH users had armed reminders or in-flight
# jobs is therefore NOT established by this script, and the runbook says so.
#
# USAGE (the token reaches this process by environment only, never argv; `--only-secrets` hands the
# child that one secret; the access token is account-wide, so it is never echoed):
#   doppler run --only-secrets SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform -- \
#     bash scripts/inngest-history-probe.sh round1
# Queries: identity | columns | estimates | round1 (all three).
# Exit: 0 measured, 3 could-not-measure(<reason>), 2 refused before any request, 78 xtrace on.

# --- hostile-environment prologue -------------------------------------------------------------
# Runs only when EXECUTED. The suite SOURCES this file for its lints, and wiping the sourcing
# shell's exported variables would wipe the suite's own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # First statement of the run: a traced run would print the token's expansion. `$-` is tested, not
  # enumerated, because `SHELLOPTS=xtrace` and `bash -x` both land in it.
  [[ $- != *x* ]] || { printf 'inngest-history-probe: refusing to run with xtrace on\n' >&2; exit 78; }
  set +x
  set -uo pipefail
  unset BASH_XTRACEFD SHELLOPTS BASH_ENV ENV PS4 DOPPLER_TOKEN 2>/dev/null || true
  # Drop every other variable the caller exported: a child (curl) must hold nothing but the token,
  # PATH and HOME. In-process, never by re-exec, so the token is never on an `env` argv.
  for _v in $(compgen -e); do
    case "$_v" in
      PATH|HOME|SUPABASE_ACCESS_TOKEN|LC_ALL|LANG) ;;
      *) unset "$_v" 2>/dev/null || true ;;
    esac
  done
  unset _v
  export LC_ALL=C
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/bearer-curl.sh
source "$SCRIPT_DIR/lib/bearer-curl.sh" || { printf 'inngest-history-probe: bearer-curl.sh unavailable\n' >&2; exit 2; }

readonly PINNED_REF="pigsfuxruiopinouvjwy"
readonly API_HOST="https://api.supabase.com"
readonly MAX_TIME=20
readonly MAX_TABLES=80
readonly WANT_ROLE="supabase_read_only_user"

# --- the closed allowlist ---------------------------------------------------------------------
# Every query carries the same proof columns so ANY response shows the role and the settings it ran
# under: a response that cannot is not printed.
readonly Q_identity="select current_user as db_role, current_setting('transaction_read_only') as ro, current_setting('statement_timeout') as stmt_timeout, (select rolbypassrls from pg_catalog.pg_roles where rolname = current_user) as bypassrls, to_regclass('public.goose_db_version') is not null as has_goose, to_regclass('public.function_runs') is not null as has_function_runs, (to_regclass('public.kb_files') is not null or to_regclass('public.workspace_invitations') is not null or to_regclass('public.byok_delegation_acceptances') is not null) as has_app_tables"
readonly Q_columns="select current_user as db_role, current_setting('transaction_read_only') as ro, current_setting('statement_timeout') as stmt_timeout, c.relname as table_name, a.attname as column_name, pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace join pg_catalog.pg_attribute a on a.attrelid = c.oid where n.nspname = 'public' and c.relkind in ('r', 'p') and a.attnum > 0 and not a.attisdropped order by c.relname, a.attnum"
readonly Q_estimates="select current_user as db_role, current_setting('transaction_read_only') as ro, current_setting('statement_timeout') as stmt_timeout, c.relname as table_name, c.reltuples::bigint as est_rows, coalesce(s.n_live_tup, -1)::bigint as live_rows, c.relrowsecurity as rls_on, (select count(p.polrelid) from pg_catalog.pg_policy p where p.polrelid = c.oid)::int as n_policies from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace left join pg_catalog.pg_stat_user_tables s on s.relid = c.oid where n.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname"
# shellcheck disable=SC2034  # read by the suite, which sources this file for its lints
readonly QUERY_NAMES=(identity columns estimates)

# The only functions a literal may call (plus SQL keywords that precede a parenthesis).
readonly SQL_FUNCS_OK=" current_setting to_regclass format_type count coalesce in or and not exists select join on from where as is "
# Anything that makes a literal a row-returning or state-changing statement.
readonly SQL_FORBIDDEN_RE='(^|[^a-z_])(limit|distinct|insert|update|delete|drop|alter|create|grant|revoke|copy|call|do|vacuum|truncate|listen|notify|pg_sleep|pg_terminate_backend|pg_cancel_backend|nextval|set_config|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)([^a-z_]|$)|\*|->|#>|@>|<@|\?|;|\$|%'

# _sql_ok <literal> -- 0 only for a single read-only catalog statement. The suite lints every Q_*
# with this same function, so the check cannot drift from what is sent.
_sql_ok() {
  local sql="${1:-}" lower fn
  [[ -n "$sql" ]] || return 1
  [[ "$sql" == select\ * ]] || return 1
  lower="$(printf '%s' "$sql" | tr 'A-Z' 'a-z')"
  # `select *` is excluded by the forbidden set's `\*`; so is every jsonb operator and a `;`.
  if printf '%s' "$lower" | grep -qE "$SQL_FORBIDDEN_RE"; then return 1; fi
  # Every identifier that precedes a `(` must be an allowed function or keyword.
  while IFS= read -r fn; do
    [[ -n "$fn" ]] || continue
    [[ "$SQL_FUNCS_OK" == *" $fn "* ]] || return 1
  done < <(printf '%s' "$lower" | grep -oE '[a-z_][a-z0-9_.]*[[:space:]]*\(' | sed -E 's/[[:space:]]*\($//; s/^.*\.//')
  return 0
}

# --- could-not-measure ------------------------------------------------------------------------
readonly REASONS=" credential_refused xtrace bad_call transport timeout credential_unauthorized role_privilege endpoint_unavailable rate_limited server_error empty_body shape readonly_unverifiable unbounded_statement not_inngest_project too_many_tables unsafe_name "
# cnm <reason> -- the ONLY way a failure is reported. The reason is a fixed enum word; nothing from a
# response, a token or a column ever reaches this line.
cnm() {
  local r="$1"
  [[ "$REASONS" == *" $r "* ]] || r="shape"
  printf 'could-not-measure(%s)\n' "$r"
  return 3
}

# --- the one transport ------------------------------------------------------------------------
# _send <query-name> -- sets RESP_BODY (the response body) and returns 0 only for a 2xx; any other
# outcome returns 3 after printing a could-not-measure line. The body lives in a shell variable
# only: never a file, never a log.
RESP_BODY=""
_send() {
  local name="$1" sql="" payload raw code rc
  case "$name" in
    identity)  sql="$Q_identity" ;;
    columns)   sql="$Q_columns" ;;
    estimates) sql="$Q_estimates" ;;
    *) printf 'refused: unknown query\n' >&2; return 2 ;;
  esac
  _sql_ok "$sql" || { cnm bad_call; return 3; }
  # The same predicate bc_curl applies, run first, so a refusal is named here instead of being folded
  # into a transport rc (bc_curl returns 2, which curl also uses for an init failure).
  bc_ok_var SUPABASE_ACCESS_TOKEN || { cnm credential_refused; return 3; }
  payload="$(jq -nc --arg q "$sql" '{query: $q}' 2>/dev/null)" || { cnm bad_call; return 3; }
  rc=0
  raw="$(bc_curl inngest-history-probe 'Authorization:Bearer :SUPABASE_ACCESS_TOKEN' -- \
    -sS --max-time "$MAX_TIME" --request POST \
    --url "${API_HOST}/v1/projects/${PINNED_REF}/database/query/read-only" \
    --header 'Content-Type: application/json' --data "$payload" \
    -w $'\n%{http_code}' 2>/dev/null)" || rc=$?
  case "$rc" in
    0) ;;
    28) cnm timeout; return 3 ;;
    78) cnm xtrace; return 3 ;;
    64) cnm bad_call; return 3 ;;
    *) cnm transport; return 3 ;;
  esac
  code="${raw##*$'\n'}"
  RESP_BODY="${raw%$'\n'*}"
  [[ "$code" =~ ^[0-9]{3}$ ]] || { cnm transport; return 3; }
  case "$code" in
    200|201) ;;
    401) cnm credential_unauthorized; return 3 ;;
    403) cnm role_privilege; return 3 ;;
    404|405|410) cnm endpoint_unavailable; return 3 ;;
    429) cnm rate_limited; return 3 ;;
    5??) cnm server_error; return 3 ;;
    *) cnm shape; return 3 ;;
  esac
  [[ -n "$RESP_BODY" ]] || { cnm empty_body; return 3; }
  return 0
}

# --- shape helpers ----------------------------------------------------------------------------
# An identifier may be printed only if it has the shape of a Postgres object name AND does not look
# like an id, a hash, a number or an address: it starts with a letter, is lower-case word characters,
# has no run of six digits, and is not 32 hex characters.
_ident_ok() {
  local s="${1:-}"
  [[ "$s" =~ ^[a-z][a-z0-9_]{0,62}$ ]] || return 1
  [[ ! "$s" =~ [0-9]{6,} ]] || return 1
  [[ ! "$s" =~ ^[0-9a-f]{32}$ ]] || return 1
  return 0
}
_type_ok() {
  local s="${1:-}" re='^[a-z][][a-z0-9_ (),]{0,63}$'
  [[ "$s" =~ $re ]] || return 1
  [[ ! "$s" =~ [0-9]{6,} ]] || return 1
  return 0
}
_int_ok() { [[ "${1:-}" =~ ^-?[0-9]{1,15}$ ]]; }
_bool_ok() { [[ "${1:-}" == true || "${1:-}" == false ]]; }

# _rows <body> <key>... -- succeed only if the body is a non-empty JSON array whose every element is an
# object with EXACTLY these keys (any order). jq's own error text is discarded.
_rows() {
  local body="$1"; shift
  local keys; keys="$(printf '%s\n' "$@" | sort | jq -R . 2>/dev/null | jq -sc . 2>/dev/null)" || return 1
  printf '%s' "$body" | jq -e --argjson keys "$keys" \
    'type == "array" and length > 0 and all(.[]; type == "object" and ((keys | sort) == $keys))' >/dev/null 2>&1
}

# _proof <body> -- every row carries the role and settings it ran under; refuse unless they are the
# read-only role, a read-only transaction and a bounded statement timeout. Sets PROOF_TIMEOUT.
PROOF_TIMEOUT=""
_proof() {
  local body="$1" role ro to
  role="$(printf '%s' "$body" | jq -r '[.[].db_role] | unique | join(",")' 2>/dev/null)" || { cnm shape; return 3; }
  ro="$(printf '%s' "$body" | jq -r '[.[].ro] | unique | join(",")' 2>/dev/null)" || { cnm shape; return 3; }
  to="$(printf '%s' "$body" | jq -r '[.[].stmt_timeout] | unique | join(",")' 2>/dev/null)" || { cnm shape; return 3; }
  [[ "$role" == "$WANT_ROLE" && "$ro" == "on" ]] || { cnm readonly_unverifiable; return 3; }
  [[ "$to" =~ ^[0-9]+(ms|s|min|h|d)?$ ]] || { cnm readonly_unverifiable; return 3; }
  [[ "$to" =~ ^0(ms|s|min|h|d)?$ ]] && { cnm unbounded_statement; return 3; }
  PROOF_TIMEOUT="$to"
  return 0
}

# --- the three measurements -------------------------------------------------------------------
# Each prints its lines to stdout only after every value passed its shape check, and returns 3 with a
# could-not-measure line otherwise.
IDENTITY_BYPASSRLS=""
m_identity() {
  _send identity || return $?
  local b="$RESP_BODY" goose fr app byp
  _rows "$b" db_role ro stmt_timeout bypassrls has_goose has_function_runs has_app_tables || { cnm shape; return 3; }
  [[ "$(printf '%s' "$b" | jq 'length' 2>/dev/null)" == "1" ]] || { cnm shape; return 3; }
  _proof "$b" || return $?
  goose="$(printf '%s' "$b" | jq -r '.[0].has_goose' 2>/dev/null)"
  fr="$(printf '%s' "$b" | jq -r '.[0].has_function_runs' 2>/dev/null)"
  app="$(printf '%s' "$b" | jq -r '.[0].has_app_tables' 2>/dev/null)"
  byp="$(printf '%s' "$b" | jq -r '.[0].bypassrls' 2>/dev/null)"
  _bool_ok "$goose" && _bool_ok "$fr" && _bool_ok "$app" && _bool_ok "$byp" || { cnm shape; return 3; }
  # The project is the Inngest one iff both sentinels exist and no web-platform app table does.
  if [[ "$goose" != true || "$fr" != true || "$app" != false ]]; then cnm not_inngest_project; return 3; fi
  IDENTITY_BYPASSRLS="$byp"
  printf 'identity: role=%s read_only=on statement_timeout=%s sentinel_goose=present sentinel_function_runs=present app_tables=absent bypassrls=%s\n' \
    "$WANT_ROLE" "$PROOF_TIMEOUT" "$byp"
}

m_columns() {
  _send columns || return $?
  local b="$RESP_BODY" n t c d tables=0 cols=0 json=0 line
  _rows "$b" db_role ro stmt_timeout table_name column_name data_type || { cnm shape; return 3; }
  _proof "$b" || return $?
  declare -A tcols=() tjson=() tref=()
  while IFS=$'\t' read -r t c d; do
    _ident_ok "$t" && _ident_ok "$c" && _type_ok "$d" || { cnm unsafe_name; return 3; }
    cols=$((cols + 1))
    if [[ -z "${tcols[$t]:-}" ]]; then tables=$((tables + 1)); tcols[$t]=0; tjson[$t]=0; tref[$t]=""; fi
    [[ "$tables" -le "$MAX_TABLES" ]] || { cnm too_many_tables; return 3; }
    tcols[$t]=$((tcols[$t] + 1))
    case "$d" in json|jsonb) tjson[$t]=$((tjson[$t] + 1)); json=$((json + 1)) ;; esac
    # Column names that could hold a user reference: names only, by a fixed pattern.
    if [[ "$c" =~ (user|account|workspace|tenant|customer|founder|actor|email|sender|recipient|(^|_)ip($|_)) ]]; then
      tref[$t]="${tref[$t]:+${tref[$t]},}$c"
    fi
  done < <(printf '%s' "$b" | jq -r '.[] | [.table_name, .column_name, .data_type] | @tsv' 2>/dev/null)
  [[ "$tables" -gt 0 ]] || { cnm shape; return 3; }
  printf 'columns: tables=%s columns=%s json_typed_columns=%s\n' "$tables" "$cols" "$json"
  for t in $(printf '%s\n' "${!tcols[@]}" | sort); do
    line="columns: table=$t cols=${tcols[$t]} json_typed=${tjson[$t]}"
    [[ -z "${tref[$t]}" ]] || line="$line candidate_user_reference_columns=${tref[$t]}"
    printf '%s\n' "$line"
  done
}

m_estimates() {
  _send estimates || return $?
  local b="$RESP_BODY" t est live rls pol n=0 hidden=0
  _rows "$b" db_role ro stmt_timeout table_name est_rows live_rows rls_on n_policies || { cnm shape; return 3; }
  _proof "$b" || return $?
  while IFS=$'\t' read -r t est live rls pol; do
    _ident_ok "$t" && _int_ok "$est" && _int_ok "$live" && _bool_ok "$rls" && _int_ok "$pol" || { cnm unsafe_name; return 3; }
    n=$((n + 1))
    [[ "$n" -le "$MAX_TABLES" ]] || { cnm too_many_tables; return 3; }
    printf 'estimates: table=%s est_rows=%s live_rows=%s rls=%s policies=%s\n' "$t" "$est" "$live" "$([[ "$rls" == true ]] && echo on || echo off)" "$pol"
    # RLS on with no policy hides every row from a role without BYPASSRLS: a row read would come
    # back empty and read as a zero. Said once per table so no later query is mistaken for evidence.
    if [[ "$rls" == true && "$pol" == "0" && "$IDENTITY_BYPASSRLS" == false ]]; then hidden=$((hidden + 1)); fi
  done < <(printf '%s' "$b" | jq -r '.[] | [.table_name, .est_rows, .live_rows, .rls_on, .n_policies] | @tsv' 2>/dev/null)
  [[ "$n" -gt 0 ]] || { cnm shape; return 3; }
  printf 'estimates: tables=%s row_level_security_hides_rows_from_this_role=%s (a row-level read, including a min/max time bound, would read as empty: could-not-measure(rls_masks_rows), not a zero)\n' "$n" "$hidden"
  printf 'estimates: note=an estimate above zero supports measured-present only; it never supports measured-absent\n'
}

# --- entry ------------------------------------------------------------------------------------
main() {
  local ref="$PINNED_REF" what=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ref) [ "$#" -ge 2 ] || { printf 'refused: --ref needs a value\n' >&2; return 2; }; ref="$2"; shift 2 ;;
      identity|columns|estimates|round1) [ -z "$what" ] || { printf 'refused: one query name only\n' >&2; return 2; }; what="$1"; shift ;;
      *) printf 'refused: unknown argument\n' >&2; return 2 ;;
    esac
  done
  [ -n "$what" ] || { printf 'refused: a query name is required (identity|columns|estimates|round1)\n' >&2; return 2; }
  [ "$ref" = "$PINNED_REF" ] || { printf 'refused: only the pinned Inngest project is probed\n' >&2; return 2; }
  command -v jq >/dev/null 2>&1 || { cnm transport; return 3; }
  printf 'probe=inngest-history project_pinned=ok endpoint=database/query/read-only\n'
  local rc=0
  # Identity first in EVERY invocation; nothing else is sent unless it passed.
  m_identity || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  case "$what" in
    identity) ;;
    columns)   m_columns   || rc=$? ;;
    estimates) m_estimates || rc=$? ;;
    round1)    m_columns || rc=$?; if [ "$rc" -eq 0 ]; then m_estimates || rc=$?; fi ;;
  esac
  return "$rc"
}

# Sourced by the suite for its lints; run when executed.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
