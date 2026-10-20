#!/usr/bin/env bash
# inngest-history-probe.test.sh -- Guard 2 of the item C1 plan (#9927): the probe can only send its
# committed read-only queries to the pinned project and can only print shapes.
#
# Everything here runs against a STUB `curl` on PATH. There is no network, no Doppler and no
# credential: the token is a synthetic string. The stub records every request (name, URL, auth
# check, statement count), the SQL it carried, its own argv and the NAMES of its environment, so the
# suite asserts what the probe SENT, not what it said it would send. It answers from files, so one
# case can make it return a role the probe must refuse, an HTTP status, an empty body or a leaking
# one.
#
# The probe is executed under `env -i` with a junk environment (a decoy secret, a decoy Doppler
# token): the hostile-environment prologue must leave the curl child with only PATH, HOME and the
# token.
set -euo pipefail

# A direct invocation inherits the machine-global 4 GiB /tmp tmpfs; test-all.sh defaults this to
# /var/tmp and a direct run does not.
export TMPDIR="${TMPDIR:-/var/tmp}"

SUITE="$(basename "$0")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-history-probe.sh"

PASSES=0
FAILURES=()
pass() { PASSES=$((PASSES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Canonical fixture-root guard, copied BYTE-FOR-BYTE from plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh compares the bytes).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# ---- Instrument self-test -------------------------------------------------
# Drive BOTH helpers once and refuse to continue unless BOTH counters moved.
pass "instrument self-test: pass() increments"
fail "instrument self-test: fail() records (EXPECTED — not a real failure)"
if [[ "$PASSES" -ne 1 || "${#FAILURES[@]}" -ne 1 ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: passes=%s failures=%s (expected 1/1)\n' "$PASSES" "${#FAILURES[@]}" >&2
  exit 2
fi
FAILURES=()

# ---- Fixture root -----------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR%/}/inngest-probe-test.XXXXXXXX")"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/state"
REAL_JQ="$(command -v jq)"
[[ -x "$REAL_JQ" ]] || { echo "need jq" >&2; exit 2; }
BASE_PATH="$WORK/bin:$(dirname "$REAL_JQ"):/usr/bin:/bin"

# Synthetic and split across a concatenation so no contiguous token-shaped literal sits in source.
TOKEN="tok-SYNTH.not-a-real"".credential_0123abcd"
printf '%s' "$TOKEN" > "$WORK/state/token"

# ---- The stub curl ----------------------------------------------------------
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Records the request; answers from files under ../state. Fixtures are located from THIS file's own
# path because the probe's prologue deliberately strips every variable but PATH, HOME and the token.
SD="$(cd "$(dirname "$0")/.." && pwd)/state"
{ echo "---"; printf 'arg=%s\n' "$@"; } >> "$SD/argv.log"
env | cut -d= -f1 | sort >> "$SD/env.log"
url=""; data=""; cfg=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --data) data="$2"; shift 2 ;;
    --config) cfg=1; shift 2 ;;
    *) shift ;;
  esac
done
hdr=""
if [ "$cfg" = 1 ]; then IFS= read -r hdr || true; fi
auth=bad
[ "$hdr" = "header = \"Authorization: Bearer $(cat "$SD/token")\"" ] && auth=ok
q="$(printf '%s' "$data" | jq -r .query 2>/dev/null)"
n=$(( $(wc -l < "$SD/requests.log") + 1 ))
printf '%s' "$q" > "$SD/sql.$n"
case "$q" in
  *has_goose*) name=identity ;;
  *column_name*) name=columns ;;
  *est_rows*) name=estimates ;;
  *) name=unknown ;;
esac
stmts="$(printf '%s' "$q" | tr -cd ';' | wc -c)"
printf 'name=%s url=%s auth=%s stmts=%s\n' "$name" "$url" "$auth" "$stmts" >> "$SD/requests.log"
if [ -f "$SD/curl_rc.$name" ]; then exit "$(cat "$SD/curl_rc.$name")"; fi
f="$SD/resp.$name"
if [ ! -f "$f" ]; then printf '\n599'; exit 0; fi
code="$(head -n1 "$f")"
body="$(tail -n +2 "$f")"
printf '%s\n%s' "$body" "$code"
STUB
chmod +x "$WORK/bin/curl"

# ---- Fixtures ----------------------------------------------------------------
ROLE="supabase_read_only_user"
proof() { printf '"db_role":"%s","ro":"on","stmt_timeout":"8s"' "${1:-$ROLE}"; }
identity_ok() { printf '[{%s,"bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]' "$(proof)"; }
columns_ok() {
  printf '[{%s,"table_name":"function_runs","column_name":"run_id","data_type":"uuid"},' "$(proof)"
  printf '{%s,"table_name":"function_runs","column_name":"account_id","data_type":"uuid"},' "$(proof)"
  printf '{%s,"table_name":"events","column_name":"workspace_id","data_type":"uuid"},' "$(proof)"
  printf '{%s,"table_name":"events","column_name":"data","data_type":"jsonb"},' "$(proof)"
  printf '{%s,"table_name":"events","column_name":"worker_ip","data_type":"text"},' "$(proof)"
  printf '{%s,"table_name":"apps","column_name":"created_at","data_type":"timestamp with time zone"}]' "$(proof)"
}
estimates_ok() {
  printf '[{%s,"table_name":"apps","est_rows":3,"live_rows":3,"rls_on":true,"n_policies":0},' "$(proof)"
  printf '{%s,"table_name":"events","est_rows":120000,"live_rows":118000,"rls_on":true,"n_policies":0},' "$(proof)"
  printf '{%s,"table_name":"function_runs","est_rows":-1,"live_rows":-1,"rls_on":false,"n_policies":0}]' "$(proof)"
}
set_resp() { # <name> <code> <body>
  assert_fixture_dir "$WORK"
  printf '%s\n%s' "$2" "$3" > "$WORK/state/resp.$1"
}
reset_state() {
  assert_fixture_dir "$WORK"
  rm -f "$WORK"/state/resp.* "$WORK"/state/curl_rc.* "$WORK"/state/sql.* "$WORK"/state/argv.log "$WORK"/state/env.log
  : > "$WORK/state/requests.log"; : > "$WORK/state/argv.log"; : > "$WORK/state/env.log"
  set_resp identity 200 "$(identity_ok)"
  set_resp columns 200 "$(columns_ok)"
  set_resp estimates 200 "$(estimates_ok)"
}

P_RC=0; P_OUT=""; P_ERR=""
run_probe() { # <probe args...> -- env additions come from P_ENV (array)
  local script="${PROBE_SH:-$PROBE}"
  assert_fixture_dir "$WORK"
  P_RC=0
  env -i PATH="$BASE_PATH" HOME="$WORK" SUPABASE_ACCESS_TOKEN="${P_TOKEN-$TOKEN}" \
    LEAK_DECOY_SECRET="decoy-secret-must-not-reach-curl" DOPPLER_TOKEN="decoy-doppler-token" \
    GITHUB_TOKEN="decoy-github-token" "${P_ENV[@]+"${P_ENV[@]}"}" \
    bash "${P_BASH_FLAGS[@]+"${P_BASH_FLAGS[@]}"}" "$script" "$@" > "$WORK/out" 2> "$WORK/err" || P_RC=$?
  P_OUT="$(cat "$WORK/out")"; P_ERR="$(cat "$WORK/err")"
}
P_ENV=(); P_BASH_FLAGS=(); P_TOKEN="$TOKEN"
nreq() { grep -c . "$WORK/state/requests.log" || true; }
req_names() { sed -E 's/^name=([a-z]+) .*/\1/' "$WORK/state/requests.log" | tr '\n' ' '; }
anywhere() { # <needle> -- in stdout, stderr, argv log, or the stub's environment-name log
  grep -qF -- "$1" "$WORK/out" "$WORK/err" "$WORK/state/argv.log" "$WORK/state/env.log"
}
streams_have() { grep -qF -- "$1" "$WORK/out" "$WORK/err"; }

# ---- Source the probe for its lints (the prologue runs only when EXECUTED) -----
# shellcheck source=scripts/inngest-history-probe.sh
source "$PROBE"

# ======================================================================
# A. STATIC -- the allowlist and the single transport
# ======================================================================
[[ "${#QUERY_NAMES[@]}" -eq 3 ]] && pass "A1: the allowlist holds exactly the three round-1 queries" || fail "A1: allowlist size is ${#QUERY_NAMES[@]}"
for n in "${QUERY_NAMES[@]}"; do
  v="Q_$n"
  if _sql_ok "${!v}"; then pass "A2: literal Q_$n is one read-only catalog statement"; else fail "A2: literal Q_$n fails the lint"; fi
done
# Every literal carries the proof columns, or its response could not show the role it ran under.
for n in "${QUERY_NAMES[@]}"; do
  v="Q_$n"
  [[ "${!v}" == *"current_user as db_role"* && "${!v}" == *"transaction_read_only"* && "${!v}" == *"statement_timeout"* ]] \
    && pass "A3: Q_$n returns the role, the read-only setting and the statement timeout" || fail "A3: Q_$n lacks a proof column"
done
# The lint must be able to FAIL: each of these is a mutation of a literal a future edit might add.
BAD_SQL=(
  "select * from public.t"
  "select a from public.t limit 1"
  "select distinct a from public.t"
  "select a from public.t; select b from public.u"
  "select data->>'x' from public.t"
  "select data->'x' from public.t"
  "select data#>'{x}' from public.t"
  "select a from public.t where data @> '{}'"
  "select pg_sleep(5)"
  "select set_config('a','b',false)"
  "select nextval('s')"
  "select * from dblink('x','y')"
  "insert into public.t values (1)"
  "select a from public.t where b = \$1"
  "update public.t set a = 1"
  "with x as (select 1) delete from public.t"
  "SELECT a FROM public.t LIMIT 1"
  ""
  "show transaction_read_only"
)
for s in "${BAD_SQL[@]}"; do
  if _sql_ok "$s"; then fail "A4: the lint ACCEPTED [${s:0:48}]"; else pass "A4: the lint refuses [${s:0:48}]"; fi
done
# One transport: exactly one bc_curl call site, no bare curl invocation, one pinned ref and host.
n_bc="$(grep -vE '^[[:space:]]*#' "$PROBE" | grep -cE '(^|[^_a-z])bc_curl[[:space:]]+inngest-history-probe' || true)"
n_curl="$(grep -vE '^[[:space:]]*#' "$PROBE" | grep -cE '(^|[;&|(]|[[:space:]])curl[[:space:]]+-' || true)"
[[ "$n_bc" -eq 1 && "$n_curl" -eq 0 ]] && pass "A5: exactly one transport call site (bc_curl) and no bare curl" || fail "A5: bc_curl=$n_bc bare-curl=$n_curl"
[[ "$(grep -c '^readonly PINNED_REF=' "$PROBE")" -eq 1 && "$(grep -c '^readonly API_HOST="https://api.supabase.com"$' "$PROBE")" -eq 1 ]] \
  && pass "A6: the project ref and the API host are each one pinned literal" || fail "A6: pin literals missing or duplicated"
grep -qF -- '/database/query/read-only"' "$PROBE" && ! grep -vE '^[[:space:]]*#' "$PROBE" | grep -qE 'database/query"' \
  && pass "A7: the only endpoint is the dedicated read-only one" || fail "A7: the general query endpoint is referenced"

# ======================================================================
# B. BEHAVIOUR against the stub
# ======================================================================
reset_state
run_probe round1
[[ "$P_RC" -eq 0 ]] && pass "B1: a well-formed round1 exits 0" || fail "B1: rc=$P_RC out=${P_OUT:0:200}"
[[ "$(nreq)" -eq 3 && "$(req_names)" == "identity columns estimates " ]] \
  && pass "B2: round1 sends exactly three requests, identity FIRST" || fail "B2: requests=[$(req_names)]"
# Each captured body is byte-equal to a committed allowlist literal, sent to the pinned read-only URL.
ok=1
for i in 1 2 3; do
  case "$i" in 1) want="$Q_identity" ;; 2) want="$Q_columns" ;; 3) want="$Q_estimates" ;; esac
  [[ "$(cat "$WORK/state/sql.$i")" == "$want" ]] || ok=0
done
[[ "$ok" == 1 ]] && pass "B3: every request body is byte-equal to its committed literal" || fail "B3: a request body is not an allowlist literal"
[[ "$(grep -c 'url=https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query/read-only ' "$WORK/state/requests.log")" -eq 3 ]] \
  && pass "B4: every request went to the pinned project's read-only endpoint" || fail "B4: a request went elsewhere"
[[ "$(grep -c 'auth=ok' "$WORK/state/requests.log")" -eq 3 && "$(grep -c 'stmts=0' "$WORK/state/requests.log")" -eq 3 ]] \
  && pass "B5: the credential arrived on the config channel and every request is a single statement" || fail "B5: auth or statement count wrong"
anywhere "$TOKEN" && fail "B6: the token appears in stdout, stderr, the stub's argv or its environment names" \
  || pass "B6: the token is on no argv, no stream and no environment name"
# The stub's environment holds nothing but the allowed names.
extra="$(sort -u "$WORK/state/env.log" | grep -vxE 'PATH|HOME|SUPABASE_ACCESS_TOKEN|LC_ALL|LANG|_|PWD|SHLVL|OLDPWD' || true)"
[[ -z "$extra" ]] && pass "B7: the curl child's environment holds only PATH, HOME and the token (decoy secrets were dropped)" \
  || fail "B7: unexpected environment names reached curl: $(echo "$extra" | tr '\n' ' ')"
streams_have "identity: role=supabase_read_only_user read_only=on" && streams_have "columns: tables=3 columns=6 json_typed_columns=1" \
  && pass "B8: the identity and column summaries print counts and names only" || fail "B8: summaries missing or wrong: ${P_OUT:0:300}"
streams_have "candidate_user_reference_columns=account_id" && streams_have "candidate_user_reference_columns=workspace_id,worker_ip" \
  && pass "B9: candidate user-reference COLUMN NAMES are listed (names only)" || fail "B9: candidate columns not listed"
streams_have "estimates: table=events est_rows=120000 live_rows=118000 rls=on policies=0" \
  && streams_have "row_level_security_hides_rows_from_this_role=2" \
  && pass "B10: estimates print numbers and the RLS-masks-rows note (a row read would read as empty)" || fail "B10: estimates output wrong: ${P_OUT:0:400}"
# NON-CANONICAL but valid: reordered keys, pretty-printed. The same stdout.
canon="$P_OUT"
reset_state
set_resp identity 200 "$(identity_ok | jq '.[0] | to_entries | reverse | from_entries | [.]')"
set_resp columns 200 "$(columns_ok | jq '.')"
set_resp estimates 200 "$(estimates_ok | jq -S '.')"
run_probe round1
[[ "$P_RC" -eq 0 && "$P_OUT" == "$canon" ]] && pass "B11: a reordered, pretty-printed valid response prints the same output (must-pass)" \
  || fail "B11: a valid response in a different shape changed the output (rc=$P_RC)"

# ---- refusals before any request ----
for argset in "bogus" "" "round1 identity" "--ref other-ref round1" "--ref" "round1 --nope" "columns extra"; do
  reset_state
  # shellcheck disable=SC2086  # the argument words are split on purpose
  run_probe $argset
  [[ "$P_RC" -eq 2 && "$(nreq)" -eq 0 ]] && pass "B12: [$argset] is refused (rc 2) with ZERO requests" || fail "B12: [$argset] rc=$P_RC requests=$(nreq)"
done
reset_state; run_probe --ref pigsfuxruiopinouvjwy identity
[[ "$P_RC" -eq 0 && "$(nreq)" -eq 1 ]] && pass "B13: the pinned ref passed explicitly is accepted (the refusal above is about the OTHER ref)" || fail "B13: rc=$P_RC"
reset_state; P_TOKEN="has a space"; run_probe round1
[[ "$P_RC" -eq 3 && "$(nreq)" -eq 0 ]] && streams_have "could-not-measure(credential_refused)" \
  && pass "B14: an unusable token makes ZERO requests and says credential_refused" || fail "B14: rc=$P_RC requests=$(nreq)"
reset_state; P_TOKEN=""; run_probe round1
[[ "$P_RC" -eq 3 && "$(nreq)" -eq 0 ]] && pass "B14b: an empty token makes ZERO requests" || fail "B14b: rc=$P_RC requests=$(nreq)"
P_TOKEN="$TOKEN"

# ---- identity gates everything: a failed preflight sends nothing further ----
id_case() { # <label> <reason> <identity-json>
  reset_state; set_resp identity 200 "$3"; run_probe round1
  if [[ "$P_RC" -eq 3 && "$(nreq)" -eq 1 ]] && streams_have "could-not-measure($2)" && ! streams_have "columns:" && ! streams_have "estimates:"; then
    pass "B15: $1 -> could-not-measure($2), ONE request, nothing further sent"
  else
    fail "B15: $1 rc=$P_RC requests=$(nreq) out=${P_OUT:0:160}"
  fi
}
id_case "wrong role" readonly_unverifiable '[{"db_role":"postgres","ro":"on","stmt_timeout":"8s","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'
id_case "transaction not read-only" readonly_unverifiable '[{"db_role":"supabase_read_only_user","ro":"off","stmt_timeout":"8s","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'
id_case "unbounded statement timeout" unbounded_statement '[{"db_role":"supabase_read_only_user","ro":"on","stmt_timeout":"0","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'
id_case "garbage statement timeout" readonly_unverifiable '[{"db_role":"supabase_read_only_user","ro":"on","stmt_timeout":"soon","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'
id_case "sentinel table absent" not_inngest_project '[{"db_role":"supabase_read_only_user","ro":"on","stmt_timeout":"8s","bypassrls":false,"has_goose":false,"has_function_runs":true,"has_app_tables":false}]'
id_case "web-platform app tables present" not_inngest_project '[{"db_role":"supabase_read_only_user","ro":"on","stmt_timeout":"8s","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":true}]'
id_case "missing proof column" shape '[{"db_role":"supabase_read_only_user","stmt_timeout":"8s","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'
id_case "two rows" shape "$(identity_ok | jq -c '. + .')"
id_case "non-boolean flag" shape '[{"db_role":"supabase_read_only_user","ro":"on","stmt_timeout":"8s","bypassrls":false,"has_goose":"yes","has_function_runs":true,"has_app_tables":false}]'

# ---- a failed or odd read is NEVER a zero ----
status_case() { # <http-code> <reason>
  reset_state; set_resp identity "$1" '{"message":"boundary SECRET-LEAK-echo-0xDEAD select current_user"}'; run_probe round1
  if [[ "$P_RC" -eq 3 && "$(nreq)" -eq 1 ]] && streams_have "could-not-measure($2)" && ! streams_have "SECRET-LEAK-echo" && ! streams_have "select current_user"; then
    pass "B16: HTTP $1 -> could-not-measure($2); the error body (a SQL echo and a decoy value) reaches no stream"
  else
    fail "B16: HTTP $1 rc=$P_RC requests=$(nreq) out=${P_OUT:0:120} err=${P_ERR:0:120}"
  fi
}
status_case 401 credential_unauthorized
status_case 403 role_privilege
status_case 404 endpoint_unavailable
status_case 405 endpoint_unavailable
status_case 410 endpoint_unavailable
status_case 429 rate_limited
status_case 500 server_error
status_case 503 server_error
status_case 302 shape
for rcode in 28:timeout 7:transport 6:transport 35:transport; do
  assert_fixture_dir "$WORK"; reset_state; printf '%s' "${rcode%%:*}" > "$WORK/state/curl_rc.identity"; run_probe round1
  [[ "$P_RC" -eq 3 && "$(nreq)" -eq 1 ]] && streams_have "could-not-measure(${rcode##*:})" \
    && pass "B17: curl exit ${rcode%%:*} -> could-not-measure(${rcode##*:}), never a zero" || fail "B17: curl ${rcode%%:*} rc=$P_RC out=${P_OUT:0:100}"
done
reset_state; set_resp identity 200 ""; run_probe round1
[[ "$P_RC" -eq 3 ]] && streams_have "could-not-measure(empty_body)" && pass "B18: an empty 200 body is empty_body" || fail "B18: rc=$P_RC out=${P_OUT:0:100}"
reset_state; set_resp identity 200 '{"message":"not an array"}'; run_probe round1
[[ "$P_RC" -eq 3 ]] && streams_have "could-not-measure(shape)" && pass "B19: a non-array 200 body is shape" || fail "B19: rc=$P_RC"
reset_state; set_resp identity 200 '[]'; run_probe round1
[[ "$P_RC" -eq 3 ]] && streams_have "could-not-measure(shape)" && pass "B19b: an empty array is shape, not a zero" || fail "B19b: rc=$P_RC"
reset_state; set_resp columns 200 '[]'; run_probe round1
[[ "$P_RC" -eq 3 && "$(nreq)" -eq 2 ]] && streams_have "could-not-measure(shape)" && ! streams_have "columns: tables=0" \
  && pass "B20: zero column rows is could-not-measure(shape), never 'tables=0'" || fail "B20: rc=$P_RC out=${P_OUT:0:200}"
reset_state; set_resp estimates 200 '[]'; run_probe round1
[[ "$P_RC" -eq 3 && "$(nreq)" -eq 3 ]] && streams_have "could-not-measure(shape)" && ! streams_have "tables=0" \
  && pass "B20b: zero estimate rows is could-not-measure(shape), never a zero" || fail "B20b: rc=$P_RC"

# ---- the formatter prints shapes only ----
leak_case() { # <label> <table-name-value>
  reset_state
  set_resp columns 200 "$(printf '[{%s,"table_name":"%s","column_name":"run_id","data_type":"uuid"}]' "$(proof)" "$2")"
  run_probe round1
  if [[ "$P_RC" -eq 3 ]] && streams_have "could-not-measure(unsafe_name)" && ! streams_have "$2"; then
    pass "B21: $1 as a table name -> unsafe_name, and it is on no stream"
  else
    fail "B21: $1 rc=$P_RC out=${P_OUT:0:160}"
  fi
}
leak_case "an email-shaped value" "someone@example.com"
leak_case "a UUID" "3f2b8c1e-4d5a-4e6f-8a7b-9c0d1e2f3a4b"
leak_case "a 32-hex id" "0123456789abcdef0123456789abcdef"
leak_case "a long digit run" "t1234567"
leak_case "a digits-only id" "12345"
leak_case "an upper-case word" "Customer_Table"
leak_case "free text" "has space"
for badnum in '"1e9"' '"abc"' '12.5' 'null' '"1; DROPME_x9"'; do
  reset_state
  set_resp estimates 200 "$(printf '[{%s,"table_name":"apps","est_rows":%s,"live_rows":1,"rls_on":true,"n_policies":0}]' "$(proof)" "$badnum")"
  run_probe round1
  [[ "$P_RC" -eq 3 ]] && streams_have "could-not-measure(unsafe_name)" && ! streams_have "DROPME_x9" \
    && pass "B22: a non-integer estimate [$badnum] is refused" || fail "B22: [$badnum] rc=$P_RC out=${P_OUT:0:120}"
done
reset_state
set_resp columns 200 "$(printf '[{%s,"table_name":"apps","column_name":"id","data_type":"user@example.com"}]' "$(proof)")"
run_probe round1
[[ "$P_RC" -eq 3 ]] && ! streams_have "user@example.com" && pass "B23: an email-shaped data type is refused and printed nowhere" || fail "B23: rc=$P_RC"

# ---- tracing ----
reset_state; P_BASH_FLAGS=(-x); run_probe round1
[[ "$P_RC" -eq 78 && "$(nreq)" -eq 0 ]] && ! anywhere "$TOKEN" && pass "B24: bash -x is refused (78) with zero requests and no token on any stream" || fail "B24: rc=$P_RC requests=$(nreq)"
P_BASH_FLAGS=()
reset_state; P_ENV=(SHELLOPTS=xtrace); run_probe round1
[[ "$P_RC" -eq 78 && "$(nreq)" -eq 0 ]] && ! anywhere "$TOKEN" && pass "B25: SHELLOPTS=xtrace is refused (78) with zero requests and no token on any stream" || fail "B25: rc=$P_RC requests=$(nreq)"
P_ENV=()
reset_state; P_ENV=(BASH_ENV="$WORK/does-not-exist" PS4='+${SUPABASE_ACCESS_TOKEN}'); run_probe identity
[[ "$P_RC" -eq 0 ]] && ! anywhere "$TOKEN" && pass "B26: a hostile BASH_ENV and PS4 in the caller's environment change nothing and leak nothing" || fail "B26: rc=$P_RC"
P_ENV=()

# ======================================================================
# C. MUTANTS -- the rows above must see each one
# ======================================================================
mut_probe() { # <label> <python-snippet-on-variable-s>  -- writes $WORK/probe.mut.sh; 0 if the mutation landed
  assert_fixture_dir "$WORK"
  local rc=0
  python3 - "$PROBE" "$WORK/probe.mut.sh" "$2" <<'PY' || rc=$?
import sys
src, dst, snippet = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
ns = {"s": s}
exec(snippet, ns)
t = ns["s"]
if t == s:
    sys.exit(3)
open(dst, "w").write(t)
PY
  if [[ "$rc" -ne 0 ]]; then fail "mutant $1: the mutation did not land"; return 1; fi
  return 0
}
# The mutant script sits next to a copy of lib/ so its `source "$SCRIPT_DIR/lib/bearer-curl.sh"` resolves.
mkdir -p "$WORK/mut/lib"; cp "$HERE/lib/bearer-curl.sh" "$WORK/mut/lib/bearer-curl.sh"
run_mutant() { # <label> <snippet> <expect-fn>
  if mut_probe "$1" "$2"; then
    assert_fixture_dir "$WORK"
    cp "$WORK/probe.mut.sh" "$WORK/mut/inngest-history-probe.sh"
    PROBE_SH="$WORK/mut/inngest-history-probe.sh"
    "$3"
    PROBE_SH=""
  fi
}
# M1: a literal gains a LIMIT. The send-time lint must refuse it: bad_call, and only identity was sent.
m1() {
  reset_state; run_probe columns
  [[ "$P_RC" -eq 3 && "$(nreq)" -eq 1 ]] && streams_have "could-not-measure(bad_call)" \
    && pass "mutant M1: a LIMIT added to a literal is refused at send time (bad_call, the bad query was never sent)" \
    || fail "mutant M1: SURVIVED rc=$P_RC requests=$(nreq)"
}
run_mutant M1 "s = s.replace(\"where n.nspname = 'public' and c.relkind in ('r', 'p') and a.attnum > 0\", \"where n.nspname = 'public' and c.relkind in ('r', 'p') and a.attnum > 0 limit 5\")" m1
# M2: the identity proof is removed. The wrong-role case that stopped the real probe must now go through.
m2() {
  reset_state; set_resp identity 200 '[{"db_role":"postgres","ro":"on","stmt_timeout":"8s","bypassrls":false,"has_goose":true,"has_function_runs":true,"has_app_tables":false}]'; run_probe identity
  if [[ "$P_RC" -eq 0 ]]; then pass "mutant M2: removing the role proof lets a non-read-only role through (the B15 wrong-role row sees it)"
  else fail "mutant M2: SURVIVED -- the role proof is not what refuses a wrong role"; fi
}
run_mutant M2 "s = s.replace('  _proof \"\$b\" || return \$?\n  goose=', '  goose=', 1)" m2
# M3: the name shape check is removed. The email-shaped table name must now reach stdout, which proves the leak rows can SEE a leak.
m3() {
  reset_state
  set_resp columns 200 "$(printf '[{%s,"table_name":"someone@example.com","column_name":"run_id","data_type":"uuid"}]' "$(proof)")"
  run_probe columns
  if streams_have "could-not-measure(unsafe_name)"; then fail "mutant M3: SURVIVED -- the leak row is not exercising the name check"
  else pass "mutant M3: without the name check the email-shaped name is accepted (the B21 leak rows can see a leak)"; fi
}
run_mutant M3 "s = s.replace('_ident_ok \"\$t\" && _ident_ok \"\$c\" && _type_ok \"\$d\" || { cnm unsafe_name; return 3; }', 'true', 1)" m3
# M4: a 5xx is treated as success. The reason word must change, which the B16 rows assert.
m4() {
  reset_state; set_resp identity 500 '{"message":"x"}'; run_probe identity
  if streams_have "could-not-measure(server_error)"; then fail "mutant M4: SURVIVED"
  else pass "mutant M4: treating 5xx as success changes the verdict (the B16 status rows see it)"; fi
}
run_mutant M4 "s = s.replace('5??) cnm server_error; return 3 ;;', '5??) ;;', 1)" m4
# M5: the pinned ref is replaced. B4 asserts the URL, so a different project is visible.
m5() {
  reset_state; run_probe identity
  if [[ "$(grep -c 'projects/pigsfuxruiopinouvjwy/' "$WORK/state/requests.log")" -eq 0 ]]; then pass "mutant M5: a changed project ref changes the URL the stub records (the B4 pin sees it)"
  else fail "mutant M5: SURVIVED"; fi
}
run_mutant M5 "s = s.replace('readonly PINNED_REF=\"pigsfuxruiopinouvjwy\"', 'readonly PINNED_REF=\"zzzzzzzzzzzzzzzzzzzz\"', 1)" m5

# ======================================================================
# Verdict
# ======================================================================
# Late dispatch re-validation (the launder defence): re-drive both helpers after every row and
# require both counters to move. Reported with printf + exit, never through the helpers under test.
_LATE_P="$PASSES"; _LATE_F="${#FAILURES[@]}"
pass "late dispatch re-validation: pass() still increments (EXPECTED)"
fail "late dispatch re-validation: fail() still records (EXPECTED — not a real failure)"
if [[ "$PASSES" -ne "$((_LATE_P + 1))" || "${#FAILURES[@]}" -ne "$((_LATE_F + 1))" ]]; then
  printf 'LATE DISPATCH RE-VALIDATION FAILED: pass() moved %s->%s (want +1), fail() moved %s->%s (want +1).\n' \
    "$_LATE_P" "$PASSES" "$_LATE_F" "${#FAILURES[@]}" >&2
  exit 2
fi
PASSES=$((PASSES - 1))
unset 'FAILURES[-1]'

printf '\n%s: %s passed, %s failed\n' "$SUITE" "$((PASSES - 1))" "${#FAILURES[@]}"
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  printf '  - %s\n' "${FAILURES[@]}"
fi

# Both operands are literals on the lines IMMEDIATELY above the `if` (scripts/guard-vacuity-floor.test.sh
# slices the `if` plus its contiguous simple assignments, so a name bound further up is unbound there).
SELFTEST_PASSES=1
MIN_ASSERTIONS=98
REAL=$((PASSES - SELFTEST_PASSES))
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s real assertions ran, floor is %s -- rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "${#FAILURES[@]}" -eq 0 ]] || exit 1
exit 0
