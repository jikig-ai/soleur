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
# Every helper gets its OWN repos-marker path (a root CI runner would otherwise share /run state
# between rows and a second row would silently inherit the first one's rate-limit window).
MARKER_N=0
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
    SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
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
SERVED = {"/v2/known/repo/tags/list", "/v2/known/second/tags/list"}
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        # zot defaultPolicy:[] — auth is enforced BEFORE the repo lookup, so an anonymous
        # request gets 401 on EVERY path (including a nonexistent repo).
        if self.headers.get("Authorization", "") != EXPECT:
            self.send_response(401); self.end_headers(); return
        if self.path in SERVED:
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
    SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
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

# (e) real script, NOTHING listening (#7262) => a transport failure must take the `000` branch.
# curl prints `000` via -w AND exits non-zero, so the `|| echo 000` fallback appends a second
# `000`: before the fix CODE was `000000`, which missed the `000)` arm and landed in the
# catch-all as "unexpected code 000000" -- all 10 production SUPPRESS rows 08-13..09-28 read
# exactly that, so the private-net-down verdict never once fired. Port 1 on loopback has no
# listener (binding it needs root), so the connect is refused immediately. Only this
# behavioural row reaches the live capture; the seam override bypasses it.
DEAD_PING="$(mktemp "$TMP/ping.XXXXXX")"; DEAD_OUT="$(mktemp "$TMP/out.XXXXXX")"; DEAD_EC=0
SOLEUR_ZOT_PROBE_PING_LOG="$DEAD_PING" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
  ZOT_ENDPOINT="127.0.0.1:1" ZOT_PROBE_REPO=known/repo \
  ZUSER=zuser ZTOK=ztok timeout 20 bash "$SUT" >"$DEAD_OUT" 2>&1 || DEAD_EC=$?
assert "(e) dead endpoint => the 000 UNREACHABLE verdict (private-net path down)" \
  "grep -q 'SUPPRESS ping: 000 — 127.0.0.1:1 UNREACHABLE' '$DEAD_OUT'"
assert "(e) dead endpoint => NOT the unexpected-code catch-all (the 000000 double-write)" \
  "! grep -q 'unexpected code' '$DEAD_OUT'"
assert "(e) dead endpoint => NO ping (absence alarms)" "[[ ! -s '$DEAD_PING' ]]"
assert "(e) dead endpoint => exit 0" "[[ '$DEAD_EC' -eq 0 ]]"

# (b) COPY with the stdin `--config -` auth channel stripped => anonymous => 401 => exit 3, no ping
# (proves the auth channel — formerly `-u` — is load-bearing).
STRIP_U="$TMP/probe-no-u.sh"
sed 's/ -m 10 --config - "http/ -m 10 "http/' "$SUT" > "$STRIP_U"
assert "(b) the strip actually removed the auth channel from the probe curl" \
  "grep -q \" -s -o /dev/null -w\" '$STRIP_U' && ! grep -qF -e '--config - \"http' '$STRIP_U' && ! cmp -s '$SUT' '$STRIP_U'"
run_probe "$STRIP_U" known/repo
assert "(b) auth channel stripped => anonymous => 401 => NO ping" "[[ '$PINGED' == no ]]"
assert "(b) auth channel stripped => exit 3 (HARD failure — proves the auth channel is load-bearing)" "[[ '$EC' -eq 3 ]]"
assert "(b) auth channel stripped => reports the auth-broke hard failure" "grep -q 'HARD FAILURE: 401' <<<\"\$OUT\""

# (c) COPY with `-f` injected into the probe curl => the 404 code capture is corrupted
# (curl prints '404' then exits non-zero => `|| echo 000` appends => CODE=404000), so the
# clean 404 classification is destroyed (proves the ABSENCE of -f is load-bearing).
FORCE_F="$TMP/probe-force-f.sh"
sed 's| -s -o /dev/null -w| -sf -o /dev/null -w|' "$SUT" > "$FORCE_F"
assert "(c) the -f injection actually added -f to the probe curl" \
  "grep -qF -e \"'*' -sf -o /dev/null -w\" '$FORCE_F'"
run_probe "$FORCE_F" nonexistent/repo
assert "(c) -f injected => the 404 classification is DESTROYED (no EMPTY/DETACHED verdict)" \
  "! grep -q 'EMPTY/DETACHED' <<<\"\$OUT\""
assert "(c) -f injected => the corrupted code lands in the unexpected-code branch" \
  "grep -q 'unexpected code' <<<\"\$OUT\""
assert "(c) -f injected => still no ping (never green over a corrupted verdict)" "[[ '$PINGED' == no ]]"

# --- credential channel: stdin config, never argv (argv is readable by every local user) -------
# A stub `curl` on PATH records its argv and drains its stdin, then answers 200. The real-registry rows
# above prove the stdin `user =` line authenticates end to end; these prove WHERE the credential rides
# and that an unsafe value is refused before any curl runs.
echo "--- credential channel: argv clean, stdin exact; unsafe values refused ---"
mkdir -p "$TMP/stubbin"
cat > "$TMP/stubbin/curl" <<'STUBCURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_ARGV"
cfg=0; for a in "$@"; do [[ "$a" == "--config" ]] && cfg=1; done
[[ "$cfg" == 1 ]] && cat >> "$STUB_STDIN"
printf '200'
STUBCURL
chmod +x "$TMP/stubbin/curl"
run_stub() {  # <ZUSER> <ZTOK> [repo list] -> EC / PINGED / OUT / SARGV / SSTDIN (files)
  local pinglog outf ec=0
  SARGV="$(mktemp "$TMP/sargv.XXXXXX")"; SSTDIN="$(mktemp "$TMP/sstdin.XXXXXX")"
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  STUB_ARGV="$SARGV" STUB_STDIN="$SSTDIN" PATH="$TMP/stubbin:$PATH" \
    SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
    ZOT_ENDPOINT="127.0.0.1:9" ZOT_PROBE_REPO="${3:-known/repo}" ZUSER="$1" ZTOK="$2" \
    timeout 20 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}
run_stub zuser synthetic-fixture-token-0001
assert "(f) valid credential => probe ran, 200 => ping, exit 0" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
assert "(f) the credential is NOT on curl's argv (neither user nor token)" \
  "[[ -s '$SARGV' ]] && ! grep -qF -e synthetic-fixture-token-0001 -e zuser '$SARGV' && ! grep -qF -e ' -u ' '$SARGV'"
assert "(f) the argv asks curl to read its config from stdin" "grep -qF -e '--config - ' '$SARGV'"
assert "(f) stdin carries exactly one config line: user = \"zuser:<token>\"" \
  "[[ \"\$(cat '$SSTDIN')\" == 'user = \"zuser:synthetic-fixture-token-0001\"' && \"\$(wc -l < '$SSTDIN')\" -eq 1 ]]"

# Unsafe values (a quote or backslash would close/escape the quoted config string; a newline would inject
# a second directive) are refused with the SAME FATAL exit 1 as an unset credential, BEFORE curl runs,
# and the value is never echoed.
unsafe_row() {  # <label> <ZUSER> <ZTOK> <must-not-echo>
  run_stub "$2" "$3"
  assert "(g) $1 => FATAL exit 1, no ping" "[[ '$EC' -eq 1 && '$PINGED' == no ]] && grep -q 'FATAL: ZOT_PULL_USER/ZOT_PULL_TOKEN contains a character' <<<\"\$OUT\""
  assert "(g) $1 => curl never invoked (nothing sent)" "[[ ! -s '$SARGV' && ! -s '$SSTDIN' ]]"
  # Not via assert(): the value carries quotes/backslashes that would break its eval'd condition string.
  if grep -qF -e "$4" <<<"$OUT"; then FAIL=$((FAIL + 1)); echo "  FAIL: (g) $1 => the value is not echoed (it WAS echoed)"
  else PASS=$((PASS + 1)); echo "  PASS: (g) $1 => the value is not echoed"; fi
}
unsafe_row "token with a double quote" zuser 'synthetic"fixture' 'synthetic"fixture'
unsafe_row "token with a backslash"    zuser 'synthetic\fixture' 'synthetic\fixture'
unsafe_row "token with a newline (directive injection)" zuser $'synthetic\nurl = "http://evil.invalid/"' 'evil.invalid'
unsafe_row "user with a double quote"  'zu"ser' synthetic-fixture-token-0001 'zu"ser'

# Mutation proof: the same rows must RED against a copy that carries the credential on argv again.
ARGV_MUT="$TMP/probe-argv.sh"
sed 's| --config - "http| -u "$ZUSER:$ZTOK" "http|; s|< <(printf .user = "%s:%s"\\n. "$ZUSER" "$ZTOK") ||' "$SUT" > "$ARGV_MUT"
SUT_REAL="$SUT"; SUT="$ARGV_MUT"; run_stub zuser synthetic-fixture-token-0001; SUT="$SUT_REAL"
assert "(h) mutation check: the argv form of the probe IS caught by the (f) argv assertion" \
  "grep -qF -e synthetic-fixture-token-0001 '$SARGV'"

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
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'webhook-deploy' >/dev/null"
assert "zot .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'DOPPLER_CONFIG_DIR' >/dev/null"
assert "zot .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c '/tmp/.doppler' >/dev/null"
assert "zot .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -cE '^PrivateTmp=true' >/dev/null '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal DOPPLER_TOKEN= — otherwise
# dropping the key arg (empty token = the #6548 bug) still matches (test-design review).
assert "server.tf zot_consumer_probe_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-zot-consumer-probe" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-zot-consumer-probe' '$SERVER_TF'"
# Cross-cutting: dedicated read-scoped token (least-privilege; NOT the full-prd var.doppler_token).
assert "doppler_service_token.web_probes resource exists" \
  "grep -qE 'resource \"doppler_service_token\" \"web_probes\"' '$TOKEN_TF'"
assert "web_probes token is read-scoped (access=\"read\") + soleur/prd config" \
  "awk '/\"doppler_service_token\" \"web_probes\"/,/^}/' '$TOKEN_TF' | grep -cE 'access[[:space:]]*=[[:space:]]*\"read\"' >/dev/null"
assert "web_probes token is scoped to config \"prd\" (the probes run doppler --config prd)" \
  "awk '/\"doppler_service_token\" \"web_probes\"/,/^}/' '$TOKEN_TF' | grep -cE 'config[[:space:]]*=[[:space:]]*\"prd\"' >/dev/null"
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
    SOLEUR_PROBE_CANARY_MARKER="$CANARY_MARKER" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
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

# --- #7103 R3 (4.3): --canary-only runs WITHOUT the credentials the probe otherwise demands ---
# This is the mode the unit's ExecStartPre invokes, outside the `doppler run` wrapper. It has to
# work with ZOT_PULL_USER/ZOT_PULL_TOKEN and ZOT_PROBE_REPO all unset, because the entire point
# is to emit the Source-4 positive control on a host whose prd token is dead — the state in
# which the canary matters most and, before this, was the one state it could not reach.
#
# Asserted behaviourally, not just as source ordering: a guard added above the flag check would
# leave the ordering assertion in journald-config.test.sh green while turning this into a
# silent no-op that the operator would read as a dead vector agent.
rm -f "$CANARY_MARKER"
CANARY_ONLY_OUT="$(mktemp "$TMP/canaryonly.XXXXXX")"
CANARY_ONLY_RC=0
env -u ZOT_PULL_USER -u ZOT_PULL_TOKEN -u ZUSER -u ZTOK -u ZOT_PROBE_REPO \
  SOLEUR_PROBE_CANARY_MARKER="$CANARY_MARKER" \
  bash "$SUT" --canary-only >/dev/null 2>"$CANARY_ONLY_OUT" || CANARY_ONLY_RC=$?
assert "--canary-only EMITS the canary with no credentials present (the dead-token case)" \
  "grep -q 'SOLEUR_PROBE_CANARY' '$CANARY_ONLY_OUT'"
assert "--canary-only exits 0 rather than tripping the credential FATAL guard" \
  "[[ '$CANARY_ONLY_RC' == '0' ]]"
# It must not run the probe itself — no HTTP verdict, no heartbeat ping.
assert "--canary-only does NOT emit a zot serviceability verdict (it is a beacon, not a probe run)" \
  "! grep -qE 'servable|UNREACHABLE|SUPPRESS' '$CANARY_ONLY_OUT'"
# And it shares the rate-limit, so wiring it as ExecStartPre alongside the in-probe call does
# not double the emit rate against the Better Stack quota.
CANARY_ONLY_OUT2="$(mktemp "$TMP/canaryonly2.XXXXXX")"
env -u ZOT_PULL_USER -u ZOT_PULL_TOKEN -u ZUSER -u ZTOK -u ZOT_PROBE_REPO \
  SOLEUR_PROBE_CANARY_MARKER="$CANARY_MARKER" \
  bash "$SUT" --canary-only >/dev/null 2>"$CANARY_ONLY_OUT2" || true
assert "--canary-only honours the same rate-limit marker (no double emit as ExecStartPre)" \
  "! grep -q 'SOLEUR_PROBE_CANARY' '$CANARY_ONLY_OUT2'"

# ===== #7258 Step A: the probe takes a comma-separated repository list (all-must-pass) ==========
# One heartbeat per host stays; it is pinged iff EVERY non-empty element classifies 200. A 401 on any
# element exits 3. Every fault line names its repo, and a rate-limited per-repo marker proves a
# healthy run per repository from telemetry. Codes are injected through the POSITIONAL override seam.
echo "--- #7258: comma-separated repository list, all-must-pass aggregation ---"
WEB_R=web/repo
BOOT_R=boot/repo
run_override_multi() {  # <repo list> <positional codes> [marker file] -> EC / PINGED / MOUT (stderr) / FAULTS (fault lines only)
  local repos="$1" codes="$2" pinglog ec=0 rmark
  MARKER_N=$((MARKER_N + 1))
  rmark="${3:-$TMP/repos.$MARKER_N}"
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; MOUT="$(mktemp "$TMP/mout.XXXXXX")"; FAULTS="$(mktemp "$TMP/faults.XXXXXX")"
  SOLEUR_ZOT_PROBE_STATUS_OVERRIDE="$codes" SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" \
    SOLEUR_PROBE_REPOS_MARKER="$rmark" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.m$MARKER_N" \
    ZOT_ENDPOINT=127.0.0.1:1 ZOT_PROBE_REPO="$repos" ZUSER=u ZTOK=t \
    bash "$SUT" >/dev/null 2>"$MOUT" || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes
  grep -F -e 'SUPPRESS' -e 'HARD FAILURE' "$MOUT" > "$FAULTS" || true
}
# Marker lines name BOTH repos on every run, so fault-line assertions read FAULTS (SUPPRESS / HARD
# FAILURE lines only), never MOUT; marker assertions read MOUT.
has_marker() {  # <repo> <code> <verdict>
  grep -qE "SOLEUR_ZOT_PROBE_REPO repo=$1 code=$2 verdict=$3 ts=[0-9]+\$" "$MOUT"
}
count_markers() { local n; n=$(grep -c 'SOLEUR_ZOT_PROBE_REPO ' "$MOUT" || true); printf '%s' "$n"; }
faults_name() { grep -qF "repo=$1" "$FAULTS"; }

# T1 — both servable => ping, exit 0, a marker per repo.
run_override_multi "$WEB_R,$BOOT_R" 200,200
assert "T1 200,200 => ping logged"                         "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
assert "T1 200,200 => marker for the web repo (servable)"   "has_marker $WEB_R 200 servable"
assert "T1 200,200 => marker for the bootstrap repo (servable)" "has_marker $BOOT_R 200 servable"
assert "T1 200,200 => exactly two marker lines"             "[[ \"\$(count_markers)\" -eq 2 ]]"
assert "T1 200,200 => no fault line at all"                 "[[ ! -s '$FAULTS' ]]"
# H2 — a must-PASS non-canonical input: the trailing comma the contract explicitly permits.
run_override_multi "$WEB_R,$BOOT_R," 200,200
assert "H2 trailing comma with every element 200 => still pings" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"

# T2 — one faulting repo suppresses the ping, and the fault line names THAT repo only.
run_override_multi "$WEB_R,$BOOT_R" 200,404
assert "T2 200,404 => NO ping (a conjunction cannot mask)"  "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
assert "T2 200,404 => the SUPPRESS line names the bootstrap repo" "faults_name $BOOT_R"
assert "T2 200,404 => no fault line names the web repo"     "! faults_name $WEB_R"
assert "T2 200,404 => keeps the EMPTY/DETACHED prefix"      "grep -qF 'EMPTY/DETACHED' '$FAULTS'"
assert "T2 200,404 => markers carry each repo's own verdict" "has_marker $WEB_R 200 servable && has_marker $BOOT_R 404 empty"

# T3 — reversed order and the other fault classes.
run_override_multi "$WEB_R,$BOOT_R" 404,200
assert "T3 404,200 => NO ping (reversed order)"             "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
assert "T3 404,200 => the fault line names the web repo, not the bootstrap repo" "faults_name $WEB_R && ! faults_name $BOOT_R"
run_override_multi "$WEB_R,$BOOT_R" 200,000
assert "T3 200,000 => NO ping, UNREACHABLE verdict naming the bootstrap repo" "[[ '$PINGED' == no ]] && grep -qF 'UNREACHABLE' '$FAULTS' && faults_name $BOOT_R"
run_override_multi "$WEB_R,$BOOT_R" 200,503
assert "T3 200,503 => NO ping, WEDGED verdict naming the bootstrap repo" "[[ '$PINGED' == no ]] && grep -qF 'WEDGED' '$FAULTS' && faults_name $BOOT_R"
run_override_multi "$WEB_R,$BOOT_R" 200,302
assert "T3 200,302 => NO ping (catch-all), unexpected-code line naming the bootstrap repo" "[[ '$PINGED' == no ]] && grep -qF 'unexpected code 302' '$FAULTS' && faults_name $BOOT_R"

# T4 — a 401 on EITHER position is HARD (exit 3), no ping, and the other repo's line is still emitted.
run_override_multi "$WEB_R,$BOOT_R" 200,401
assert "T4 200,401 => exit 3, NO ping"                       "[[ '$EC' -eq 3 && '$PINGED' == no ]]"
assert "T4 200,401 => HARD FAILURE names the bootstrap repo" "grep -F 'HARD FAILURE: 401' '$FAULTS' >/dev/null && faults_name $BOOT_R && ! faults_name $WEB_R"
assert "T4 200,401 => the OTHER repo is still probed and its marker emitted" "has_marker $WEB_R 200 servable"
assert "T4 200,401 => the 401 repo's marker is emitted BEFORE the exit" "has_marker $BOOT_R 401 auth-broke"
run_override_multi "$WEB_R,$BOOT_R" 401,200
assert "T4 401,200 => exit 3, NO ping"                       "[[ '$EC' -eq 3 && '$PINGED' == no ]]"
assert "T4 401,200 => the second repo is NOT skipped by an early exit (marker present)" "has_marker $BOOT_R 200 servable && has_marker $WEB_R 401 auth-broke"
run_override_multi "$WEB_R,$BOOT_R" 401,404
assert "T4 401,404 => 401 wins over another fault: exit 3" "[[ '$EC' -eq 3 && '$PINGED' == no ]]"
run_override_multi "$WEB_R,$BOOT_R" 404,401
assert "T4 404,401 => 401 wins over another fault: exit 3" "[[ '$EC' -eq 3 && '$PINGED' == no ]]"

# T5 — the positional seam over the NON-EMPTY elements, in order.
run_override_multi "$WEB_R" 200
assert "T5 one repo, one code => the pre-change behaviour (ping, exit 0)" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
run_override_multi "$WEB_R,$BOOT_R" 200
assert "T5 two repos, one override code => the missing position reads 000: NO ping" "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
assert "T5 => the unlisted position is the UNREACHABLE verdict for the bootstrap repo" "grep -qF 'UNREACHABLE' '$FAULTS' && faults_name $BOOT_R"
run_override_multi "a/x,,b/y" 200,200
assert "T5 a/x,,b/y with 200,200 => both probed in non-empty order, ping" "[[ '$PINGED' == yes ]] && has_marker a/x 200 servable && has_marker b/y 200 servable"

# T6 — nothing to probe, or an element that cannot be put in a URL, is FATAL before any curl/ping/marker.
run_override_multi ",," 200,200
assert "T6 ',,' (no non-empty element) => FATAL exit 1"      "[[ '$EC' -eq 1 && '$PINGED' == no ]] && grep -qF 'FATAL' '$MOUT'"
assert "T6 ',,' => no marker line and no marker file"        "[[ \"\$(count_markers)\" -eq 0 && ! -e '$TMP/repos.$MARKER_N' ]]"
run_override_multi "a/b, c/d" 200,200
assert "T6 an element containing whitespace => FATAL exit 1, no ping" "[[ '$EC' -eq 1 && '$PINGED' == no ]] && grep -qF 'FATAL' '$MOUT'"
assert "T6 whitespace element => no marker line"             "[[ \"\$(count_markers)\" -eq 0 ]]"
run_stub zuser synthetic-fixture-token-0001 "a/b, c/d"
assert "T6 whitespace element => curl was never invoked (no URL built from it)" "[[ '$EC' -eq 1 && ! -s '$SARGV' && ! -s '$SSTDIN' ]]"
run_override_multi "a/b,c/d," 200,200
assert "T6b a/b,c/d, (trailing comma) with 200,200 => ping, exit 0" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"

# T7 — static (Guard 2): the probed list is exactly {the repo derived from var.image_name, the repo the
# hosts pull at boot}. The expected path is DERIVED from the ZIREF pins, never restated here.
echo "--- #7258: static parity — the probed list equals the repos the hosts pull ---"
PROBE_TF="$SCRIPT_DIR/web-probe.tf"
CLOUD_INIT_WEB="$SCRIPT_DIR/cloud-init.yml"
CLOUD_INIT_INNGEST="$SCRIPT_DIR/cloud-init-inngest.yml"
pin_path_of() {  # <file> -> the repository path of its ZIREF pin (empty when none)
  sed -n 's|^[[:space:]]*ZIREF="[^/]*/\([^:@"]*\)[:@].*|\1|p' "$1"
}
tf_const() {  # <file> -> the bootstrap-repo constant in web-probe.tf locals
  sed -n 's|^[[:space:]]*zot_probe_repo_inngest_bootstrap[[:space:]]*=[[:space:]]*"\([^"]*\)".*|\1|p' "$1"
}
PIN_WEB="$(pin_path_of "$CLOUD_INIT_WEB")"
PIN_INGEST="$(pin_path_of "$CLOUD_INIT_INNGEST")"
TF_BOOT="$(tf_const "$PROBE_TF")"
# Non-vacuity: the extractions are non-empty AND independent of the constant under test.
assert "T7 the cloud-init.yml ZIREF pin path was extracted (non-empty)"          "[[ -n '$PIN_WEB' ]]"
assert "T7 the cloud-init-inngest.yml ZIREF pin path was extracted (non-empty)"  "[[ -n '$PIN_INGEST' ]]"
assert "T7 the two hosts' pins name the same repository"                         "[[ '$PIN_WEB' == '$PIN_INGEST' ]]"
assert "T7 web-probe.tf declares the bootstrap-repo constant (non-empty)"        "[[ -n '$TF_BOOT' ]]"
assert "T7 the constant equals the repository path both hosts pull at boot"      "[[ '$TF_BOOT' == '$PIN_WEB' && '$TF_BOOT' == '$PIN_INGEST' ]]"
assert "T7 the web repo is still derived from var.image_name" \
  "grep -qE '^[[:space:]]*zot_probe_repo_web[[:space:]]*=[[:space:]]*regex\\(\"\\^\\[\\^:@\\]\\+\", replace\\(var\\.image_name' '$PROBE_TF'"
assert "T7 local.zot_probe_repo is EXACTLY the comma join of those two (a two-element set, not a floor)" \
  "grep -qE '^[[:space:]]*zot_probe_repo[[:space:]]*=[[:space:]]*join\\(\",\", \\[local\\.zot_probe_repo_web, local\\.zot_probe_repo_inngest_bootstrap\\]\\)[[:space:]]*\$' '$PROBE_TF'"
assert "T7 no new root variable carries the repo (variables.tf is a registry-replace trigger path)" \
  "! grep -qF 'variable \"inngest_bootstrap_repo\"' '$SCRIPT_DIR/variables.tf'"
# H3 — the extraction helper is driven against a synthetic fixture whose pin names a DIFFERENT, consistent
# repo: it must return THAT path (so the check cannot be a self-comparison with the constant).
PIN_FIXTURE="$(mktemp "$TMP/pinfix.XXXXXX")"
# shellcheck disable=SC2016  # the literal $ZURL is the fixture text, not an expansion
printf '    ZIREF="$ZURL/acme/other-repo:v9.9.9@sha256:%064d"\n' 0 > "$PIN_FIXTURE"
assert "H3 the pin-extraction helper reads the fixture's own repository path (not the constant)" \
  "[[ \"\$(pin_path_of '$PIN_FIXTURE')\" == 'acme/other-repo' ]]"
printf '    NOT_A_PIN="x"\n' > "$PIN_FIXTURE"
assert "H3 a file with no pin yields an EMPTY extraction (the non-empty guard has something to catch)" \
  "[[ -z \"\$(pin_path_of '$PIN_FIXTURE')\" ]]"

# T8 — behavioural, against the mock registry that now serves known/repo AND known/second.
echo "--- #7258: behavioural, two repositories against the mock registry ---"
run_probe "$SUT" "known/repo,known/second"
assert "T8 both repositories served => ping, exit 0"   "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
run_probe "$SUT" "known/repo,nonexistent/repo"
assert "T8 known/repo,nonexistent/repo => NO ping"     "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
assert "T8 => the EMPTY/DETACHED verdict names the nonexistent repo" "grep -qF 'EMPTY/DETACHED for nonexistent/repo' <<<\"\$OUT\""
run_probe "$SUT" "nonexistent/repo,known/repo"
assert "T8 nonexistent/repo,known/repo (reversed) => NO ping" "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second"
assert "T8 stub curl: both repos probed, ping, exit 0"   "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
assert "T8 stub curl: invoked exactly once per repo"     "[[ \"\$(wc -l < '$SARGV')\" -eq 2 ]]"
assert "T8 stub curl: each repo's tag-list URL was requested" "grep -qF '/v2/known/repo/tags/list' '$SARGV' && grep -qF '/v2/known/second/tags/list' '$SARGV'"
assert "T8 stub curl: no argv carries the credential, on either request" \
  "! grep -qF -e synthetic-fixture-token-0001 -e zuser '$SARGV' && ! grep -qF -e ' -u ' '$SARGV'"
assert "T8 stub curl: each request's stdin is exactly one user = line (two lines in all, identical)" \
  "[[ \"\$(wc -l < '$SSTDIN')\" -eq 2 && \"\$(sort -u '$SSTDIN')\" == 'user = \"zuser:synthetic-fixture-token-0001\"' ]]"

# T9 — the per-repo marker: fields, rate limit, and a corrupt/future-dated marker file fails toward EMITTING.
echo "--- #7258: per-repo marker line, rate limit ---"
MK="$TMP/repos.t9"
rm -f "$MK"
run_override_multi "$WEB_R,$BOOT_R" 200,404 "$MK"
assert "T9 first run emits one marker per repo, any verdict" "[[ \"\$(count_markers)\" -eq 2 ]] && has_marker $WEB_R 200 servable && has_marker $BOOT_R 404 empty"
run_override_multi "$WEB_R,$BOOT_R" 200,200 "$MK"
assert "T9 a second run inside the window emits NO marker (rate limit)" "[[ \"\$(count_markers)\" -eq 0 ]]"
marker_row() {  # <label> <@missing|@empty|content>
  case "$2" in
    @missing) rm -f "$MK" ;;
    @empty)   : > "$MK" ;;
    *)        printf '%s\n' "$2" > "$MK" ;;
  esac
  run_override_multi "$WEB_R,$BOOT_R" 200,200 "$MK"
  assert "T9 marker file $1 => the markers ARE emitted (never silence)" "[[ \"\$(count_markers)\" -eq 2 ]]"
}
marker_row "missing" "@missing"
marker_row "empty" "@empty"
marker_row "garbage (non-numeric)" "not-a-number"
marker_row "future-dated (numeric, later than now)" "$(( $(date +%s) + 99999 ))"
marker_row "an hour old (past the 1800 s window)" "$(( $(date +%s) - 3600 ))"
printf '%s\n' "$(date +%s)" > "$MK"
run_override_multi "$WEB_R,$BOOT_R" 200,200 "$MK"
assert "T9 a fresh numeric marker inside the window => NO markers (the control for the rows above)" "[[ \"\$(count_markers)\" -eq 0 ]]"
# The shared window helper also fixes the canary: a numeric FUTURE-dated canary marker used to read as
# fresh forever (now - last is negative), a silent-canary defect; it must now emit.
CANARY_FUT="$TMP/canary.future"
printf '%s\n' "$(( $(date +%s) + 99999 ))" > "$CANARY_FUT"
FUT_OUT="$(mktemp "$TMP/canaryfut.XXXXXX")"; FUT_PL="$(mktemp "$TMP/ping.XXXXXX")"
SOLEUR_ZOT_PROBE_STATUS_OVERRIDE=200 SOLEUR_ZOT_PROBE_PING_LOG="$FUT_PL" \
  SOLEUR_PROBE_CANARY_MARKER="$CANARY_FUT" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" \
  ZOT_PROBE_REPO=known/repo ZUSER=u ZTOK=t bash "$SUT" >/dev/null 2>"$FUT_OUT" || true
assert "T9 a FUTURE-dated canary marker emits the canary (the latent silent-canary defect)" \
  "grep -qF 'SOLEUR_PROBE_CANARY' '$FUT_OUT'"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
