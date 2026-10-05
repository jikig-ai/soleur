#!/usr/bin/env bash
# Drives pages-build-identity-probe.sh against a local origin, one case per arm.
#
# AC19 (ADR-194) requires the failing arm to be "exercised by a run where the
# expected SHA is deliberately wrong". Case M2 is that run.
#
# ANTI-VACUITY: the assertion floor below is emitted WITHOUT routing through
# pass()/fail(), because a floor dispatched through the helper it backstops is
# disarmed by the same one-line edit that disarms every assertion it protects.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/pages-build-identity-probe.sh"
PORT="${PROBE_TEST_PORT:-8763}"
PASSES=0; FAILS=0; ASSERTED=0

pass() { PASSES=$((PASSES + 1)); ASSERTED=$((ASSERTED + 1)); echo "[ok] $1"; }
fail() { FAILS=$((FAILS + 1));  ASSERTED=$((ASSERTED + 1)); echo "[FAIL] $1"; }

srv_pid=""
start_srv() { # $1=status $2=body
  python3 - "$1" "$2" "$PORT" <<'PY' &
import sys, http.server
code, body, port = int(sys.argv[1]), sys.argv[2].encode(), int(sys.argv[3])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        s.send_response(code); s.send_header("Content-Length", str(len(body)))
        s.end_headers(); s.wfile.write(body)
    def log_message(s, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
  srv_pid=$!
  for _ in $(seq 1 40); do
    curl -sS -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}
stop_srv() { [ -n "$srv_pid" ] && kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; srv_pid=""; }
trap stop_srv EXIT

run_probe() { # $1=expected-sha -> sets RC/OUT
  OUT="$(PROBE_URL="http://127.0.0.1:${PORT}/version.txt" EXPECTED_SHA="$1" \
         PROBE_ATTEMPTS=1 PROBE_SLEEP_SECONDS=0 bash "$PROBE" 2>&1)"; RC=$?
}

SHA="abc123def456abc123def456abc123def456abcd"

# --- M1 MATCH -------------------------------------------------------------
start_srv 200 "$SHA" || { echo "harness: server did not start"; exit 1; }
run_probe "$SHA"; stop_srv
[ "$RC" -eq 0 ] && pass "M1 correct sha -> rc 0" || fail "M1 expected rc 0, got $RC"
grep -q 'MATCH' <<<"$OUT" && pass "M1 reports MATCH" || fail "M1 output: $OUT"

# --- M2 MISMATCH (AC19: the deliberately-wrong SHA run) --------------------
start_srv 200 "0000000000000000000000000000000000000000" || exit 1
run_probe "$SHA"; stop_srv
[ "$RC" -eq 1 ] && pass "M2 wrong sha -> rc 1 (AC19)" || fail "M2 expected rc 1, got $RC"
grep -q 'MISMATCH' <<<"$OUT" && pass "M2 reports MISMATCH" || fail "M2 output: $OUT"
grep -q 'UNREACHABLE' <<<"$OUT" && fail "M2 must NOT report UNREACHABLE" || pass "M2 does not collapse into UNREACHABLE"

# --- M3 ABSENT (the stale/preview signature) -------------------------------
start_srv 404 "not found" || exit 1
run_probe "$SHA"; stop_srv
[ "$RC" -eq 3 ] && pass "M3 404 -> rc 3 ABSENT" || fail "M3 expected rc 3, got $RC"
grep -q 'ABSENT' <<<"$OUT" && pass "M3 reports ABSENT" || fail "M3 output: $OUT"
grep -q 'UNREACHABLE' <<<"$OUT" && fail "M3 404 must NOT read as UNREACHABLE" || pass "M3 404 is a definite verdict, not 'could not check'"

# --- M4 UNREACHABLE (nothing listening) ------------------------------------
run_probe "$SHA"
[ "$RC" -eq 2 ] && pass "M4 no listener -> rc 2 UNREACHABLE" || fail "M4 expected rc 2, got $RC"
grep -q "NOT 'the deploy is correct'" <<<"$OUT" && pass "M4 refuses to read as success (AP-021)" || fail "M4 output: $OUT"

# --- M5 body flood is truncated and backtick-stripped ----------------------
FLOOD="$(python3 -c 'print("`x`" * 400)')"
start_srv 200 "$FLOOD" || exit 1
run_probe "$SHA"; stop_srv
[ "$RC" -eq 1 ] && pass "M5 html/flood body -> rc 1" || fail "M5 expected rc 1, got $RC"
[ "${#OUT}" -lt 400 ] && pass "M5 body truncated (${#OUT} bytes)" || fail "M5 flooded output: ${#OUT} bytes"
grep -q '`' <<<"$OUT" && fail "M5 backticks must be stripped" || pass "M5 backticks stripped"

# --- M6 empty served body is a MISMATCH, not a MATCH -----------------------
start_srv 200 "" || exit 1
run_probe "$SHA"; stop_srv
[ "$RC" -eq 1 ] && pass "M6 empty body -> rc 1" || fail "M6 expected rc 1, got $RC"

echo
echo "=== $PASSES passed, $FAILS failed, $ASSERTED asserted ==="

MIN_ASSERTIONS=14
if [ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]; then
  echo "ANTI-VACUITY: only $ASSERTED assertions ran, floor is $MIN_ASSERTIONS." >&2
  echo "Assertions were removed or the dispatch was disarmed." >&2
  exit 1
fi
if [ "$((PASSES + FAILS))" -ne "$ASSERTED" ]; then
  echo "ACCOUNTING: passes+fails ($((PASSES + FAILS))) != asserted ($ASSERTED)." >&2
  exit 1
fi
[ "$FAILS" -eq 0 ] || exit 1
echo "OK"
