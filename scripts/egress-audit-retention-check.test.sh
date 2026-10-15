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
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin"

# curl shim: ROWS_OLDEST / ROWS_NEWEST / HTTP_CODE select the answer; CURL_ARGV_LOG records argv.
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
  *"order=last_seen.asc"*) body="${ROWS_OLDEST:-[]}" ;;
  *"order=bucket_start.desc"*) body="${ROWS_NEWEST:-[]}" ;;
  *) echo "shim: unexpected query $url" >&2; exit 64 ;;
esac
printf '%s\n%s' "$body" "${HTTP_CODE:-200}"
SHIM
chmod +x "$ROOT/bin/curl"

cat > "$ROOT/gw-active" <<'EOF'
#!/usr/bin/env bash
echo '{"n":3}'
EOF
cat > "$ROOT/gw-idle" <<'EOF'
#!/usr/bin/env bash
echo '{"n":0}'
EOF
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
  : > "$ROOT/argv.log"
  : > "$ROOT/stdin.log"
  local out rc
  out="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" HOME="$ROOT" \
    CURL_ARGV_LOG="$ROOT/argv.log" CURL_STDIN_LOG="$ROOT/stdin.log" \
    SUPABASE_URL="https://example-ref.supabase.test" SUPABASE_SERVICE_ROLE_KEY="synthetic-service-key-0001" \
    "$@" bash "$SUT" 2>"$ROOT/stderr.log")"
  rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$want" ]]; then pass "$desc (rc=$rc)"; else fail "$desc (want rc=$want, got rc=$rc; stdout=$out; stderr=$(head -c 200 "$ROOT/stderr.log"))"; fi
}

echo "-- retention (always checked) --"
run 0 "oldest row 10 days old, collection not expected: OK" ROWS_OLDEST="[{\"last_seen\":\"$(iso 864000)\"}]"
[[ "$LAST_OUT" == "OK" ]] && pass "stdout is exactly OK" || fail "stdout is exactly OK (got: $LAST_OUT)"
run 0 "empty table, collection not expected: OK" ROWS_OLDEST="[]"
run 1 "oldest row 40 days old: the sweep has stopped" ROWS_OLDEST="[{\"last_seen\":\"$(iso 3456000)\"}]"
[[ "$LAST_OUT" != "OK" ]] && pass "a failing run does not print OK" || fail "a failing run does not print OK"
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
FRESH="[{\"bucket_start\":\"$(iso 1200)\"}]"
STALE="[{\"bucket_start\":\"$(iso 7200)\"}]"
run 0 "collection expected, newest bucket 20 min old, gateway active: OK" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="$FRESH" GW_QUERY_CMD="$ROOT/gw-active"
run 1 "collection expected, newest bucket 2 h old, gateway active: stale" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"
run 1 "collection expected, no row at all, gateway active: stale" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="[]" GW_QUERY_CMD="$ROOT/gw-active"
run 0 "collection expected, newest bucket 2 h old, gateway idle: nothing to ingest" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-idle"
run 1 "collection expected but the gateway activity query fails: unknown is a failure" EGRESS_AUDIT_EXPECT_COLLECTION=1 ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-broken"
run 0 "collection NOT expected: a stale bucket is not asserted" ROWS_OLDEST="[]" ROWS_NEWEST="$STALE" GW_QUERY_CMD="$ROOT/gw-active"

echo "-- credential hygiene --"
run 0 "baseline run for the hygiene assertions" ROWS_OLDEST="[]"
if grep -q "synthetic-service-key-0001" "$ROOT/argv.log"; then fail "the key never appears on curl's argv"; else pass "the key never appears on curl's argv"; fi
if grep -q "synthetic-service-key-0001" "$ROOT/stdin.log"; then pass "the key reaches curl through the stdin config"; else fail "the key reaches curl through the stdin config"; fi
if grep -q "synthetic-service-key-0001" "$ROOT/stderr.log"; then fail "the key is never written to stderr"; else pass "the key is never written to stderr"; fi
run 2 "refuses to run under shell tracing" SHELLOPTS=xtrace

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $((PASS + FAIL)) -lt 24 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 24.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
