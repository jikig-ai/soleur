#!/usr/bin/env bash
# Drives origin-tls-probe.sh against a local server, one case per verdict arm (#10479).
#
# ANTI-VACUITY. The floor and the passes+fails==asserted reconciliation at the bottom are emitted
# with a direct echo + exit 1, NOT through pass()/fail(): a floor dispatched through the helper it
# backstops is disarmed by the one-line edit that disarms every assertion it protects. ASSERTED is
# its own counter, incremented by pass() and fail() alike, so a neutered helper leaves it at 0.
# The port is ephemeral and the server proves its identity (a per-run token header), so a foreign
# listener cannot make the cases pass against the wrong server.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/origin-tls-probe.sh"
PASSES=0; FAILS=0; ASSERTED=0

pass() { PASSES=$((PASSES + 1)); ASSERTED=$((ASSERTED + 1)); echo "[ok] $1"; }
fail() { FAILS=$((FAILS + 1));  ASSERTED=$((ASSERTED + 1)); echo "[FAIL] $1"; }

WORK="$(mktemp -d)"
TOKEN="probe-test-$$-$RANDOM"
REQLOG="$WORK/requests.log"
HDRLOG="$WORK/probe-header.log"
srv_pid=""
PORT=""
# $1=status $2=transport header value ('' for none)
start_srv() {
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
  : > "$REQLOG"; : > "$HDRLOG"
  python3 - "$1" "$2" "$PORT" "$TOKEN" "$REQLOG" "$HDRLOG" <<'PY' &
import sys, http.server
code, transport, port, token, reqlog, hdrlog = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        with open(reqlog, "a") as f:
            f.write("%s | cache-control=%s\n" % (s.path, s.headers.get("Cache-Control")))
        with open(hdrlog, "a") as f:
            f.write("x-origin-tls-probe=%s\n" % s.headers.get("x-origin-tls-probe"))
        s.send_response(code)
        if transport: s.send_header("x-origin-transport", transport)
        s.send_header("x-probe-test-server", token)
        s.send_header("cf-cache-status", "DYNAMIC"); s.send_header("Content-Length", "0")
        s.end_headers()
    def log_message(s, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
  srv_pid=$!
  for _ in $(seq 1 50); do
    kill -0 "$srv_pid" 2>/dev/null || return 1
    hdrs="$(curl -sS -o /dev/null -D - "http://127.0.0.1:${PORT}/" 2>/dev/null | tr -d '\r')" || hdrs=""
    if grep -qix "x-probe-test-server: $TOKEN" <<<"$hdrs"; then return 0; fi
    sleep 0.1
  done
  return 1
}
stop_srv() { [ -n "$srv_pid" ] && kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; srv_pid=""; }
cleanup() { stop_srv; rm -rf "$WORK"; }
trap cleanup EXIT

run() { OUT="$(ORIGIN_TLS_PROBE_ALLOW_HTTP=1 ORIGIN_TLS_PROBE_URL="http://127.0.0.1:${PORT}/health" bash "$PROBE" "$@" 2>&1)"; RC=$?; }
expect_rc() { # $1=name $2=rc $3=substring
  [ "$RC" -eq "$2" ] && pass "$1 -> rc $2" || fail "$1 expected rc $2, got $RC ($OUT)"
  case "$OUT" in *"$3"*) pass "$1 reports '$3'" ;; *) fail "$1 output lacks '$3': $OUT" ;; esac
}

start_srv 200 TLSv1.3 || { echo "harness: server did not start"; exit 1; }
run;                    expect_rc "P1 200 + TLS header (default)" 0 "result=TLS-ON-ORIGIN-HOP"
run --require-tls;      expect_rc "P2 200 + TLS header (--require-tls)" 0 "transport=TLSv1.3"
# The request itself: cache-busted and no-cache, so a cached response cannot be mistaken for a live hop.
if grep -Eq '^/health\?origin-tls-probe=[0-9]+-[0-9]+-[0-9]+ \| cache-control=no-cache$' "$REQLOG"; then
  pass "P1b the probe sends a unique cache-buster query and Cache-Control: no-cache"
else
  fail "P1b request shape wrong: $(cat "$REQLOG")"
fi
# A base URL that already has a query string gets '&', not a second '?'.
OUT="$(ORIGIN_TLS_PROBE_ALLOW_HTTP=1 ORIGIN_TLS_PROBE_URL="http://127.0.0.1:${PORT}/health?x=1" bash "$PROBE" 2>&1)"; RC=$?
grep -Eq '^/health\?x=1&origin-tls-probe=' "$REQLOG" && pass "P1c existing query string joined with '&'" || fail "P1c query join wrong: $(tail -1 "$REQLOG")"
stop_srv

start_srv 200 "" || exit 1
run;                    expect_rc "P3 200, no header, default (pre-flip truth)" 0 "result=PLAIN-ORIGIN-HOP"
run --require-tls;      expect_rc "P4 200, no header, --require-tls (must NOT pass)" 3 "NO-TLS-ON-ORIGIN-HOP"
stop_srv

# P5: a value that is not a TLS version never counts as TLS, and what is echoed is sanitised.
start_srv 200 "unknown" || exit 1
run;                    expect_rc "P5 transport 'unknown' is not TLS (default)" 0 "result=UNEXPECTED-TRANSPORT"
run --require-tls;      expect_rc "P5b transport 'unknown' is not TLS (--require-tls)" 3 "UNEXPECTED-TRANSPORT"
stop_srv
start_srv 200 'TLSv1.3;evil$(id)' || exit 1
run --require-tls
case "$OUT" in *'$('*|*';'*) fail "P5c echoed header value not sanitised: $OUT" ;; *) pass "P5c echoed header value is sanitised" ;; esac
[ "$RC" -eq 3 ] && pass "P5d a decorated TLS-looking value is not TLS -> rc 3" || fail "P5d expected rc 3, got $RC"
stop_srv

start_srv 526 "" || exit 1
run;                    expect_rc "P6 526 (Cloudflare refused the origin certificate)" 1 "http=526"
stop_srv

# P7: other non-200s are a verdict too, not 'OK'.
start_srv 301 TLSv1.3 || exit 1
run;                    expect_rc "P7 301 is NOT-200" 1 "result=NOT-200"
stop_srv

# --- canary mode (ADR-321 ORIGIN-TLS CANARY rule) ---
# The header name is pinned against the Terraform rule, so the probe and the rule cannot drift apart.
TF_RULES="$SCRIPT_DIR/seo-config-rules.tf"
if grep -v '^[[:space:]]*#' "$TF_RULES" | grep -qF 'http.request.headers[\"x-origin-tls-probe\"]'; then pass "C0 the rule matches the header the probe sends (x-origin-tls-probe)"; else fail "C0 header name in seo-config-rules.tf does not match the probe"; fi
start_srv 200 TLSv1.3 || exit 1
run;                    expect_rc "C1 default mode, TLS header" 0 "result=TLS-ON-ORIGIN-HOP"
[ "$(grep -c 'x-origin-tls-probe=1' "$HDRLOG")" -eq 0 ] && pass "C1b default mode does NOT send the canary header" || fail "C1b default mode sent the canary header: $(cat "$HDRLOG")"
: > "$HDRLOG"
run --canary;           expect_rc "C2 --canary, TLS header (rule applied, certificate accepted)" 0 "mode=canary result=TLS-ON-ORIGIN-HOP"
grep -qx 'x-origin-tls-probe=1' "$HDRLOG" && pass "C2b --canary sends x-origin-tls-probe: 1" || fail "C2b canary header missing: $(cat "$HDRLOG")"
stop_srv
start_srv 200 "" || exit 1
run --canary;           expect_rc "C3 --canary, no TLS header (rule did NOT apply: must not pass, implies --require-tls)" 3 "mode=canary result=NO-TLS-ON-ORIGIN-HOP"
stop_srv
start_srv 526 "" || exit 1
run --canary;           expect_rc "C4 --canary, 526 (rule applied, Cloudflare refused the certificate)" 1 "mode=canary result=NOT-200"
stop_srv

# P8: nothing listening -> UNREACHABLE, its own exit code, never a verdict, with curl's exit code.
OUT="$(ORIGIN_TLS_PROBE_ALLOW_HTTP=1 ORIGIN_TLS_PROBE_URL="http://127.0.0.1:${PORT}/health" bash "$PROBE" 2>&1)"; RC=$?
expect_rc "P8 connection refused" 2 "UNREACHABLE"
case "$OUT" in *"curl_exit=7"*) pass "P8b the curl exit code is reported (7 = connection refused)" ;; *) fail "P8b curl_exit missing: $OUT" ;; esac

# P9: usage errors are rc 64, not probe results.
OUT="$(bash "$PROBE" --expect tls 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && pass "P9 unknown flag -> rc 64" || fail "P9 expected rc 64, got $RC"
OUT="$(ORIGIN_TLS_PROBE_URL="http://127.0.0.1:1/health" bash "$PROBE" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && pass "P9b a non-https target is refused without the test seam -> rc 64" || fail "P9b expected rc 64, got $RC"
OUT="$(ORIGIN_TLS_PROBE_URL="ftp://example.invalid/health" bash "$PROBE" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && pass "P9c a non-http(s) scheme is refused -> rc 64" || fail "P9c expected rc 64, got $RC"

echo
echo "=== origin-tls-probe: $PASSES passed, $FAILS failed, $ASSERTED asserted ==="

MIN_ASSERTIONS=37
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
