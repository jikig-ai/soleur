#!/usr/bin/env bash
# Tests the web-host git-data CONSUMER-perspective reachability probe (#6548,
# web-git-data-probe.sh). A fail-SOFT overlay: a single blip must never page, so the
# probe pings only on a real connect and stays silent (exit 0) otherwise.
#
# TWO layers (mirrors disk-monitor.test.sh's PATH-stub accumulator + the registry
# private-nic-guard.test.sh env-seam harness):
#   1. SEAM-DRIVEN classification: SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE injects the
#      connect result so both branches (ping / no-ping, both exit 0) are exercised
#      without a live git-data; SOLEUR_GIT_DATA_PROBE_PING_LOG re-routes the ping to a
#      file so ping/no-ping is directly observable.
#   2. BEHAVIORAL _reachable(): a real bounded connect against a localhost listener we
#      open (positive control — proves nc/`/dev/tcp` actually connects) and against a
#      closed port (127.0.0.1:1, immediate refusal — bounded, fast).
#
# ENV-DRIVEN plain bash: we EXECUTE the real .sh directly (no templatefile render).
# Pure bash + python3 + a loopback socket — no docker, network egress, or root.
#
# Run: bash apps/web-platform/infra/web-git-data-probe.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-git-data-probe.sh"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [[ -n "${LISTEN_PID:-}" ]] && kill "$LISTEN_PID" 2>/dev/null' EXIT

echo "=== web-host git-data consumer-probe (#6548) tests ==="
assert "web-git-data-probe.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"

# --- run helpers -------------------------------------------------------------------------
# EC = exit code, PINGED = yes|no (seam ping-log non-empty), OUT = combined output.
run_seam() {  # <reachable|unreachable>
  local override="$1" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE="$override" SOLEUR_GIT_DATA_PROBE_PING_LOG="$pinglog" \
    GIT_DATA_HEARTBEAT_URL="https://synthetic.invalid/beat/git-data" \
    bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

run_real() {  # <endpoint host:port> — real _reachable(), no override
  local endpoint="$1" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  GIT_DATA_ENDPOINT="$endpoint" SOLEUR_GIT_DATA_PROBE_PING_LOG="$pinglog" \
    GIT_DATA_HEARTBEAT_URL="https://synthetic.invalid/beat/git-data" \
    timeout 20 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

# --- SEAM: reachable => ping + exit 0 ----------------------------------------------------
echo "--- seam: reachable => ping + exit 0 ---"
run_seam reachable
assert "reachable pings the heartbeat" "[[ '$PINGED' == yes ]]"
assert "reachable exits 0" "[[ '$EC' -eq 0 ]]"

# --- SEAM: unreachable => NO ping + exit 0 (fail-soft) -----------------------------------
echo "--- seam: unreachable => NO ping + exit 0 (fail-soft) ---"
run_seam unreachable
assert "unreachable does NOT ping (absence alarms)" "[[ '$PINGED' == no ]]"
assert "unreachable is fail-soft (exit 0, never pages inline)" "[[ '$EC' -eq 0 ]]"
assert "unreachable explains the suppression" "grep -q 'SUPPRESS ping' <<<\"\$OUT\""

# --- BEHAVIORAL: real _reachable() connects to a live loopback listener ------------------
echo "--- behavioral: real bounded connect against a live loopback listener ---"
PORT_FILE="$TMP/listen_port"
python3 - "$PORT_FILE" >/dev/null 2>&1 <<'PY' &
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
with open(sys.argv[1], "w") as f:
    f.write(str(s.getsockname()[1]))
# Accept-and-close so a connect-and-close probe completes cleanly; live for the suite.
t = time.time()
s.settimeout(1.0)
while time.time() - t < 40:
    try:
        c, _ = s.accept(); c.close()
    except socket.timeout:
        pass
PY
LISTEN_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
assert "the loopback listener published its port" "[[ -s '$PORT_FILE' ]]"
LISTEN_PORT="$(cat "$PORT_FILE" 2>/dev/null || true)"

run_real "127.0.0.1:$LISTEN_PORT"
assert "real connect to the live listener => reachable => ping" "[[ '$PINGED' == yes ]]"
assert "real connect to the live listener => exit 0" "[[ '$EC' -eq 0 ]]"

# --- BEHAVIORAL: real _reachable() against a closed port (immediate refusal) -------------
# 127.0.0.1:1 is effectively never listening => connection refused instantly (bounded, fast).
# Positive control above proves the ping fires on a real connect, so this "no ping" is not vacuous.
echo "--- behavioral: real bounded connect against a closed port => no ping ---"
run_real "127.0.0.1:1"
assert "real connect to a closed port => unreachable => NO ping" "[[ '$PINGED' == no ]]"
assert "real connect to a closed port => fail-soft exit 0" "[[ '$EC' -eq 0 ]]"

# --- static drift-guard: doppler-auth unit-start contract (#6548 unit-start fix) ----------
# The unit runs `doppler run` as ROOT. Without Environment=HOME=/root the doppler CLI's
# os.UserHomeDir() init dies "$HOME is not defined" BEFORE it exec's the probe; without a
# DOPPLER_TOKEN in the per-host env file it cannot authenticate. Both gaps together made the
# unit fail to start on web-1 (delivered-but-inert). Assert both, and that the fix does not
# re-open the #6536 /tmp/.doppler ownership clash surface.
echo "--- static: doppler-auth unit-start contract ---"
SVC="$SCRIPT_DIR/web-git-data-probe.service"
SERVER_TF="$SCRIPT_DIR/server.tf"
assert "git-data .service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert "git-data .service does NOT source webhook-deploy (deploy-owned; imports /tmp/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'webhook-deploy'"
assert "git-data .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'DOPPLER_CONFIG_DIR'"
assert "git-data .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q '/tmp/.doppler'"
assert "git-data .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -qE '^PrivateTmp=true' '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal (test-design review).
assert "server.tf git_data_probe_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-git-data-probe" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-git-data-probe' '$SERVER_TF'"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
