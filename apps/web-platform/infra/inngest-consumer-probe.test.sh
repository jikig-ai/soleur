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
assert "rate-limited run still withholds the ping" "[[ ! -s \"\$(ls -t $TMP/rlping.* | head -1)\" ]]"

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
    INNGEST_CONSUMER_URL="http://127.0.0.1:1/hb" \
    timeout 25 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
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
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'DOPPLER_CONFIG_DIR'"
assert ".service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q '/tmp/.doppler'"
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
  "awk '/\"betteruptime_heartbeat\" \"inngest_consumer\"/,/^}/' '$INNGEST_TF' | grep -qE 'paused[[:space:]]*=[[:space:]]*true'"
assert "the new heartbeat carries lifecycle ignore_changes=[paused] (arm must never be reverted)" \
  "awk '/\"betteruptime_heartbeat\" \"inngest_consumer\"/,/^}/' '$INNGEST_TF' | grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*\\[paused\\]'"
assert "the pre-existing inngest_heartbeat_url_prd still sources the ORIGINAL heartbeat (no value repoint)" \
  "awk '/\"doppler_secret\" \"inngest_heartbeat_url_prd\"/,/^}/' '$INNGEST_TF' | grep -qE 'value[[:space:]]*=[[:space:]]*betteruptime_heartbeat\\.inngest_prd\\.url'"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
