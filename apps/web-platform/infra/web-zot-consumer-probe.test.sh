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
# #7258: ZOT_PROBE_REPO is a COMMA-SEPARATED LIST. The T1-T16 rows below cover all-must-pass
# aggregation (one ping per host, only when every repo is 200), the fault-line repo= suffix, the
# per-repo SOLEUR_ZOT_PROBE_VERDICT marker and its 30 min window, list parsing (empty elements, a newline,
# an OCI-name alphabet), and Guard 2: the probed list equals the repos the hosts pull AND the value
# reaches the probe through every writer unchanged (server.tf, cloud-init.yml, web-probe-envwrite.sh).
#
# #10004: a ZOT_PROBE_REPO element may be `repo@sha256:<64 hex>`; the P-rows below cover the pinned-manifest HEAD
# (aggregation across positions, the skip rule, the request shape, the digest grammar) against the same mock registry
# (its HEAD digest table: a=200 b=404 c=403 d=503) and a stub curl (STUB_TAGS_CODE / STUB_MANIFEST_CODE / _ONLY),
# and the H-rows prove the instruments can fail. Guard 2 below holds for web-1 only: web-1's two server.tf writers
# carry the PINNED local, while the cloud-init template var keeps the BARE one so no born host bakes a pin.
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

# Instrument self-test (ADR-193): drive assert() with a condition that must FAIL and refuse to continue
# unless the FAIL counter moved; a disarmed assert() would otherwise report every row green. Reported with
# printf and exit, never through assert(), and the counters are restored so the totals are unaffected.
_PF=$FAIL; assert "instrument self-test (expected FAIL, discarded)" "false" >/dev/null
if [[ "$FAIL" -ne $((_PF + 1)) ]]; then printf 'FAIL: assert() cannot fail — the suite is disarmed\n'; exit 1; fi
FAIL=$_PF

TMP="$(mktemp -d)"
SRV_PID=""
# Every helper gets its OWN repos-marker path (a root CI runner would otherwise share /run state
# between rows and a second row would silently inherit the first one's rate-limit window).
MARKER_N=0
H1_PID=""
cleanup() { rm -rf "$TMP"; [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null; [[ -n "$H1_PID" ]] && kill "$H1_PID" 2>/dev/null; return 0; }
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
    SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
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
# #10004: manifest HEAD table. The digest decides the code (a=served, b=evicted, c=403, d=503); every
# request (method + path) is appended to the log file argv[2], so a row can assert WHICH request the probe sent.
DIG = {"a": 200, "b": 404, "c": 403, "d": 503}
LOG = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def do_HEAD(self):
        with open(LOG, "a") as f:
            f.write("HEAD " + self.path + "\n")
        if self.headers.get("Authorization", "") != EXPECT:
            self.send_response(401); self.end_headers(); return
        parts = self.path.split("/")
        if len(parts) == 6 and parts[1] == "v2" and parts[2] == "known" and parts[4] == "manifests" \
           and parts[3] in ("repo", "second") and parts[5].startswith("sha256:") and len(parts[5]) == 71:
            self.send_response(DIG.get(parts[5][7], 404)); self.end_headers(); return
        self.send_response(404); self.end_headers()
    def do_GET(self):
        with open(LOG, "a") as f:
            f.write("GET " + self.path + "\n")
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
REQLOG="$TMP/mock_requests.log"; : > "$REQLOG"
python3 "$SRV_PY" "$PORT_FILE" "$REQLOG" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
assert "mock registry published its port" "[[ -s '$PORT_FILE' ]]"
PORT="$(cat "$PORT_FILE" 2>/dev/null || true)"

# EC / PINGED / OUT for a real probe against the mock (no status override).
run_probe() {  # <script> <repo>
  local script="$1" repo="$2" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" SOLEUR_PROBE_VERBOSE=1 \
    SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
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
SOLEUR_ZOT_PROBE_PING_LOG="$DEAD_PING" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
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
  "grep -qF -e \" -sf -o /dev/null -w\" '$FORCE_F'"
run_probe "$FORCE_F" nonexistent/repo
assert "(c) -f injected => the 404 classification is DESTROYED (no EMPTY/DETACHED verdict)" \
  "! grep -q 'EMPTY/DETACHED' <<<\"\$OUT\""
assert "(c) -f injected => the corrupted code lands in the unexpected-code branch" \
  "grep -q 'unexpected code' <<<\"\$OUT\""
assert "(c) -f injected => still no ping (never green over a corrupted verdict)" "[[ '$PINGED' == no ]]"

# #10004: ONE request function serves tags/list and the pinned-manifest HEAD, so the three mutants above land on
# BOTH requests with a single edit: prove there is exactly one site carrying each matched text, then prove the
# -f injection destroys the HEAD classification too (a 404 pin must not read as MISSING under -f).
assert "(i) the probe has exactly ONE curl request site (each mutant text occurs once, so (b)/(c)/(h) land on tags/list AND the HEAD)" \
  "[[ \"\$(grep -cF -e ' -s -o /dev/null -w' '$SUT')\" -eq 1 && \"\$(grep -cF -e ' -m 10 --config - \"http' '$SUT')\" -eq 1 ]]"
run_probe "$FORCE_F" "known/repo,known/second@sha256:$(printf '%064d' 0 | tr 0 b)"
assert "(c) -f injected => the HEAD of an evicted pin is NOT classified as MISSING (the 404 is corrupted to 404000)" \
  "! grep -qF 'is MISSING' <<<\"\$OUT\" && grep -qF 'unexpected code 404000' <<<\"\$OUT\" && [[ '$PINGED' == no ]]"

# --- credential channel: stdin config, never argv (argv is readable by every local user) -------
# A stub `curl` on PATH records its argv and drains its stdin, then answers 200. The real-registry rows
# above prove the stdin `user =` line authenticates end to end; these prove WHERE the credential rides
# and that an unsafe value is refused before any curl runs.
echo "--- credential channel: argv clean, stdin exact; unsafe values refused ---"
mkdir -p "$TMP/stubbin"
cat > "$TMP/stubbin/curl" <<'STUBCURL'
#!/usr/bin/env bash
# Heartbeat call (#9757): `-o /dev/null` and NO `-w`. It prints nothing, honours -f against STUB_HB_CODE, fails on
# demand (STUB_HB_RC for every attempt, STUB_HB_FAIL_FIRST=1 for the first attempt only), and is recorded to its OWN
# files (STUB_HB_ARGV / STUB_HB_STDIN) so the registry request's `user = "..."` stdin in STUB_STDIN is never confused
# with the heartbeat's `url = "..."` stdin. STUB_HB_NOSTDIN=1 makes it ignore its stdin (the instrument control).
hb=0; hbw=0; hbcfg=0; hbprev=""
for a in "$@"; do
  [[ "$a" == -w ]] && hbw=1
  [[ "$hbprev" == -o && "$a" == /dev/null ]] && hb=1
  [[ "$a" == --config ]] && hbcfg=1
  hbprev="$a"
done
if [[ "$hb" == 1 && "$hbw" == 0 ]]; then
  printf '%s\n' "$*" >> "${STUB_HB_ARGV:-/dev/null}"
  [[ -n "${STUB_HB_ENVDUMP:-}" ]] && env | grep -E '^URL=|uptime\.betterstack\.test' > "$STUB_HB_ENVDUMP"   # filtered by VALUE (any name holding the URL is kept), never the whole ambient environment
  [[ "$hbcfg" == 1 && "${STUB_HB_NOSTDIN:-}" != 1 ]] && cat >> "${STUB_HB_STDIN:-/dev/null}"
  hbn=$(wc -l < "${STUB_HB_ARGV:-/dev/null}")
  [[ "${STUB_HB_FAIL_FIRST:-}" == 1 && "$hbn" -eq 1 ]] && exit 7
  hbforce=0; for a in "$@"; do case "$a" in --*) ;; -*f*) hbforce=1 ;; esac; done
  [[ "$hbforce" == 1 && "$((10#${STUB_HB_CODE:-200}))" -ge 400 ]] && exit 22
  exit "${STUB_HB_RC:-0}"
fi
printf '%s\n' "$*" >> "$STUB_ARGV"
cfg=0; for a in "$@"; do [[ "$a" == "--config" ]] && cfg=1; done
[[ "$cfg" == 1 ]] && cat >> "$STUB_STDIN"
# #10004: the code is per request kind (STUB_TAGS_CODE for tags/list, STUB_MANIFEST_CODE for a manifest URL),
# and the stub honours what real curl does: -f (a short cluster containing f) turns a 4xx/5xx into NO output
# and exit 22, and a transport failure prints 000 AND exits non-zero (the `000000` shape the probe normalizes).
code=200; force=0
for a in "$@"; do
  case "$a" in
    --*) ;;
    -*f*) force=1 ;;
    */manifests/*)
      code="${STUB_MANIFEST_CODE:-200}"
      # STUB_MANIFEST_ONLY=<repo> confines STUB_MANIFEST_CODE to that repository's manifest URL (others answer 200).
      [[ -z "${STUB_MANIFEST_ONLY:-}" || "$a" == *"/v2/${STUB_MANIFEST_ONLY}/"* ]] || code=200 ;;
    */tags/list) code="${STUB_TAGS_CODE:-200}" ;;
  esac
done
if [[ "$force" == 1 && "$((10#$code))" -ge 400 ]]; then exit 22; fi
printf '%s' "$code"
[[ "$code" == 000 ]] && exit 7
exit 0
STUBCURL
chmod +x "$TMP/stubbin/curl"
run_stub() {  # <ZUSER> <ZTOK> [repo list] -> EC / PINGED / OUT / SARGV / SSTDIN (files)
  local pinglog outf ec=0
  SARGV="$(mktemp "$TMP/sargv.XXXXXX")"; SSTDIN="$(mktemp "$TMP/sstdin.XXXXXX")"
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  STUB_ARGV="$SARGV" STUB_STDIN="$SSTDIN" PATH="$TMP/stubbin:$PATH" \
    SOLEUR_ZOT_PROBE_PING_LOG="$pinglog" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$((++MARKER_N))" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
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

# --- heartbeat channel (#9757): the heartbeat URL reaches curl on its stdin config, never on argv --------------
# Every row above uses the ping-log seam, which returns BEFORE the transport, so none of them ever executed the
# heartbeat curl. These rows run with NO SOLEUR_ZOT_PROBE_PING_LOG: the stub answers the registry request 200 (the
# probe reaches _ping) and records each heartbeat call to its own files. The URL is judged BEFORE any request: a
# scheme other than https://, an empty rest, or any byte outside the allowed class is refused with ZERO heartbeat
# requests, one value-free SOLEUR_CREDENTIAL_REFUSED marker per hour (its OWN refusal stamp, never the canary's or
# the per-repo marker's; CTO ruling 2026-10-15) and the unchanged fail-soft exit status.
echo "--- heartbeat channel: stdin config, per-attempt, shape guard, refusal limiter (#9757) ---"
HB_GOOD='https://uptime.betterstack.test/api/v1/heartbeat/synthetic-zot-token'
HB_OTHER='https://uptime.betterstack.test/api/v1/heartbeat/A.b_c~d:9?x=1&y=%2B+z-Q'
HB_ARGV_FORM='--disable --noproxy * -gfsS -m 10 -o /dev/null --config -'
HB_MARKER_HEAD='SOLEUR_CREDENTIAL_REFUSED script=web-zot-consumer-probe'
# HEC / HB_ARGV / HB_STDIN / HB_REGARGV / HOUT (files) / HOUTTXT / N_HB (heartbeat curls) / N_MARK / N_WARN.
run_hb() {  # <resolved heartbeat URL value, delivered under the key-named variable> [extra env assignments, applied last so they win]
  local url="$1" ec=0; shift
  MARKER_N=$((MARKER_N + 1))
  HB_ARGV="$(mktemp "$TMP/hbargv.XXXXXX")"; HB_STDIN="$(mktemp "$TMP/hbstdin.XXXXXX")"
  HB_REGARGV="$TMP/hbreg.argv.$MARKER_N"; HOUT="$(mktemp "$TMP/hbout.XXXXXX")"
  env -u SOLEUR_ZOT_PROBE_PING_LOG -u SOLEUR_ZOT_PROBE_STATUS_OVERRIDE -u WEB_ZOT_CONSUMER_URL \
    STUB_ARGV="$HB_REGARGV" STUB_STDIN="$TMP/hbreg.stdin.$MARKER_N" STUB_HB_ARGV="$HB_ARGV" STUB_HB_STDIN="$HB_STDIN" \
    PATH="$TMP/stubbin:$PATH" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$MARKER_N" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
    SOLEUR_PROBE_REFUSAL_MARKER="$TMP/refusal.$MARKER_N" \
    ZOT_ENDPOINT=127.0.0.1:9 ZOT_PROBE_REPO=known/repo ZUSER=zuser ZTOK=ztok WEB_ZOT_CONSUMER_URL_KEY=WEB_ZOT_CONSUMER_URL_SYNTH "WEB_ZOT_CONSUMER_URL_SYNTH=$url" "$@" \
    timeout 20 bash "$SUT" >"$HOUT" 2>&1 || ec=$?
  HEC=$ec
  # shellcheck disable=SC2034  # read by NAME inside the assert() eval strings
  HOUTTXT="$(cat "$HOUT")"
  N_HB="$(wc -l < "$HB_ARGV" | tr -d ' ')"
  N_MARK="$(grep -c 'SOLEUR_CREDENTIAL_REFUSED' "$HOUT" || true)"
  N_WARN="$(grep -c 'heartbeat URL refused' "$HOUT" || true)"
}
hb_stdin_all_are() {  # <url>: at least one stdin line was recorded and every one is exactly url = "<url>"
  local want; want="$(printf 'url = "%s"' "$1")"
  [[ -s "$HB_STDIN" && "$(sort -u "$HB_STDIN")" == "$want" ]]
}
hb_stdin_lines() { wc -l < "$HB_STDIN" | tr -d ' '; }
hb_epoch_age() {  # <file> -> seconds since the epoch value it holds (empty when unreadable)
  local v; v="$(cat "$1" 2>/dev/null)" || return 0; [[ "$v" =~ ^[0-9]+$ ]] && printf '%s' "$(( $(date +%s) - v ))"
}

# (a) a well-formed https canary with a DIFFERENT token than the fixture, using every allowed punctuation class
run_hb "$HB_OTHER"
HB_BASE_EC="$HEC"
assert "(hb-a) well-formed https URL: exactly one heartbeat curl, exit 0" "[[ '$N_HB' -eq 1 && '$HEC' -eq 0 ]]"
assert "(hb-a) the heartbeat argv is exactly the --disable --noproxy * -gfsS -m 10 -o /dev/null --config - form (no URL word)" \
  "[[ -s '$HB_ARGV' ]] && grep -qxF -e '$HB_ARGV_FORM' '$HB_ARGV'"
assert "(hb-a) the URL is on no argv at all (neither the heartbeat's nor the registry request's)" \
  "[[ -s '$HB_REGARGV' ]] && ! grep -qF -e uptime -e betterstack -e heartbeat -e 'A.b_c' '$HB_ARGV' '$HB_REGARGV'"
assert "(hb-a) the heartbeat stdin is exactly one url = \"...\" line carrying the stored URL" \
  "[[ \"\$(hb_stdin_lines)\" -eq 1 ]] && hb_stdin_all_are '$HB_OTHER'"
assert "(hb-a) no marker and no WARN on a healthy ping" "[[ '$N_MARK' -eq 0 && '$N_WARN' -eq 0 ]] && ! grep -q 'WARN' <<<\"\$HOUTTXT\""

# (b) per-attempt stdin: a process substitution is consumed once, so attempt 2 needs its OWN fresh url line
run_hb "$HB_GOOD" STUB_HB_FAIL_FIRST=1
assert "(hb-b) first attempt fails => two attempts, two identical recorded url lines (the second did not read EOF)" \
  "[[ '$N_HB' -eq 2 && \"\$(hb_stdin_lines)\" -eq 2 ]] && hb_stdin_all_are '$HB_GOOD'"
assert "(hb-b) the second attempt succeeded: exit 0 and no FAILED warning" "[[ '$HEC' -eq 0 ]] && ! grep -q 'ping FAILED' <<<\"\$HOUTTXT\""
run_hb "$HB_GOOD" STUB_HB_RC=7
assert "(hb-b) both attempts fail => two curls, one FAILED warning, still fail-soft exit 0" \
  "[[ '$N_HB' -eq 2 && '$HEC' -eq 0 ]] && grep -q 'heartbeat ping FAILED' <<<\"\$HOUTTXT\""
# instrument control: a stub that ignores stdin records no url line, so the per-attempt row's predicate must be able to say NO
run_hb "$HB_GOOD" STUB_HB_FAIL_FIRST=1 STUB_HB_NOSTDIN=1
assert "(hb-b) instrument: a stub that ignores stdin makes the per-attempt predicate FAIL (two attempts, zero recorded lines)" \
  "[[ '$N_HB' -eq 2 ]] && ! hb_stdin_all_are '$HB_GOOD'"
run_hb "$HB_GOOD" STUB_HB_CODE=404
assert "(hb-b) the stub honours -f: a 404 heartbeat answer fails both attempts (curl exit 22) and the probe stays fail-soft" \
  "[[ '$N_HB' -eq 2 && '$HEC' -eq 0 ]] && grep -q 'heartbeat ping FAILED' <<<\"\$HOUTTXT\""

# (c) hostile and malformed values: ONE defect per row (a good URL plus one bad thing), defined ONCE as parallel arrays
HB_BAD_LABEL=(); HB_BAD_REASON=(); HB_BAD_VAL=()
hb_bad() { HB_BAD_LABEL+=("$1"); HB_BAD_REASON+=("$2"); HB_BAD_VAL+=("$3"); }
hb_bad 'an empty rest (https://)'                token_shape 'https://'
hb_bad 'a scheme other than https (http://)'     token_shape "http://${HB_GOOD#https://}"
hb_bad 'an uppercase scheme (HTTPS://)'          token_shape "HTTPS://${HB_GOOD#https://}"
hb_bad 'a leading space'                         token_shape " ${HB_GOOD}"
hb_bad 'a trailing space'                        token_shape "${HB_GOOD} "
hb_bad 'a double quote'                          token_shape "${HB_GOOD}\""
hb_bad 'a single quote'                          token_shape "${HB_GOOD}'"
hb_bad 'a backslash'                             token_shape "${HB_GOOD}\\x"
hb_bad 'a newline then a smuggled url = directive' control_char "${HB_GOOD}"$'\n''url = "http://203.0.113.1/smuggled"'
hb_bad 'a carriage return'                       control_char "${HB_GOOD}"$'\r'
hb_bad 'a tab'                                   control_char "${HB_GOOD}"$'\t'
hb_bad 'a semicolon'                             token_shape "${HB_GOOD};x"
hb_bad 'a dollar sign'                           token_shape "${HB_GOOD}\$x"
hb_bad 'a backtick'                              token_shape "${HB_GOOD}\`x"
hb_bad 'an at sign (userinfo)'                   token_shape "https://u@${HB_GOOD#https://}"
hb_bad 'a hash'                                  token_shape "${HB_GOOD}#x"
HB_BAD_N=16
hb_bad_distinct() { printf '%s\0' "${HB_BAD_VAL[@]}" | sort -zu | tr -cd '\0' | wc -c | tr -d ' '; }
hb_bad_with_token() { local v n=0; for v in "${HB_BAD_VAL[@]}"; do [[ "$v" == *synthetic-zot-token* ]] && n=$((n + 1)); done; printf '%s' "$n"; }
hb_bad_cntrl_vals() { local v n=0; for v in "${HB_BAD_VAL[@]}"; do [[ "$v" == *[[:cntrl:]]* ]] && n=$((n + 1)); done; printf '%s' "$n"; }
hb_bad_cntrl_reasons() { local r n=0; for r in "${HB_BAD_REASON[@]}"; do [[ "$r" == control_char ]] && n=$((n + 1)); done; printf '%s' "$n"; }
hb_bad_equals_good() { local v; for v in "${HB_BAD_VAL[@]}"; do [[ "$v" == "$HB_GOOD" ]] && return 0; done; return 1; }
assert "(hb-c) the hostile-value array holds exactly $HB_BAD_N rows (labels, reasons and values in step)" \
  "[[ '${#HB_BAD_VAL[@]}' -eq $HB_BAD_N && '${#HB_BAD_LABEL[@]}' -eq $HB_BAD_N && '${#HB_BAD_REASON[@]}' -eq $HB_BAD_N ]]"
assert "(hb-c) the rows are content-asserted: all $HB_BAD_N values distinct, none equals the good URL, all but the empty rest carry the good token" \
  "[[ \"\$(hb_bad_distinct)\" -eq $HB_BAD_N && \"\$(hb_bad_with_token)\" -eq $((HB_BAD_N - 1)) ]] && ! hb_bad_equals_good"
assert "(hb-c) exactly the control-character rows (newline, CR, tab) carry a control char and a control_char reason" \
  "[[ \"\$(hb_bad_cntrl_vals)\" -eq 3 && \"\$(hb_bad_cntrl_reasons)\" -eq 3 ]]"
for _i in "${!HB_BAD_VAL[@]}"; do
  run_hb "${HB_BAD_VAL[$_i]}"
  assert "(hb-c) refuses ${HB_BAD_LABEL[$_i]}: zero heartbeat curls (the registry request still ran), exactly one marker, exit status unchanged" \
    "[[ '$N_HB' -eq 0 && '$N_MARK' -eq 1 && '$HEC' -eq '$HB_BASE_EC' && -s '$HB_REGARGV' ]]"
  assert "(hb-c) refuses ${HB_BAD_LABEL[$_i]}: marker names reason=${HB_BAD_REASON[$_i]} and the variable, and no URL text is echoed" \
    "grep -qxF -e '$HB_MARKER_HEAD reason=${HB_BAD_REASON[$_i]} var=WEB_ZOT_CONSUMER_URL' '$HOUT' && ! grep -qF -e betterstack -e synthetic-zot-token -e 203.0.113.1 -e 'https://' '$HOUT'"
done
# unset URL is the pre-existing WARN arm (not a refusal): zero heartbeat curls, no marker, same exit
run_hb ""
assert "(hb-c) an empty URL keeps the existing WARN arm: zero heartbeat curls, no marker, exit 0" \
  "[[ '$N_HB' -eq 0 && '$N_MARK' -eq 0 && '$HEC' -eq 0 ]] && grep -qF 'WEB_ZOT_CONSUMER_URL unset' <<<\"\$HOUTTXT\""

# (d) the refusal limiter: its OWN stamp, 3600 s, future-dated or garbage reads as emit, unwritable fails OPEN
RS="$TMP/refusal.window"; rm -f "$RS"
hb_sum_mark=0; hb_sum_warn=0; hb_sum_hb=0; hb_sum_badec=0
for _ in 1 2 3 4; do
  run_hb "${HB_GOOD}\"" SOLEUR_PROBE_REFUSAL_MARKER="$RS"
  hb_sum_mark=$((hb_sum_mark + N_MARK)); hb_sum_warn=$((hb_sum_warn + N_WARN)); hb_sum_hb=$((hb_sum_hb + N_HB))
  [[ "$HEC" -eq "$HB_BASE_EC" ]] || hb_sum_badec=$((hb_sum_badec + 1))
done
assert "(hb-d) four refused runs inside one window log ONE marker and ONE WARN, make zero heartbeat curls, and EVERY run keeps the baseline exit status" \
  "[[ '$hb_sum_mark' -eq 1 && '$hb_sum_warn' -eq 1 && '$hb_sum_hb' -eq 0 && '$hb_sum_badec' -eq 0 ]]"
assert "(hb-d) the emit wrote the refusal stamp (a current epoch)" "[[ -n \"\$(hb_epoch_age '$RS')\" && \"\$(hb_epoch_age '$RS')\" -ge 0 && \"\$(hb_epoch_age '$RS')\" -lt 120 ]]"

hb_aged_row() {  # <label> <seed: age in seconds | @future | @garbage | @empty> <expected markers> <stamp: rewritten|unchanged>
  local seed="$2" want="$3" kind="$4" before
  case "$seed" in
    @future)  printf '%s\n' "$(( $(date +%s) + 99999 ))" > "$RS" ;;
    @garbage) printf 'not-an-epoch\n' > "$RS" ;;
    @text:*)  printf '%s\n' "${seed#@text:}" > "$RS" ;;
    @empty)   : > "$RS" ;;
    *)        printf '%s\n' "$(( $(date +%s) - seed ))" > "$RS" ;;
  esac
  before="$(cat "$RS")"
  run_hb "${HB_GOOD}\"" SOLEUR_PROBE_REFUSAL_MARKER="$RS"
  assert "(hb-d) $1 => $want marker(s), zero heartbeat curls" "[[ '$N_MARK' -eq $want && '$N_HB' -eq 0 ]]"
  if [[ "$kind" == rewritten ]]; then
    assert "(hb-d) $1 => the stamp was rewritten to the current epoch" "[[ \"\$(cat '$RS')\" != '$before' && \"\$(hb_epoch_age '$RS')\" -ge 0 && \"\$(hb_epoch_age '$RS')\" -lt 120 ]]"
  else
    assert "(hb-d) $1 => the stamp was left alone" "[[ \"\$(cat '$RS')\" == '$before' ]]"
  fi
}
hb_aged_row 'a stamp aged 2000 s still suppresses (the window is 3600 s, not the shared 1800 s)' 2000 0 unchanged
hb_aged_row 'a stamp aged 3700 s re-emits' 3700 1 rewritten
hb_aged_row 'a future-dated stamp emits' @future 1 rewritten
hb_aged_row 'a garbage stamp emits' @garbage 1 rewritten
# Short stamps: shorter than the 10-character cap, so only the numeric guard (and the base-10 coercion) can judge them.
hb_aged_row 'a 3-character non-numeric stamp (abc) emits' @text:abc 1 rewritten
hb_aged_row 'a 4-character mixed stamp (12ab) emits' @text:12ab 1 rewritten
hb_aged_row 'a leading-zero 9 stamp (0000000009, an invalid octal) is read as base 10 and emits' @text:0000000009 1 rewritten
hb_aged_row 'a leading-zero 8 stamp (0000000008) is read as base 10 and emits' @text:0000000008 1 rewritten
hb_aged_row 'an 11-digit stamp (longer than any epoch) emits' @text:12345678901 1 rewritten
hb_aged_row 'an empty stamp emits' @empty 1 rewritten
hb_aged_row 'a fresh stamp (control for the rows above) suppresses' 5 0 unchanged
# Boundary rows at the exact edge of the 3600 s window. A run that straddles a clock-second tick would age the stamp by one
# more second and move the edge under the assertion, so the helper re-seeds until a run began and ended inside one second.
hb_exact_age_run() {  # <age seconds> -> a refused run against a stamp of exactly that age; HB_T0 = that second; rc 1 if no tick-free run in 5 tries
  local age="$1" t0 t1
  for _ in 1 2 3 4 5; do
    t0="$(date +%s)"; printf '%s\n' "$((t0 - age))" > "$RS"
    run_hb "${HB_GOOD}\"" SOLEUR_PROBE_REFUSAL_MARKER="$RS"
    t1="$(date +%s)"; HB_T0="$t0"; [[ "$t0" == "$t1" ]] && return 0
  done
  return 1
}
hb_exact_age_run 3599; HB_EXACT_OK=$?
assert "(hb-d) a stamp aged exactly 3599 s suppresses (one second inside the window): no marker, no WARN, zero heartbeat curls, stamp left alone" \
  "[[ '$HB_EXACT_OK' -eq 0 && '$N_MARK' -eq 0 && '$N_WARN' -eq 0 && '$N_HB' -eq 0 && \"\$(cat '$RS')\" -eq '$((HB_T0 - 3599))' ]]"
hb_exact_age_run 3600; HB_EXACT_OK=$?
assert "(hb-d) a stamp aged exactly 3600 s emits (the window is closed at 3600: age < 3600 suppresses) and the stamp is rewritten to now" \
  "[[ '$HB_EXACT_OK' -eq 0 && '$N_MARK' -eq 1 && '$N_WARN' -eq 1 && '$N_HB' -eq 0 && \"\$(cat '$RS')\" -eq '$HB_T0' ]]"

# the refusal stamp is its OWN file: a fresh canary/per-repo stamp must not suppress the refusal marker, and vice versa
HB_CAN="$TMP/canary.own"; HB_REP="$TMP/repos.own"; HB_REF="$TMP/refusal.own"; rm -f "$HB_REF"
HB_SEED=$(( $(date +%s) - 100 )); printf '%s\n' "$HB_SEED" > "$HB_CAN"; printf '%s\n' "$HB_SEED" > "$HB_REP"
run_hb "${HB_GOOD}\"" SOLEUR_PROBE_CANARY_MARKER="$HB_CAN" SOLEUR_PROBE_REPOS_MARKER="$HB_REP" SOLEUR_PROBE_REFUSAL_MARKER="$HB_REF"
assert "(hb-d) fresh canary AND per-repo stamps do not suppress the refusal marker (own stamp)" "[[ '$N_MARK' -eq 1 ]] && ! grep -q 'SOLEUR_PROBE_CANARY' '$HOUT'"
assert "(hb-d) the refusal emit did not touch the canary or per-repo stamps" "[[ \"\$(cat '$HB_CAN')\" == '$HB_SEED' && \"\$(cat '$HB_REP')\" == '$HB_SEED' && -s '$HB_REF' ]]"
rm -f "$HB_CAN" "$HB_REP"; printf '%s\n' "$(date +%s)" > "$HB_REF"
run_hb "${HB_GOOD}\"" SOLEUR_PROBE_CANARY_MARKER="$HB_CAN" SOLEUR_PROBE_REPOS_MARKER="$HB_REP" SOLEUR_PROBE_REFUSAL_MARKER="$HB_REF"
assert "(hb-d) a fresh refusal stamp does not suppress the canary or the per-repo markers (and the refusal itself stays suppressed)" \
  "[[ '$N_MARK' -eq 0 ]] && grep -q 'SOLEUR_PROBE_CANARY' '$HOUT' && grep -q 'SOLEUR_ZOT_PROBE_VERDICT' '$HOUT'"

# an UNWRITABLE stamp path fails OPEN: the marker is emitted on every tick (loud, never silent)
HB_UNW="$TMP/no-such-dir/refusal.stamp"; hb_unw_mark=0
for _ in 1 2; do run_hb "${HB_GOOD}\"" SOLEUR_PROBE_REFUSAL_MARKER="$HB_UNW"; hb_unw_mark=$((hb_unw_mark + N_MARK)); done
assert "(hb-d) an unwritable stamp path fails OPEN: two refused runs, two markers, exit status unchanged, nothing created" \
  "[[ '$hb_unw_mark' -eq 2 && '$HEC' -eq '$HB_BASE_EC' && ! -e '$HB_UNW' ]]"

# regression: the shared window helper keeps its 1800 s window for its existing callers (canary, per-repo markers)
hb_win_row() {  # <label> <env var holding the stamp path> <age> <expected: emit|suppress> <marker text>
  local stamp="$TMP/win.$MARKER_N.stamp"
  printf '%s\n' "$(( $(date +%s) - $3 ))" > "$stamp"
  run_hb "$HB_GOOD" "$2=$stamp"
  if [[ "$4" == emit ]]; then assert "(hb-d) $1 aged $3 s emits" "grep -q '$5' '$HOUT'"
  else assert "(hb-d) $1 aged $3 s suppresses" "! grep -q '$5' '$HOUT'"; fi
}
hb_win_row 'a canary stamp' SOLEUR_PROBE_CANARY_MARKER 1700 suppress SOLEUR_PROBE_CANARY
hb_win_row 'a canary stamp' SOLEUR_PROBE_CANARY_MARKER 1900 emit SOLEUR_PROBE_CANARY
hb_win_row 'a per-repo stamp' SOLEUR_PROBE_REPOS_MARKER 1700 suppress SOLEUR_ZOT_PROBE_VERDICT
hb_win_row 'a per-repo stamp' SOLEUR_PROBE_REPOS_MARKER 1900 emit SOLEUR_ZOT_PROBE_VERDICT

# static shape (the S6-HB identity checks, restated so this suite fails on its own): one guard-class literal on a
# non-comment line BEFORE the single stdin url line, one per-attempt _hb_curl called twice, -g kept
HB_CLASS='[!A-Za-z0-9._~:/?\&=%+-]'
hb_code() { sed 's/^[[:space:]]*#.*//' "$SUT"; }
HB_CODE_TXT="$(hb_code)"
hb_line_of() { grep -nF -e "$1" <<<"$HB_CODE_TXT" | head -1 | cut -d: -f1; }
assert "(hb-s) the guard-class literal is DEFINED (source order) before the single stdin url line, exactly once on a non-comment line" \
  "[[ \"\$(grep -cF -e '$HB_CLASS' <<<\"\$HB_CODE_TXT\")\" -eq 1 && \"\$(grep -cF -e 'url = \"' <<<\"\$HB_CODE_TXT\")\" -eq 1 && -n \"\$(hb_line_of '$HB_CLASS')\" && \"\$(hb_line_of '$HB_CLASS')\" -lt \"\$(hb_line_of 'url = \"')\" ]]"
assert "(hb-s) _hb_curl is defined once and called twice (one fresh process substitution per attempt)" "[[ \"\$(hb_code | grep -oE '_hb_curl' | wc -l)\" -eq 3 ]]"
assert "(hb-s) the heartbeat curl keeps -g and the --disable --noproxy '*' confinement" \
  "[[ \"\$(grep -cF -e \"curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config -\" <<<\"\$HB_CODE_TXT\")\" -eq 1 ]]"

# REAL-curl smoke. Every row above runs a stub curl, which accepts any argv, so a flag the real curl rejects (exit 2,
# "curl: option ...") would pass them all. Extract the SUT's own _hb_curl definition and run it against the real curl at a
# closed port: a well-formed argv gets as far as the connect and fails with rc 7; a rejected option gives rc 2. The
# definition silences curl's stderr, so a second copy with that redirect removed shows the text itself.
HB_DEF="$TMP/hb_curl.def"; HB_DEF_LOUD="$TMP/hb_curl_loud.def"
sed -n '/^_hb_curl()/p' "$SUT" > "$HB_DEF"
sed 's| 2>/dev/null||' "$HB_DEF" > "$HB_DEF_LOUD"
SMOKE_RC="$(env URL='https://127.0.0.1:9/p' bash -c ". \"\$1\"; _hb_curl; echo \$?" _ "$HB_DEF" 2>&1)"
# shellcheck disable=SC2034  # read by NAME inside the assert() eval strings below
SMOKE_TXT="$(env URL='https://127.0.0.1:9/p' bash -c ". \"\$1\"; _hb_curl; echo \"rc=\$?\"" _ "$HB_DEF_LOUD" 2>&1)"
assert "(hb-smoke) the extracted _hb_curl definition is one non-empty line and the stderr-visible copy differs from it" \
  "[[ \"\$(wc -l < '$HB_DEF')\" -eq 1 && -s '$HB_DEF' ]] && ! cmp -s '$HB_DEF' '$HB_DEF_LOUD'"
assert "(hb-smoke) the curl on the test shell's PATH is the real one, not the stub" \
  "[[ \"\$(command -v curl)\" != '$TMP/stubbin/curl' && -x \"\$(command -v curl)\" ]]"
assert "(hb-smoke) the real curl accepts the argv: exit 7 (connection refused), never 2 (option rejected)" "[[ '$SMOKE_RC' == 7 ]]"
assert "(hb-smoke) the real curl's own message is a connect failure, with no 'curl: option' and no '(2)' text" \
  "grep -qF '(7)' <<<\"\$SMOKE_TXT\" && ! grep -qF -e 'curl: option' -e '(2)' <<<\"\$SMOKE_TXT\""

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
has_marker() {  # <repo> <code> <verdict> [pin_verdict, default none]
  grep -qE "SOLEUR_ZOT_PROBE_VERDICT repo=$1 code=$2 verdict=$3 ts=[0-9]+ pin_verdict=${4:-none}\$" "$MOUT"
}
count_markers() { local n; n=$(grep -c 'SOLEUR_ZOT_PROBE_VERDICT ' "$MOUT" || true); printf '%s' "$n"; }
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
assert "T7 the one guessed variable name is absent from variables.tf (the real guard: variables.tf is not in the diff, AC5)" \
  "! grep -qF 'variable \"inngest_bootstrap_repo\"' '$SCRIPT_DIR/variables.tf'"
# Guard 2, the WIRE: the list the probe is HANDED, not only the list web-probe.tf builds. Each writer must
# pass the joined local through unchanged; truncating, narrowing or dropping it at any one of them leaves the
# probe covering one repo while the heartbeat stays green.
SERVER_TF="$SCRIPT_DIR/server.tf"
ENVWRITE="$SCRIPT_DIR/web-probe-envwrite.sh"
assert "T7 server.tf hands the joined local to the cloud-init template (zot_probe_repo = local.zot_probe_repo)" \
  "grep -qE '^[[:space:]]*zot_probe_repo[[:space:]]*=[[:space:]]*local\\.zot_probe_repo[[:space:]]*\$' '$SERVER_TF'"
assert "T7 server.tf's triggers_replace hashes the PINNED local (a pin bump re-runs the SSH provisioner on web-1)" \
  "grep -qE '^[[:space:]]*local\\.zot_probe_repo_pinned,[[:space:]]*\$' '$SERVER_TF' && ! grep -qE '^[[:space:]]*local\\.zot_probe_repo,[[:space:]]*\$' '$SERVER_TF'"
# The slot order matters as much as presence: swapping the two %s arguments (or the two names) would write
# ZOT_ENDPOINT=<list> and ZOT_PROBE_REPO=<endpoint> with every "is the local present" row still green.
# shellcheck disable=SC2016  # the literal ${local.*} are the HCL text under test
SSH_ARGS="$(printf "' '%s' '%s' 'WEB_ZOT_CONSUMER_URL_" '${local.registry_endpoint}' '${local.zot_probe_repo_pinned}')"
SSH_FMT='ZOT_ENDPOINT=%s\\nZOT_PROBE_REPO=%s\\nWEB_ZOT_CONSUMER_URL_KEY=%s'  # the HCL source carries a doubled backslash
ssh_line() { grep -E '^[[:space:]]*"\( umask' "$SERVER_TF"; }
ssh_writer_ok() {  # the printf that writes ZOT_PROBE_REPO: names in order, joined local in the second slot
  ssh_line | grep -cF -- "$SSH_FMT" >/dev/null && ssh_line | grep -cF -- "$SSH_ARGS" >/dev/null
}
assert "T7 server.tf's SSH provisioner writes ZOT_PROBE_REPO from the PINNED local (the only live path on web-1)" "ssh_writer_ok"
# shellcheck disable=SC2016  # the literal ${zot_probe_repo} is the template text under test
CI_LINE="$(printf "    SOLEUR_ZOT_PROBE_REPO='%s'" '${zot_probe_repo}')"
ci_line_ok() { grep -qxF -- "$CI_LINE" "$CLOUD_INIT_WEB"; }
assert "T7 cloud-init.yml bakes the templated list into SOLEUR_ZOT_PROBE_REPO verbatim" "ci_line_ok"
assert "T7 web-probe-envwrite.sh passes SOLEUR_ZOT_PROBE_REPO to the ZOT_PROBE_REPO printf slot unmodified" \
  "grep -qF '\"\$SOLEUR_ZOT_ENDPOINT\" \"\$SOLEUR_ZOT_PROBE_REPO\" \"WEB_ZOT_CONSUMER_URL_' '$ENVWRITE'"
ENV_FMT='ZOT_ENDPOINT=%s\nZOT_PROBE_REPO=%s\nWEB_ZOT_CONSUMER_URL_KEY=%s'
env_fmt_ok() { grep -cF -- "$ENV_FMT" "$ENVWRITE" >/dev/null; }
assert "T7 web-probe-envwrite.sh's printf names the slots in order (ZOT_ENDPOINT first, ZOT_PROBE_REPO second)" "env_fmt_ok"
# The pull side, completely: EVERY registry-prefixed pin in the two cloud-init files, and the deploy-time
# ALLOWED_IMAGES set, name only repositories the probe covers (a third pin or a third image is a repository
# the probe would not see).
pin_rows() {  # <file...> -> the repository path of every NAME*REF="$<var>/path[:@]..." pin or `docker pull "$<var>/path`, one per line
  sed -n -e 's|^[[:space:]]*[A-Za-z0-9_]*REF[A-Za-z0-9_]*="[$]*[$A-Za-z0-9_{}]*/\([^:@"]*\)[:@].*|\1|p' \
         -e 's|.*docker pull "[$]*[$A-Za-z0-9_{}]*/\([^:@"]*\)[:@"].*|\1|p' "$@"
}
all_pins() { pin_rows "$@" | sort -u; }
# #6780 widened the registry-ref set: the refresh consumer's BREF
# ("$${ZOT_EP}/$${BUNDLE_REPO}@sha256:<pointer>") is a third registry-prefixed
# pin by design — the signed config-bundle channel pulls a SECOND repository
# (jikig-ai/soleur-inngest-config via the BUNDLE_REPO var literal) that the
# zot consumer probe deliberately does not cover. The contract is now: every
# pin names the bootstrap repo OR the BUNDLE_REPO form, and the bootstrap
# repo still gets exactly its two pins.
assert "T7 every registry-prefixed pin in both cloud-init files names the bootstrap repository or the #6780 BUNDLE_REPO form (a fourth pin fails here)" \
  "[[ -z \"\$(all_pins '$CLOUD_INIT_WEB' '$CLOUD_INIT_INNGEST' | grep -vxF 'jikig-ai/soleur-inngest-bootstrap' | grep -v 'BUNDLE_REPO')\" ]]"
# The pin set is also counted: exactly the two ZIREF bootstrap pins exist today (one per host class).
assert "T7 exactly two registry-prefixed BOOTSTRAP pins exist across both cloud-init files (one per host class)" \
  "[[ \"\$(pin_rows '$CLOUD_INIT_WEB' '$CLOUD_INIT_INNGEST' | grep -cxF 'jikig-ai/soleur-inngest-bootstrap')\" -eq 2 ]]"
ALLOWED_PATHS="$(sed -n '/^declare -A ALLOWED_IMAGES=(/,/^)/p' "$SCRIPT_DIR/ci-deploy.sh" | sed 's/^[[:space:]]*#.*//' | sed -n 's|.*="ghcr\.io/\([^"]*\)".*|\1|p' | LC_ALL=C sort)"
# The web image's path as web-probe.tf derives it: the var.image_name default minus registry and tag.
IMG_WEB="$(sed -n '/^variable "image_name"/,/^}/p' "$SCRIPT_DIR/variables.tf" | sed -n 's|^[[:space:]]*default[[:space:]]*=[[:space:]]*"ghcr\.io/\([^:@"]*\)[:@"].*|\1|p')"
allowed_set_ok() {  # ALLOWED_IMAGES (comments ignored) is exactly {web image path, probed bootstrap path}
  [[ -n "$IMG_WEB" && "$ALLOWED_PATHS" == "$(printf '%s\n%s\n' "$IMG_WEB" "$TF_BOOT" | LC_ALL=C sort)" ]]
}
assert "T7 ci-deploy.sh ALLOWED_IMAGES holds exactly two images (web + bootstrap) and the bootstrap one is the probed constant" \
  "[[ \"\$(wc -l <<<'$ALLOWED_PATHS')\" -eq 2 ]] && grep -qxF '$TF_BOOT' <<<'$ALLOWED_PATHS'"
assert "T7 ci-deploy.sh ALLOWED_IMAGES is exactly {the var.image_name repo, the probed bootstrap repo}: no duplicate, no third, no lookalike" "allowed_set_ok"
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
marker_row "garbage, longer than 10 characters (length guard)" "not-a-number"
# Short garbage reaches the non-numeric arm itself (a longer value is caught by the length guard first).
marker_row "garbage 'abc' (non-numeric arm)" "abc"
marker_row "garbage '12ab' (digits then letters)" "12ab"
marker_row "garbage '1e5' (exponent form)" "1e5"
marker_row "garbage '-5' (negative)" "-5"
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

# T10 — TWO faulting repos: the aggregation is a conjunction over the whole list, not a "one fault" flag.
echo "--- #7258: aggregation under multiple faults, fault-line attribution ---"
for pair in 404,404 000,000 503,404 000,302; do
  run_override_multi "$WEB_R,$BOOT_R" "$pair"
  assert "T10 $pair (both faulting) => NO ping, exit 0" "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
  assert "T10 $pair => one fault line per faulting repo, each naming its own repo" \
    "[[ \"\$(wc -l < '$FAULTS')\" -eq 2 ]] && faults_name $WEB_R && faults_name $BOOT_R"
done
run_override_multi "$WEB_R,$BOOT_R" 401,401
assert "T10 401,401 (both auth-broke) => exit 3, NO ping" "[[ '$EC' -eq 3 && '$PINGED' == no ]]"
assert "T10 401,401 => a HARD FAILURE line per repo" "[[ \"\$(grep -cF 'HARD FAILURE: 401' '$FAULTS')\" -eq 2 ]] && faults_name $WEB_R && faults_name $BOOT_R"
# A fault line names ONLY the faulting repo and ends with it, for every fault class.
for c in 000 503 302 404 401; do
  run_override_multi "$WEB_R,$BOOT_R" "200,$c"
  assert "T10 200,$c => exactly one fault line, naming only the bootstrap repo, ending with it" \
    "[[ \"\$(wc -l < '$FAULTS')\" -eq 1 ]] && faults_name $BOOT_R && ! faults_name $WEB_R && grep -qE 'repo=$BOOT_R\$' '$FAULTS'"
  run_override_multi "$WEB_R,$BOOT_R" "$c,200"
  assert "T10 $c,200 => exactly one fault line, naming only the web repo, ending with it" \
    "[[ \"\$(wc -l < '$FAULTS')\" -eq 1 ]] && faults_name $WEB_R && ! faults_name $BOOT_R && grep -qE 'repo=$WEB_R\$' '$FAULTS'"
done

# T11 — the list is NOT capped at two: a third element is probed, marked and gates the ping.
run_override_multi "a/x,b/y,c/z" 200,200,200
assert "T11 three repos, all 200 => ping, a marker per repo" "[[ '$PINGED' == yes && \"\$(count_markers)\" -eq 3 ]] && has_marker c/z 200 servable"
run_override_multi "a/x,b/y,c/z" 200,200,404
assert "T11 the THIRD repo faulting => NO ping, fault line naming only it" "[[ '$PINGED' == no ]] && faults_name c/z && ! faults_name a/x && ! faults_name b/y"

# T12 — a newline in the value would let `read` drop every later element and silently shrink the conjunction.
echo "--- #7258: list parsing guards ---"
run_override_multi $'a/b\nc/d' 200,200
assert "T12 a newline in ZOT_PROBE_REPO => FATAL exit 1 before any curl, ping or marker" \
  "[[ '$EC' -eq 1 && '$PINGED' == no && \"\$(count_markers)\" -eq 0 ]] && grep -qF 'newline' '$MOUT'"

# T13 — an element outside the OCI repository-name alphabet changes the request path (or makes curl glob)
# rather than naming a repository: FATAL exit 1, no ping, no marker. The control row must PING.
# The dot-segment, hyphen-edged and underscore-edged rows pin the component rule: a component that starts or ends
# with a separator is refused (`a/./b` would be normalised to `a/b` by the HTTP client, so the probe would
# check a different repository than the list names). Every row must also hit the FATAL arm that names it.
for bad in 'a/b?c' 'a/b#c' 'a/../b' 'a[1-2]' 'a{b,c}' 'Upper/Case' '/abs/x' 'trail/' 'a//b' '-flag/x' '.hidden/x' 'a/b:tag' 'a/b@sha' \
           'a/./b' 'a/.' 'a/-b' 'a./b' '_a/b' 'a/_b' 'a_/b-' 'a/b.' 'a/b-'; do
  run_override_multi "$bad" 200
  assert "T13 element '$bad' => FATAL exit 1 (invalid-name arm), no ping, no marker" \
    "[[ '$EC' -eq 1 && '$PINGED' == no && \"\$(count_markers)\" -eq 0 ]] && grep -qF 'not a valid repository name' '$MOUT'"
done
run_override_multi "a-b/c_d.e,f/g-h" 200,200
assert "T13 control: a name using every permitted separator (. _ - /) pings" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"

# T14 — the window length and the doubtful marker contents. A 60 s window would defeat the quota rationale;
# a >10-digit or zero-padded value must never silence the markers for good.
echo "--- #7258: marker window length and hardened doubtful states ---"
printf '%s\n' "$(( $(date +%s) - 600 ))" > "$MK"
run_override_multi "$WEB_R,$BOOT_R" 200,200 "$MK"
assert "T14 a 10-minute-old marker => still inside the 30-minute window: NO markers" "[[ \"\$(count_markers)\" -eq 0 ]]"
marker_row "31 minutes old (just past the window)" "$(( $(date +%s) - 1860 ))"
marker_row "a 20-digit number (overflows integer compares)" "99999999999999999999"
marker_row "zero-padded and old (would read as invalid octal)" "0000000008"
# 2^64 + now wraps to a FRESH epoch under 64-bit arithmetic: without the width guard it would read as "just
# written" and silence the markers for good.
marker_row "2^64 + now (wraps to a fresh epoch)" "$(python3 -c "print(2**64 + $(date +%s))")"
# A clock that cannot be read must emit, never silence (a missing marker would otherwise read 0 - 0 < 1800).
mkdir -p "$TMP/nodate"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nodate/date"; chmod +x "$TMP/nodate/date"
rm -f "$MK"
PATH="$TMP/nodate:$PATH" run_override_multi "$WEB_R,$BOOT_R" 200,200 "$MK"
assert "T14 an unreadable clock (date fails) with no marker => the markers ARE emitted" "[[ \"\$(count_markers)\" -eq 2 ]]"

# T15 — the two markers must not share a default path: the canary stamps first in the same run, which
# would close the window for every repo marker for good (the telemetry meant to prove a healthy run).
def_of() { sed -n "s|^[[:space:]]*local m=\"[$]{$1:-\([^}]*\)}\".*|\1|p" "$SUT"; }  # the real assignment, never a comment
DEF_CANARY="$(def_of SOLEUR_PROBE_CANARY_MARKER)"
DEF_REPOS="$(def_of SOLEUR_PROBE_REPOS_MARKER)"
assert "T15 both default marker paths were extracted, one assignment each (non-empty, single line)" \
  "[[ -n '$DEF_CANARY' && -n '$DEF_REPOS' && \"\$(wc -l <<<'$DEF_CANARY')\" -eq 1 && \"\$(wc -l <<<'$DEF_REPOS')\" -eq 1 ]]"
assert "T15 the canary and per-repo marker default paths DIFFER" "[[ '$DEF_CANARY' != '$DEF_REPOS' ]]"
DEF_REFUSAL="$(def_of SOLEUR_PROBE_REFUSAL_MARKER)"
assert "T15 the refusal marker (#9757) has its own default path under /run, distinct from the canary's and the per-repo marker's" \
  "[[ -n '$DEF_REFUSAL' && \"\$(wc -l <<<'$DEF_REFUSAL')\" -eq 1 && '$DEF_REFUSAL' == /run/* && '$DEF_REFUSAL' != '$DEF_CANARY' && '$DEF_REFUSAL' != '$DEF_REPOS' ]]"

# T16 — instrument controls. has_marker must be able to FAIL (a stub that always returned true would
# otherwise pass every positive row), and the run must have executed at least the floor of assertions.
run_override_multi "$WEB_R,$BOOT_R" 200,404
assert "T16 has_marker is strict: the wrong code is not a match"    "! has_marker $WEB_R 404 servable"
assert "T16 has_marker is strict: the wrong verdict is not a match" "! has_marker $BOOT_R 404 servable && ! has_marker $BOOT_R 200 empty"
assert "T16 has_marker is strict: an unlisted repo is not a match"  "! has_marker nobody/here 200 servable"

# ===== #10004: the probe HEADs the pinned manifest ============================================
# A ZOT_PROBE_REPO element is `<repo>` or `<repo>@sha256:<64 lowercase hex>`. For an element that carries a
# digest whose tags/list answered 200 the probe sends ONE authenticated manifest HEAD; the heartbeat is pinged
# only when every tags/list AND every pin HEAD is 200. Pin codes are driven through the mock registry (digest
# letter table: a=200 b=404 c=403 d=503) and through the stub curl (STUB_MANIFEST_CODE / STUB_TAGS_CODE).
echo "--- #10004: pinned-manifest HEAD ---"
hex64() { printf '%064d' 0 | tr 0 "$1"; }
DIG_OK="sha256:$(hex64 a)"; DIG_GONE="sha256:$(hex64 b)"; DIG_403="sha256:$(hex64 c)"; DIG_503="sha256:$(hex64 d)"
out_has() { grep -qF -- "$1" <<<"$OUT"; }
out_marker() {  # <repo> <code> <verdict> <pin_verdict> -- against the combined output of the last run_probe / run_stub
  grep -qE "SOLEUR_ZOT_PROBE_VERDICT repo=$1 code=$2 verdict=$3 ts=[0-9]+ pin_verdict=$4\$" <<<"$OUT"
}
req_count() { local n; n=$(grep -c -- "$1" "$REQLOG" || true); printf '%s' "$n"; }

# P1 — both healthy, the bootstrap element pinned: ping, exactly one manifest HEAD, the right markers.
: > "$REQLOG"; run_probe "$SUT" "known/repo,known/second@$DIG_OK"
assert "P1 pinned element served => ping, exit 0" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
assert "P1 exactly one manifest request, and it is a HEAD of the pinned digest" \
  "[[ \"\$(req_count manifests)\" -eq 1 ]] && grep -qxF 'HEAD /v2/known/second/manifests/$DIG_OK' '$REQLOG'"
assert "P1 no GET of any manifest path (HEAD only)" "! grep -qE '^GET .*manifests' '$REQLOG'"
assert "P1 markers: the bare element says none, the pinned one says pinned" \
  "out_marker known/repo 200 servable none && out_marker known/second 200 servable pinned"

# P2 — an evicted pin suppresses the ping while tags/list still answers 200 (the defect this change closes).
: > "$REQLOG"; run_probe "$SUT" "known/repo,known/second@$DIG_GONE"
assert "P2 pin 404, tags 200 => NO ping, exit 0 (absence alarms)" "[[ '$PINGED' == no && '$EC' -eq 0 ]]"
assert "P2 the fault line says the pinned manifest is MISSING, names ref= and ends with repo=" \
  "out_has 'pinned manifest known/second@$DIG_GONE is MISSING' && grep -qE 'ref=known/second@$DIG_GONE repo=known/second\$' <<<\"\$OUT\""
assert "P2 marker: tags servable, pin_verdict=pin-missing" "out_marker known/second 200 servable pin-missing"
# P2b / P2c — a pin fault on ANY element, first or second, is never cleared by a healthy neighbour.
: > "$REQLOG"; run_probe "$SUT" "known/repo@$DIG_OK,known/second@$DIG_GONE"
assert "P2b two pinned elements, the SECOND evicted => NO ping, fault names the second repo" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && grep -qE 'repo=known/second\$' <<<\"\$OUT\" && out_marker known/repo 200 servable pinned && out_marker known/second 200 servable pin-missing"
: > "$REQLOG"; run_probe "$SUT" "known/repo@$DIG_GONE,known/second@$DIG_OK"
assert "P2c two pinned elements, the FIRST evicted => NO ping, fault names the first repo" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && grep -qE 'repo=known/repo\$' <<<\"\$OUT\" && out_marker known/repo 200 servable pin-missing"
assert "P2c no early exit: the healthy second pin was still HEADed and marked" \
  "grep -qxF 'HEAD /v2/known/second/manifests/$DIG_OK' '$REQLOG' && out_marker known/second 200 servable pinned"

# P4 (mock half) — every non-200, non-404, non-401 pin code suppresses the ping and is named.
run_probe "$SUT" "known/repo,known/second@$DIG_403"
assert "P4 pin 403 => NO ping, the line names the code AND the manifest URL it asked for, marker unexpected" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && out_has 'unexpected code 403 for 127.0.0.1:$PORT/v2/known/second/manifests/$DIG_403' && out_marker known/second 200 servable unexpected"
run_probe "$SUT" "known/repo,known/second@$DIG_503"
assert "P4 pin 503 => NO ping, WEDGED, marker wedged" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && out_has 'WEDGED' && out_marker known/second 200 servable wedged"

# P3 / P4 (stub half) — a 401 or a transport failure on the manifest request, tags/list answering 200.
STUB_MANIFEST_CODE=401 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P3 pin 401 (second element) => exit 3, NO ping" "[[ '$EC' -eq 3 && '$PINGED' == no ]]"
assert "P3 pin 401 => HARD FAILURE naming the pinned repo, and the other element's marker is still emitted" \
  "out_has 'HARD FAILURE: 401' && grep -qE 'repo=known/second\$' <<<\"\$OUT\" && out_marker known/second 200 servable auth-broke && out_marker known/repo 200 servable none"
STUB_MANIFEST_CODE=401 run_stub zuser synthetic-fixture-token-0001 "known/repo@$DIG_OK,known/second"
assert "P3 pin 401 (first element) => exit 3, NO ping, the second element still marked" \
  "[[ '$EC' -eq 3 && '$PINGED' == no ]] && out_marker known/repo 200 servable auth-broke && out_marker known/second 200 servable none"
STUB_MANIFEST_CODE=000 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P4 pin 000 (transport failure) => NO ping, exit 0, the UNREACHABLE wording, marker unreachable" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && out_has 'UNREACHABLE' && out_marker known/second 200 servable unreachable"
assert "P4 pin 000 => the 000000 double-write is normalized (not the unexpected-code catch-all)" "! out_has 'unexpected code'"
# H2 — the stub can discriminate: with the default stub (200 everywhere) the same list pings and exits 0.
run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "H2 control: the default stub answers 200 to the manifest too => ping, exit 0 (so the P3/P4 stub rows can fail)" \
  "[[ '$PINGED' == yes && '$EC' -eq 0 ]] && out_marker known/second 200 servable pinned"

# P5 — the skip rule: a pin is not HEADed when its tags/list was not 200 (no second timeout, no duplicate fault).
STUB_TAGS_CODE=404 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P5 tags/list 404 => NO ping, and NO manifest request reached curl" "[[ '$PINGED' == no ]] && ! grep -qF '/manifests/' '$SARGV'"
assert "P5 tags/list 404 => the pinned element reports pin_verdict=skipped, the bare one none" \
  "out_marker known/second 404 empty skipped && out_marker known/repo 404 empty none"
STUB_TAGS_CODE=000 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P5 tags/list 000 => NO manifest request, pin skipped" "[[ '$PINGED' == no ]] && ! grep -qF '/manifests/' '$SARGV' && out_marker known/second 000 unreachable skipped"
STUB_TAGS_CODE=503 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P5 tags/list 503 => NO manifest request, pin skipped" "[[ '$PINGED' == no ]] && ! grep -qF '/manifests/' '$SARGV' && out_marker known/second 503 wedged skipped"
: > "$REQLOG"; run_probe "$SUT" "known/repo,nonexistent/repo@$DIG_OK"
assert "P5 mock: a pinned element whose tag list is 404 is never HEADed" "[[ '$PINGED' == no ]] && [[ \"\$(req_count manifests)\" -eq 0 ]]"
run_override_multi "$WEB_R,$BOOT_R@$DIG_OK" 200,403
assert "P5 seam: tags/list 403 still lands in 'unexpected code 403 for .../tags/list' (ci-deploy.sh documents this arm), pin skipped" \
  "[[ '$PINGED' == no ]] && grep -qE 'unexpected code 403 for 127\\.0\\.0\\.1:1/v2/'$BOOT_R'/tags/list' '$FAULTS' && has_marker $BOOT_R 403 unexpected skipped && has_marker $WEB_R 200 servable none"
run_override_multi "$WEB_R,$BOOT_R@$DIG_OK" 200,200
assert "P5 seam: tags 200 on a pinned element but nothing listening => the pin HEAD is UNREACHABLE (no ping)" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && has_marker $BOOT_R 200 servable unreachable"

# P6 — bare elements only: no manifest request at all; the single-repo env of web-2 behaves exactly as before.
: > "$REQLOG"; run_probe "$SUT" "known/repo,known/second"
assert "P6 bare elements => ping, and not one manifest request" "[[ '$PINGED' == yes && '$EC' -eq 0 && \"\$(req_count manifests)\" -eq 0 ]]"
assert "P6 bare elements => both markers say pin_verdict=none" "out_marker known/repo 200 servable none && out_marker known/second 200 servable none"
: > "$REQLOG"; run_probe "$SUT" "known/repo"
assert "P6 the single-repo env value (web-2) pings and says none" "[[ '$PINGED' == yes ]] && out_marker known/repo 200 servable none && [[ \"\$(req_count manifests)\" -eq 0 ]]"

# P7 — the element grammar: `repo` or `repo@sha256:<64 lowercase hex>` and nothing else.
echo "--- #10004: ref grammar ---"
UPPER_HEX="sha256:$(hex64 A)"; SHA512="sha512:$(printf '%0128d' 0 | tr 0 a)"
for bad in "known/second:v1" "known/second:v1@$DIG_OK" "known/second@sha256:abc" "known/second@$UPPER_HEX" "known/second@$SHA512" \
           "known/second@" "known/second@${DIG_OK}x" "known/second@${DIG_OK}a" "known/second@${DIG_OK:0:70}" "known/second@$DIG_OK@$DIG_OK" "@$DIG_OK" "known/second@sha256:"; do
  run_stub zuser synthetic-fixture-token-0001 "known/repo,$bad"
  assert "P7 element '${bad:0:48}' => FATAL exit 1 (curl never invoked, no ping, no marker)" \
    "[[ '$EC' -eq 1 && '$PINGED' == no && ! -s '$SARGV' ]] && out_has 'not a valid repository name' && ! out_has 'SOLEUR_ZOT_PROBE_VERDICT'"
done
run_probe "$SUT" "known/repo@$DIG_OK,known/second@$DIG_OK"
assert "H3 must-PASS: two valid pinned elements ping (a parser that rejects everything cannot pass the rows above)" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"
run_probe "$SUT" "known/repo,known/second@$DIG_OK,"
assert "H3 must-PASS: a trailing comma after a pinned element still pings" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"

# H1 — the mock can discriminate: a copy whose HEAD answers 200 for EVERY digest must turn P2 green-on-evicted.
H1_PY="$TMP/mock_zot_h1.py"
sed 's/DIG.get(parts\[5\]\[7\], 404)/200/' "$SRV_PY" > "$H1_PY"
assert "H1 the all-200 mock mutation landed" "! cmp -s '$SRV_PY' '$H1_PY' && grep -qF 'self.send_response(200); self.end_headers(); return' '$H1_PY'"
H1_PORT_FILE="$TMP/zot_port_h1"; : > "$H1_PORT_FILE"
python3 "$H1_PY" "$H1_PORT_FILE" "$TMP/mock_h1_requests.log" >/dev/null 2>&1 &
H1_PID=$!
for _ in $(seq 1 100); do [[ -s "$H1_PORT_FILE" ]] && break; sleep 0.1; done
PORT_REAL="$PORT"; PORT="$(cat "$H1_PORT_FILE" 2>/dev/null || true)"
run_probe "$SUT" "known/repo,known/second@$DIG_GONE"
PORT="$PORT_REAL"; kill "$H1_PID" 2>/dev/null || true
assert "H1 against the all-200 mock the EVICTED pin pings: the P2 row discriminates (the real mock answers 404)" "[[ '$PINGED' == yes ]]"

# P9 — the request shape, against the stub curl.
echo "--- #10004: request shape ---"
run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P9 curl is invoked once per bare element and twice for a pinned one (3 in all)" "[[ \"\$(wc -l < '$SARGV')\" -eq 3 ]]"
assert "P9 exactly one request targets a manifest, and it is the pinned digest" \
  "[[ \"\$(grep -cF '/manifests/' '$SARGV')\" -eq 1 ]] && grep -qF -e '/v2/known/second/manifests/$DIG_OK' '$SARGV'"
assert "P9 the manifest request is a HEAD (-I) and the tag-list requests are not" \
  "[[ \"\$(grep -F '/manifests/' '$SARGV' | grep -cF -e ' -I ')\" -eq 1 && \"\$(grep -F '/tags/list' '$SARGV' | grep -cF -e ' -I ' || true)\" -eq 0 ]]"
assert "P9 no request carries -f (it would destroy the 404 classification), --retry, or -L/--location" \
  "! grep -qE -e ' -[a-zA-Z]*[fL][a-zA-Z]* ' -e '--retry' -e '--location' '$SARGV'"
assert "P9 the credential is on no argv; stdin holds one identical user = line per curl (3)" \
  "! grep -qF -e synthetic-fixture-token-0001 -e zuser -e ' -u ' '$SARGV' && [[ \"\$(wc -l < '$SSTDIN')\" -eq 3 && \"\$(sort -u '$SSTDIN')\" == 'user = \"zuser:synthetic-fixture-token-0001\"' ]]"
assert "P9 the manifest request reads its config from stdin like the tag lists" "[[ \"\$(grep -cF -e '--config - ' '$SARGV')\" -eq 3 ]]"

# P11 — control characters in the credential and in a list element. Each row is paired with a mutated copy of
# the probe that drops exactly the guard arm the row exists for; the row's condition must then FAIL.
echo "--- #10004: control-character rows, each proven able to fail ---"
unsafe_row "user with a newline (directive injection)" $'zuser\nevilsuffix' synthetic-fixture-token-0001 'evilsuffix'
unsafe_row "user with a backslash"  'zu\ser' synthetic-fixture-token-0001 'zu\ser'
unsafe_row "user with a tab"        $'zu\tser' synthetic-fixture-token-0001 $'zu\tser'
unsafe_row "token with a tab"       zuser $'synthetic\tfixture' $'synthetic\tfixture'
run_stub zuser synthetic-fixture-token-0001 $'known/repo,known/sec\tond'
assert "P11 a tab inside a list element => FATAL exit 1 naming whitespace, curl never invoked" \
  "[[ '$EC' -eq 1 && '$PINGED' == no && ! -s '$SARGV' ]] && out_has 'contains whitespace'"
MUT_NOCNTRL="$TMP/probe-no-cntrl.sh"; MUT_NOBSL="$TMP/probe-no-bsl.sh"; MUT_NOWS="$TMP/probe-no-ws.sh"
sed 's/|\*\[\[:cntrl:\]\]\*)/)/' "$SUT" > "$MUT_NOCNTRL"
sed 's/|\*\\\\\*|/|/' "$SUT" > "$MUT_NOBSL"
sed 's/\*\[\[:space:\]\]\*)/*__never_matches__*)/' "$SUT" > "$MUT_NOWS"
assert "P11 each guard-arm mutant landed (cmp -s) and the targeted text is gone" \
  "! cmp -s '$SUT' '$MUT_NOCNTRL' && ! grep -qF '|*[[:cntrl:]]*)' '$MUT_NOCNTRL' && ! cmp -s '$SUT' '$MUT_NOBSL' && ! grep -qF '|*\\\\*|' '$MUT_NOBSL' && ! cmp -s '$SUT' '$MUT_NOWS' && grep -qF '__never_matches__' '$MUT_NOWS'"
unsafe_holds() { [[ "$EC" -eq 1 && ! -s "$SARGV" && ! -s "$SSTDIN" ]]; }  # the refusal contract of an unsafe credential
SUT_REAL="$SUT"
SUT="$MUT_NOCNTRL"; run_stub zuser $'synthetic\tfixture'; TOKTAB_HOLDS=no; unsafe_holds && TOKTAB_HOLDS=yes
run_stub $'zu\tser' synthetic-fixture-token-0001;        USRTAB_HOLDS=no; unsafe_holds && USRTAB_HOLDS=yes
run_stub $'zuser\nevilsuffix' synthetic-fixture-token-0001; USRNL_HOLDS=no; unsafe_holds && USRNL_HOLDS=yes
SUT="$MUT_NOBSL"; run_stub 'zu\ser' synthetic-fixture-token-0001; USRBS_HOLDS=no; unsafe_holds && USRBS_HOLDS=yes
SUT="$MUT_NOWS"; run_stub zuser synthetic-fixture-token-0001 $'known/repo,known/sec\tond'; WS_TEXT=no; grep -qF 'contains whitespace' <<<"$OUT" && WS_TEXT=yes
SUT="$SUT_REAL"
assert "P11 mutant (cntrl arm dropped): the tab-in-token row FAILS (the refusal no longer holds)" "[[ '$TOKTAB_HOLDS' == no ]]"
assert "P11 mutant (cntrl arm dropped): the tab-in-user row FAILS" "[[ '$USRTAB_HOLDS' == no ]]"
assert "P11 mutant (cntrl arm dropped): the newline-in-user row FAILS" "[[ '$USRNL_HOLDS' == no ]]"
assert "P11 mutant (backslash arm dropped): the backslash-in-user row FAILS" "[[ '$USRBS_HOLDS' == no ]]"
assert "P11 mutant (whitespace arm dropped): the tab-in-element row FAILS (the whitespace FATAL text is gone)" "[[ '$WS_TEXT' == no ]]"

# P13 — member shapes the rows above sampled once (each is a fixture the aggregation must treat the same way).
echo "--- #10004: positions, codes and kinds the aggregation must not special-case ---"
: > "$REQLOG"; run_probe "$SUT" "known/repo,,known/second@$DIG_GONE"
assert "P13 an INTERIOR empty element before a pinned one does not shift the pin: it is HEADed and its eviction suppresses the ping" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && grep -qxF 'HEAD /v2/known/second/manifests/$DIG_GONE' '$REQLOG' && out_marker known/second 200 servable pin-missing"
run_probe "$SUT" "known/second@$DIG_GONE,known/repo"
assert "P13 a pin fault followed by a BARE healthy element is not cleared by it" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && out_marker known/repo 200 servable none"
: > "$REQLOG"; run_probe "$SUT" "known/repo@$DIG_OK,known/second@$DIG_OK,known/repo@$DIG_GONE"
assert "P13 a THIRD pinned element is HEADed and its eviction suppresses the ping (no two-element cap)" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && [[ \"\$(req_count manifests)\" -eq 3 ]] && out_has 'ref=known/repo@$DIG_GONE repo=known/repo'"
STUB_MANIFEST_CODE=204 run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
assert "P13 a 2xx other than 200 on the pin (204) is NOT healthy: no ping, named code, marker unexpected" \
  "[[ '$PINGED' == no && '$EC' -eq 0 ]] && out_has 'unexpected code 204' && out_marker known/second 200 servable unexpected"
STUB_MANIFEST_CODE=401 STUB_MANIFEST_ONLY=known/repo run_stub zuser synthetic-fixture-token-0001 "known/repo@$DIG_OK,known/second@$DIG_OK"
assert "P13 a 401 on the FIRST pin is not cleared by a healthy SECOND pin: exit 3, no ping" \
  "[[ '$EC' -eq 3 && '$PINGED' == no ]] && out_marker known/repo 200 servable auth-broke && out_marker known/second 200 servable pinned"
tags_skip_row() {  # <tags code> <expected tags verdict> <expected exit code>
  STUB_TAGS_CODE="$1" run_stub zuser synthetic-fixture-token-0001 "known/repo,known/second@$DIG_OK"
  assert "P13 tags/list $1 on a pinned element => verdict $2, the pin is NOT HEADed (skipped), exit $3, no ping" \
    "[[ '$PINGED' == no && '$EC' -eq $3 ]] && ! grep -qF '/manifests/' '$SARGV' && out_marker known/second $1 $2 skipped"
}
tags_skip_row 204 unexpected 0
tags_skip_row 302 unexpected 0
tags_skip_row 401 auth-broke 3
# the negative controls out_marker needs (has_marker has T16): it must be able to say NO.
run_probe "$SUT" "known/repo,known/second@$DIG_GONE"
assert "T16 out_marker is strict: a pin-missing run is not pinned, and a wrong code is not a match" \
  "! out_marker known/second 200 servable pinned && ! out_marker known/second 404 servable pin-missing && out_marker known/second 200 servable pin-missing"
# Source-shape rows that no behavioural fixture can reach (comment-stripped, anchored on the call form).
probe_code() { sed 's/^[[:space:]]*#.*//' "$SUT"; }
# shellcheck disable=SC2016  # the literal $URL is the probe source text under test
# `_ping` appears twice in the comment-stripped probe: its definition and the single aggregation call. `curl` followed by
# a flag, a quote, a dollar or a continuation appears twice: one in the per-attempt `_hb_curl` (called twice by `_ping`, and
# `_hb_curl` is not a `curl` word) and one in the single request function. Counting TOKENS (not lines) sees a second call
# on a line that already holds one.
ping_words() { local n; n=$(probe_code | grep -oE '(^|[^[:alnum:]_])_ping([^[:alnum:]_]|$)' | wc -l); printf '%s' "$n" | tr -d ' '; }
curl_words() { local n; n=$(probe_code | grep -oE '(^|[^[:alnum:]_/])curl[[:space:]]+[-"$'"'"'\\]' | wc -l); printf '%s' "$n" | tr -d ' '; }
other_fetchers() { local n; n=$(probe_code | grep -cE '(/usr/bin/curl|\bwget\b|\bnc\b|/dev/tcp/)' || true); printf '%s' "$n"; }
assert "P13 _ping is defined once and called once (a second call, in any spelling, would bypass the aggregation chokepoint)" "[[ \"\$(ping_words)\" -eq 2 ]]"
assert "P13 curl appears exactly 2 times (one in the per-attempt _hb_curl, one in the single request function)" "[[ \"\$(curl_words)\" -eq 2 ]]"
assert "P13 no other network client (/usr/bin/curl, wget, nc, /dev/tcp) appears in the probe" "[[ \"\$(other_fetchers)\" -eq 0 ]]"
# Guard 2 reach: no other infra .tf reads the pinned local, and web-1's provisioner writes the env file exactly once.
tf_files() { grep -rlF "$1" "$SCRIPT_DIR" --include='*.tf' --include='*.tf.json' --include='*.hcl' --include='*.tftest.hcl' | xargs -n1 basename | sort | tr '\n' ' '; }
assert "P13 only web-probe.tf (definition) and server.tf (web-1's sites) reference the pinned local, in any terraform file form" \
  "[[ \"\$(tf_files zot_probe_repo_pinned)\" == 'server.tf web-probe.tf ' ]]"
assert "P13 the digest local is read by web-probe.tf alone" "[[ \"\$(tf_files zot_probe_digest_inngest_bootstrap)\" == 'web-probe.tf ' ]]"
block_pinned() { awk '/^resource "terraform_data" "zot_consumer_probe_install"/,/^}/' "$SERVER_TF" | grep -cF 'local.zot_probe_repo_pinned' || true; }
assert "P13 both server.tf uses (triggers_replace and the env-file printf) sit INSIDE terraform_data.zot_consumer_probe_install" "[[ \"\$(block_pinned)\" -eq 2 ]]"
env_path_writers() { grep -E '/etc/default/web-zot-consumer-probe' "$SERVER_TF" | grep -cE '(^|[^a-z])(tee|install|cp|mv|sed|dd)[[:space:]]|>>|[^-]>[[:space:]]*/etc/default/web-zot-consumer-probe' || true; }
assert "P13 web-1's provisioner has exactly ONE writer of /etc/default/web-zot-consumer-probe (no tee, cp, sed, >>, or second redirect)" "[[ \"\$(env_path_writers)\" -eq 1 ]]"
# Guard 2 reach on the BIRTH path and the baked files: nothing there may reassign the list or carry a digest literal.
assert "P13 web-probe-envwrite.sh only validates and prints the list: no assignment, and exactly one ZOT_PROBE_REPO printf slot" \
  "[[ \"\$(grep -cE '^[[:space:]]*(export[[:space:]]+)?SOLEUR_ZOT_PROBE_REPO=' '$ENVWRITE')\" -eq 0 && \"\$(grep -oE 'ZOT_PROBE_REPO=%s' '$ENVWRITE' | wc -l)\" -eq 1 ]]"
assert "P13 cloud-init.yml assigns SOLEUR_ZOT_PROBE_REPO exactly once, and the unit sets no ZOT_PROBE_REPO of its own" \
  "[[ \"\$(grep -c 'SOLEUR_ZOT_PROBE_REPO=' '$CLOUD_INIT_WEB')\" -eq 1 ]] && ! grep -qE '^[[:space:]]*Environment=.*ZOT_PROBE_REPO' '$SCRIPT_DIR/web-zot-consumer-probe.service'"
assert "P13 no baked script or unit carries a digest literal (a pin there would reach every born host)" \
  "! grep -qE '@sha256:[0-9a-f]{64}' '$ENVWRITE' '$SCRIPT_DIR/web-zot-consumer-probe.service' '$SCRIPT_DIR/web-zot-consumer-probe.timer'"
assert "P12 the ZIREF regex keeps its exact tail (a terraform-less box cannot evaluate it; this literal pins the shape)" \
  "grep -qF 'v[0-9]+\\\\.[0-9]+\\\\.[0-9]+@(sha256:[0-9a-f]{64})' '$PROBE_TF'"

# T16 additions — the new marker field is strict too.
run_override_multi "$WEB_R,$BOOT_R@$DIG_OK" 200,404
assert "T16 has_marker is strict about pin_verdict: a skipped pin is not none, and not pinned" \
  "has_marker $BOOT_R 404 empty skipped && ! has_marker $BOOT_R 404 empty none && ! has_marker $BOOT_R 404 empty pinned"

# P12 — static wiring (Guard 2). The bash suite cannot evaluate Terraform regex(), so these rows pin SHAPE (an
# anchored ZIREF regex, the right file, a trailing [0], no digest literal) and a gated `terraform console` row
# evaluates the real expression against both cloud-init files. The pin reaches web-1 only: the bare local keeps
# feeding cloud-init, so no born host bakes a pin that nothing re-delivers (cattle pin-rot).
echo "--- #10004: static wiring — the digest the probe HEADs is the digest the hosts pull ---"
zi_digest() {  # <file> -> the sha256 digest of every ZIREF pin line in it (one per line)
  sed -n 's|^[[:space:]]*ZIREF="[^"]*@\(sha256:[0-9a-f]\{64\}\)"[[:space:]]*$|\1|p' "$1"
}
ZI_WEB="$(zi_digest "$CLOUD_INIT_WEB")"; ZI_INGEST="$(zi_digest "$CLOUD_INIT_INNGEST")"
assert "P12 exactly one ZIREF digest was extracted from each cloud-init file (non-empty, single line)" \
  "[[ -n '$ZI_WEB' && -n '$ZI_INGEST' && \"\$(wc -l <<<'$ZI_WEB')\" -eq 1 && \"\$(wc -l <<<'$ZI_INGEST')\" -eq 1 ]]"
assert "P12 both hosts pull the same digest" "[[ '$ZI_WEB' == '$ZI_INGEST' ]]"
digest_line() { grep -E '^[[:space:]]*zot_probe_digest_inngest_bootstrap[[:space:]]*=' "$PROBE_TF"; }
# shellcheck disable=SC2016  # the literal ${path.module} is the HCL text under test
digest_shape_ok() {
  local l; l="$(digest_line)"
  [[ -n "$l" && "$(wc -l <<<"$l")" -eq 1 && "$l" == *'ZIREF=\"'* \
     && "$l" == *'file("${path.module}/cloud-init-inngest.yml")'* && "$l" =~ \)\[0\][[:space:]]*$ ]]
}
assert "P12 web-probe.tf derives the digest from the ZIREF= line (anchored), of cloud-init-inngest.yml, with a trailing [0]" "digest_shape_ok"
assert "P12 web-probe.tf carries NO sha256:<64 hex> literal (a hard-coded stale digest fails here)" "! grep -qE 'sha256:[0-9a-f]{64}' '$PROBE_TF'"
# shellcheck disable=SC2016  # the literal ${local.*} are the HCL text under test
PINNED_EXPECT='zot_probe_repo_pinned = join(",", [local.zot_probe_repo_web, "${local.zot_probe_repo_inngest_bootstrap}@${local.zot_probe_digest_inngest_bootstrap}"])'
pinned_join_ok() {
  [[ "$(grep -E '^[[:space:]]*zot_probe_repo_pinned[[:space:]]*=' "$PROBE_TF" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g')" == "$PINNED_EXPECT" ]]
}
assert "P12 local.zot_probe_repo_pinned is EXACTLY {the bare web repo, the bootstrap repo@digest}: two elements, the web one bare" "pinned_join_ok"
assert "P12 server.tf names the pinned local at exactly two sites (the triggers_replace entry and the env-file printf), nowhere else" \
  "[[ \"\$(grep -cF 'local.zot_probe_repo_pinned' '$SERVER_TF')\" -eq 2 ]]"
assert "P12 the cloud-init-bound value is still the BARE local (so no born host receives a pin) and holds no @" \
  "grep -qE '^[[:space:]]*zot_probe_repo[[:space:]]*=[[:space:]]*local\\.zot_probe_repo[[:space:]]*\$' '$SERVER_TF' && [[ \"\$(grep -E '^[[:space:]]*zot_probe_repo[[:space:]]*=[[:space:]]*join' '$PROBE_TF')\" != *@* ]]"
# H5 — the extraction helper reads a fixture's own digest (must-PASS, non-canonical), and returns nothing when there is no pin.
ZI_FIX="$(mktemp "$TMP/zifix.XXXXXX")"
# shellcheck disable=SC2016  # the literal $ZOT_EP is the fixture text, not an expansion
printf '        ZIREF="$ZOT_EP/acme/other:v9.9.9@sha256:%064d"\n' 0 > "$ZI_FIX"
assert "H5 zi_digest reads the fixture's own digest, not the constant" "[[ \"\$(zi_digest '$ZI_FIX')\" == \"sha256:\$(printf '%064d' 0)\" ]]"
printf '        NOT_A_PIN="x"\n' > "$ZI_FIX"
assert "H5 a file with no ZIREF line yields an EMPTY extraction (the non-empty guard has something to catch)" "[[ -z \"\$(zi_digest '$ZI_FIX')\" ]]"

# The console row evaluates the REAL expression from web-probe.tf. Gated on terraform being installed; a skip is
# printed and counted separately and never counts toward MIN_ASSERTS.
TF_SKIPPED=0
tf_console_digest() {  # <dir holding cloud-init-inngest.yml> -> the digest web-probe.tf's expression returns for it
  local dir="$1" scr expr
  scr="$(mktemp -d "$TMP/tfconsole.XXXXXX")"
  expr="$(digest_line | sed -E 's/^[[:space:]]*zot_probe_digest_inngest_bootstrap[[:space:]]*=[[:space:]]*//')"
  expr="${expr//\$\{path.module\}/$dir}"
  printf 'locals {\n  zot_probe_repo_inngest_bootstrap = "%s"\n  zot_probe_digest_inngest_bootstrap = %s\n}\n' "$TF_BOOT" "$expr" > "$scr/main.tf"
  printf 'local.zot_probe_digest_inngest_bootstrap\n' | timeout 60 terraform -chdir="$scr" console 2>/dev/null | tr -d '"\r '
}
if command -v terraform >/dev/null 2>&1; then
  TF_DIG="$(tf_console_digest "$SCRIPT_DIR")"
  assert "P12 terraform console: the expression returns a sha256 digest (a string, so [0] is in place)" "[[ '$TF_DIG' =~ ^sha256:[0-9a-f]{64}\$ ]]"
  assert "P12 terraform console: the derived digest equals the ZIREF digest of BOTH cloud-init files" "[[ '$TF_DIG' == '$ZI_WEB' && '$TF_DIG' == '$ZI_INGEST' ]]"
  FIXDIR="$(mktemp -d "$TMP/zidir.XXXXXX")"
  sed "s|@sha256:[0-9a-f]\{64\}\"|@sha256:$(printf '%064d' 0 | tr 0 c)\"|" "$CLOUD_INIT_INNGEST" > "$FIXDIR/cloud-init-inngest.yml"
  assert "H5 terraform console follows the FILE: a fixture with another digest yields that digest (must-PASS, non-canonical)" \
    "[[ \"\$(tf_console_digest '$FIXDIR')\" == \"sha256:\$(printf '%064d' 0 | tr 0 c)\" && '$TF_DIG' != \"sha256:\$(printf '%064d' 0 | tr 0 c)\" ]]"
else
  # SOLEUR_REQUIRE_TERRAFORM=1 turns the skip into a failure; it is opt-in and no workflow exports it yet.
  [[ "${SOLEUR_REQUIRE_TERRAFORM:-}" != 1 ]] || assert "terraform is required here (SOLEUR_REQUIRE_TERRAFORM=1) but is not installed" "false"
  TF_SKIPPED=$((TF_SKIPPED + 3)); echo "  SKIP: 3 terraform-console rows (terraform is not installed here) — NOT counted toward MIN_ASSERTS"
fi

# --- #9639 F6 (lean subset): the unit stops expanding the secret; the script resolves it AFTER its refusal ----------------
# Same defect and fix as web-private-nic-guard (see that suite for the full row set and the hostile-key table). This unit's
# refusal is conditional on the pull credential (ZOT_PULL_TOKEN / ZTOK) being set, or on the heartbeat key name
# (WEB_ZOT_CONSUMER_URL_KEY) being set outside --canary-only; under `doppler run` both always are, and the launches below
# set both unless a row says otherwise. The --canary-only ExecStartPre runs outside doppler and reads no URL, so the key
# name alone does not refuse it (the canary-only rows pin that).
echo "--- F6 (#9639): zot unit wrapper expands nothing; lookup follows the refusal ---"
# shellcheck disable=SC2016  # the F6 conditions are single-quoted on purpose: assert() evals them in this shell, where the variables are live
F6_URL='https://uptime.betterstack.test/api/v1/heartbeat/F6-SECRET-9639'
# shellcheck disable=SC2034  # read inside the single-quoted assert() conditions
F6_TOK=F6-SECRET-9639
F6_SCRIPT_PATH=/usr/local/bin/web-zot-consumer-probe.sh
F6_LINE="$(sed -n 's/^ExecStart=//p' "$SVC" | sed -n '1p' | sed 's/\$\$/$/g')"   # systemd's $$ is a literal $
# The pre-fix ExecStart, kept ONLY as the leak control's mutant (never compared with the tree).
F6_OLD_LINE="/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export WEB_ZOT_CONSUMER_URL=\"\${!WEB_ZOT_CONSUMER_URL_KEY}\"; exec $F6_SCRIPT_PATH'\\'''"
F6_EXEC="$TMP/f6-exec-web-zot-consumer-probe.sh"; cp "$SUT" "$F6_EXEC"; chmod +x "$F6_EXEC"   # the unit execs the path itself; the repo copy is not mode +x
printf 'set -x\n' > "$TMP/f6-xt.env"
# `doppler run ... -- CMD`: skip to the `--` and exec CMD. It never expands the secret itself (its own xtrace would print
# the value and void the leak control); the test environment pre-exports the secret, as doppler would inject it.
printf '#!/usr/bin/env bash\nwhile [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n' > "$TMP/stubbin/doppler"
chmod +x "$TMP/stubbin/doppler"
mkdir -p "$TMP/f6-dead"; printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/f6-dead/doppler"; chmod +x "$TMP/f6-dead/doppler"
run_unit() {   # <ExecStart text> <none|xtrace|benv> [extra env words, applied last] : script path rewritten to the (mutant) script
  local line="$1" form="$2" ec=0 sut="${F6_SUT:-$F6_EXEC}"; shift 2
  [[ "$line" == *"$F6_SCRIPT_PATH"* ]] || { printf '[FATAL] run_unit: the ExecStart text does not name %s; the rewrite would be a silent no-op\n' "$F6_SCRIPT_PATH" >&2; exit 1; }
  local -a fenv=()
  case "$form" in xtrace) fenv=(SHELLOPTS=xtrace) ;; benv) fenv=(BASH_ENV="$TMP/f6-xt.env") ;; esac
  MARKER_N=$((MARKER_N + 1))
  HB_ARGV="$(mktemp "$TMP/hbargv.XXXXXX")"; HB_STDIN="$(mktemp "$TMP/hbstdin.XXXXXX")"; HOUT="$(mktemp "$TMP/hbout.XXXXXX")"
  env -u SOLEUR_ZOT_PROBE_PING_LOG -u SOLEUR_ZOT_PROBE_STATUS_OVERRIDE -u WEB_ZOT_CONSUMER_URL -u SHELLOPTS -u BASH_ENV -u ZOT_PULL_TOKEN -u ZOT_PULL_USER -u ZTOK -u ZUSER \
    STUB_ARGV="$TMP/hbreg.argv.$MARKER_N" STUB_STDIN="$TMP/hbreg.stdin.$MARKER_N" STUB_HB_ARGV="$HB_ARGV" STUB_HB_STDIN="$HB_STDIN" \
    PATH="$TMP/stubbin:$PATH" SOLEUR_PROBE_REPOS_MARKER="$TMP/repos.$MARKER_N" SOLEUR_PROBE_CANARY_MARKER="$TMP/canary.$MARKER_N" \
    SOLEUR_PROBE_REFUSAL_MARKER="$TMP/refusal.$MARKER_N" \
    ZOT_ENDPOINT=127.0.0.1:9 ZOT_PROBE_REPO=known/repo ZOT_PULL_USER=zuser ZOT_PULL_TOKEN=ztok \
    WEB_ZOT_CONSUMER_URL_KEY=WEB_ZOT_CONSUMER_URL_SYNTH WEB_ZOT_CONSUMER_URL_SYNTH="$F6_URL" \
    ${fenv[@]+"${fenv[@]}"} "$@" \
    timeout 20 bash -c 'eval "$1"' _ "${line//"$F6_SCRIPT_PATH"/$sut}" >"$HOUT" 2>&1 || ec=$?
  HEC=$ec
  # shellcheck disable=SC2034  # read by NAME inside the assert() eval strings
  HOUTTXT="$(cat "$HOUT")"
  N_HB="$(wc -l < "$HB_ARGV" | tr -d ' ')"
}
assert "F6 static: no Exec* directive of the zot unit holds an indirect expansion" \
  '[[ "$(grep -cE "^[[:space:]]*Exec[A-Za-z]*=.*[$]{1,2}[{][!]" "$SVC" || true)" -eq 0 ]]'
assert "F6 static: ExecStart runs the probe directly under doppler run: names it, no dollar sign, no export" \
  '[[ "$F6_LINE" == *"$F6_SCRIPT_PATH"* && "$F6_LINE" != *\$* && "$F6_LINE" != *export* && "$F6_LINE" == *"doppler run"* ]]'
for f6_form in xtrace benv; do
  run_unit "$F6_LINE" "$f6_form"
  assert "F6 unit[$f6_form]: the real ExecStart exits 78 with the refusal on a non-trace line (the script RAN; got rc=$HEC)" \
    '[[ "$HEC" -eq 78 && "$(grep -v "^+" "$HOUT" | grep -c "refusing to trace with a live credential" || true)" -ge 1 ]]'
  assert "F6 unit[$f6_form]: the heartbeat URL (and its secret path token) is in neither stream and no request was made" \
    '[[ "$HOUTTXT" != *"$F6_TOK"* && "$N_HB" -eq 0 ]]'
done
run_unit "$F6_OLD_LINE" xtrace
assert "F6 control: the PRE-FIX ExecStart under SHELLOPTS=xtrace prints the secret (the harness can see the defect; rc=$HEC)" \
  '[[ "$HOUTTXT" == *"$F6_TOK"* && "$HEC" -eq 78 ]]'
run_unit "$F6_LINE" xtrace PATH="$TMP/f6-dead:$TMP/stubbin:$PATH"
assert "F6 dispatch: with a doppler that never execs the probe there is NO refusal text (so the rows above discriminate)" \
  '[[ "$HOUTTXT" != *"refusing to trace"* && "$HEC" -eq 0 ]]'
run_unit "$F6_LINE" none
assert "F6 positive: the untraced real ExecStart delivers the URL to the heartbeat curl on its stdin config, once (rc=$HEC)" \
  '[[ "$HEC" -eq 0 && "$N_HB" -eq 1 ]] && hb_stdin_all_are "$F6_URL"'
run_unit "$F6_LINE" none WEB_ZOT_CONSUMER_URL_KEY=WEB_ZOT_CONSUMER_URL_WEB_1 WEB_ZOT_CONSUMER_URL_WEB_1="$F6_URL"
assert "F6 production-shaped key [WEB_ZOT_CONSUMER_URL_WEB_1] resolves and delivers" '[[ "$N_HB" -eq 1 ]] && hb_stdin_all_are "$F6_URL"'
run_unit "$F6_LINE" none WEB_ZOT_CONSUMER_URL=https://uptime.betterstack.test/api/v1/heartbeat/STRAY-9639
assert "F6 transitional: a stray exported bare WEB_ZOT_CONSUMER_URL (old wrapper) loses to the key's value" '[[ "$N_HB" -eq 1 ]] && hb_stdin_all_are "$F6_URL"'
F6_PLANT="$TMP/f6-plant"; rm -f "$F6_PLANT"
run_unit "$F6_LINE" none "WEB_ZOT_CONSUMER_URL_KEY=a[\$(touch $F6_PLANT)]"
assert "F6 hostile key a[\$(touch ...)]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
  '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"WEB_ZOT_CONSUMER_URL_KEY"* && "$HOUTTXT" != *touch* ]]'
run_unit "$F6_LINE" none "WEB_ZOT_CONSUMER_URL_KEY=lowercase"
assert "F6 lowercase key: refused, no heartbeat, exit 0" '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"WEB_ZOT_CONSUMER_URL_KEY"* ]]'
# Every Exec* line of the unit (backslash continuations joined, as systemd reads them): ExecStartPre AND ExecStart.
# shellcheck disable=SC2034  # read inside the single-quoted assert() condition
F6_ALLEXEC="$(awk '{ if (sub(/\\$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' "$SVC" | grep -E '^[[:space:]]*Exec[A-Za-z]*=' || true)"
assert "F6 static: EVERY Exec* directive of the zot unit (continuations joined) is dollar-free and export-free, so no second line can expand the secret" \
  '[[ -n "$F6_ALLEXEC" && "$F6_ALLEXEC" != *\$* && "$F6_ALLEXEC" != *export* ]]'
# Both refusal disjuncts: the pull credential alone, and the heartbeat key name alone (outside --canary-only).
run_unit "$F6_LINE" xtrace ZOT_PULL_TOKEN=
assert "F6 refusal[key only]: with the key name set and no pull credential, a traced launch exits 78 with the URL in neither stream (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to trace"* && "$HOUTTXT" != *"$F6_TOK"* && "$N_HB" -eq 0 ]]'
run_unit "$F6_LINE" xtrace WEB_ZOT_CONSUMER_URL_KEY=
assert "F6 refusal[credential only]: with the pull credential set and no key name, a traced launch exits 78 (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to trace"* && "$N_HB" -eq 0 ]]'
# --canary-only (the ExecStartPre, outside doppler): the key name alone must NOT refuse it, a pull credential still does.
F6_CANARY_LINE="$(sed -n 's/^ExecStartPre=-//p' "$SVC" | sed -n '1p')"
run_unit "$F6_CANARY_LINE" xtrace ZOT_PULL_TOKEN=
assert "F6 canary-only[key only, traced]: the canary RUNS: no refusal, exit 0, the Source-4 canary line is emitted and its marker written, the URL is in no stream (rc=$HEC)" \
  '[[ "$HEC" -eq 0 && "$HOUTTXT" != *"refusing to trace"* && "$HOUTTXT" != *"$F6_TOK"* && -s "$TMP/canary.$MARKER_N" && "$(grep -v "^+" "$HOUT" | grep -c "SOLEUR_PROBE_CANARY" || true)" -ge 1 ]]'
# The legacy credential name (ZTOK) is a disjunct of its own, and the argument shapes that are NOT the exact --canary-only
# launch must refuse (a looser test of "${1:-}" would admit them).
run_unit "$F6_LINE" xtrace ZOT_PULL_TOKEN= ZTOK=ztok WEB_ZOT_CONSUMER_URL_KEY=
assert "F6 refusal[legacy ZTOK only]: with only the legacy-named pull credential set, a traced launch exits 78 (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to trace"* && "$N_HB" -eq 0 ]]'
F6_EMPTYARG="''"
for f6_shape in "foo --canary-only" "--canary-only=1" "$F6_EMPTYARG"; do
  run_unit "${F6_CANARY_LINE/--canary-only/$f6_shape}" xtrace ZOT_PULL_TOKEN=
  assert "F6 canary-only shape [$f6_shape]: only the exact --canary-only argument is exempt; any other argument shape with the key name set refuses (rc=$HEC)" \
    '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to trace"* && "$HOUTTXT" != *"$F6_TOK"* ]]'
done
run_unit "$F6_CANARY_LINE" xtrace WEB_ZOT_CONSUMER_URL_KEY=
assert "F6 canary-only[credential, traced]: a pull credential still refuses the canary, exactly as before (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to trace"* ]]'
# Not exported: the heartbeat curl dumps ITS environment; only the key-named line (where doppler injects the secret) may hold the URL.
F6_ENVDUMP="$TMP/f6-envdump"; rm -f "$F6_ENVDUMP"
run_unit "$F6_LINE" none STUB_HB_ENVDUMP="$F6_ENVDUMP"
assert "F6 not exported: the resolved URL reaches no child environment (only the injected key-named variable holds it)" \
  '[[ -s "$F6_ENVDUMP" && "$(grep -v "^WEB_ZOT_CONSUMER_URL_SYNTH=" "$F6_ENVDUMP" | grep -cF -- "$F6_URL" || true)" -eq 0 && "$(grep -cF -- "$F6_URL" "$F6_ENVDUMP" || true)" -eq 1 ]]'
rm -f "$F6_ENVDUMP"
run_unit "$F6_LINE" none STUB_HB_ENVDUMP="$F6_ENVDUMP" URL=https://uptime.betterstack.test/api/v1/heartbeat/PRESET-9639
assert "F6 preset URL: an exported URL inherited from the environment does not ride the heartbeat curl's environment (no URL= line)" \
  '[[ -s "$F6_ENVDUMP" && "$(grep -c "^URL=" "$F6_ENVDUMP" || true)" -eq 0 && "$N_HB" -eq 1 ]]'
# The BODY clause of _key_ok: upper-case-led names whose only illegal bytes are the ones bash evaluates inside ${!name}.
# A lowercase lead is refused by the earlier clause and would never reach it.
for f6_k in "A[\$(touch $F6_PLANT)]" "A[0]" "A[B]" "A=B" "A.B" "A/B" "A@" "A*"; do
  rm -f "$F6_PLANT"; run_unit "$F6_LINE" none "WEB_ZOT_CONSUMER_URL_KEY=$f6_k"
  assert "F6 body-clause key [$f6_k]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
    '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"WEB_ZOT_CONSUMER_URL_KEY"* && "$HOUTTXT" != *"$f6_k"* ]]'
done
# Every printable ASCII character outside [A-Z0-9_], inside an upper-case-led name, is refused: a generated list, not a hand-picked one.
f6_bodybad=""
for f6_ord in $(seq 33 126); do
  f6_c="$(printf "\\x$(printf '%02x' "$f6_ord")")"
  case "$f6_c" in [A-Z0-9_]) continue ;; esac
  rm -f "$F6_PLANT"; run_unit "$F6_LINE" none "WEB_ZOT_CONSUMER_URL_KEY=A${f6_c}B"
  { [[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"WEB_ZOT_CONSUMER_URL_KEY"* ]]; } || f6_bodybad+="$f6_c"
done
assert "F6 body clause (generated): every printable ASCII character outside [A-Z0-9_] inside an upper-case-led key is refused (offenders: [$f6_bodybad])" \
  '[[ -z "$f6_bodybad" ]]'
# Order: a mutant that resolves the URL above the refusal leaks it under SHELLOPTS=xtrace.
F6_MUT="$TMP/f6-mut-hoist-zot.sh"
sed '/^set -u$/a\
__leak="${!WEB_ZOT_CONSUMER_URL_KEY:-}"' "$SUT" > "$F6_MUT"; chmod +x "$F6_MUT"
assert "F6 mutant[hoist]: the edit landed (the copy differs from the SUT)" '! cmp -s "$SUT" "$F6_MUT"'
F6_SUT="$F6_MUT" run_unit "$F6_LINE" xtrace
assert "F6 mutant[hoist]: a lookup hoisted above the refusal leaks the URL under SHELLOPTS=xtrace (the order row can see it)" '[[ "$HOUTTXT" == *"$F6_TOK"* ]]'
f6z_line_of() { awk -v n="$1" 'index($0, n) && $0 !~ /^[[:space:]]*#/ { print NR; exit }' "$SUT"; }   # first NON-comment line holding the text
assert "F6 order: the indirect lookup is on a later line than the refusal AND than the --canary-only exit" \
  '[[ -n "$(f6z_line_of "refusing to trace with a live credential")" && "$(f6z_line_of "\${!WEB_ZOT_CONSUMER_URL_KEY")" -gt "$(f6z_line_of "refusing to trace with a live credential")" && "$(f6z_line_of "\${!WEB_ZOT_CONSUMER_URL_KEY")" -gt "$(f6z_line_of "if [ \"\${1:-}\" = \"--canary-only\" ]")" ]]'

[[ "$TF_SKIPPED" -eq 0 ]] || echo "=== $TF_SKIPPED terraform-console rows skipped (not counted) ==="
echo
echo "=== $PASS passed, $FAIL failed ==="
# Anti-vacuity floor (ADR-193): a disarmed assert() or a skipped block must not read as green. Raise it in
# the SAME edit that adds rows; it is reported with printf, never through assert().
# 427 assertions run with terraform installed; the 3 terraform-console rows are gated and a skip never counts, so
# a box without terraform floors at the count WITHOUT them (424) and must not read as a disarmed suite. The threshold
# literal sits directly above the `if` (scripts/guard-vacuity-floor.test.sh builds its mutant from that adjacency);
# the stricter full count applies in a SECOND check wherever terraform ran, so no row can be deleted behind slack.
MIN_ASSERTS=424
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTS" ]]; then
  printf 'FAIL: only %s assertions ran (floor %s) — a block was skipped or assert() was disarmed\n' "$((PASS + FAIL))" "$MIN_ASSERTS"
  exit 1
fi
if [[ "$TF_SKIPPED" -eq 0 && "$((PASS + FAIL))" -lt "$((MIN_ASSERTS + 3))" ]]; then
  printf 'FAIL: only %s assertions ran with terraform present (floor %s) — a row was deleted\n' "$((PASS + FAIL))" "$((MIN_ASSERTS + 3))"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
