#!/usr/bin/env bash
# inngest-registry-probe.sh — 2.0 pre-flight empty-registry probe for the Inngest
# dedicated-host cutover (#6178, ADR-100). Runs ON A WEB HOST (delivered via the
# infra-config push, invoked through the /hooks/inngest-registry-probe GET hook).
#
# The dedicated Inngest host (10.0.1.40) is deny-all-public and firewall-scoped to
# the web-host private subnet, so a GitHub runner CANNOT reach :8288 directly — a
# web host CAN over the private net (SEC-H2). This probe POSTs the top-level
# `{ functions { id } }` GraphQL query to the dedicated host and REPORTS whether
# the registry is EMPTY. That is the load-bearing 2.0 gate: the cutover flip must
# only run against an EMPTY dark registry — a non-empty one means a second scheduler
# would register + double-fire against prod Postgres.
#
# It does NOT itself decide abort — it reports; the `op=execute` workflow arm asserts.
#
# Output (stdout): a single pure-JSON object — counts + function ids ONLY, never
# reminder bodies / actors / connection strings (P2-sec-a). The webhook (adnanh/
# webhook v2.8.2) returns cmd.CombinedOutput() even on 200 and the workflow parses
# the body as a JSON OBJECT, so on the SUCCESS path this script writes NOTHING
# non-JSON to EITHER stream (summary → journald via `logger` only):
#   { "registry_empty": <bool>, "function_count": <int>, "function_ids": [<id>...] }
#
# Fail-LOUD (non-zero exit + stderr) on a non-array `.data.functions` — a fetch
# failure, a GraphQL error envelope, or any unexpected shape (incl. a bare array).
# A false-clean empty registry here would green-light a cutover against a host we
# never actually reached. Purity + fail-loud modelled on inngest-inventory.sh's
# fetch_functions (:115-190).
#
# Single-shot (#6258, ADR-106): this probe issues exactly ONE non-paginated GraphQL
# query — there is NO cursor loop — so it needs no wall-clock deadline / page ceiling
# (Deepen Finding 12, Phase 0.3 resolved). It gets only the START/DONE SOLEUR_INNGEST_
# PREFLIGHT_* marker + a `--connect-timeout` on its single curl (bound a TCP-connect stall).
#
# Test seam: INNGEST_PROBE_FUNCTIONS_FIXTURE (a file with the /v0/gql functions
# response) short-circuits the curl.
set -euo pipefail

readonly LOG_TAG="inngest-registry-probe"

# The DEDICATED host GQL over the private net (NOT loopback 127.0.0.1 — this probe
# runs on a web host, not on the inngest host). INNGEST_REMOTE_GQL_URL mirrors the
# sibling scripts' INNGEST_GQL_URL/SCHEDULE_REMINDER_URL parameterisation.
GQL_URL="${INNGEST_REMOTE_GQL_URL:-http://10.0.1.40:8288/v0/gql}"
FUNCTIONS_FIXTURE="${INNGEST_PROBE_FUNCTIONS_FIXTURE:-}"
CONNECT_TIMEOUT="${INNGEST_CONNECT_TIMEOUT:-5}"
PREFLIGHT_OP="verify-registry"
PREFLIGHT_HOST="${INNGEST_PREFLIGHT_HOST:-$(hostname 2>/dev/null || echo unknown)}"
PREFLIGHT_START_S=0

# shellcheck disable=SC2016  # GraphQL query, not a shell expansion
readonly FUNCTIONS_GQL_QUERY='query RegistryProbe { functions { id } }'

# Observability markers (#6258 Deepen Finding 8) — journald-ONLY (stdout IS the pure-JSON
# webhook body). Escape-notation Unicode-separator sanitizer (cq-regex-unicode-separators-
# escape-only). This single-shot probe emits START (before the network call) + DONE only.
_pf_sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' \
    | sed $'s/\xc2\x85//g; s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'   # U+0085 NEL, U+2028, U+2029
}
# _pf_scrub (#6258 review P1): redact connection strings/credentials + strip control
# chars / Unicode separators from UNTRUSTED GraphQL errors[].message text before the
# FATAL/ERROR diagnostic lines emit it to journald (→ Better Stack) or stdout (→ the
# Actions run log). A DSN can appear in a DB errors[].message. stdin→stdout.
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

# Fetch the registered-function list via /v0/gql (fixture or private-net curl).
# Echoes the raw GraphQL response {data:{functions:[...]}}. Injection-safe body via
# jq -n. On a real curl failure emit a GraphQL error envelope (no .data.functions)
# so run_probe fails LOUD below instead of recording a false-clean empty registry.
fetch_functions() {
  if [[ -n "$FUNCTIONS_FIXTURE" ]]; then
    cat "$FUNCTIONS_FIXTURE"
    return 0
  fi
  local body
  body=$(jq -nc --arg q "$FUNCTIONS_GQL_QUERY" '{query:$q}')
  curl -s --max-time 15 --connect-timeout "$CONNECT_TIMEOUT" -X POST -H "Content-Type: application/json" \
    --data-binary "$body" "$GQL_URL" \
    || echo '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}'
}

run_probe() {
  # START marker — the LITERAL first action, before any network call (Finding 8).
  PREFLIGHT_START_S=$(date +%s)
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_START op=$PREFLIGHT_OP host=$PREFLIGHT_HOST window=single-shot page_ceiling=1 deadline_s=0"

  local fn_body function_ids function_count registry_empty
  fn_body=$(fetch_functions)

  # Fail LOUD (not false-clean) if the /v0/gql functions query failed or returned a
  # non-array .data.functions. A legitimately-empty registry returns
  # {data:{functions:[]}} → passes this gate → registry_empty:true correctly; a
  # fetch failure, a GraphQL error envelope, or any unexpected shape (incl. a bare
  # array) trips it. The guard is NOT loosened to accept any shape.
  if ! echo "$fn_body" | jq -e '.data.functions | type == "array"' >/dev/null 2>&1; then
    # P2-sec-a purity: surface only GraphQL error MESSAGES + .data KEY NAMES.
    local fn_errs fn_keys
    fn_errs=$(echo "$fn_body" | jq -c '[(.errors // [])[].message]' 2>/dev/null || echo '["<unparseable response>"]')
    fn_errs=$(printf '%s' "$fn_errs" | _pf_scrub)   # #6258 P1: no DSN/creds to journald+stdout
    fn_keys=$(echo "$fn_body" | jq -c '((.data // {}) | keys)' 2>/dev/null || echo '[]')
    # journald-only TIMEOUT marker (enum reason, never a raw GraphQL message — Finding 13).
    _pf_marker "SOLEUR_INNGEST_PREFLIGHT_TIMEOUT op=$PREFLIGHT_OP pages=1 elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 )) pages_timed_out=0 last_curl_exit=0 reason=gql_error"
    logger -t "$LOG_TAG" "ERROR: /v0/gql functions unreachable or non-array: errors=$fn_errs data_keys=$fn_keys" 2>/dev/null || true
    echo "inngest-registry-probe: FATAL /v0/gql functions query failed or non-array (errors=$fn_errs data_keys=$fn_keys); is the dedicated inngest-server reachable at $GQL_URL? — refusing to emit a false-clean empty registry"
    echo "ERROR: /v0/gql functions non-array (errors=$fn_errs data_keys=$fn_keys)" >&2
    exit 1
  fi

  function_ids=$(echo "$fn_body" | jq -c '[ .data.functions[] | .id ] | sort')
  function_count=$(echo "$function_ids" | jq 'length')
  if [[ "$function_count" -eq 0 ]]; then registry_empty=true; else registry_empty=false; fi

  # Observability summary (counts + ids ONLY, never bodies) → journald only.
  logger -t "$LOG_TAG" "registry probe: empty=$registry_empty function_count=$function_count" 2>/dev/null || true
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_DONE op=$PREFLIGHT_OP pages=1 elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))"

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  jq -nc --argjson empty "$registry_empty" --argjson count "$function_count" --argjson ids "$function_ids" \
    '{registry_empty:$empty, function_count:$count, function_ids:$ids}'
}

# Run only when executed directly — sourcing (unit tests) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_probe
fi
