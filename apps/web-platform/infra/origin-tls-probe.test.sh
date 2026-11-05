#!/usr/bin/env bash
# Drives origin-tls-probe.sh against a local server, one case per verdict arm (#10479).
#
# ANTI-VACUITY: the assertion floor at the bottom is emitted WITHOUT routing through pass()/fail().
# A floor dispatched through the helper it backstops is disarmed by the one-line edit that disarms
# every assertion it protects.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/origin-tls-probe.sh"
PORT="${PROBE_TEST_PORT:-8764}"
PASSES=0; FAILS=0

pass() { PASSES=$((PASSES + 1)); echo "[ok] $1"; }
fail() { FAILS=$((FAILS + 1)); echo "[FAIL] $1"; }

srv_pid=""
# $1=status $2=transport header value ('' for none) $3=required request header ('' for none)
start_srv() {
  python3 - "$1" "$2" "$3" "$PORT" <<'PY' &
import sys, http.server
code, transport, need, port = int(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        c, t = code, transport
        if need and s.headers.get(need) != "1":   # models the canary rule: header absent -> flexible path
            t = ""
        s.send_response(c)
        if t: s.send_header("x-origin-transport", t)
        s.send_header("cf-cache-status", "DYNAMIC"); s.send_header("Content-Length", "0")
        s.end_headers()
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

run() { OUT="$(ORIGIN_TLS_PROBE_URL="http://127.0.0.1:${PORT}/health" bash "$PROBE" "$@" 2>&1)"; RC=$?; }
expect_rc() { # $1=name $2=rc $3=substring
  [ "$RC" -eq "$2" ] && pass "$1 -> rc $2" || fail "$1 expected rc $2, got $RC ($OUT)"
  case "$OUT" in *"$3"*) pass "$1 reports '$3'" ;; *) fail "$1 output lacks '$3': $OUT" ;; esac
}

start_srv 200 TLSv1.3 "" || { echo "harness: server did not start"; exit 1; }
run;                    expect_rc "P1 200 + transport header (default)" 0 "transport=TLSv1.3"
run --expect tls;       expect_rc "P2 200 + transport header (--expect tls)" 0 "result=OK"
stop_srv

start_srv 200 "" "" || exit 1
run;                    expect_rc "P3 200, no header, --expect any (pre-flip truth)" 0 "transport=none"
run --expect tls;       expect_rc "P4 200, no header, --expect tls (must NOT pass)" 3 "NO-TLS-ON-ORIGIN-HOP"
stop_srv

start_srv 526 "" "" || exit 1
run;                    expect_rc "P5 526 (Cloudflare refused the origin certificate)" 1 "http=526"
stop_srv

start_srv 200 TLSv1.3 x-origin-tls-probe || exit 1
run --canary --expect tls; expect_rc "P6 canary request gets the strict path" 0 "mode=canary"
run --expect tls;          expect_rc "P7 non-canary request stays on the plain path" 3 "NO-TLS-ON-ORIGIN-HOP"
stop_srv

# P8: nothing listening -> UNREACHABLE, its own exit code, never a verdict.
OUT="$(ORIGIN_TLS_PROBE_URL="http://127.0.0.1:${PORT}/health" bash "$PROBE" 2>&1)"; RC=$?
expect_rc "P8 connection refused" 2 "UNREACHABLE"

# P9: bad flags are a usage error, not a probe result.
OUT="$(bash "$PROBE" --expect maybe 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && pass "P9 bad --expect -> rc 64" || fail "P9 expected rc 64, got $RC"

# Floor, outside pass()/fail(): at least 16 assertions must have run, or the suite proved nothing.
TOTAL=$((PASSES + FAILS))
if [ "$TOTAL" -lt 16 ]; then echo "FLOOR: only $TOTAL assertions ran (need >= 16)"; exit 1; fi
echo "=== origin-tls-probe: $PASSES passed, $FAILS failed ==="
[ "$FAILS" -eq 0 ] && echo OK
exit "$FAILS"
