#!/usr/bin/env bash
# inngest-registry-probe.sh — 2.0 pre-flight empty-registry probe for the Inngest
# dedicated-host cutover (#6178, ADR-100). Runs ON A WEB HOST (delivered via the
# infra-config push, invoked through the /hooks/inngest-registry-probe GET hook).
#
# The dedicated Inngest host (10.0.1.40) is deny-all-public and firewall-scoped to
# the web-host private subnet, so a GitHub runner CANNOT reach :8288 directly — a
# web host CAN over the private net (SEC-H2). This probe POSTs the top-level
# `{ functions { id slug triggers { type value } } }` GraphQL query to the
# dedicated host and REPORTS whether the registry is EMPTY. That is the
# load-bearing 2.0 gate: the cutover flip must only run against an EMPTY dark
# registry — a non-empty one means a second scheduler would register +
# double-fire against prod Postgres. (#6940: the slug/triggers fields are
# additive — the zero-run discovery in op=verify reads `triggers[].type` to tell
# CRON functions from event-driven ones, ADR-146 §Deferred item 1.)
#
# It does NOT itself decide abort — it reports; the `op=execute` workflow arm asserts.
#
# Output (stdout): a single pure-JSON object — counts + function ids/triggers
# ONLY, never reminder bodies / actors / connection strings (P2-sec-a). The
# webhook (adnanh/webhook v2.8.2) returns cmd.CombinedOutput() even on 200 and
# the workflow parses the body as a JSON OBJECT, so on the SUCCESS path this
# script writes NOTHING non-JSON to EITHER stream (summary → journald via
# `logger` only):
#   { "registry_empty": <bool>, "function_count": <int>, "function_ids": [<id>...],
#     "functions": [{ "id": <id>, "slug": <slug|null>,
#                     "triggers": [{ "type": "CRON"|"EVENT"|..., "value": <str> }] }] }
# `functions` is additive (#6940): a `.triggers` field absent per-object degrades
# to [], never a crash, so an older registry response shape still parses.
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
# >>> inngest-link-env >>>
# (#10136) The Inngest link the web hosts' resolver (ci-deploy.sh resolve_inngest_link) chose, read from
# /etc/soleur/inngest-link.env. PARSED, NEVER SOURCED: a key allowlist plus an exact literal check of the three values,
# so a hostile or corrupt file can neither run code nor select another endpoint (anything else is `invalid`: the default
# http endpoint plus a loud marker; the resolver, the tuple gate and the canary are the real gate, this file is advisory
# for the probes). It OVERRIDES an inherited INNGEST_REMOTE_GQL_URL (server.tf writes an explicit http one into the
# consumer probe's env, which would otherwise win). Byte-identical in inngest-registry-probe.sh and
# inngest-doublefire-probe.sh (the doublefire test compares the two); the registry probe is the documented owner.
INNGEST_LINK_ENV_FILE="${INNGEST_LINK_ENV_FILE:-/etc/soleur/inngest-link.env}"
LINK_BASE="http://10.0.1.40:8288"
LINK_CACERT=""
LINK_STATE="default"
_link_env_resolve() {
  local f="$INNGEST_LINK_ENV_FILE" k v url="" scheme="" cacert="" bad=0 n=0
  LINK_BASE="http://10.0.1.40:8288"; LINK_CACERT=""; LINK_STATE="default"
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then return 0; fi
  if [ ! -f "$f" ] || [ -L "$f" ] || [ ! -r "$f" ]; then LINK_STATE="invalid"; return 0; fi
  while IFS='=' read -r k v || [ -n "$k" ]; do
    n=$((n + 1))
    if [ "$n" -gt 16 ]; then bad=1; break; fi
    case "$k" in
      INNGEST_LINK_URL) url="$v" ;;
      INNGEST_LINK_SCHEME) scheme="$v" ;;
      INNGEST_LINK_CACERT) cacert="$v" ;;
      '') ;;
      *) bad=1 ;;
    esac
  done < "$f"
  if [ "$bad" = 0 ] && [ "$url" = "http://10.0.1.40:8288" ] && [ "$scheme" = "http" ] && [ -z "$cacert" ]; then
    LINK_STATE="http"
  elif [ "$bad" = 0 ] && [ "$url" = "https://10.0.1.40:8443" ] && [ "$scheme" = "https" ] && [ "$cacert" = "/etc/soleur/inngest-ca.pem" ]; then
    LINK_BASE="$url"; LINK_CACERT="$cacert"; LINK_STATE="https"
  else
    LINK_STATE="invalid"
  fi
  return 0
}
_link_env_resolve
LINK_CURL_TLS=()
case "$LINK_STATE" in
  http) GQL_URL="$LINK_BASE/v0/gql" ;;
  https) GQL_URL="$LINK_BASE/v0/gql"; LINK_CURL_TLS=(--cacert "$LINK_CACERT" --noproxy '*') ;;
  invalid) logger -t "${LOG_TAG:-inngest-probe}" "SOLEUR_INNGEST_LINK_ENV_INVALID file=$INNGEST_LINK_ENV_FILE action=default_http" 2>/dev/null || true ;;
esac
# <<< inngest-link-env <<<
FUNCTIONS_FIXTURE="${INNGEST_PROBE_FUNCTIONS_FIXTURE:-}"
CONNECT_TIMEOUT="${INNGEST_CONNECT_TIMEOUT:-5}"
PREFLIGHT_OP="verify-registry"
PREFLIGHT_HOST="${INNGEST_PREFLIGHT_HOST:-$(hostname 2>/dev/null || echo unknown)}"
PREFLIGHT_START_S=0

# shellcheck disable=SC2016  # GraphQL query, not a shell expansion
# #6940: `slug` + `triggers { type value }` are additive selections — the pinned
# schema (knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/
# inngest-graphql-schema.md) has `Function.triggers: [FunctionTrigger!]` with
# `type`/`value` subfields; a bare `triggers` is a GraphQL validation error.
# Same selection ci-deploy.sh already runs against this endpoint.
readonly FUNCTIONS_GQL_QUERY='query RegistryProbe { functions { id slug triggers { type value } } }'

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
  curl -s --max-time 15 --connect-timeout "$CONNECT_TIMEOUT" ${LINK_CURL_TLS[@]+"${LINK_CURL_TLS[@]}"} -X POST -H "Content-Type: application/json" \
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

  # #6940 — additive per-function projection. Missing `triggers` degrades to []
  # (`// []`); a malformed ELEMENT (non-object, or triggers non-array non-null)
  # still fails LOUD under set -e rather than silently un-discovering crons.
  local functions
  functions=$(echo "$fn_body" | jq -c \
    '[ .data.functions[] | {id, slug, triggers: [ ((.triggers // [])[]) | {type, value} ]} ]')

  # Observability summary (counts + ids ONLY, never bodies) → journald only.
  logger -t "$LOG_TAG" "registry probe: empty=$registry_empty function_count=$function_count" 2>/dev/null || true
  _pf_marker "SOLEUR_INNGEST_PREFLIGHT_DONE op=$PREFLIGHT_OP pages=1 elapsed_ms=$(( ($(date +%s) - PREFLIGHT_START_S) * 1000 ))"

  # Single pure-JSON object on stdout (the webhook body the workflow jq-parses).
  jq -nc --argjson empty "$registry_empty" --argjson count "$function_count" --argjson ids "$function_ids" --argjson fns "$functions" \
    '{registry_empty:$empty, function_count:$count, function_ids:$ids, functions:$fns}'
}

# --tls-handshake (#10136, plan Phase 3 "handshake evidence"): the web-host proof that the Inngest host's TLS listener is
# reachable AND verifies against the pinned CA, with no new probe script. (a) `curl --cacert <CA>` must return 200 on /health;
# (b) the SAME request without the CA must fail with a certificate-verification error (curl exit 60), so (a) is not an
# accident of a server that accepts everything. Independent of the link env (it runs BEFORE the flip too). The output is one
# line of fixed tokens plus numeric curl exit codes - never curl's stderr, never a certificate or a path. No -k, no --capath.
# Exit 0 only when verified=200 AND the unverified leg exited 60. CA file: INNGEST_CA_FILE (test seam), default the host file.
tls_handshake() {
  local ca="${INNGEST_CA_FILE:-/etc/soleur/inngest-ca.pem}" url="https://10.0.1.40:8443/health"
  local code_v="" rc_v=0 rc_u=0 vtok utok result=fail
  code_v=$(curl --disable --noproxy '*' -s -o /dev/null -w '%{http_code}' --connect-timeout "$CONNECT_TIMEOUT" --max-time 10 \
    --cacert "$ca" "$url" 2>/dev/null) || rc_v=$?
  curl --disable --noproxy '*' -s -o /dev/null --connect-timeout "$CONNECT_TIMEOUT" --max-time 10 "$url" >/dev/null 2>&1 || rc_u=$?
  if [[ "$rc_v" -eq 0 && "$code_v" == 200 ]]; then vtok=200; else vtok=fail; fi
  case "$rc_u" in 60) utok=fail ;; 0) utok=ACCEPTED ;; *) utok=other ;; esac
  if [[ "$vtok" == 200 && "$utok" == fail ]]; then result=pass; fi
  [[ "$rc_v" =~ ^[0-9]{1,3}$ ]] || rc_v=255
  [[ "$rc_u" =~ ^[0-9]{1,3}$ ]] || rc_u=255
  printf 'inngest-tls-handshake verified=%s verified_rc=%s unverified=%s unverified_rc=%s result=%s\n' "$vtok" "$rc_v" "$utok" "$rc_u" "$result"
  logger -t "$LOG_TAG" "SOLEUR_INNGEST_TLS_HANDSHAKE verified=$vtok unverified=$utok result=$result" 2>/dev/null || true
  [[ "$result" == pass ]]
}

# Run only when executed directly — sourcing (unit tests) must NOT hit the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --tls-handshake) tls_handshake ;;
    "") run_probe ;;
    *) echo "inngest-registry-probe: unknown argument (only --tls-handshake is accepted)" >&2; exit 2 ;;
  esac
fi
