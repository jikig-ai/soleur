#!/usr/bin/env bash
# cloudflare-readonly.sh - six READ-ONLY Cloudflare checks for the Class R live-read acts (#10479, #12441, Ref #10205):
# four GET reads and two fixed read-only GraphQL analytics reads (the one documented POST exception, below).
#
# Jikigai-internal. It is inert wherever the CF_* token variables are absent, and it refuses unless it runs under the
# Doppler project `soleur` and config `prd_terraform` (those two variables are a mistake-guard: the environment can be forged).
#
# Subcommands (a closed set; there is no path, query, method, host or token-variable pass-through):
#   ssl-mode            A. zone SSL mode                      GET /zones/{zone}/settings/ssl
#   config-entrypoint   B. config-settings ruleset entrypoint  GET /zones/{zone}/rulesets/phases/http_config_settings/entrypoint
#   pagerules-ssl       C. legacy page rules, SSL actions only GET /zones/{zone}/pagerules?status=active
#   change-history      E. bounded 7-day audit-log read        GET /accounts/{account}/logs/audit  (counts only)
#   analytics-health <hours>       F. /health origin response time per hour   POST /graphql, one fixed query (#12441)
#   analytics-edge-errors <hours>  G. edge 5xx status counts per hour         POST /graphql, one fixed query (#12441)
#   --list              print the six names, exit 0 (no credential, no network)
# The four GET subcommands take no further argument. The two analytics ones take exactly one more: a whole number of hours, 1 to
# 216 (9 days, the one verified window), no default, checked before any credential is read.
#
# Invocation (direct exec; never wrap this file in a shell under doppler run, the Credentials paragraph forbids it):
#   doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh <subcommand> [<hours>]
# Run it from the repository checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is
# empty (a freshly fetched origin/main), never from a plugin-cache copy. Until this file is on origin/main that diff cannot
# be empty, so the first live read is after the merge.
#
# Token binding (no flag, no fallback; CF_API_TOKEN is never used):
#   ssl-mode -> CF_API_TOKEN_ZONE_SETTINGS     config-entrypoint -> CF_API_TOKEN_RULESETS
#   pagerules-ssl -> CF_API_TOKEN_PAGERULES_READ (zone-scoped Page Rules: Read on soleur.ai only; read-only; no fallback to
#   CF_API_TOKEN_RULESETS, which returned 403 on /pagerules, and no fallback to any other token)
#   change-history -> CF_API_TOKEN_AUDIT plus CF_ACCOUNT_ID       the others also need CF_ZONE_ID
#   analytics-health, analytics-edge-errors -> CF_API_TOKEN_ANALYTICS_READ (Analytics:Read on the zone soleur.ai only; read-only;
#   expires 2027-02-07, after which a 401 records `token-invalid`; no fallback to any other token). Nothing else reads it.
# CF_API_TOKEN_ZONE_SETTINGS and CF_API_TOKEN_RULESETS are Terraform-scoped and write-capable (no read-only equivalent exists
# yet); that exception is removable when read-only equivalents are minted, which is a credential change and the owner's.
# CF_API_TOKEN_PAGERULES_READ is the read-only token minted for check C (#10479), so C is no longer part of that exception.
# CF_API_TOKEN_AUDIT is read-only but is documented under the Doppler dev config, so change-history is expected to record
# `no-credential` or `other: refused-source` until the owner relocates it (where it lives is an open question). This wrapper's
# safety is structural: one GET call site plus ONE read-only-POST call site (cf_graphql), absolute curl path, fixed URLs, an EMPTY
# environment for curl AND for every jq and date child (`/usr/bin/env -i`; an empty HOME means a planted ~/.jq is not
# loaded and `$ENV` is empty, verified on jq 1.8.2), the credential on curl's stdin config only, and the xtrace refusal. See standing-delegation.md
# section 9 (Credentials) for the stated exception. A 403 is recorded as unverified and never answered by a token swap.
#
# READ-ONLY POST EXCEPTION (#12441): a GraphQL read is an HTTP POST that only reads. Exactly two fixed queries are compiled into this
# file (GQL_HEALTH_TPL, GQL_EDGE_TPL); the only substitutions are the zone id and two window stamps computed from the clock, so the
# caller's integer never enters the query text and no query text, filter, path, host or method comes from the caller. The body
# reaches curl only as a data-raw line of the stdin config, beside the Authorization and Content-Type lines, never on argv. The
# window is complete UTC hours, [end - hours, end), so the newest series point lags by up to one hour. Counts are sampled estimates.
# A zone the token cannot see and a wrong zone id are not distinguished (`no-zone-access`), like the 401 / 403 note below.
# Unverified (public docs do not cover them; the first sanctioned read after the merge is the check, at most two fix PRs in total):
# the edgeResponseStatus dimension and its range operators, orderBy datetimeHour_DESC on this node, and the duration quantile names.
#
# RESIDUAL, not fixed here: BASH_ENV, exported BASH_FUNC_* functions, SHELLOPTS and PS4, LD_PRELOAD and the shebang's PATH lookup
# (`#!/usr/bin/env bash`) are caller-environment channels that act in this script's OWN bash before and around its checks, so
# `env -i` on the children does not reach them. The caller is the operator's `doppler run`; nothing in this file claims to defend
# against a hostile caller environment.
# ACCEPTED RESIDUAL: a rule ref or an id is operator-authored data and is printed verbatim after a shape check (1 to 64 characters
# of A-Z a-z 0-9 _ -); it is data under the Boundary paragraph of section 9, never an instruction, and the shapes are bounded.
#
# Documentation basis (documentation only; no authenticated call was made), verified 2026-11-04:
#   - Zone settings GET: the generic response is { success, errors, messages, result } with the setting object under
#     result (https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/get/).
#   - Ruleset entrypoint (https://developers.cloudflare.com/ruleset-engine/rulesets-api/view/): a top-level result.version
#     is shown for "get a zone ruleset" but not for the entrypoint GET, so version is OPTIONAL and prints null when absent;
#     the "no entrypoint" status is documented only for the entrypoint VERSION endpoints (404), so any 404 here is not-found.
#   - Audit logs v2 (https://developers.cloudflare.com/api/resources/accounts/subresources/logs/subresources/audit/methods/list/):
#     since and before are the only query parameters not labelled optional, so BOTH are sent; rows carry action.type,
#     action.time and resource.type; there is no end-of-results signal (truncated means the row count equals the limit);
#     the page lists the accepted permissions as Account Settings Read or Write (it does not name "Audit Logs Read").
# Not verified (assumptions the wrapper tolerates, not relies on):
#   - The ssl-specific entry of the zone-settings response was not in the page excerpt read, so a body without result is
#     bad-response, never guessed.
#   - action_parameters.ssl for set_config is not documented, so ssl is read defensively and enum-checked.
#   - Page rules: any one of Zone Read, Zone Write, Page Rules Read or Page Rules Write is accepted (from the plan deepen pass,
#     not re-read). CF_API_TOKEN_RULESETS lacks it (a live 403, 2026-11-05), so check C is bound to the dedicated read-only
#     CF_API_TOKEN_PAGERULES_READ; a 403 there is still a valid recorded result and is never answered by a token swap.
#
# Output contract: the first stdout line is `cloudflare-readonly: <subcommand> ok` or
# `cloudflare-readonly: <subcommand> unverified - <reason>`, then (ok only) one JSON projection line, EXCEPT exits 64 and 78
# and the `--list` mode: exits 64 and 78 write one fixed line to stderr only (nothing was sent). Messages are fixed,
# single-line and value-free, with ONE stated exception: on an analytics api-error the FIRST GraphQL error message is printed as
# `api-error (graphql: <msg>)` only when it passes a fixed in-full check (letters, digits, space and . _ ' " ( ) -, 1 to 160
# characters; no credential word, no copy of the live token, no dotted quad); otherwise plain `api-error`. It is vendor text, so data.
# A response body, a rule expression, a description, a page-rule pattern, an actor or an IP
# is never printed; every vendor string that is printed is enum- or regex-checked first. curl and jq diagnostics are
# captured and reduced to `curl exit <n>` / `jq exit <n>` (the one stated exception to "stderr is never discarded":
# they can quote body fragments); this wrapper's own diagnostics always reach stderr.
# bad-response has three distinct spellings: `bad-response (jq exit <n>)` only for a real non-zero jq exit, `bad-response (shape)`
# when jq succeeded but the body is not the expected shape (or is empty), and plain `bad-response` for a non-numeric HTTP status.
# The 401 / 403 reasons (token-invalid / token-lacks-scope) are keyed on the HTTP status alone: the cause is NOT distinguished
# from an IP or WAF block.
#
# Exit codes: 0 ok | 10 no-credential | 11 token-invalid / token-lacks-scope (401, 403) | 14 not-found, api-error, no-zone-access,
#   upstream-error (429, 5xx, other non-2xx, curl failure), bad-response or no-tool | 64 usage or refused source / token
#   shape / id shape / date failure (nothing was sent) | 78 refused to run under shell tracing with a live credential.
#
# Records mapping (section 9 Records; the wrapper verdict is NOT a Records verdict). Each check is its own
# Checked: / Unverified: line with a stable key: `Cloudflare ssl-mode (A) #10479`, `Cloudflare config-entrypoint (B) #10479`,
# `Cloudflare pagerules-ssl (C) #10479`, `Cloudflare change-history (E) #10479`, `Cloudflare analytics-health (F) #12441`,
# `Cloudflare analytics-edge-errors (G) #12441`.
#   A ssl-mode          figure value=<value>; Records ok when value is strict (the runbook claim), bad on any other value.
#                       An A ok NEVER stands alone for a flip go: read it together with B.
#   B config-entrypoint figures rule_count, enabled_ssl_rules (the count of rules that are enabled, i.e. `enabled != false`,
#                       with a non-null ssl) and per rule ref, enabled, ssl and two host booleans. The host booleans are
#                       LITERAL SUBSTRING figures only and are not a verdict input: a wildcard such as
#                       ends_with(http.host, ".soleur.ai") or an expression of true defeats them. Records ok ONLY when
#                       the baseline (both ORIGIN-TLS switches off) enabled_ssl_rules is 2 AND one of those rules has ref dcb85b75bc3c4f4aa2a8c13a080bf854 with ssl=flexible
#                       (the other is the `ssl = "full"` rule on soleur.ai and www) AND rule_count is 5; anything else is
#                       recorded not ok with the figures. rule_count is 5 because the ruleset carries the three baseline rules plus the
#                       two ALWAYS-PRESENT ORIGIN-TLS rules (ADR-321: the canary and the strict flip; present but disabled
#                       while their Doppler switches ENABLE_ORIGIN_TLS_CANARY_RULE / ENABLE_ORIGIN_TLS_STRICT are off, so the
#                       count never changes when a switch flips). enabled_ssl_rules is 2 PLUS one for each of those switches that is
#                       on: 2 with both off, 3 with the canary on, 4 with both on; read it against the switches' Doppler state.
#                       The wrapper CANNOT verify that
#                       the rule's expression is host-scoped (it never prints the expression), so Records ok does not depend
#                       on the host booleans; the owner compares the live expression with
#                       apps/web-platform/infra/seo-config-rules.tf before any flip go. The 5, the 2 and the ref are DATED
#                       SNAPSHOTS (re-derived 2026-11-07: rule_count 3 -> 5 when the two ORIGIN-TLS rules became static blocks;
#                       2026-11-05: enabled_ssl_rules 1 -> 2, the `ssl = "full"` rule was missed on 2026-11-04): they are
#                       re-derived from that file at read time,
#                       and the wrapper test fails when the counts here drift from it.
#   C pagerules-ssl     figures active_rule_count, ssl_rule_count and per rule the matches_app_host substring figure. Records
#                       ok ONLY when ssl_rule_count is 0. Any SSL page rule is recorded not ok with the figures and flagged
#                       for CTO review even when matches_app_host is false (a wildcard pattern defeats that boolean).
#   E change-history    figures rows, truncated, by_action_type (every type with its count) and by_resource_type. Never a
#                       `Checked:` line: always `Unverified: ..., other: window-7d-only` unless it yields a positive change
#                       finding. Evidence only, never a gate.
#   F analytics-health  figures rows and the per-hour count, avg_ms, p50_ms and p90_ms; evidence only, never a gate, `Unverified:` until
#                       the first sanctioned read. G analytics-edge-errors  figures by_status (counts per observed 5xx status) and
#                       truncated; same rule. Neither computes an exact error rate (counts are sampled).
#   What to do next, by reason: `api-error (graphql: unknown field ...)` -> a wrapper fix PR (at most two in total across both
#   queries); `no-zone-access` -> check the zone id and the token's zone; `token-invalid` -> the token (expires 2027-02-07) was
#   rotated or expired, which is the owner's credential change; `no-credential` -> the Doppler config lacks the token.
# Reasons to Records vocabulary: exit 10 -> no-credential; exits 11 and 14 -> `other: <reason token>` (the vocabulary includes no-zone-access); exit 64 for a
# usage error records nothing (re-run correctly); exit 64 for a refused source or token shape -> `other: refused-source`;
# status 78 -> `other: xtrace`; a checkout whose diff against origin/main for this file is non-empty -> `other: wrapper-drift`
# (fetch, rebase, re-diff, re-run); 429 / 5xx -> one re-run after a pause is allowed, the newest line governs.
# Cloud (Devin) sessions: the session-level cloud-ack-before-secrets obligation applies and is not implemented here.
set -uo pipefail

# (#7797) Refuse to run under shell tracing while a live credential is set: tracing echoes commands AFTER
# expansion, so the Bearer value would leak the moment it is bound. Test the STATE, not a list of ways to enable it.
case "$-" in
  *x*)
    if [ -n "${CF_API_TOKEN_ZONE_SETTINGS:+x}${CF_API_TOKEN_RULESETS:+x}${CF_API_TOKEN_PAGERULES_READ:+x}${CF_API_TOKEN_AUDIT:+x}${CF_API_TOKEN_ANALYTICS_READ:+x}${CF_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

export LC_ALL=C
PATH=/usr/bin:/bin
# TLS-subverting and resolver environment: closing --disable (curlrc) and --noproxy (proxy vars) does not touch these.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

# Absolute curl. No environment override exists; the suite rewrites exactly this line in a sandbox copy.
CURL=/usr/bin/curl

BASE='https://api.cloudflare.com/client/v4'
GQL_URL="$BASE/graphql"
SUBCOMMANDS=(ssl-mode config-entrypoint pagerules-ssl change-history analytics-health analytics-edge-errors)
TOKEN_RE='^[A-Za-z0-9._~+/=-]+$'
ID_RE='^[0-9a-f]{32}$'
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
LIMIT=50
QLIMIT=0
HOURS=0
MAX_HOURS=216
GQL_MSG_RE='^[A-Za-z0-9 ._'"'"'"()-]{1,160}$'
WIN_START=""
WIN_END=""
GQL_MSG=""
SUB=""
TOKVAR=""
TOK=""
BODY=""
STATUS=""

# The two fixed GraphQL query bodies (compiled in; the only substitutions are the zone id and the two window stamps, each validated
# upstream). Read-only by construction: no mutation, no subscription, no introspection. Placeholders: @ZONE@ @START@ @END@.
GQL_HEALTH_TPL='{"query":"query{viewer{zones(filter:{zoneTag:\"@ZONE@\"}){httpRequestsAdaptiveGroups(limit:300,filter:{datetime_geq:\"@START@\",datetime_lt:\"@END@\",clientRequestPath:\"/health\"},orderBy:[datetimeHour_ASC]){count dimensions{datetimeHour} avg{originResponseDurationMs} quantiles{originResponseDurationMsP50 originResponseDurationMsP90}}}}}"}'
GQL_EDGE_TPL='{"query":"query{viewer{zones(filter:{zoneTag:\"@ZONE@\"}){httpRequestsAdaptiveGroups(limit:1000,filter:{datetime_geq:\"@START@\",datetime_lt:\"@END@\",clientRequestHTTPHost:\"app.soleur.ai\",edgeResponseStatus_geq:500,edgeResponseStatus_lt:600},orderBy:[datetimeHour_DESC]){count dimensions{datetimeHour edgeResponseStatus}}}}}"}'

die() { # $1 = exit code, $2 = fixed message (never a value)
  printf 'cloudflare-readonly: %s\n' "$2" >&2
  exit "$1"
}
unverified() { # $1 = reason, $2 = exit code
  printf 'cloudflare-readonly: %s unverified - %s\n' "$SUB" "$1"
  exit "$2"
}
emit_ok() { # $1 = one-line JSON projection
  printf 'cloudflare-readonly: %s ok\n%s\n' "$SUB" "$1"
}
bad_jq() { # $1 = a real NON-ZERO jq exit status; jq's own diagnostics quote body fragments and are dropped
  unverified "bad-response (jq exit $1)" 14
}
bad_shape() { # jq succeeded but the body is not the expected shape (or is empty)
  unverified "bad-response (shape)" 14
}

# --- jq helpers: every printed vendor string goes through one of these ---
JQ_DEFS='def enum: if type == "string" and test("\\A(off|flexible|full|strict)\\z") then . else "other" end;
def sslv: if . == null then null else enum end;
def idv: if type == "string" and test("\\A[A-Za-z0-9_-]{1,64}\\z") then . else "invalid" end;
def rfc: "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z\\z";
def tsn: if . == null then null elif type == "string" and test(rfc) then . else "invalid" end;
def gk: if type == "string" and test("\\A[a-z_.]{1,64}\\z") then . else "invalid" end;
def tkey: sub("Z$"; "") | if contains(".") then . else . + ".0" end;
def dur: . == null or (type == "number" and . >= 0 and . <= 1e7);
def cnt: type == "number" and . == floor and . >= 0 and . <= 1e12;
def r1: if . == null then null else ((. * 10 | round) / 10) end;
def verstr: if . == null then null elif (type == "string" or type == "number") and (tostring | test("\\A[0-9]{1,10}\\z")) then tostring else "invalid" end;'

# guard_body <jq condition>: type guard on the whole body. success:false is an api-error, anything
# that is not the expected shape (including a jq failure) is bad-response. Never keyed on `.result | length`.
guard_body() {
  local kind jrc
  kind=$(/usr/bin/env -i /usr/bin/jq -r "if .success == false then \"api\" elif ($1) then \"ok\" else \"bad\" end" < <(printf '%s' "$BODY") 2>&1)
  jrc=$?
  if [ "$jrc" -ne 0 ]; then bad_jq "$jrc"; fi
  case "$kind" in
    ok) : ;;
    api) unverified api-error 14 ;;
    *) bad_shape ;;
  esac
}
# project <jq program>: run the projection and emit it; a jq failure never prints jq's diagnostic.
project() {
  local res jrc
  res=$(/usr/bin/env -i /usr/bin/jq -c --argjson limit "$LIMIT" --argjson qlimit "$QLIMIT" --argjson hours "$HOURS" "$JQ_DEFS $1" < <(printf '%s' "$BODY") 2>&1)
  jrc=$?
  if [ "$jrc" -ne 0 ]; then bad_jq "$jrc"; fi
  emit_ok "$res"
}

# --- credential / source checks (fail closed) ---
guard_source() { # a mistake-guard; env can be forged
  if [ -z "${DOPPLER_PROJECT:-}" ] || [ -z "${DOPPLER_CONFIG:-}" ]; then
    die 64 "refused: no Doppler source set (run under: doppler run -p soleur -c prd_terraform --)"
  fi
  if [ "${DOPPLER_PROJECT:-}" != soleur ] || [ "${DOPPLER_CONFIG:-}" != prd_terraform ]; then
    die 64 "refused: unexpected token source"
  fi
}
load_credential() { # $1 = zone | account ; needs TOKVAR ; sets TOK (never exported)
  guard_source
  TOK="${!TOKVAR:-}"
  TOK="${TOK%"${TOK##*[![:space:]]}"}"
  if [ -z "$TOK" ]; then unverified "no-credential ($TOKVAR)" 10; fi
  if [[ ! "$TOK" =~ $TOKEN_RE ]]; then
    die 64 "refused: token shape of $TOKVAR cannot be carried safely on the config channel"
  fi
  case "$1" in
    zone)
      if [ -z "${CF_ZONE_ID:-}" ]; then unverified "no-credential (CF_ZONE_ID)" 10; fi
      if [[ ! "$CF_ZONE_ID" =~ $ID_RE ]]; then die 64 "refused: CF_ZONE_ID is not a 32-character hex id"; fi
      ;;
    account)
      if [ -z "${CF_ACCOUNT_ID:-}" ]; then unverified "no-credential (CF_ACCOUNT_ID)" 10; fi
      if [[ ! "$CF_ACCOUNT_ID" =~ $ID_RE ]]; then die 64 "refused: CF_ACCOUNT_ID is not a 32-character hex id"; fi
      ;;
  esac
}

# --- the ONE request chokepoint: GET only, one call, empty curl environment ---
# The credential travels on curl's stdin as a config line, fed by a PROCESS SUBSTITUTION (never a pipe: SIGPIPE 141
# under pipefail; never a here-string: older bash writes it to a temp file). curl's stderr is merged into the capture
# only so it can be reduced to its exit status.
preflight() { # the tools every read needs, checked before any request is made
  [ -x /usr/bin/jq ] || unverified "no-tool (jq)" 14
}
cf_get() { # $1 = full URL ; sets BODY, or exits with the mapped verdict
  local url="$1" out rc
  preflight
  out=$(/usr/bin/env -i "$CURL" --disable --noproxy '*' -X GET -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "$url" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK") 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    unverified "upstream-error (curl exit $rc)" 14
  fi
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  if [[ ! "$STATUS" =~ ^[0-9]{3}$ ]]; then unverified bad-response 14; fi
  case "$STATUS" in
    2??) : ;;
    401) unverified token-invalid 11 ;;
    403) unverified token-lacks-scope 11 ;;
    404) unverified not-found 14 ;;
    *) unverified upstream-error 14 ;;
  esac
}

# --- the ONE read-only POST chokepoint (the two analytics subcommands): a compiled-in query, one call, empty curl environment ---
# A GraphQL read is an HTTP POST. The body is a fixed template with a zone id and two window stamps substituted; it reaches curl
# only as a `data-raw` line of the stdin config (never argv), beside the Authorization and Content-Type header lines.
gql_stdin() { # $1 = the escaped body ; the three config lines of the POST
  printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\ndata-raw = "%s"\n' "$TOK" "$1"
}
cf_graphql() { # $1 = the finished one-line JSON body ; sets BODY, or exits with the mapped verdict
  local body="$1" esc out rc
  preflight
  case "$body" in
    '{"query":"query{viewer{zones(filter:{zoneTag:\"'*) : ;;
    *) die 64 "refused: request body does not start with the fixed query prefix" ;;
  esac
  if [[ "$body" =~ [[:cntrl:]] ]]; then die 64 "refused: request body holds a control character"; fi
  esc="${body//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  out=$(/usr/bin/env -i "$CURL" --disable --noproxy '*' -X POST -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "$GQL_URL" < <(gql_stdin "$esc") 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then unverified "upstream-error (curl exit $rc)" 14; fi
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  if [[ ! "$STATUS" =~ ^[0-9]{3}$ ]]; then unverified bad-response 14; fi
  case "$STATUS" in
    2??) : ;;
    400) gql_api_error ;;
    401) unverified token-invalid 11 ;;
    403) unverified token-lacks-scope 11 ;;
    404) unverified not-found 14 ;;
    *) unverified upstream-error 14 ;;
  esac
}
# gql_message: sets GQL_MSG to the FIRST error message only when it passes a fixed in-full check (one short plain-text line), else "".
# The whole gate runs in bash (jq's ^ and $ are line anchors, so a multi-line message would pass a jq regex). Vendor text, so data.
gql_message() {
  local m jrc lm
  GQL_MSG=""
  m=$(/usr/bin/env -i /usr/bin/jq -j 'if (.errors | type) == "array" and (.errors[0].message | type) == "string" then .errors[0].message else empty end' < <(printf '%s' "$BODY") 2>&1)
  jrc=$?
  if [ "$jrc" -ne 0 ]; then return 0; fi
  if [[ "$m" =~ [[:cntrl:]] ]]; then return 0; fi
  if [[ ! "$m" =~ $GQL_MSG_RE ]]; then return 0; fi
  lm="${m,,}"
  case "$lm" in *bearer* | *token* | *authorization*) return 0 ;; esac
  if [ -n "$TOK" ] && [[ "$m" == *"$TOK"* ]]; then return 0; fi
  if [[ "$m" =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then return 0; fi
  GQL_MSG="$m"
}
gql_api_error() { # an api-error, with the bounded vendor message when it passes the gate
  gql_message
  if [ -n "$GQL_MSG" ]; then unverified "api-error (graphql: $GQL_MSG)" 14; fi
  unverified api-error 14
}
# guard_gql <jq condition on the groups array>: GraphQL has no .success. An error list is an api-error; zones [] is no-zone-access;
# one zone whose groups satisfy the condition is ok; anything else (including data null and two zones) is bad-response (shape).
guard_gql() {
  local kind jrc
  kind=$(/usr/bin/env -i /usr/bin/jq -r "$JQ_DEFS if ((.errors | type) == \"array\" and (.errors | length) > 0) then \"api\" elif ((.errors == null or (.errors | type) == \"array\") and (.data.viewer.zones | type) == \"array\") then (.data.viewer.zones | if length == 0 then \"nozone\" elif (length == 1 and (.[0] | type) == \"object\" and (.[0].httpRequestsAdaptiveGroups | type) == \"array\" and (.[0].httpRequestsAdaptiveGroups | ($1))) then \"ok\" else \"bad\" end) else \"bad\" end" < <(printf '%s' "$BODY") 2>&1)
  jrc=$?
  if [ "$jrc" -ne 0 ]; then bad_jq "$jrc"; fi
  case "$kind" in
    ok) : ;;
    api) gql_api_error ;;
    nozone) unverified no-zone-access 14 ;;
    *) bad_shape ;;
  esac
}
# gql_fill <template>: substitute the zone id and the two stamps (all validated: a 32-hex id and two UTC stamps)
gql_fill() {
  local b="$1"
  b="${b//@ZONE@/$CF_ZONE_ID}"
  b="${b//@START@/$WIN_START}"
  b="${b//@END@/$WIN_END}"
  printf '%s' "$b"
}
# gql_window: complete UTC hours only, [end - HOURS h, end), by epoch arithmetic; the partial current hour is excluded, so the
# series lags by up to one hour. The caller's integer never enters the query text: only the two computed stamps do.
gql_window() {
  local t end start rc
  [ -x /usr/bin/date ] || unverified "no-tool (date)" 14
  t=$(/usr/bin/env -i /usr/bin/date -u +%s)
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$t" =~ ^[0-9]{10}$ ]]; then die 64 "refused: date produced no valid UTC stamp"; fi
  end=$((10#$t - 10#$t % 3600))
  start=$((end - HOURS * 3600))
  WIN_END=$(/usr/bin/env -i /usr/bin/date -u -d "@$end" +%Y-%m-%dT%H:%M:%SZ)
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$WIN_END" =~ $STAMP_RE ]]; then die 64 "refused: date produced no valid UTC stamp"; fi
  WIN_START=$(/usr/bin/env -i /usr/bin/date -u -d "@$start" +%Y-%m-%dT%H:%M:%SZ)
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$WIN_START" =~ $STAMP_RE ]]; then die 64 "refused: date produced no valid UTC stamp"; fi
}
# need_hours "$@": the analytics arity and hours grammar, checked before load_credential (a bad argument with no token exits 64, not
# 10). A whole number, no default, 1 to 216 (9 days, the one verified window). Written with `if`, never a second `case "$SUB"`.
need_hours() {
  if [ "$#" -ne 2 ]; then
    die 64 "usage: cloudflare-readonly.sh analytics-health|analytics-edge-errors <hours> (refused: missing or extra argument; the analytics subcommands take hours 1-$MAX_HOURS)"
  fi
  if [[ ! "$2" =~ ^[1-9][0-9]{0,2}$ ]]; then die 64 "refused: hours must be a whole number from 1 to $MAX_HOURS"; fi
  if [ "$2" -gt "$MAX_HOURS" ]; then die 64 "refused: hours is above the maximum of $MAX_HOURS"; fi
  HOURS="$2"
}

# --- the six reads (four GET, two read-only POST) ---
sub_ssl_mode() {
  cf_get "$BASE/zones/$CF_ZONE_ID/settings/ssl"
  guard_body '.success == true and (.result | type) == "object"'
  project '.result as $r | {subcommand: "ssl-mode", id: ($r.id | idv), value: ($r.value | enum), modified_on: ($r.modified_on | tsn)}'
}
sub_config_entrypoint() {
  cf_get "$BASE/zones/$CF_ZONE_ID/rulesets/phases/http_config_settings/entrypoint"
  guard_body '.success == true and (.result | type) == "object" and ((.result.rules // []) | type) == "array" and all((.result.rules // [])[]; type == "object")'
  project '.result as $r | ($r.rules // []) as $rules | [$rules[] | {ref: (.ref | idv), enabled: (.enabled != false), ssl: ((.action_parameters | if type == "object" then .ssl else null end) | sslv), mentions_app_host: ((.expression // "") | type == "string" and contains("\"app.soleur.ai\"")), mentions_lb_staging_host: ((.expression // "") | type == "string" and contains("\"lb-staging.soleur.ai\""))}] as $rr | {subcommand: "config-entrypoint", id: ($r.id | idv), version: ($r.version | verstr), last_updated: ($r.last_updated | tsn), rule_count: ($rules | length), enabled_ssl_rules: ([$rr[] | select(.enabled and .ssl != null)] | length), rules: $rr}'
}
sub_pagerules_ssl() {
  cf_get "$BASE/zones/$CF_ZONE_ID/pagerules?status=active"
  guard_body '.success == true and (.result | type) == "array" and all(.result[]; type == "object")'
  project '.result as $p | [$p[] | select(any((.actions // [])[]; type == "object" and .id == "ssl"))] as $s | {subcommand: "pagerules-ssl", active_rule_count: ($p | length), ssl_rule_count: ($s | length), ssl_rules: [$s[] | {id: (.id | idv), status: (.status | if . == "active" or . == "disabled" then . else "other" end), target_count: ((.targets // []) | length), ssl: ([(.actions // [])[] | select(type == "object" and .id == "ssl") | .value][0] | sslv), matches_app_host: any((.targets // [])[]; type == "object" and ((.constraint.value // "") | type == "string" and contains("app.soleur.ai")))}]}'
}
sub_change_history() {
  local now since rc
  [ -x /usr/bin/date ] || unverified "no-tool (date)" 14
  now=$(/usr/bin/env -i /usr/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$now" =~ $STAMP_RE ]]; then die 64 "refused: date produced no valid UTC stamp"; fi
  since=$(/usr/bin/env -i /usr/bin/date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$since" =~ $STAMP_RE ]]; then die 64 "refused: date produced no valid UTC stamp"; fi
  cf_get "$BASE/accounts/$CF_ACCOUNT_ID/logs/audit?since=$since&before=$now&limit=$LIMIT&direction=desc"
  guard_body '.success == true and (.result | type) == "array" and all(.result[]; type == "object")'
  project '.result as $r | [$r[] | (.action | if type == "object" then .time else null end) | select(type == "string" and test(rfc))] as $times | {subcommand: "change-history", rows: ($r | length), truncated: (($r | length) >= $limit), oldest_time: ($times | min_by(tkey)), newest_time: ($times | max_by(tkey)), by_action_type: ([$r[] | ((.action | if type == "object" then .type else null end) | gk)] | group_by(.) | map({key: .[0], value: length}) | from_entries), by_resource_type: ([$r[] | ((.resource | if type == "object" then .type else null end) | gk)] | group_by(.) | map({key: .[0], value: length}) | from_entries)}'
}

sub_analytics_health() {
  local body
  gql_window
  body=$(gql_fill "$GQL_HEALTH_TPL")
  cf_graphql "$body"
  guard_gql 'all(.[]; type == "object" and (.count | cnt) and ((.dimensions | type) == "object") and (.dimensions.datetimeHour | type == "string" and test(rfc)) and ((.avg | type) == "object") and (.avg.originResponseDurationMs | dur) and ((.quantiles | type) == "object") and (.quantiles.originResponseDurationMsP50 | dur) and (.quantiles.originResponseDurationMsP90 | dur))'
  project '.data.viewer.zones[0].httpRequestsAdaptiveGroups as $g | {subcommand: "analytics-health", window_hours: $hours, rows: ($g | length), note: "count is a sampled estimate (adaptive sampling); durations are origin response time for /health, not host- or requestSource-scoped", series: [$g[] | {hour: .dimensions.datetimeHour, count: .count, avg_ms: (.avg.originResponseDurationMs | r1), p50_ms: (.quantiles.originResponseDurationMsP50 | r1), p90_ms: (.quantiles.originResponseDurationMsP90 | r1)}]}'
}
sub_analytics_edge_errors() {
  local body
  gql_window
  body=$(gql_fill "$GQL_EDGE_TPL")
  cf_graphql "$body"
  guard_gql 'all(.[]; type == "object" and (.count | cnt) and ((.dimensions | type) == "object") and (.dimensions.datetimeHour | type == "string" and test(rfc)) and (.dimensions.edgeResponseStatus | type == "number" and . == floor and . >= 500 and . <= 599))'
  QLIMIT=1000
  project '.data.viewer.zones[0].httpRequestsAdaptiveGroups as $g | {subcommand: "analytics-edge-errors", window_hours: $hours, rows: ($g | length), truncated: (($g | length) >= $qlimit), note: "counts are sampled estimates (adaptive sampling); edge-generated blank 502/503/504 pages may be under-reported by this dataset", by_status: ([$g[] | {k: (.dimensions.edgeResponseStatus | tostring), c: .count}] | group_by(.k) | map({key: .[0].k, value: (map(.c) | add)}) | from_entries), hourly: ([$g[] | {hour: .dimensions.datetimeHour, status: .dimensions.edgeResponseStatus, count: .count}] | sort_by([.hour, .status]))}'
}

# --- argument handling: one argument (the analytics subcommands take hours as a second, validated by need_hours in their arm) ---
if [ "$#" -eq 1 ] && [ "$1" = "--list" ]; then
  printf '%s\n' "${SUBCOMMANDS[@]}"
  exit 0
fi
case "${1:-}" in
  analytics-health | analytics-edge-errors) : ;;
  *)
    if [ "$#" -ne 1 ]; then
      die 64 "usage: cloudflare-readonly.sh <subcommand> | --list (refused: missing or extra argument)"
    fi
    ;;
esac
SUB="${1:-}"

# --- dispatcher: the only place a request can be selected; anything unlisted is refused before any request ---
case "$SUB" in
  ssl-mode) TOKVAR=CF_API_TOKEN_ZONE_SETTINGS; load_credential zone; sub_ssl_mode ;;
  config-entrypoint) TOKVAR=CF_API_TOKEN_RULESETS; load_credential zone; sub_config_entrypoint ;;
  pagerules-ssl) TOKVAR=CF_API_TOKEN_PAGERULES_READ; load_credential zone; sub_pagerules_ssl ;;
  change-history) TOKVAR=CF_API_TOKEN_AUDIT; load_credential account; sub_change_history ;;
  analytics-health) need_hours "$@"; TOKVAR=CF_API_TOKEN_ANALYTICS_READ; load_credential zone; sub_analytics_health ;;
  analytics-edge-errors) need_hours "$@"; TOKVAR=CF_API_TOKEN_ANALYTICS_READ; load_credential zone; sub_analytics_edge_errors ;;
  *) die 64 "refused: unknown subcommand" ;;
esac
exit 0
