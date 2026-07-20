#!/usr/bin/env bash
# Tests the web-host zot CONSUMER-perspective serviceability probe (#6438 §1, AC1,
# web-zot-consumer-probe.sh). The probe HEADs a REAL repo tag-list with Basic auth and
# classifies the HTTP code: 200 servable (ping), 404 store-empty (suppress), 401 auth
# broke (HARD failure, exit 3), 5xx/000 (suppress). The #6400 shape reproduced inside a
# probe is a servable auth gate over a dead store — so `-u` and the *absence* of `-f` are
# both load-bearing, and this suite proves each behaviorally.
#
# TWO layers (mirrors disk-monitor.test.sh's accumulator + registry private-nic-guard's
# env-seam harness):
#   1. SEAM classification (SOLEUR_ZOT_PROBE_STATUS_OVERRIDE + SOLEUR_ZOT_PROBE_PING_LOG):
#      every branch's ping-decision + exit code, no live registry.
#   2. BEHAVIORAL -u/-f (AC1's core): a real python3 mock registry that enforces the exact
#      zot `defaultPolicy:[]` contract (401 before repo lookup on ANY path without auth;
#      200 for the served repo WITH auth; 404 for a nonexistent repo WITH auth). We run the
#      real script against it, plus two SED-mutated COPIES that prove -u and no-`-f` are
#      load-bearing: strip `-u` => 401 => exit 3; inject `-f` => the 404 code capture is
#      corrupted (`404` + `|| echo 000` => `404000`) => the 404 classification is destroyed.
#
# ENV-DRIVEN plain bash: we EXECUTE the real .sh directly. Pure bash + python3 + a loopback
# HTTP server — no docker, network egress, or root.
#
# Run: bash apps/web-platform/infra/web-zot-consumer-probe.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-zot-consumer-probe.sh"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
SRV_PID=""
cleanup() { rm -rf "$TMP"; [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null; }
trap cleanup EXIT

echo "=== web-host zot consumer-probe (#6438 §1, AC1) tests ==="
assert "web-zot-consumer-probe.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"

# --- SEAM: classification via SOLEUR_ZOT_PROBE_STATUS_OVERRIDE ----------------------------
# EC = exit code, PINGED = yes|no (seam ping-log non-empty). REPO/ZUSER/ZTOK are set so the
# probe passes its own required-env gate before reaching the override.
run_override() {  # <injected http code>
  local code="$1" pinglog ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"
  SOLEUR_ZOT_PROBE_STATUS_OVERRIDE="$code" SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" \
    ZOT_PROBE_REPO=known/repo ZUSER=u ZTOK=t \
    bash "$SUT" >/dev/null 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes
}

echo "--- seam: HTTP-code classification ---"
run_override 200
assert "200 => ping logged"       "[[ '$PINGED' == yes ]]"
assert "200 => exit 0"            "[[ '$EC' -eq 0 ]]"
run_override 404
assert "404 => NO ping"           "[[ '$PINGED' == no ]]"
assert "404 => exit 0 (absence alarms)" "[[ '$EC' -eq 0 ]]"
run_override 401
assert "401 => NO ping"           "[[ '$PINGED' == no ]]"
assert "401 => exit 3 (HARD failure, not 'alive')" "[[ '$EC' -eq 3 ]]"
run_override 000
assert "000 => NO ping"           "[[ '$PINGED' == no ]]"
assert "000 => exit 0 (unreachable, absence alarms)" "[[ '$EC' -eq 0 ]]"
run_override 503
assert "503 (5xx wedged) => NO ping" "[[ '$PINGED' == no ]]"
assert "503 => exit 0 (absence alarms)" "[[ '$EC' -eq 0 ]]"

# --- required-env gate (guards the -u/-f mutants below have creds to reach the probe) -----
echo "--- seam: required-env gate ---"
gate_ec=0
ZOT_PROBE_REPO="" ZUSER=u ZTOK=t bash "$SUT" >/dev/null 2>&1 || gate_ec=$?
assert "missing ZOT_PROBE_REPO => FATAL exit 1" "[[ '$gate_ec' -eq 1 ]]"
gate_ec=0
ZOT_PROBE_REPO=known/repo ZUSER="" ZTOK="" bash "$SUT" >/dev/null 2>&1 || gate_ec=$?
assert "missing ZUSER/ZTOK => FATAL exit 1 (anonymous proves nothing)" "[[ '$gate_ec' -eq 1 ]]"

# --- BEHAVIORAL: real mock registry (AC1 core) -------------------------------------------
echo "--- behavioral: real mock zot registry (auth + -u + no-'-f') ---"
SRV_PY="$TMP/mock_zot.py"
cat > "$SRV_PY" <<'PY'
import base64, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
EXPECT = "Basic " + base64.b64encode(b"zuser:ztok").decode()
SERVED = "/v2/known/repo/tags/list"
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        # zot defaultPolicy:[] — auth is enforced BEFORE the repo lookup, so an anonymous
        # request gets 401 on EVERY path (including a nonexistent repo).
        if self.headers.get("Authorization", "") != EXPECT:
            self.send_response(401); self.end_headers(); return
        if self.path == SERVED:
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"name":"known/repo","tags":["v1"]}')
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): return
srv = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PY

PORT_FILE="$TMP/zot_port"
python3 "$SRV_PY" "$PORT_FILE" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
assert "mock registry published its port" "[[ -s '$PORT_FILE' ]]"
PORT="$(cat "$PORT_FILE" 2>/dev/null || true)"

# EC / PINGED / OUT for a real probe against the mock (no status override).
run_probe() {  # <script> <repo>
  local script="$1" repo="$2" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" SOLEUR_PROBE_VERBOSE=1 \
    ZOT_ENDPOINT="127.0.0.1:$PORT" ZOT_PROBE_REPO="$repo" ZUSER=zuser ZTOK=ztok \
    timeout 20 bash "$script" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

# (a) real script, served repo, correct auth => 200 => ping.
run_probe "$SUT" known/repo
assert "(a) authed probe of the served repo => 200 => ping" "[[ '$PINGED' == yes ]]"
assert "(a) => exit 0"                                       "[[ '$EC' -eq 0 ]]"
assert "(a) => reports servable (200)"                       "grep -q 'servable (200)' <<<\"\$OUT\""

# (d) real script, nonexistent repo, correct auth => 404 => no ping.
run_probe "$SUT" nonexistent/repo
assert "(d) authed probe of a nonexistent repo => 404 => NO ping" "[[ '$PINGED' == no ]]"
assert "(d) => exit 0 (absence alarms)"                           "[[ '$EC' -eq 0 ]]"
assert "(d) => reports the #6400-inside-the-probe 404 case"       "grep -q 'EMPTY/DETACHED' <<<\"\$OUT\""

# (b) COPY with `-u ...` stripped => anonymous => 401 => exit 3, no ping (proves -u load-bearing).
STRIP_U="$TMP/probe-no-u.sh"
sed 's/ -u "$ZUSER:$ZTOK"//' "$SUT" > "$STRIP_U"
assert "(b) the -u strip actually removed the auth flag from the probe curl" \
  "grep -q 'curl -s -o /dev/null -w' '$STRIP_U' && ! grep -q 'curl -s -u' '$STRIP_U'"
run_probe "$STRIP_U" known/repo
assert "(b) -u stripped => anonymous => 401 => NO ping" "[[ '$PINGED' == no ]]"
assert "(b) -u stripped => exit 3 (HARD failure — proves -u is load-bearing)" "[[ '$EC' -eq 3 ]]"
assert "(b) -u stripped => reports the auth-broke hard failure" "grep -q 'HARD FAILURE: 401' <<<\"\$OUT\""

# (c) COPY with `-f` injected into the probe curl => the 404 code capture is corrupted
# (curl prints '404' then exits non-zero => `|| echo 000` appends => CODE=404000), so the
# clean 404 classification is destroyed (proves the ABSENCE of -f is load-bearing).
FORCE_F="$TMP/probe-force-f.sh"
sed 's/curl -s -u/curl -sf -u/' "$SUT" > "$FORCE_F"
assert "(c) the -f injection actually added -f to the probe curl" \
  "grep -q 'curl -sf -u \"\$ZUSER:\$ZTOK\"' '$FORCE_F'"
run_probe "$FORCE_F" nonexistent/repo
assert "(c) -f injected => the 404 classification is DESTROYED (no EMPTY/DETACHED verdict)" \
  "! grep -q 'EMPTY/DETACHED' <<<\"\$OUT\""
assert "(c) -f injected => the corrupted code lands in the unexpected-code branch" \
  "grep -q 'unexpected code' <<<\"\$OUT\""
assert "(c) -f injected => still no ping (never green over a corrupted verdict)" "[[ '$PINGED' == no ]]"

# --- static drift-guard: doppler-auth unit-start contract + observability delivery --------
# (#6438 §1 unit-start fix.) The unit runs `doppler run` as ROOT. Without Environment=HOME=/root
# the doppler CLI dies "$HOME is not defined" BEFORE it exec's the probe; without a DOPPLER_TOKEN
# in the per-host env file it cannot authenticate. Both gaps made all 3 units fail to start on
# web-1. This block also asserts the cross-cutting fix pieces: the dedicated read-scoped token
# resource, and the positive-control Source-4 canary (the probes are otherwise silent-on-success,
# so a dead vector Source 4 would be invisible — luks-#6604 pattern).
echo "--- static: doppler-auth unit-start contract + observability ---"
SVC="$SCRIPT_DIR/web-zot-consumer-probe.service"
SERVER_TF="$SCRIPT_DIR/server.tf"
TOKEN_TF="$SCRIPT_DIR/web-probe-read-token.tf"
assert "zot .service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert "zot .service does NOT source webhook-deploy (deploy-owned; imports /tmp/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'webhook-deploy'"
assert "zot .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'DOPPLER_CONFIG_DIR'"
assert "zot .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q '/tmp/.doppler'"
assert "zot .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -qE '^PrivateTmp=true' '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal DOPPLER_TOKEN= — otherwise
# dropping the key arg (empty token = the #6548 bug) still matches (test-design review).
assert "server.tf zot_consumer_probe_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-zot-consumer-probe" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-zot-consumer-probe' '$SERVER_TF'"
# Cross-cutting: dedicated read-scoped token (least-privilege; NOT the full-prd var.doppler_token).
assert "doppler_service_token.web_probes resource exists" \
  "grep -qE 'resource \"doppler_service_token\" \"web_probes\"' '$TOKEN_TF'"
assert "web_probes token is read-scoped (access=\"read\") + soleur/prd config" \
  "awk '/\"doppler_service_token\" \"web_probes\"/,/^}/' '$TOKEN_TF' | grep -qE 'access[[:space:]]*=[[:space:]]*\"read\"'"
assert "web_probes token is scoped to config \"prd\" (the probes run doppler --config prd)" \
  "awk '/\"doppler_service_token\" \"web_probes\"/,/^}/' '$TOKEN_TF' | grep -qE 'config[[:space:]]*=[[:space:]]*\"prd\"'"
# Positive-control Source-4 canary — assert it FIRES (behaviorally), not merely that the string exists
# in the file (a deleted _canary call would leave the string in the function def + comments). Prove
# three properties: (a) fires on a run with a fresh marker; (b) rate-limits (no re-emit within window);
# (c) fires INDEPENDENT of zot health (emits even on a 000 verdict — the observability-review property).
CANARY_MARKER="$TMP/canary.marker"
run_canary() {  # <override-code> <marker-reset:yes|no> -> sets CANARY_OUT
  local code="$1" reset="$2" pl
  [[ "$reset" == yes ]] && rm -f "$CANARY_MARKER"
  pl="$(mktemp "$TMP/pl.XXXXXX")"; CANARY_OUT="$(mktemp "$TMP/canary.XXXXXX")"
  SOLEUR_ZOT_PROBE_STATUS_OVERRIDE="$code" SOLEUR_ZOT_PROBE_PING_LOG="$pl" \
    SOLEUR_PROBE_CANARY_MARKER="$CANARY_MARKER" \
    ZOT_PROBE_REPO=known/repo ZUSER=u ZTOK=t \
    bash "$SUT" >/dev/null 2>"$CANARY_OUT" || true
}
run_canary 200 yes
assert "zot probe EMITS SOLEUR_PROBE_CANARY to stderr on a fresh-marker run (fires, not just present)" \
  "grep -q 'SOLEUR_PROBE_CANARY' '$CANARY_OUT'"
run_canary 200 no
assert "zot probe RATE-LIMITS the canary (no re-emit within the window)" \
  "! grep -q 'SOLEUR_PROBE_CANARY' '$CANARY_OUT'"
run_canary 000 yes
assert "zot probe canary fires INDEPENDENT of zot health (emits even on a 000 unreachable verdict)" \
  "grep -q 'SOLEUR_PROBE_CANARY' '$CANARY_OUT'"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
