#!/usr/bin/env bash
# Tests the registry-host zot LIVENESS heartbeat feeder (#6537, cloud-init-registry.yml).
#
# WHY THIS EXISTS. `betteruptime_heartbeat.registry_prd` was provisioned paused=true on
# 2026-07-07 as a bootstrap step, to be armed once "the web-host probe cron ships". That probe
# was NEVER written (ZOT_HEARTBEAT_URL had zero consumers repo-wide), so the monitor sat inert
# for 9 days while its own source comment claimed a feeder existed. This suite covers the
# feeder that finally arms it.
#
# WHAT IT COVERS. The disk heartbeat (registry_disk_prd, 900s) already alarms HOST death by
# absence, so this feeder's job is the narrower gap it cannot see: **zot process dead, host
# alive, disk fine**. The ping is therefore ABSENCE-BASED and gated on a real zot probe —
# pinging unconditionally would re-create the exact green-over-dead-registry blindness of
# #6400.
#
# THE LOAD-BEARING CHOICE: the probe targets the host's OWN PRIVATE IP (10.0.1.30:5000),
# never localhost. zot publishes `-p 0.0.0.0:5000:5000`, so a localhost probe answers even
# when the private NIC is absent — which is precisely how #6400 stayed green for ~14 days
# (cloud-init-registry.yml documents this verbatim at the private-NIC guard preamble). T3 is
# the whole reason this suite exists: it FAILS a localhost implementation that every other
# test would pass.
#
# TWO layers (mirrors private-nic-guard.test.sh:20-31):
#   1. BEHAVIORAL: RENDER the feeder out of the Terraform template and EXECUTE it against
#      synthesized PATH stubs (cq-test-fixtures-synthesized-only). No live host, no network.
#   2. STRUCTURAL grep assertions: the systemd timer cadence, the curl bound, and the
#      negative-space "never probes localhost" guard.
#
# NON-VACUITY: T1 is the positive control for the emit path itself, so T2/T3/T4's "NO ping"
# can never pass merely because the script died at line 1 — the same fixture harness emits
# under T1.
#
# Static + pure-bash — no docker, no network, no doppler, no root.
#
# Run: bash apps/web-platform/infra/zot-liveness-heartbeat.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"
FEEDER_PATH="/usr/local/bin/zot-liveness-heartbeat.sh"
TEST_IP="10.0.1.30"
TEST_HB_URL="https://uptime.betterstack.com/api/v1/heartbeat/synthetic-liveness"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TIMEOUT_BIN="$(command -v timeout || true)"

echo "=== registry zot liveness heartbeat feeder (#6537) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"
assert "the timeout binary is available (bounds a lost curl bound)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- RENDER: template -> executable bash -------------------------------------------------
RENDERED="$TMP/feeder.sh"
awk -v want="  - path: $FEEDER_PATH" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent {
    if ($0 ~ /^      /) { print substr($0, 7); next }
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    exit
  }
' "$CI" > "$RENDERED"

assert "feeder block extracted from the template (non-empty)" "[[ -s '$RENDERED' ]]"
assert "extracted block is the feeder (has a shebang)" "head -1 '$RENDERED' | grep -q '^#!'"

sed -i "s|\${private_ip}|$TEST_IP|g" "$RENDERED"
sed -i "s|\${liveness_heartbeat_url}|$TEST_HB_URL|g" "$RENDERED"
sed -i 's|\$\${|${|g' "$RENDERED"

# Charset must be at least as wide as Terraform's own var names (digits included) — a missed
# digit-bearing var never trips `set -u` inside quotes, so the suite would silently execute a
# broken feeder. Mirrors private-nic-guard.test.sh's identical assert + rationale.
assert "render left no unrendered TF interpolation" "! grep -qE '\\\$\{[A-Za-z0-9_.]+\}' '$RENDERED'"
assert "rendered feeder is syntactically valid bash" "bash -n '$RENDERED'"
chmod +x "$RENDERED"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# ONE curl stub serves both callers, discriminating by target. It records EVERY probed URL to
# $STUB_PROBES, which is what makes T3's negative-space assertion ("localhost was never
# probed") observable rather than inferred.
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
target=""
for a in "$@"; do
  case "$a" in
    http://*|https://*) target="$a" ;;
  esac
done
printf '%s\n' "$target" >> "$STUB_PROBES"
case "$target" in
  *10.0.1.30:5000*)   exit "${STUB_PRIVATE_RC:-0}" ;;
  *localhost:5000*)   exit "${STUB_LOCALHOST_RC:-0}" ;;
  *127.0.0.1:5000*)   exit "${STUB_LOCALHOST_RC:-0}" ;;
  *heartbeat*)        printf '%s\n' "$target" >> "$STUB_EMIT"; exit 0 ;;
esac
exit 0
EOS
chmod +x "$BIN"/*

# --- Fixture harness ---------------------------------------------------------------------
# run_feeder <private_rc> <localhost_rc>
#   private_rc  : exit of the probe against 10.0.1.30:5000  (0 = zot answers on the private IP)
#   localhost_rc: exit of a probe against localhost:5000     (0 = zot answers on loopback)
# The two diverge in exactly one real-world shape — #6400's private-NIC-absent host — which is
# what T3 pins.
run_feeder() {
  local private_rc="$1" localhost_rc="$2"
  STUB_EMIT="$TMP/emit.$$.$RANDOM"
  STUB_PROBES="$TMP/probes.$$.$RANDOM"
  : > "$STUB_EMIT"
  : > "$STUB_PROBES"
  env -i \
    PATH="$BIN:/usr/bin:/bin" \
    STUB_EMIT="$STUB_EMIT" \
    STUB_PROBES="$STUB_PROBES" \
    STUB_PRIVATE_RC="$private_rc" \
    STUB_LOCALHOST_RC="$localhost_rc" \
    "$TIMEOUT_BIN" 20 bash "$RENDERED" >/dev/null 2>&1 || true
}

# --- T1: positive control — zot answers on the private IP => ping ------------------------
echo ""
echo "--- T1: zot answers on ${TEST_IP}:5000/v2/ => ping emitted"
run_feeder 0 0
assert "T1 emits a heartbeat ping" "[[ -s '$STUB_EMIT' ]]"
assert "T1 probed the private IP" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

# --- T2: zot dead, host alive, disk fine => NO ping --------------------------------------
# This is the gap the 900s disk heartbeat structurally cannot see: it pings on `df` alone, so
# it stays green with zot dead. If this test fails, the feeder is pinging unconditionally and
# the monitor is decorative.
echo ""
echo "--- T2: zot dead (connection refused), host alive => NO ping"
run_feeder 7 7
assert "T2 emits NO heartbeat ping" "[[ ! -s '$STUB_EMIT' ]]"
assert "T2 still probed zot (non-vacuous: the script ran)" "[[ -s '$STUB_PROBES' ]]"

# --- T3: THE test — private NIC absent, localhost still answers => NO ping ---------------
# #6400's exact shape. zot binds 0.0.0.0, so loopback answers on a host holding no 10.0.1.30.
# A localhost implementation passes T1/T2/T4 and FAILS ONLY HERE.
echo ""
echo "--- T3: private NIC absent, localhost:5000 still answers => NO ping"
run_feeder 7 0
assert "T3 emits NO heartbeat ping (localhost must not satisfy the probe)" "[[ ! -s '$STUB_EMIT' ]]"
assert "T3 never probed localhost at all" "! grep -qE 'localhost:5000|127\.0\.0\.1:5000' '$STUB_PROBES'"
assert "T3 probed the private IP (non-vacuous)" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

# --- T4: zot slow => no ping, no hang ----------------------------------------------------
# curl's own -m bound is what makes this true on the host; the `timeout 20` in run_feeder is
# the outside enforcement that a LOST -m bound shows up as a failure here rather than as a
# hung timer unit in production.
echo ""
echo "--- T4: zot slow (curl -m exceeded) => no ping, no hang"
run_feeder 28 28
assert "T4 emits NO heartbeat ping" "[[ ! -s '$STUB_EMIT' ]]"
assert "T4 probed zot (non-vacuous)" "[[ -s '$STUB_PROBES' ]]"

# --- STRUCTURAL --------------------------------------------------------------------------
echo ""
echo "--- structural assertions"

# A COMMENT-STRIPPED view is what makes the negative-space asserts below real. This feeder's
# comments necessarily NAME loopback in order to explain why it is forbidden, so a body-grep
# for `curl … localhost:5000` would match the prose that documents the rule and false-FAIL a
# correct implementation — while `! grep` over the raw body would false-PASS the moment the
# prose disappeared. Neither is anchoring. Stripping `#` lines and asserting on the remaining
# CODE is: a comment cannot survive the strip, and a real call cannot be removed by it.
# See AGENTS.md — "narrowing is not anchoring; anchor on syntax".
CODE="$TMP/feeder.code.sh"
grep -vE '^[[:space:]]*#' "$RENDERED" > "$CODE"
assert "comment-strip left executable code behind (non-vacuous)" "[[ -s '$CODE' ]]"

assert "feeder never issues a curl against localhost/127.0.0.1" \
  "! grep -qE 'curl.*(localhost|127\\.0\\.0\\.1):5000' '$CODE'"
assert "feeder probes the private IP via curl" \
  "grep -qE 'curl.*${TEST_IP}:5000/v2/' '$CODE'"
assert "feeder bounds the probe with curl -m" "grep -qE 'curl.*-m[[:space:]]*[0-9]+' '$CODE'"

# Delivery is asserted on the write_files `- path:` construct — a syntactic anchor prose
# cannot forge — rather than a bare mention of the unit name anywhere in the file.
assert "systemd service unit is delivered" \
  "grep -qE '^[[:space:]]*- path: /etc/systemd/system/zot-liveness-heartbeat.service[[:space:]]*$' '$CI'"
assert "systemd timer unit is delivered" \
  "grep -qE '^[[:space:]]*- path: /etc/systemd/system/zot-liveness-heartbeat.timer[[:space:]]*$' '$CI'"
# The timer, not cron: cron's 60s floor leaves zero margin against the 60s period + 30s grace.
assert "timer fires every 60s" "grep -qE '^[[:space:]]*OnUnitActiveSec=60s[[:space:]]*$' '$CI'"
assert "timer arms shortly after boot" "grep -qE '^[[:space:]]*OnBootSec=[0-9]+s[[:space:]]*$' '$CI'"
assert "timer is enabled in runcmd" \
  "grep -qE '^[[:space:]]*- systemctl.*enable.*zot-liveness-heartbeat\\.timer' '$CI'"
assert "feeder is NOT scheduled via cron.d (60s floor leaves no margin vs the 90s deadline)" \
  "! grep -qE '^[[:space:]]*- path: /etc/cron\\.d/zot-liveness-heartbeat' '$CI'"
# The URL is baked via templatefile (non-secret host routing), so there is no empty-variable
# failure mode and no doppler wrapper (#4116) — assert the negative so a future "harden it
# with doppler run" edit has to justify re-introducing that failure mode.
assert "feeder ExecStart is NOT wrapped in doppler run (URL is baked; #4116)" \
  "! grep -qE '^[[:space:]]*ExecStart=.*doppler.*zot-liveness-heartbeat' '$CI'"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
