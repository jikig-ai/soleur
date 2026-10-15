#!/usr/bin/env bash
# Behavioural suite for scripts/egress-audit-retention-check.sh (#9545, ADR-288).
# `curl` is a PATH shim that answers by URL and REFUSES (exit 64) any call that does not pass its
# credentials through a stdin config (`-K -`) or does not name the expected table, so a script that
# queries the wrong thing or puts a key on argv cannot pass. The gateway-activity query is a stub
# command passed in GW_QUERY_CMD. Synthetic values only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/egress-audit-retention-check.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

[[ -f "$SUT" ]] || { echo "FAIL: $SUT does not exist"; echo "RESULT: 0 passed, 1 failed"; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/egress-retention-check.XXXXXX")"
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
assert_fixture_dir "$ROOT"
cleanup_suite() {
  assert_fixture_dir "$ROOT"
  rm -rf "$ROOT"
}
trap cleanup_suite EXIT
mkdir -p "$ROOT/bin"

# curl shim: ROWS_OLDEST / ROWS_NEWEST / HTTP_CODE select the answer; CURL_ARGV_LOG records argv.
assert_fixture_dir "$ROOT"
cat > "$ROOT/bin/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGV_LOG"
if [[ "$*" != *" -K -"* && "$*" != "-K -"* && "$*" != *"-K -"* ]]; then echo "shim: credentials must come via -K - on stdin" >&2; exit 64; fi
cat > "$CURL_STDIN_LOG"
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
[[ "$url" == *"/rest/v1/workspace_egress_audit_rollup?"* ]] || { echo "shim: unexpected url $url" >&2; exit 64; }
if [[ "${CURL_FAIL:-0}" == 1 ]]; then exit 7; fi
case "$url" in
  *"?select=last_seen&order=last_seen.asc&limit=1") body="${ROWS_OLDEST:-[]}" ;;
  *"?select=bucket_start&workspace_id=in.("*")&order=bucket_start.desc&limit=1") body="${ROWS_NEWEST:-[]}"; printf '%s' "$url" > "$CURL_URL_LOG" ;;
  *) echo "shim: unexpected query $url" >&2; exit 64 ;;
esac
printf '%s\n%s' "$body" "${HTTP_CODE:-200}"
SHIM
chmod +x "$ROOT/bin/curl"

assert_fixture_dir "$ROOT"
cat > "$ROOT/gw-active" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$1" > "$GW_SQL_LOG"
echo '{"n":3}'
EOF
assert_fixture_dir "$ROOT"
cat > "$ROOT/gw-idle" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$1" > "$GW_SQL_LOG"
echo '{"n":0}'
EOF
assert_fixture_dir "$ROOT"
cat > "$ROOT/gw-broken" <<'EOF'
#!/usr/bin/env bash
echo 'boom' >&2
exit 1
EOF
chmod +x "$ROOT/gw-active" "$ROOT/gw-idle" "$ROOT/gw-broken"

iso() { date -u -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }

run() { # run <expected-rc> <description> [VAR=value ...]
  local want="$1" desc="$2"
  shift 2
  assert_fixture_dir "$ROOT"
  : > "$ROOT/argv.log"
  : > "$ROOT/stdin.log"
  : > "$ROOT/gwsql.log"
  local out rc
  out="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" HOME="$ROOT" \
    CURL_ARGV_LOG="$ROOT/argv.log" CURL_STDIN_LOG="$ROOT/stdin.log" GW_SQL_LOG="$ROOT/gwsql.log" CURL_URL_LOG="$ROOT/url.log" \
    SUPABASE_URL="https://example-ref.supabase.test" SUPABASE_SERVICE_ROLE_KEY="synthetic-service-key-0001" \
    "$@" bash "$SUT" 2>"$ROOT/stderr.log")"
  rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$want" ]]; then pass "$desc (rc=$rc)"; else fail "$desc (want rc=$want, got rc=$rc; stdout=$out; stderr=$(head -c 200 "$ROOT/stderr.log"))"; fi
}

echo "-- retention (always checked) --"
run 0 "oldest row 10 days old, collection not expected: OK" ROWS_OLDEST="[{\"last_seen\":\"$(iso 864000)\"}]"
if [[ "$LAST_OUT" == "OK" ]]; then pass "stdout is exactly OK"; else fail "stdout is exactly OK (got: $LAST_OUT)"; fi
run 0 "empty table, collection not expected: OK" ROWS_OLDEST="[]"
run 1 "oldest row 40 days old: the sweep has stopped" ROWS_OLDEST="[{\"last_seen\":\"$(iso 3456000)\"}]"
if [[ "$LAST_OUT" != "OK" ]]; then pass "a failing run does not print OK"; else fail "a failing run does not print OK"; fi
run 1 "oldest row just past the 35 day line (35 days + 1 h)" ROWS_OLDEST="[{\"last_seen\":\"$(iso $((35 * 86400 + 3600)))\"}]"
run 0 "oldest row just inside the 35 day line (34 days)" ROWS_OLDEST="[{\"last_seen\":\"$(iso $((34 * 86400)))\"}]"

echo "-- an unavailable read is a failure, never a pass --"
run 1 "curl fails (network)" CURL_FAIL=1
run 1 "HTTP 401 from the REST API" HTTP_CODE=401 ROWS_OLDEST="[]"
run 1 "HTTP 500 from the REST API" HTTP_CODE=500 ROWS_OLDEST="[]"
run 1 "a non-JSON body" ROWS_OLDEST="<html>gateway timeout</html>"
run 2 "no service-role key in the environment" SUPABASE_SERVICE_ROLE_KEY=
run 2 "no Supabase URL in the environment" SUPABASE_URL=

echo "-- freshness (only when collection is expected) --"
CANARY="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
FRESH="[{\"bucket_start\":\"$(iso 1200)\"}]"
STEADY_OLD="[{\"bucket_start\":\"$(iso 2760)\"}]"   # 46 min: the oldest a healthy newest bucket gets
JUST_IN="[{\"bucket_start\":\"$(iso 4380)\"}]"      # 73 min: inside the 75 min line
STALE="[{\"bucket_start\":\"$(iso 7200)\"}]"
EXPECT=(EGRESS_AUDIT_EXPECT_COLLECTION=1 EGRESS_AUDIT_CANARY_WORKSPACES="$CANARY" ROWS_OLDEST="[]")
run 0 "collection expected, newest bucket 20 min old, gateway active: OK" "${EXPECT[@]}" ROWS_NEWEST="$FRESH" GW_QUERY_CMD="$ROOT/gw-active"
run 0 "collection expected, newest bucket 46 min old (steady-state worst case), gateway active: OK" "${EXPECT[@]}" ROWS_NEWEST="$STEADY_OLD" GW_QUERY_CMD="$ROOT/gw-active"
run 0 "collection expected, newest bucket 73 min old, gateway active: still inside the line" "${EXPECT[@]}" ROWS_NEWEST="$JUST_IN" GW_QUERY_CMD="$ROOT/gw-active"
run 1 "collection expected, newest bucket 2 h old, gateway active: stale" "${EXPECT[@]}" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
run 1 "collection expected, no row at all, gateway active: stale" "${EXPECT[@]}" ROWS_NEWEST="[]" GW_QUERY_CMD="$ROOT/gw-active"
run 0 "collection expected, newest bucket 2 h old, gateway idle: nothing to ingest" "${EXPECT[@]}" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-idle"
run 1 "collection expected but the gateway activity query fails: unknown is a failure" "${EXPECT[@]}" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-broken"
run 0 "collection NOT expected: a stale bucket is not asserted" ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
run 2 "collection expected but no canary workspace list: refuses rather than guess" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
run 2 "a malformed canary id (query-injection shaped) is refused" EGRESS_AUDIT_EXPECT_COLLECTION=1 EGRESS_AUDIT_CANARY_WORKSPACES="x' OR 1=1 --" ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"

echo "-- the gateway query is scoped, lagged and status-allowlisted --"
run 1 "stale bucket with an active gateway (to capture the query)" "${EXPECT[@]}" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
GWSQL="$(cat "$ROOT/gwsql.log")"
if [[ "$GWSQL" == *"raw LIKE '%$CANARY%'"* ]]; then pass "the query names the canary workspace"; else fail "the query names the canary workspace (got: $GWSQL)"; fi
if [[ "$GWSQL" == *"dt <= now() - INTERVAL 35 MINUTE"* && "$GWSQL" == *"dt > now() - INTERVAL 60 MINUTE"* ]]; then pass "the query ignores events newer than 35 minutes (not landed yet)"; else fail "the query ignores events newer than 35 minutes"; fi
if [[ "$GWSQL" == *"(200|403|502|503|504)"* ]]; then pass "the query counts only the statuses the pipeline ingests (so 407 is excluded)"; else fail "the query counts only the statuses the pipeline ingests"; fi
CANARY2="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
run 1 "two canaries, stale bucket, gateway active (to capture the query)" EGRESS_AUDIT_EXPECT_COLLECTION=1 EGRESS_AUDIT_CANARY_WORKSPACES="$CANARY,$CANARY2" ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
GWSQL2="$(cat "$ROOT/gwsql.log")"
if [[ "$GWSQL2" == *"AND (raw LIKE '%$CANARY%' OR raw LIKE '%$CANARY2%') FORMAT"* ]]; then pass "two canaries are OR-ed inside one parenthesised group"; else fail "two canaries are OR-ed inside one parenthesised group (got: $GWSQL2)"; fi
if [[ "$(cat "$ROOT/url.log")" == *"workspace_id=in.($CANARY,$CANARY2)"* ]]; then pass "the freshness read is scoped to the canary workspaces"; else fail "the freshness read is scoped to the canary workspaces"; fi
# The status pattern must match a real Better Stack row (plain quotes, as observed) and an escaped one.
PAT="$(printf '%s' "$GWSQL" | sed -n "s/.*match(raw, '\([^']*\)').*/\1/p")"
if python3 -c 'import re,sys; p=sys.argv[1]; ok=all(re.search(p,l) for l in (r"{\"workspace\":\"w\",\"status\":\"200\"}", r"{\\\"status\\\":\\\"503\\\"}")) and not any(re.search(p,l) for l in (r"{\"status\":\"407\"}", r"{\"status\":\"2000\"}x" if False else r"{\"status\":\"418\"}")); sys.exit(0 if ok else 1)' "$PAT"; then pass "the status pattern matches plain and escaped rows and not 407 or 418"; else fail "the status pattern matches plain and escaped rows and not 407 or 418 (pattern: $PAT)"; fi
if [[ "$GWSQL" != *"[0-9a-f]{8}-"* ]]; then pass "the query no longer matches every UUID-shaped row"; else fail "the query no longer matches every UUID-shaped row"; fi

echo "-- credential hygiene --"
run 0 "baseline run for the hygiene assertions" ROWS_OLDEST="[]"
if grep -q "synthetic-service-key-0001" "$ROOT/argv.log"; then fail "the key never appears on curl's argv"; else pass "the key never appears on curl's argv"; fi
if grep -q "synthetic-service-key-0001" "$ROOT/stdin.log"; then pass "the key reaches curl through the stdin config"; else fail "the key reaches curl through the stdin config"; fi
if grep -q "synthetic-service-key-0001" "$ROOT/stderr.log"; then fail "the key is never written to stderr"; else pass "the key is never written to stderr"; fi
run 78 "refuses to run under shell tracing while the key is set" SHELLOPTS=xtrace

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $((PASS + FAIL)) -lt 37 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 37.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
