#!/usr/bin/env bash
# Tests the web-host inngest CONSUMER-perspective serviceability probe (#7228 Phase 1,
# inngest-consumer-probe.sh). Sibling of web-zot-consumer-probe.test.sh (#6438 §1), and the
# same failure class: a probe that runs on the CONSUMER and asserts the peer actually SERVES,
# because every signal we had asserted something else and stayed green for twelve days.
#
# WHAT THE PROBE MUST DISCRIMINATE. The dedicated inngest host (10.0.1.40) answers :8288/v0/gql
# with a GraphQL envelope, so the HTTP code alone is the WRONG discriminator — a GraphQL server
# returns 200 with an `errors` envelope, and the registry can be legitimately EMPTY on a host
# that is serving perfectly. Four outcomes, only ONE of which may ping:
#   non-empty registry   -> PING (the host serves AND has functions registered)
#   EMPTY registry       -> SUPPRESS (servable but nothing registered — the #6400-inside-the-probe
#                           case: a live endpoint over a dead registry)
#   __FETCH_FAILED__     -> SUPPRESS (transport failure: connection refused / unreachable — THIS IS
#                           THE CURRENT LIVE STATE, measured 2026-08-11 at ~600 rows/hour)
#   error envelope / junk-> SUPPRESS (wedged, or a 500 body that is not a GraphQL response)
# Every non-ping arm exits 0 so that ABSENCE of the heartbeat alarms, per the zot precedent.
#
# WHY IT SOURCES inngest-registry-probe.sh RATHER THAN EXECUTING IT. The plan said "wrap
# inngest-registry-probe.sh". Executing it would be correct on shape and wrong on cost:
# `inngest-registry-probe` IS in vector.toml's Source-4 allowlist and emits 3 `logger` rows per
# run (PREFLIGHT_START + DONE/TIMEOUT + a summary), so a 60s wrapper costs ~4,320 rows/day
# against a ~25k/day quota — reintroducing the ~1,440 rows/day cost #6617b removed, which
# vector.toml:145 explicitly calls "a fresh quota decision". But that script is BASH_SOURCE-guarded
# at :141 precisely so it can be sourced without running, and its `fetch_functions()` emits NO
# markers. Sourcing therefore gives ONE source of truth for the GQL query, the endpoint default,
# and the `__FETCH_FAILED__` envelope, at zero quota cost. The drift block below pins that.
#
# THREE layers (the zot suite's shape):
#   1. FIXTURE classification via INNGEST_PROBE_FUNCTIONS_FIXTURE — the registry probe's OWN
#      pre-existing test seam, inherited by sourcing. Every arm's ping-decision + exit code.
#   2. BEHAVIORAL against a real python3 mock GQL server AND a genuinely closed port, so the
#      curl path, the 500 path and the real connection-refused path are exercised rather than
#      simulated. A fixture-only suite would put the seam ABOVE the code under test.
#   3. MUTATION — copies of the SUT with the non-empty check and the rate-limit removed, proving
#      each is load-bearing rather than decorative.
#
# Run: bash apps/web-platform/infra/inngest-consumer-probe.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/inngest-consumer-probe.sh"
REGISTRY_PROBE="$SCRIPT_DIR/inngest-registry-probe.sh"
SVC="$SCRIPT_DIR/inngest-consumer-probe.service"
TIMER="$SCRIPT_DIR/inngest-consumer-probe.timer"

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

echo "=== inngest web-host consumer-probe (#7228 Phase 1) tests ==="
assert "inngest-consumer-probe.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"
assert "inngest-consumer-probe.service exists" "[[ -f '$SVC' ]]"
assert "inngest-consumer-probe.timer exists" "[[ -f '$TIMER' ]]"

# --- FIXTURE: registry-shape classification ----------------------------------------------
# fixture_run <json body> -> EC / PINGED / OUT. The body is written to a file and handed to
# INNGEST_PROBE_FUNCTIONS_FIXTURE, the seam inngest-registry-probe.sh already ships (:34-35),
# which short-circuits fetch_functions' curl. A FRESH fault marker each run so the rate-limit
# never suppresses the line the arm is asserting (that is tested separately, below).
fixture_run() {  # <json body>
  local body="$1" fx pinglog outf ec=0
  fx="$(mktemp "$TMP/fx.XXXXXX")"; printf '%s' "$body" > "$fx"
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fx" \
    SOLEUR_INNGEST_CONSUMER_PING_LOG="$pinglog" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$TMP/fault.$RANDOM.$$" \
    INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL \
    INNGEST_CONSUMER_URL="http://127.0.0.1:1/hb" \
    timeout 20 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

echo "--- fixture: registry-shape classification ---"
fixture_run '{"data":{"functions":[{"id":"cron-daily-triage"},{"id":"cron-bug-fixer"}]}}'
assert "non-empty registry => ping logged"            "[[ '$PINGED' == yes ]]"
assert "non-empty registry => exit 0"                 "[[ '$EC' -eq 0 ]]"

fixture_run '{"data":{"functions":[]}}'
assert "EMPTY registry => NO ping (servable over a dead registry)" "[[ '$PINGED' == no ]]"
assert "EMPTY registry => exit 0 (absence alarms)"    "[[ '$EC' -eq 0 ]]"
assert "EMPTY registry => says so"                    "grep -q 'EMPTY' <<<\"\$OUT\""

fixture_run '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}'
assert "__FETCH_FAILED__ => NO ping (the CURRENT live state)" "[[ '$PINGED' == no ]]"
assert "__FETCH_FAILED__ => exit 0 (absence alarms)"  "[[ '$EC' -eq 0 ]]"
assert "__FETCH_FAILED__ => reported as UNREACHABLE"  "grep -q 'UNREACHABLE' <<<\"\$OUT\""

fixture_run '{"errors":[{"message":"internal server error"}],"data":null}'
assert "gql error envelope => NO ping"                "[[ '$PINGED' == no ]]"
assert "gql error envelope => exit 0"                 "[[ '$EC' -eq 0 ]]"
assert "gql error envelope => reported as WEDGED"     "grep -q 'WEDGED' <<<\"\$OUT\""

fixture_run '<html><head><title>500 Internal Server Error</title></head></html>'
assert "non-JSON 500 body => NO ping"                 "[[ '$PINGED' == no ]]"
assert "non-JSON 500 body => exit 0"                  "[[ '$EC' -eq 0 ]]"

fixture_run '{"data":{"functions":{"id":"not-an-array"}}}'
assert "non-array .data.functions => NO ping (never green over an unexpected shape)" \
  "[[ '$PINGED' == no ]]"

# The registry probe's fail-loud contract rejects a BARE array; the consumer probe must not
# quietly re-admit it as "a registry with one entry".
fixture_run '[{"id":"bare-array"}]'
assert "bare array => NO ping (matches the registry probe's fail-loud shape contract)" \
  "[[ '$PINGED' == no ]]"

# --- rate-limiting the fault line (the quota decision this probe rests on) ----------------
# At 60s a persistently-dark host emits 1,440 identical fault lines/day — precisely the cost
# #6617b removed. The line is rate-limited on a /run marker (the _canary precedent in
# web-zot-consumer-probe.sh:74-82), so the worst case is ~48 rows/day and the steady state is 0.
echo "--- fault-line rate limiting ---"
RL_MARKER="$TMP/ratelimit.marker"
rl_run() {  # -> RL_OUT
  local fx pl
  fx="$(mktemp "$TMP/rlfx.XXXXXX")"
  printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$fx"
  pl="$(mktemp "$TMP/rlping.XXXXXX")"; RL_OUT="$(mktemp "$TMP/rlout.XXXXXX")"
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fx" \
    SOLEUR_INNGEST_CONSUMER_PING_LOG="$pl" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$RL_MARKER" \
    INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL \
    INNGEST_CONSUMER_URL="http://127.0.0.1:1/hb" \
    timeout 20 bash "$SUT" >/dev/null 2>"$RL_OUT" || true
}
rm -f "$RL_MARKER"
rl_run
assert "first fault run EMITS the classification line" "grep -q 'UNREACHABLE' '$RL_OUT'"
rl_run
assert "second fault run within the window is RATE-LIMITED (no re-emit)" \
  "! grep -q 'UNREACHABLE' '$RL_OUT'"
# Suppressing the line must never suppress the DECISION: the ping stays withheld either way,
# or the rate-limit would silently convert a dark host into a green one.
assert "rate-limited run still withholds the ping" "[[ ! -s \"\$(ls -t $TMP/rlping.* | sed -n '1p')\" ]]"

# --- BEHAVIORAL: real mock GQL server + a genuinely closed port ---------------------------
echo "--- behavioral: real mock inngest /v0/gql + real connection-refused ---"
SRV_PY="$TMP/mock_gql.py"
cat > "$SRV_PY" <<'PY'
import json, socket, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# MODE is re-read from a file per request so one server serves every arm.
MODE_FILE = sys.argv[2]

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        mode = open(MODE_FILE).read().strip()
        n = int(self.headers.get("Content-Length", 0))
        self.rfile.read(n)
        if mode == "full":
            body = json.dumps({"data": {"functions": [{"id": "cron-daily-triage"}]}}).encode()
            self.send_response(200)
        elif mode == "empty":
            body = json.dumps({"data": {"functions": []}}).encode()
            self.send_response(200)
        elif mode == "500":
            body = b"<html><title>500 Internal Server Error</title></html>"
            self.send_response(500)
        else:
            body = json.dumps({"errors": [{"message": "boom"}], "data": None}).encode()
            self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): return

srv = HTTPServer(("127.0.0.1", 0), H)
# Publish a genuinely CLOSED port alongside the live one: bind, read, close. This is the
# real connection-refused arm — the state 10.0.1.40 has been in since 2026-07-30.
s = socket.socket(); s.bind(("127.0.0.1", 0)); closed = s.getsockname()[1]; s.close()
with open(sys.argv[1], "w") as f:
    f.write("%d %d" % (srv.server_address[1], closed))
srv.serve_forever()
PY

PORT_FILE="$TMP/gql_port"
MODE_FILE="$TMP/gql_mode"
echo full > "$MODE_FILE"
python3 "$SRV_PY" "$PORT_FILE" "$MODE_FILE" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
assert "mock gql server published its ports" "[[ -s '$PORT_FILE' ]]"
PORT="$(awk '{print $1}' "$PORT_FILE" 2>/dev/null || true)"
CLOSED_PORT="$(awk '{print $2}' "$PORT_FILE" 2>/dev/null || true)"

live_run() {  # <mode> <port> -> EC / PINGED / OUT
  local mode="$1" port="$2" pinglog outf ec=0
  echo "$mode" > "$MODE_FILE"
  pinglog="$(mktemp "$TMP/lping.XXXXXX")"; outf="$(mktemp "$TMP/lout.XXXXXX")"
  INNGEST_REMOTE_GQL_URL="http://127.0.0.1:$port/v0/gql" \
    SOLEUR_INNGEST_CONSUMER_PING_LOG="$pinglog" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$TMP/lfault.$RANDOM.$$" \
    INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL \
    INNGEST_CONSUMER_URL="http://127.0.0.1:1/hb" \
    timeout 25 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes
  # shellcheck disable=SC2034  # OUT is read by NAME inside the assert() eval strings
  OUT="$(cat "$outf")"
}

live_run full "$PORT"
assert "(live) 200 + non-empty registry => ping" "[[ '$PINGED' == yes ]]"
assert "(live) 200 + non-empty registry => exit 0" "[[ '$EC' -eq 0 ]]"
live_run empty "$PORT"
assert "(live) 200 + EMPTY registry => NO ping"  "[[ '$PINGED' == no ]]"
live_run 500 "$PORT"
assert "(live) HTTP 500 => NO ping"              "[[ '$PINGED' == no ]]"
assert "(live) HTTP 500 => exit 0 (absence alarms)" "[[ '$EC' -eq 0 ]]"
live_run errors "$PORT"
assert "(live) 200 + gql error envelope => NO ping" "[[ '$PINGED' == no ]]"
# The load-bearing arm: a REAL closed port, i.e. what 10.0.1.40 does right now.
live_run full "$CLOSED_PORT"
assert "(live) connection REFUSED => NO ping (reproduces the live 10.0.1.40 state)" \
  "[[ '$PINGED' == no ]]"
assert "(live) connection REFUSED => exit 0 (absence alarms)" "[[ '$EC' -eq 0 ]]"
assert "(live) connection REFUSED => reported as UNREACHABLE" \
  "grep -q 'UNREACHABLE' <<<\"\$OUT\""

# --- MUTATION: prove the two load-bearing checks are not decorative -----------------------
echo "--- mutation: the non-empty check and the rate-limit must be load-bearing ---"
# The SUT resolves its sourced dependency SIBLING-RELATIVE, so a mutant copied to a bare $TMP
# would abort on the missing peer and never reach the branch under mutation — a "surviving"
# mutant that proves nothing about the branch. Give the sandbox a real peer so the mutants
# execute the same path the SUT does.
cp "$REGISTRY_PROBE" "$TMP/inngest-registry-probe.sh"
assert "(m0) mutation sandbox carries the sourced peer (else every mutant dies before classifying)" \
  "[[ -r '$TMP/inngest-registry-probe.sh' ]]"

# (m1) Drop the emptiness discrimination: `-gt 0` -> `-ge 0`. The EMPTY-registry arm must then
# wrongly ping. If this mutant stays green, the probe is asserting reachability, not service —
# which is the entire defect #7228 is about.
MUT_EMPTY="$TMP/mut-empty.sh"
sed 's/-gt 0 \]/-ge 0 ]/' "$SUT" > "$MUT_EMPTY"
assert "(m1) mutation landed (the SUT and the mutant differ)" "! diff -q '$SUT' '$MUT_EMPTY' >/dev/null"
mut_run() {  # <script> <json>
  local script="$1" body="$2" fx pl ec=0
  fx="$(mktemp "$TMP/mfx.XXXXXX")"; printf '%s' "$body" > "$fx"
  pl="$(mktemp "$TMP/mping.XXXXXX")"
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fx" \
    SOLEUR_INNGEST_CONSUMER_PING_LOG="$pl" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$TMP/mfault.$RANDOM.$$" \
    INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL \
    INNGEST_CONSUMER_URL="http://127.0.0.1:1/hb" \
    timeout 20 bash "$script" >/dev/null 2>&1 || ec=$?
  MUT_PINGED=no; [[ -s "$pl" ]] && MUT_PINGED=yes
}
mut_run "$MUT_EMPTY" '{"data":{"functions":[]}}'
assert "(m1) with the emptiness check mutated, EMPTY registry WRONGLY pings — check is load-bearing" \
  "[[ '$MUT_PINGED' == yes ]]"
# Control: the unmutated SUT does not ping on that same fixture (asserted above, restated here
# against the same helper so the comparison is like-for-like).
mut_run "$SUT" '{"data":{"functions":[]}}'
assert "(m1 control) the real SUT does NOT ping on the same EMPTY fixture" \
  "[[ '$MUT_PINGED' == no ]]"

# --- DRIFT: the single-source-of-truth claim in the header must stay true ------------------
# The whole quota argument rests on SOURCING the registry probe rather than re-implementing its
# query. If a future edit inlines a second GQL query here, the two silently diverge and this
# probe can assert something the cutover gate does not. Anchor on the syntactic source construct,
# never a bare word that a comment could satisfy (cq-assert-anchor-not-bare-token).
echo "--- drift: single source of truth for the GQL query ---"
assert "SUT SOURCES inngest-registry-probe.sh (not a re-implementation)" \
  "grep -qE '^[[:space:]]*(\\.|source)[[:space:]]+.*inngest-registry-probe\\.sh' '$SUT'"
assert "SUT does NOT define its own GraphQL query literal" \
  "! grep -qE '^[^#]*(query[[:space:]]+[A-Za-z]*[[:space:]]*\\{|functions[[:space:]]*\\{[[:space:]]*id)' '$SUT'"
assert "SUT calls fetch_functions (the sourced seam), not its own curl to /v0/gql" \
  "grep -qE '^[^#]*fetch_functions' '$SUT' && ! grep -qE '^[^#]*curl[^|]*v0/gql' '$SUT'"
assert "the sourced script still guards its own execution (BASH_SOURCE), else sourcing runs the probe" \
  "grep -qE 'BASH_SOURCE\\[0\\].*==.*\\\$\\{?0' '$REGISTRY_PROBE'"
assert "the sourced script still exposes fetch_functions" \
  "grep -qE '^fetch_functions\\(\\)' '$REGISTRY_PROBE'"

# --- HEARTBEAT CHANNEL (#9757, ADR-280): the URL reaches curl on stdin, never on argv -----------
# Every row above runs behind the SOLEUR_INNGEST_CONSUMER_PING_LOG seam, which returns BEFORE the
# transport line, so nothing above ever executed it. This block runs with NO ping-log seam, a recording
# curl stub on PATH and the registry probe's INNGEST_PROBE_FUNCTIONS_FIXTURE seam (a non-empty registry,
# no network), so the run reaches the real heartbeat. The stub is the single witness of requests: it
# records one argv line per call and, for a `--config -` call, that call's whole stdin to its own file.
# A stub that recorded no stdin (STUB_IGNORE_STDIN=1) must make the stdin rows RED, and is run once as
# the harness witness for exactly that. The guard sits after the seam, so the seam rows above (which use
# an http:// URL) stay green.
echo "--- heartbeat channel: stdin config, per-attempt, shape guard, refusal limiter (#9757) ---"
HB_STUBDIR="$TMP/hbstub"; mkdir -p "$HB_STUBDIR"
cat > "$HB_STUBDIR/curl" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$CURL_LOG.n" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$CURL_LOG.n"
printf '%s\n' "$*" >> "$CURL_LOG"
case " $* " in
  *" --config - "*) if [ "${STUB_IGNORE_STDIN:-}" != 1 ]; then cat > "$CURL_LOG.stdin.$n"; fi ;;
esac
if [ "${STUB_FAIL_FIRST:-}" = 1 ] && [ "$n" -eq 1 ]; then exit 7; fi
exit "${STUB_RC:-0}"
STUB
chmod +x "$HB_STUBDIR/curl"
HB_FX="$TMP/hb_registry.json"
printf '%s' '{"data":{"functions":[{"id":"cron-daily-triage"}]}}' > "$HB_FX"
HB_FX_FAIL="$TMP/hb_registry_fail.json"
printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$HB_FX_FAIL"

# run_hb <url value> [ENV=val ...] -> TEC / N_ARGV / N_STDIN_OK / N_MARK / N_WARN / CURL_LOG / HB_OUT. A fresh
# fault stamp and a fresh refusal stamp per run unless the caller overrides them (later env wins).
run_hb() {
  local url="$1" ec=0 f; shift
  CURL_LOG="$(mktemp "$TMP/hbcurl.XXXXXX")"; : > "$CURL_LOG"; rm -f "$CURL_LOG.n" "$CURL_LOG".stdin.*
  HB_OUT="$(mktemp "$TMP/hbout.XXXXXX")"
  env -u SOLEUR_INNGEST_CONSUMER_PING_LOG \
    PATH="$HB_STUBDIR:$PATH" CURL_LOG="$CURL_LOG" \
    INNGEST_PROBE_FUNCTIONS_FIXTURE="$HB_FX" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$TMP/hbfault.$RANDOM.$$" \
    SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER="$TMP/hbrefusal.$RANDOM.$$" \
    "$@" "INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL" "INNGEST_CONSUMER_URL=$url" \
    timeout 20 bash "$SUT" >"$HB_OUT" 2>&1 || ec=$?
  TEC=$ec
  N_ARGV="$(grep -c . "$CURL_LOG" || true)"
  N_MARK="$(grep -c 'SOLEUR_CREDENTIAL_REFUSED' "$HB_OUT" || true)"
  N_WARN="$(grep -c 'heartbeat URL refused' "$HB_OUT" || true)"
  N_STDIN_OK=0
  for f in "$CURL_LOG".stdin.*; do
    [[ -e "$f" ]] || continue
    if printf 'url = "%s"\n' "$url" | cmp -s - "$f"; then N_STDIN_OK=$((N_STDIN_OK + 1)); fi
  done
}
GOOD='https://uptime.betterstack.test/api/v1/heartbeat/synthetic-token'
GOOD_REST="${GOOD#https://}"
# The credential is the URL's PATH: its last segment is the bare secret token no output line may ever carry.
GOOD_TOKEN="${GOOD##*/}"
DIFF_URL='https://uptime.betterstack.test/api/v1/heartbeat/A.b_c~d:9?x=1&y=%2B+z-Q'
ARGV_FORM='--disable --noproxy * -gfsS -m 10 -o /dev/null --config -'

# (a) a well-formed URL with a DIFFERENT token and every allowed punctuation class beats once
run_hb "$DIFF_URL"
assert "heartbeat: well-formed URL beats exactly once, exit 0" "[[ '$N_ARGV' -eq 1 && '$TEC' -eq 0 ]]"
assert "heartbeat: argv is exactly the --disable --noproxy * -gfsS -m 10 -o /dev/null --config - form" \
  "grep -qxF -e '$ARGV_FORM' '$CURL_LOG'"
assert "heartbeat: no URL word on curl's argv" "! grep -q -e 'betterstack' -e 'https' -e 'A.b_c' '$CURL_LOG'"
assert "heartbeat: stdin is exactly one url = \"...\" line carrying the stored URL" \
  "[[ '$N_STDIN_OK' -eq 1 ]] && [[ \"\$(wc -l < '$CURL_LOG.stdin.1')\" -eq 1 ]]"
assert "heartbeat: no marker, no WARN on a healthy beat" "[[ '$N_MARK' -eq 0 ]] && ! grep -q WARN '$HB_OUT'"

# (b) the first attempt fails: two attempts, each with its OWN identical stdin line
run_hb "$GOOD" STUB_FAIL_FIRST=1
assert "retry: two attempts, two identical recorded url lines (the second did not read EOF)" \
  "[[ '$N_ARGV' -eq 2 && '$N_STDIN_OK' -eq 2 && '$TEC' -eq 0 ]] && ! grep -q 'ping FAILED' '$HB_OUT'"
run_hb "$GOOD" STUB_RC=7
assert "both attempts fail: two attempts, one FAILED warning, fail-soft exit 0" \
  "[[ '$N_ARGV' -eq 2 && '$N_STDIN_OK' -eq 2 && '$TEC' -eq 0 ]] && grep -q 'ping FAILED' '$HB_OUT'"
# harness witness: a stub that records no stdin makes the per-attempt rows RED
run_hb "$GOOD" STUB_FAIL_FIRST=1 STUB_IGNORE_STDIN=1
assert "witness: a stub recording no stdin line yields zero recorded url lines (the retry row would fail)" \
  "[[ '$N_ARGV' -eq 2 && '$N_STDIN_OK' -eq 0 ]]"

# (c) shape guard: ONE defect per row (a good URL plus one bad thing, built per row)
HOSTILE=(empty_rest http_scheme upper_scheme lead_space trail_space double_quote single_quote backslash
         newline_directive cr tab semicolon dollar backtick at_sign hash)
hostile_value() {  # <name> -> HV (value), HR (expected reason token)
  HR=token_shape
  case "$1" in
    empty_rest)        HV='https://' ;;
    http_scheme)       HV="http://${GOOD_REST}" ;;
    upper_scheme)      HV="HTTPS://${GOOD_REST}" ;;
    lead_space)        HV=" ${GOOD}" ;;
    trail_space)       HV="${GOOD} " ;;
    double_quote)      HV="${GOOD}\"" ;;
    single_quote)      HV="${GOOD}'" ;;
    backslash)         HV="${GOOD}\\" ;;
    newline_directive) HV="${GOOD}"$'\n''url = "https://203.0.113.1/x"'; HR=control_char ;;
    cr)                HV="${GOOD}"$'\r'; HR=control_char ;;
    tab)               HV="${GOOD}"$'\t'; HR=control_char ;;
    semicolon)         HV="${GOOD};" ;;
    dollar)            HV="${GOOD}\$" ;;
    backtick)          HV="${GOOD}\`" ;;
    at_sign)           HV="${GOOD}@" ;;
    hash)              HV="${GOOD}#" ;;
    *)                 HV=''; HR=unknown ;;
  esac
}
assert "hostile list is defined once and holds 16 entries" "[[ ${#HOSTILE[@]} -eq 16 ]]"
HOSTILE_RAN=0
for h in "${HOSTILE[@]}"; do
  hostile_value "$h"
  run_hb "$HV"
  HOSTILE_RAN=$((HOSTILE_RAN + 1))
  assert "guard refuses $h: zero heartbeat curls, exactly one marker and one WARN, exit status unchanged (0)" \
    "[[ '$N_ARGV' -eq 0 && '$N_MARK' -eq 1 && '$N_WARN' -eq 1 && '$TEC' -eq 0 ]]"
  assert "guard refuses $h: marker line is exactly reason=$HR and the variable; neither the value, its host nor its bare secret path token is echoed" \
    "grep -qxF 'SOLEUR_CREDENTIAL_REFUSED script=inngest-consumer-probe reason=$HR var=INNGEST_CONSUMER_URL' '$HB_OUT' && ! grep -qF -e 'betterstack' -e '$GOOD_TOKEN' -e '203.0.113' '$HB_OUT'"
done
assert "every one of the 16 hostile entries was exercised" "[[ '$HOSTILE_RAN' -eq 16 ]]"
# the empty-URL arm is the pre-existing WARN (not a refusal): zero curls, no marker, same text
run_hb ""
assert "empty URL: the existing WARN arm, zero curls, no marker, exit 0" \
  "[[ '$N_ARGV' -eq 0 && '$N_MARK' -eq 0 && '$TEC' -eq 0 ]] && grep -q 'INNGEST_CONSUMER_URL unset' '$HB_OUT'"

# (d) refusal limiter: its OWN stamp, a 3600 s window, fail-open
RSTAMP="$TMP/hb_refusal_limiter.stamp"
rm -f "$RSTAMP"; MARKS=0; WARNS=0; CURLS=0; BAD_EC=0
for _ in 1 2 3 4; do
  run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
  MARKS=$((MARKS + N_MARK)); WARNS=$((WARNS + N_WARN)); CURLS=$((CURLS + N_ARGV))
  [[ "$TEC" -eq 0 ]] || BAD_EC=$((BAD_EC + 1))
done
assert "limiter: four refused runs inside one window log exactly ONE marker" "[[ '$MARKS' -eq 1 ]]"
assert "limiter: four refused runs inside one window log exactly ONE refusal WARN (the WARN sits inside the limiter with the marker)" "[[ '$WARNS' -eq 1 ]]"
assert "limiter: every one of the four refused runs made zero curls and exited 0 (the limiter governs the line, never the decision)" \
  "[[ '$CURLS' -eq 0 && '$BAD_EC' -eq 0 ]]"
NOW="$(date +%s)"
printf '%s\n' "$((NOW - 2000))" > "$RSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
assert "limiter: a stamp aged 2000 s still suppresses (the window is 3600 s, not the fault 1800 s)" "[[ '$N_MARK' -eq 0 ]]"
printf '%s\n' "$((NOW - 3700))" > "$RSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
assert "limiter: a stamp aged 3700 s re-emits" "[[ '$N_MARK' -eq 1 ]]"
assert "limiter: the stamp is rewritten on emit" "[[ \"\$(cat '$RSTAMP')\" -ge '$NOW' ]]"
printf '%s\n' "$((NOW + 100000))" > "$RSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
assert "limiter: a future-dated stamp emits (a suppressing negative age is a silent-forever bug)" "[[ '$N_MARK' -eq 1 ]]"
assert "limiter: a future-dated stamp is rewritten to the present" "[[ \"\$(cat '$RSTAMP')\" -lt '$((NOW + 1000))' ]]"
printf '%s\n' 'not-a-number' > "$RSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
assert "limiter: a garbage stamp emits" "[[ '$N_MARK' -eq 1 ]]"
# Boundary rows at the exact edge of the 3600 s window. A run that straddles a clock-second tick would age the
# stamp by one more second and move the edge under the assertion, so the helper re-seeds until a run began and
# ended inside one second (the age the SUT saw is then exactly the age seeded).
hb_exact_age_run() {  # <age seconds> -> a refused run against a stamp of exactly that age; rc 1 if no tick-free run in 5 tries
  local age="$1" t0 t1
  HB_T0=0
  for _ in 1 2 3 4 5; do
    t0="$(date +%s)"; printf '%s\n' "$((t0 - age))" | tee "$RSTAMP" >/dev/null
    run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
    t1="$(date +%s)"; HB_T0="$t0"; [[ "$t0" == "$t1" ]] && return 0
  done
  return 1
}
hb_exact_age_run 3599; EXACT_OK=$?
assert "limiter: a stamp aged exactly 3599 s still suppresses (one second inside the window): no marker, no WARN, stamp untouched" \
  "[[ '$EXACT_OK' -eq 0 && '$N_MARK' -eq 0 && '$N_WARN' -eq 0 && \"\$(cat '$RSTAMP')\" -eq '$((HB_T0 - 3599))' ]]"
hb_exact_age_run 3600; EXACT_OK=$?
assert "limiter: a stamp aged exactly 3600 s emits (the window is half-open: age < 3600 suppresses) and the stamp is rewritten to now" \
  "[[ '$EXACT_OK' -eq 0 && '$N_MARK' -eq 1 && '$N_WARN' -eq 1 && \"\$(cat '$RSTAMP')\" -eq '$HB_T0' ]]"
# Stamp normalisation (the same as the zot and nic limiters): a leading-zero 8 or 9 must not be read as an invalid octal
# (the old arithmetic aborted the enclosing command, and the run fell through to a FALSE empty-registry fault line), a
# non-numeric stamp reads as "never emitted", and every one of them is rewritten on emit. The 11/16/20-digit seeds are
# future-dated or overflowing numbers: they pin "no arithmetic error, still emits", but they would emit WITHOUT the
# 10-digit length cap too. The cap itself is pinned ONLY by DISC: a zero-padded epoch 10 s old (12 characters). Without
# the cap it is read as a number 10 s old and SUPPRESSES; with it, it is not an epoch and EMITS.
for seed in 0000000008 0000000009 abc 12ab 12345678901 1234567890123456 99999999999999999999 DISC; do
  if [[ "$seed" == DISC ]]; then seed="00$(( $(date +%s) - 10 ))"; seed_name="the zero-padded 12-char epoch aged 10 s (length cap)"; else seed_name="$seed"; fi
  printf '%s\n' "$seed" > "$RSTAMP"
  run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP"
  assert "limiter: a stamp of $seed_name reads as emit: one marker, zero curls, exit 0, stamp rewritten to a current epoch" \
    "[[ '$N_MARK' -eq 1 && '$N_ARGV' -eq 0 && '$TEC' -eq 0 && \"\$(cat '$RSTAMP')\" =~ ^[0-9]{10}\$ && \"\$(cat '$RSTAMP')\" -ge '$NOW' ]]"
  assert "limiter: a stamp of $seed_name leaves no shell arithmetic error and no false registry fault line in the run output" \
    "! grep -qE -e 'value too great|syntax error|EMPTY REGISTRY|UNREACHABLE' '$HB_OUT'"
done
# The FAULT limiter (_fault) has its own stamp read and the same normalisation: a leading-zero 8/9 in the fault marker must
# not abort the script (bash: "value too great for base"), and the dark-registry fault line must still be emitted exactly
# once and the marker rewritten; the zero-padded 12-char epoch (DISC) pins the length cap there too.
FLSTAMP="$TMP/hb_fault_seed.stamp"
for seed in 0000000008 0000000009 DISC; do
  if [[ "$seed" == DISC ]]; then seed="00$(( $(date +%s) - 10 ))"; seed_name="the zero-padded 12-char epoch aged 10 s (length cap)"; else seed_name="$seed"; fi
  printf '%s\n' "$seed" > "$FLSTAMP"
  run_hb "$GOOD" "SOLEUR_INNGEST_CONSUMER_FAULT_MARKER=$FLSTAMP" "INNGEST_PROBE_FUNCTIONS_FIXTURE=$HB_FX_FAIL"
  assert "fault limiter: a fault marker of $seed_name does not crash the script and the fault line is still emitted exactly once" \
    "[[ \$(grep -c 'UNREACHABLE' '$HB_OUT') -eq 1 ]] && ! grep -qE -e 'value too great|syntax error|Illegal number' '$HB_OUT'"
  assert "fault limiter: a fault marker of $seed_name is rewritten to a current epoch on emit" \
    "[[ \"\$(cat '$FLSTAMP')\" =~ ^[0-9]{10}\$ && \"\$(cat '$FLSTAMP')\" -ge '$NOW' ]]"
done
# own-stamp rows: the refusal stamp is NOT the fault stamp, in either direction
FSTAMP="$TMP/hb_fault_limiter.stamp"
rm -f "$RSTAMP"; printf '%s\n' "$NOW" > "$FSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP" "SOLEUR_INNGEST_CONSUMER_FAULT_MARKER=$FSTAMP"
assert "own stamp: a fresh fault stamp does NOT suppress the refusal marker" "[[ '$N_MARK' -eq 1 ]]"
assert "own stamp: a refusal never writes the fault stamp" "[[ \"\$(cat '$FSTAMP')\" == '$NOW' ]]"
assert "own stamp: the refusal wrote its own stamp file" "[[ -s '$RSTAMP' ]]"
# the other direction: a refusal that REALLY ran (bad URL, healthy registry) writes the refusal stamp; a later run whose
# registry is dark (a fault line, and the ping arm is never reached) must still emit its fault line past that fresh stamp
rm -f "$FSTAMP" "$RSTAMP"
run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP" "SOLEUR_INNGEST_CONSUMER_FAULT_MARKER=$FSTAMP"
assert "own stamp: the refusal path executed (a bad URL, a healthy registry: one marker) and wrote a fresh refusal stamp but no fault stamp" \
  "[[ '$N_MARK' -eq 1 && -s '$RSTAMP' && ! -e '$FSTAMP' ]]"
run_hb "$GOOD" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$RSTAMP" "SOLEUR_INNGEST_CONSUMER_FAULT_MARKER=$FSTAMP" \
  "INNGEST_PROBE_FUNCTIONS_FIXTURE=$HB_FX_FAIL"
assert "own stamp: a fresh refusal stamp does NOT suppress a fault line (a refusal must not mask a fault)" \
  "[[ '$N_MARK' -eq 0 && '$N_ARGV' -eq 0 ]] && grep -q 'UNREACHABLE' '$HB_OUT'"
# unwritable stamp path: fails OPEN (emit on every run), exit status unchanged
BADSTAMP="$TMP/no-such-dir/sub/refusal.stamp"
MARKS=0
for _ in 1 2; do
  run_hb "${GOOD}\"" "SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER=$BADSTAMP"
  MARKS=$((MARKS + N_MARK))
done
assert "limiter: an UNWRITABLE stamp path fails OPEN (the marker emits on every run)" "[[ '$MARKS' -eq 2 && '$TEC' -eq 0 ]]"

# (e) REAL-curl smoke. Every row above runs a stub curl, which accepts any argv, so a flag the real curl rejects (exit 2,
# "curl: option ...") would pass them all. Extract the SUT's own _hb_curl definition and run it against the real curl at a
# closed port: a well-formed argv gets as far as the connect and fails with rc 7; a rejected option gives rc 2. The
# definition silences curl's stderr, so a second copy with that redirect removed shows the text itself.
HB_DEF="$TMP/hb_curl.def"; HB_DEF_LOUD="$TMP/hb_curl_loud.def"
sed -n '/^_hb_curl()/p' "$SUT" > "$HB_DEF"
sed 's| 2>/dev/null||' "$HB_DEF" > "$HB_DEF_LOUD"
SMOKE_RC="$(env URL='https://127.0.0.1:9/p' bash -c ". \"\$1\"; _hb_curl; echo \$?" _ "$HB_DEF" 2>&1)"
# shellcheck disable=SC2034  # read by NAME inside the assert() eval strings below
SMOKE_TXT="$(env URL='https://127.0.0.1:9/p' bash -c ". \"\$1\"; _hb_curl; echo \"rc=\$?\"" _ "$HB_DEF_LOUD" 2>&1)"
assert "smoke: the extracted _hb_curl definition is one non-empty line and the stderr-visible copy differs from it" \
  "[[ \"\$(wc -l < '$HB_DEF')\" -eq 1 && -s '$HB_DEF' ]] && ! cmp -s '$HB_DEF' '$HB_DEF_LOUD'"
assert "smoke: the real curl (not the stub) is first on PATH for the smoke run" \
  "[[ \"\$(command -v curl)\" != '$HB_STUBDIR/curl' && -x \"\$(command -v curl)\" ]]"
assert "smoke: the real curl accepts the argv: exit 7 (connection refused), never 2 (option rejected)" "[[ '$SMOKE_RC' == 7 ]]"
assert "smoke: the real curl's own message is a connect failure, with no 'curl: option' and no '(2)' text" \
  "grep -qF '(7)' <<<\"\$SMOKE_TXT\" && ! grep -qF -e 'curl: option' -e '(2)' <<<\"\$SMOKE_TXT\""

# --- #10363 F6: the unit stops expanding the secret; the script resolves it AFTER its refusal -----
# Same defect and fix as web-zot-consumer-probe / web-private-nic-guard (#9639 / #10637): the unit's
# ExecStart expanded INNGEST_CONSUMER_URL in an inner `bash -c` BEFORE the script could refuse to run
# under xtrace, so a traced launch (SHELLOPTS=xtrace propagating through `doppler run`, or a
# BASH_ENV `set -x`) printed the heartbeat URL to stderr -> journald -> off-box. The fix: the unit
# expands nothing and the script resolves the key-named variable AFTER an unconditional xtrace
# refusal (unconditional because this script has no --canary-only mode and the key name is always
# in the env file). Rows mirror the zot suite's F6 block.
echo "--- F6 (#10363): inngest probe unit wrapper expands nothing; lookup follows the refusal ---"
# shellcheck disable=SC2016  # the F6 conditions are single-quoted on purpose: assert() evals them in this shell
F6_URL='https://uptime.betterstack.test/api/v1/heartbeat/F6-SECRET-10363'
F6_TOK=F6-SECRET-10363
F6_SCRIPT_PATH=/usr/local/bin/inngest-consumer-probe.sh
F6_LINE="$(sed -n 's/^ExecStart=//p' "$SVC" | sed -n '1p' | sed 's/\$\$/$/g')"   # systemd's $$ is a literal $
# The pre-fix ExecStart, kept ONLY as the leak control's mutant (never compared with the tree).
F6_OLD_LINE="/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export INNGEST_CONSUMER_URL=\"\${!INNGEST_CONSUMER_URL_KEY}\"; exec $F6_SCRIPT_PATH'\\'''"
F6_EXEC="$TMP/f6-exec-inngest-consumer-probe.sh"; cp "$SUT" "$F6_EXEC"; chmod +x "$F6_EXEC"
# The relocated script resolves its sourced peer sibling-relative; give the sandbox a real peer.
cp "$REGISTRY_PROBE" "$TMP/inngest-registry-probe.sh"
printf 'set -x\n' > "$TMP/f6-xt.env"
mkdir -p "$TMP/f6-stubbin"
# `doppler run ... -- CMD`: skip to the `--` and exec CMD. It never expands the secret itself (its own
# xtrace would print the value and void the leak control); the test env pre-exports it as doppler would.
printf '#!/usr/bin/env bash\nwhile [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n' > "$TMP/f6-stubbin/doppler"
# A recording curl: one argv line per call and, for a `--config -` call, that call's whole stdin;
# F6_HB_ENVDUMP set -> dump ITS environment (the not-exported / export-mutant rows).
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$F6_HB_ARGV"\n[ -z "${F6_HB_ENVDUMP:-}" ] || env > "$F6_HB_ENVDUMP"\ncase " $* " in\n  *" --config - "*) cat > "$F6_HB_STDIN" ;;\nesac\nexit 0\n' > "$TMP/f6-stubbin/curl"
chmod +x "$TMP/f6-stubbin/doppler" "$TMP/f6-stubbin/curl"
mkdir -p "$TMP/f6-dead"; printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/f6-dead/doppler"; chmod +x "$TMP/f6-dead/doppler"
F6_SEQ=0
run_unit() {   # <ExecStart text> <none|xtrace|benv> [extra env words, applied last] : script path rewritten to the (mutant) script
  local line="$1" form="$2" ec=0 sut="${F6_SUT:-$F6_EXEC}"; shift 2
  [[ "$line" == *"$F6_SCRIPT_PATH"* ]] || { printf '[FATAL] run_unit: the ExecStart text does not name %s; the rewrite would be a silent no-op\n' "$F6_SCRIPT_PATH" >&2; exit 1; }
  local -a fenv=()
  case "$form" in xtrace) fenv=(SHELLOPTS=xtrace) ;; benv) fenv=(BASH_ENV="$TMP/f6-xt.env") ;; esac
  F6_SEQ=$((F6_SEQ + 1))
  F6_HB_ARGV="$(mktemp "$TMP/f6argv.XXXXXX")"; F6_HB_STDIN="$(mktemp "$TMP/f6stdin.XXXXXX")"; HOUT="$(mktemp "$TMP/hbout.XXXXXX")"
  env -u SOLEUR_INNGEST_CONSUMER_PING_LOG -u SHELLOPTS -u BASH_ENV -u INNGEST_CONSUMER_URL -u INNGEST_CONSUMER_URL_KEY -u INNGEST_CONSUMER_URL_SYNTH \
    PATH="$TMP/f6-stubbin:$PATH" \
    F6_HB_ARGV="$F6_HB_ARGV" F6_HB_STDIN="$F6_HB_STDIN" \
    INNGEST_PROBE_FUNCTIONS_FIXTURE="$HB_FX" \
    SOLEUR_INNGEST_CONSUMER_FAULT_MARKER="$TMP/f6fault.$F6_SEQ" \
    SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER="$TMP/f6refusal.$F6_SEQ" \
    INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL_SYNTH INNGEST_CONSUMER_URL_SYNTH="$F6_URL" \
    ${fenv[@]+"${fenv[@]}"} "$@" \
    timeout 20 bash -c 'eval "$1"' _ "${line//"$F6_SCRIPT_PATH"/$sut}" >"$HOUT" 2>&1 || ec=$?
  HEC=$ec
  # shellcheck disable=SC2034  # read by NAME inside the assert() eval strings
  HOUTTXT="$(cat "$HOUT")"
  N_HB="$(grep -c . "$F6_HB_ARGV" 2>/dev/null || true)"
}
assert "F6 static: no Exec* directive of the inngest probe unit holds an indirect expansion" \
  '[[ "$(grep -cE "^[[:space:]]*Exec[A-Za-z]*=.*[$]{1,2}[{][!]" "$SVC" || true)" -eq 0 ]]'
assert "F6 static: ExecStart runs the probe directly under doppler run: names it, no dollar sign, no export" \
  '[[ "$F6_LINE" == *"$F6_SCRIPT_PATH"* && "$F6_LINE" != *\$* && "$F6_LINE" != *export* && "$F6_LINE" == *"doppler run"* ]]'
for f6_form in xtrace benv; do
  run_unit "$F6_LINE" "$f6_form"
  assert "F6 unit[$f6_form]: the real ExecStart exits 78 with the refusal on a non-trace line (the script RAN; got rc=$HEC)" \
    '[[ "$HEC" -eq 78 && "$(grep -v "^+" "$HOUT" | grep -c "refusing to run under xtrace" || true)" -ge 1 ]]'
  assert "F6 unit[$f6_form]: the heartbeat URL (and its secret path token) is in neither stream and no request was made" \
    '[[ "$HOUTTXT" != *"$F6_TOK"* && "$N_HB" -eq 0 ]]'
done
run_unit "$F6_OLD_LINE" xtrace
assert "F6 control: the PRE-FIX ExecStart under SHELLOPTS=xtrace prints the secret (the harness can see the defect; rc=$HEC)" \
  '[[ "$HOUTTXT" == *"$F6_TOK"* && "$HEC" -eq 78 ]]'
run_unit "$F6_LINE" xtrace PATH="$TMP/f6-dead:$TMP/f6-stubbin:$PATH"
assert "F6 dispatch: with a doppler that never execs the probe there is NO refusal text (so the rows above discriminate)" \
  '[[ "$HOUTTXT" != *"refusing to run under xtrace"* && "$HEC" -eq 0 ]]'
run_unit "$F6_LINE" none
assert "F6 positive: the untraced real ExecStart resolves the key-named URL and delivers it to the heartbeat curl on its stdin config, once (rc=$HEC)" \
  '[[ "$HEC" -eq 0 && "$N_HB" -eq 1 && "$(cat "$F6_HB_STDIN")" == "url = \"$F6_URL\"" ]]'
run_unit "$F6_LINE" none INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL INNGEST_CONSUMER_URL="$F6_URL"
assert "F6 production-shaped identity key [INNGEST_CONSUMER_URL] resolves and delivers" \
  '[[ "$N_HB" -eq 1 && "$(cat "$F6_HB_STDIN")" == "url = \"$F6_URL\"" ]]'
run_unit "$F6_LINE" none INNGEST_CONSUMER_URL="https://uptime.betterstack.test/api/v1/heartbeat/STRAY-10363" INNGEST_CONSUMER_URL_KEY= INNGEST_CONSUMER_URL_SYNTH=
assert "F6 no-key: a bare exported INNGEST_CONSUMER_URL without the KEY name resolves nothing (exit 0, WARN arm, no curl)" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"INNGEST_CONSUMER_URL unset"* && "$HOUTTXT" == *"INNGEST_CONSUMER_URL_KEY"* ]]'
run_unit "$F6_LINE" xtrace INNGEST_CONSUMER_URL_KEY= INNGEST_CONSUMER_URL_SYNTH=
assert "F6 unconditional: a traced launch with NO credential set still refuses (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to run under xtrace"* ]]'
F6_PLANT="$TMP/f6-plant"; rm -f "$F6_PLANT"
run_unit "$F6_LINE" none "INNGEST_CONSUMER_URL_KEY=a[\$(touch $F6_PLANT)]"
assert "F6 hostile key a[\$(touch ...)]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
  '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"INNGEST_CONSUMER_URL_KEY"* && "$HOUTTXT" != *touch* ]]'
run_unit "$F6_LINE" none "INNGEST_CONSUMER_URL_KEY=lowercase"
assert "F6 lowercase key: refused, no heartbeat, a KEY_BAD line, exit 0" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"INNGEST_CONSUMER_URL_KEY"* ]]'
# Upper-case-led hostile keys: these exercise _key_ok's BODY clause (`*[!A-Z0-9_]*` — the one that
# stops the bytes bash evaluates inside ${!name}: array subscripts, command substitutions). Both
# rows above are lowercase-led and die in the lead clause, so without this table a mutant dropping
# the body clause ships green (reviewed, the zot suite's body-clause table at
# web-zot-consumer-probe.test.sh is the shape).
for f6_k in "A[\$(touch $F6_PLANT)]" "A[0]" "A=B" "A.B" "A/B"; do
  rm -f "$F6_PLANT"; run_unit "$F6_LINE" none "INNGEST_CONSUMER_URL_KEY=$f6_k"
  assert "F6 body-clause key [$f6_k]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
    '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"INNGEST_CONSUMER_URL_KEY"* && "$HOUTTXT" != *"$f6_k"* ]]'
done
# _key_ok is the THIRD copy; the nic-guard suite's parity row binds only nic<->zot. Pin this copy to
# both siblings — the file's own comment predicates safety on byte-identity.
assert "F6 parity: _key_ok is byte-identical to the zot AND nic-guard copies" \
  '[[ "$(grep -m1 "^_key_ok()" "$SUT")" == "$(grep -m1 "^_key_ok()" "$SCRIPT_DIR/web-zot-consumer-probe.sh")" && "$(grep -m1 "^_key_ok()" "$SUT")" == "$(grep -m1 "^_key_ok()" "$SCRIPT_DIR/web-private-nic-guard.sh")" ]]'
# A valid key name whose variable is UNSET resolves to "" -> the WARN arm, exit 0 (the last input
# cell: empty KEY, invalid KEY, stray URL without key, and unset named var).
run_unit "$F6_LINE" none INNGEST_CONSUMER_URL_KEY=INNGEST_CONSUMER_URL_UNSETVAR INNGEST_CONSUMER_URL_SYNTH=
assert "F6 unset-named-var key: resolves to empty, WARN arm, no heartbeat, exit 0" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"INNGEST_CONSUMER_URL unset"* ]]'
# Every Exec* directive of the unit (backslash continuations joined, as systemd reads them) is
# dollar-free and export-free — a future ExecStartPre must not be able to smuggle a plain-$ expansion
# past the ExecStart-only static rows.
F6_ALLEXEC="$(awk '{ if (sub(/\\$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' "$SVC" | grep -E '^[[:space:]]*Exec[A-Za-z]*=' || true)"
assert "F6 static: EVERY Exec* directive of the inngest probe unit (continuations joined) is dollar-free and export-free" \
  '[[ -n "$F6_ALLEXEC" && "$F6_ALLEXEC" != *\$* && "$F6_ALLEXEC" != *export* ]]'
# `unset URL; URL=""` (the resolve block) drops an inherited export attribute so the resolved secret
# cannot ride child environments: the heartbeat curl's environ must hold the URL ONLY under the
# doppler-injected key-named variable.
F6_ENVD="$TMP/f6-envdump"; rm -f "$F6_ENVD"
run_unit "$F6_LINE" none F6_HB_ENVDUMP="$F6_ENVD"
assert "F6 not exported: the resolved URL reaches no child environment (only the injected key-named variable holds it)" \
  '[[ -s "$F6_ENVD" && "$(grep -v "^INNGEST_CONSUMER_URL_SYNTH=" "$F6_ENVD" | grep -cF -- "$F6_URL" || true)" -eq 0 && "$(grep -cF -- "$F6_URL" "$F6_ENVD" || true)" -eq 1 ]]'
F6_MUT_EXP="$TMP/f6-mut-export.sh"; sed 's/^URL=""$/export URL=""/' "$SUT" > "$F6_MUT_EXP"; chmod +x "$F6_MUT_EXP"
assert "F6 mutant[export]: the edit landed (the copy differs from the SUT)" '! cmp -s "$SUT" "$F6_MUT_EXP"'
rm -f "$F6_ENVD"
F6_SUT="$F6_MUT_EXP" run_unit "$F6_LINE" none F6_HB_ENVDUMP="$F6_ENVD"
assert "F6 mutant[export]: an exported URL DOES ride the heartbeat curl's environment (the not-exported row can see it)" \
  '[[ -s "$F6_ENVD" && "$(grep -c "^URL=" "$F6_ENVD" || true)" -ge 1 && "$(grep "^URL=" "$F6_ENVD" | grep -cF -- "$F6_URL" || true)" -eq 1 ]]'
# Order: a mutant that resolves the URL above the refusal leaks it under SHELLOPTS=xtrace.
F6_MUT="$TMP/f6-mut-hoist-inngest.sh"
sed '/^set -u$/a\
__leak="${!INNGEST_CONSUMER_URL_KEY:-}"' "$SUT" > "$F6_MUT"; chmod +x "$F6_MUT"
assert "F6 mutant[hoist]: the edit landed (the copy differs from the SUT)" '! cmp -s "$SUT" "$F6_MUT"'
F6_SUT="$F6_MUT" run_unit "$F6_LINE" xtrace
assert "F6 mutant[hoist]: a lookup hoisted above the refusal leaks the URL under SHELLOPTS=xtrace (the order row can see it)" '[[ "$HOUTTXT" == *"$F6_TOK"* ]]'
f6i_line_of() { awk -v n="$1" 'index($0, n) && $0 !~ /^[[:space:]]*#/ { print NR; exit }' "$SUT"; }   # first NON-comment line holding the text
assert "F6 order: the indirect lookup is on a later line than the refusal" \
  '[[ -n "$(f6i_line_of "refusing to run under xtrace")" && "$(f6i_line_of "\${!INNGEST_CONSUMER_URL_KEY")" -gt "$(f6i_line_of "refusing to run under xtrace")" ]]'

# --- STATIC: unit contract (doppler-auth + observability delivery) ------------------------
# Mirrors web-zot-consumer-probe.test.sh's block. The unit runs `doppler run` as ROOT, so
# Environment=HOME=/root is required or the CLI dies before exec'ing the probe. SyslogIdentifier
# is what carries the fault classification off-box via vector.toml Source 4 — without it the
# probe's WHY is SSH-only, which hr-no-ssh-fallback-in-runbooks forbids and which is the exact
# shape of the twelve-day silence this whole change exists to end.
echo "--- static: unit contract + observability delivery ---"
VECTOR_TOML="$SCRIPT_DIR/vector.toml"
SERVER_TF="$SCRIPT_DIR/server.tf"
assert ".service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert ".service sets SyslogIdentifier=inngest-consumer-probe" \
  "grep -qE '^SyslogIdentifier=inngest-consumer-probe\$' '$SVC'"
assert ".service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'DOPPLER_CONFIG_DIR' >/dev/null"
assert ".service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c '/tmp/.doppler' >/dev/null"
assert "vector.toml Source 4 allowlists inngest-consumer-probe (else the WHY is SSH-only)" \
  "grep -qE '^[[:space:]]*\"inngest-consumer-probe\",' '$VECTOR_TOML'"
assert "server.tf writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/inngest-consumer-probe" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/inngest-consumer-probe' '$SERVER_TF'"
assert "server.tf delivers the probe script to the web host" \
  "grep -qE 'destination[[:space:]]*=[[:space:]]*\"/usr/local/bin/inngest-consumer-probe\\.sh\"' '$SERVER_TF'"
assert "server.tf enables the timer" \
  "grep -qE 'systemctl enable --now inngest-consumer-probe\\.timer' '$SERVER_TF'"
assert "the timer's cadence is declared (OnUnitActiveSec)" \
  "grep -qE '^OnUnitActiveSec=' '$TIMER'"

# --- STATIC: the heartbeat is a NEW resource, never a value edit --------------------------
# doppler_secret.inngest_heartbeat_url_prd carries ignore_changes=[value]; repointing its value
# plans NO change and applies nothing while every AC still passes. The new URL therefore needs a
# NEW resource. Assert both the new pair exists and the old secret's value line is untouched.
echo "--- static: new heartbeat + new doppler_secret (never a value edit) ---"
INNGEST_TF="$SCRIPT_DIR/inngest.tf"
assert "a NEW betteruptime_heartbeat resource exists for the consumer probe" \
  "grep -qE '^resource \"betteruptime_heartbeat\" \"inngest_consumer\"' '$INNGEST_TF'"
assert "a NEW doppler_secret resource carries its URL" \
  "grep -qE '^resource \"doppler_secret\" \"inngest_consumer_url\"' '$INNGEST_TF'"
assert "the new heartbeat is born paused=true in source (ADR-117 arm gate owns the unpause)" \
  "awk '/\"betteruptime_heartbeat\" \"inngest_consumer\"/,/^}/' '$INNGEST_TF' | grep -cE 'paused[[:space:]]*=[[:space:]]*true' >/dev/null"
assert "the new heartbeat carries lifecycle ignore_changes=[paused] (arm must never be reverted)" \
  "awk '/\"betteruptime_heartbeat\" \"inngest_consumer\"/,/^}/' '$INNGEST_TF' | grep -cE 'ignore_changes[[:space:]]*=[[:space:]]*\\[paused\\]' >/dev/null"
assert "the pre-existing inngest_heartbeat_url_prd still sources the ORIGINAL heartbeat (no value repoint)" \
  "awk '/\"doppler_secret\" \"inngest_heartbeat_url_prd\"/,/^}/' '$INNGEST_TF' | grep -cE 'value[[:space:]]*=[[:space:]]*betteruptime_heartbeat\\.inngest_prd\\.url' >/dev/null"

echo
echo "=== $PASS passed, $FAIL failed ==="
# Anti-vacuity floor: a skipped block or a disarmed assert() must not read as green. Raise it in the SAME edit that adds
# rows; it is reported with printf and exit, never through assert() (scripts/guard-vacuity-floor.test.sh builds its mutant
# from the literal sitting directly above the `if`).
MIN_ASSERTS=169
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTS" ]]; then
  printf 'FAIL: only %s assertions ran (floor %s) — a block was skipped or assert() was disarmed\n' "$((PASS + FAIL))" "$MIN_ASSERTS"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
