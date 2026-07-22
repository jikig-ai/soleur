#!/usr/bin/env bash
# Tests the WEB-host private-NIC self-report guard (#6438 §3, AC4, web-private-nic-guard.sh).
# This guard is the registry converger's web-host port with ONE deliberate divergence: it
# NEVER reboots (a reboot would power-off the sole live origin, apply-web-platform-infra.yml
# :878). So this suite is mostly negative space — proving the guard DETECTS + EMITS + pings
# the liveness beat, but NEVER mutates.
#
# UNLIKE registry private-nic-guard.test.sh (which RENDERS the guard out of a Terraform
# templatefile — un-indent -> substitute TF vars -> un-escape `$${`), this guard is ENV-DRIVEN
# PLAIN BASH delivered byte-identically by BOTH routes (SSH provisioner + cloud-init variable),
# so we EXECUTE THE REAL .sh DIRECTLY against synthesized fixtures + PATH stubs. Env seams:
# EXPECTED_IP, BETTERSTACK_INGEST_URL, BETTERSTACK_LOGS_TOKEN, WEB_NIC_GUARD_URL, and the
# SOLEUR_NIC_TEST_ROOT FS-read re-root (cq-test-fixtures-synthesized-only).
#
# AC4 (the load-bearing one) has TWO parts:
#   (i) BEHAVIORAL: a `reboot` PATH stub records every invocation; every fixture asserts the
#       trace stays empty AND the emit fired (so "no reboot" can never pass because the script
#       died early). The heartbeat ping fires ONLY when nic_ok=true (T1 is the positive control;
#       a broken NIC must let the beat lapse so absence alarms).
#  (ii) STRUCTURAL, anchored on SYNTAX not a bare `grep reboot`: the emit carries a CONSTANT
#       `reboot_count=0` and the header COMMENTS mention reboot, so a token grep false-fails a
#       correct detect-only port. We assert on a COMMENT-STRIPPED view that the reboot INVOCATION
#       PATH is absent (no standalone `reboot` line, no CONVERGED_BY=reboot, no DO_REBOOT, no
#       $REBOOT_BIN / REBOOT_CAP) — and MUTATION-test each negative so it is provably non-vacuous.
#
# Pure bash + PATH stubs — no docker, network, doppler, or root.
#
# Run: bash apps/web-platform/infra/web-private-nic-guard.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-private-nic-guard.sh"
TEST_IP="10.0.1.10"   # web-1's private address (var.web_hosts[web-1].private_ip); never a literal in the SUT.

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Resolved BEFORE any fixture strips PATH (the hide-ip arm runs on a stripped PATH).
TIMEOUT_BIN="$(command -v timeout || true)"

echo "=== web-host private-NIC self-report guard (#6438 §3, AC4) tests ==="
assert "web-private-nic-guard.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"
assert "the timeout binary is available (bounds the stubbed-sleep spin)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# `ip` serves the trigger predicate (`-4 -o addr show`) and the emit's NIC_ADDRS tail.
cat > "$BIN/ip" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "${STUB_IP_OUT:-}"
EOS

# `curl` serves three callers: the IMDS probe (private-networks), the Better Stack POST
# (--data-raw), and the liveness heartbeat ping (WEB_NIC_GUARD_URL, the only other curl).
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *private-networks*) printf '%s' "${STUB_IMDS_BODY:-}"; exit "${STUB_IMDS_RC:-0}";;
  esac
done
is_post=false
for a in "$@"; do [[ "$a" == "--data-raw" ]] && is_post=true; done
if $is_post; then
  prev=""
  for a in "$@"; do [[ "$prev" == "--data-raw" ]] && printf '%s\n' "$a" >> "$STUB_EMIT"; prev="$a"; done
  exit 0
fi
# Otherwise this is the heartbeat ping — record its URL (the last positional).
url=""; for a in "$@"; do url="$a"; done
printf '%s\n' "$url" >> "$STUB_PING"
exit 0
EOS

# A reboot stub that RECORDS every call. A correct web-host guard never invokes it, so the
# trace must stay empty in every fixture — the behavioral half of AC4.
cat > "$BIN/reboot" <<'EOS'
#!/usr/bin/env bash
echo "reboot $*" >> "$STUB_TRACE"
EOS

# Stub sleep so the absent-IP fixtures' bounded wait (~30x2s) runs instantly. With sleep
# stubbed a lost wait-bound becomes an infinite TIGHT SPIN, so run_guard wraps with `timeout`.
cat > "$BIN/sleep" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS

chmod +x "$BIN"/*

# --- Fixture harness ---------------------------------------------------------------------
# run_guard <ip_present:true|false> <imds_rc> <imds_has_expected:true|false> [hide_ip:true|false]
run_guard() {
  local ip_present="$1" imds_rc="$2" imds_expected="$3" hide_ip="${4:-false}"
  local root="$TMP/root.$$.$RANDOM"
  rm -rf "$root"; mkdir -p "$root/proc/sys/kernel/random"
  printf '99999.00 0.00\n' > "$root/proc/uptime"
  printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n' > "$root/proc/sys/kernel/random/boot_id"

  # Synthesized `ip -4 -o addr show`. Public eth0 is ALWAYS present (the #6400 shape: the host
  # is reachable/green while the private NIC is missing). enp7s0 carries EXPECTED_IP iff present.
  if [[ "$ip_present" == true ]]; then
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0
3: enp7s0    inet ${TEST_IP}/32 scope global enp7s0"
  else
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0"
  fi

  # Synthesized Hetzner IMDS private-networks YAML (`- ip:` then a 2-space `network_id:`).
  STUB_IMDS_BODY=""
  if [[ "$imds_expected" == true ]]; then
    STUB_IMDS_BODY="- ip: ${TEST_IP}
  network_id: 1001
  network_name: soleur-private
"
  fi
  export STUB_IMDS_BODY STUB_IMDS_RC="$imds_rc"
  export STUB_EMIT="$root/emit"; : > "$STUB_EMIT"
  export STUB_PING="$root/ping"; : > "$STUB_PING"
  export STUB_TRACE="$root/trace"; : > "$STUB_TRACE"

  # hide_ip models the probe-fault class: `ip` unresolvable (lives in /usr/sbin, off cron's
  # default PATH) while curl still resolves. The stripped PATH is used ALONE so the real
  # /usr/sbin/ip cannot leak in and mask the fault.
  local run_path="$BIN:$PATH"
  if [[ "$hide_ip" == true ]]; then
    local nobin="$root/nobin"; mkdir -p "$nobin"
    local b p
    for b in curl reboot sleep; do cp "$BIN/$b" "$nobin/$b"; done
    for b in bash awk grep cat sed head cut tr tail seq; do
      p="$(command -v "$b" 2>/dev/null || true)"; [[ -n "$p" ]] && ln -sf "$p" "$nobin/$b" 2>/dev/null || true
    done
    run_path="$nobin"
  fi

  PATH="$run_path" EXPECTED_IP="$TEST_IP" SOLEUR_NIC_TEST_ROOT="$root" \
    BETTERSTACK_LOGS_TOKEN=synthetic-token BETTERSTACK_INGEST_URL="https://synthetic.invalid/ingest" \
    WEB_NIC_GUARD_URL="https://synthetic.invalid/beat/web-nic-guard" \
    "$TIMEOUT_BIN" 10 bash "$SUT" >/dev/null 2>&1

  # shellcheck disable=SC2034  # consumed by assert() conditions via eval
  EMIT="$(cat "$root/emit" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  PING="$(cat "$root/ping" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  TRACE="$(cat "$root/trace" 2>/dev/null || true)"
}

field() { printf '%s' "$EMIT" | grep -oE "$1=[^ \"]+" | head -1 | cut -d= -f2; }

# --- BEHAVIORAL: T1 ip present => nic_ok, converged_by=already, heartbeat PINGED ----------
# T1 is the POSITIVE CONTROL for the whole ping suite: it proves the ping stub + mechanism are
# live, so every "NOT pinged" below means something.
echo "--- behavioral: T1 ip present => already, ping fires ---"
run_guard true 0 true
assert "T1 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T1 nic_ok=true" "[[ \"\$(field nic_ok)\" == true ]]"
assert "T1 converged_by=already" "[[ \"\$(field converged_by)\" == already ]]"
assert "T1 heartbeat PINGED (nic_ok=true)" "grep -q 'web-nic-guard' <<<\"\$PING\""
assert "T1 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T1 emit carries the CONSTANT reboot_count=0" "grep -qE '(^| )reboot_count=0( |\")' <<<\"\$EMIT\""

# --- BEHAVIORAL: T2 ip absent + IMDS corroborates => detect-only, NO reboot, NO ping ------
echo "--- behavioral: T2 ip absent, IMDS corroborates => detect-only ---"
run_guard false 0 true
assert "T2 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T2 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T2 converged_by=detect-only (NOT reboot — web host never power-cycles the sole origin)" \
  "[[ \"\$(field converged_by)\" == detect-only ]]"
assert "T2 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T2 heartbeat NOT pinged (broken NIC must let the beat lapse)" "[[ -z \"\$PING\" ]]"
assert "T2 imds_has_expected=true is carried for discrimination" "[[ \"\$(field imds_has_expected)\" == true ]]"

# --- BEHAVIORAL: T3 ip probe unresolvable => probe-fault, NO reboot, NO ping --------------
echo "--- behavioral: T3 ip binary absent => probe-fault ---"
run_guard false 0 true true
assert "T3 emits an event (the fault is observable off-box)" "[[ -n \"\$EMIT\" ]]"
assert "T3 converged_by=probe-fault (zero evidence, not a NIC diagnosis)" \
  "[[ \"\$(field converged_by)\" == probe-fault ]]"
assert "T3 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T3 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T3 heartbeat NOT pinged" "[[ -z \"\$PING\" ]]"

# --- BEHAVIORAL: emit field contract (full set, always) ----------------------------------
echo "--- behavioral: emit field contract ---"
run_guard true 0 true
assert "emit marker is SOLEUR_PRIVATE_NIC" "grep -q 'SOLEUR_PRIVATE_NIC' <<<\"\$EMIT\""
for f in nic_ok converged_by imds_rc imds_nets imds_has_expected reboot_count zot_store_mounted uptime_s boot_id zot_last_err; do
  assert "emit carries $f" "grep -qE '(^| )$f=' <<<\"\$EMIT\""
done
assert "emit's reboot_count is the CONSTANT 0 (no-reboot invariant self-evident in every beat)" \
  "[[ \"\$(field reboot_count)\" == 0 ]]"

# --- AC4 STRUCTURAL: the reboot INVOCATION PATH is absent (comment-stripped view) ---------
# Anchored on SYNTAX, not a token grep: the header comments mention reboot and the emit carries
# `reboot_count=0`, so a bare `grep reboot` on the RAW file false-fails a correct port. Strip
# full-line `#` comments first, then assert on the code that remains.
echo "--- AC4 structural: no reboot invocation path (comment-stripped) ---"
STRIPPED="$(grep -vE '^[[:space:]]*#' "$SUT")"
assert "the stripped view is non-empty (comment-strip did not nuke the script)" "[[ -n \"\$STRIPPED\" ]]"
assert "the stripped view still carries the emit line (strip kept the code)" \
  "grep -q 'SOLEUR_PRIVATE_NIC' <<<\"\$STRIPPED\""
# Document WHY the strip is required: the RAW file DOES contain the token 'reboot' (in comments +
# reboot_count=0), so a naive `grep reboot == absent` would false-fail this correct detect-only port.
assert "rationale: the RAW file contains the token 'reboot' (why a bare grep false-fails)" \
  "grep -q 'reboot' '$SUT'"

assert "AC4: no standalone 'reboot' command line" \
  "! grep -qE '^[[:space:]]*reboot([[:space:]]|\$)' <<<\"\$STRIPPED\""
assert "AC4: no CONVERGED_BY=reboot execution path" \
  "! grep -q 'CONVERGED_BY=reboot' <<<\"\$STRIPPED\""
assert "AC4: no DO_REBOOT gate" \
  "! grep -q 'DO_REBOOT' <<<\"\$STRIPPED\""
assert "AC4: no \$REBOOT_BIN resolution" \
  "! grep -q 'REBOOT_BIN' <<<\"\$STRIPPED\""
assert "AC4: no REBOOT_CAP budget (the registry's reboot machinery is intentionally absent)" \
  "! grep -q 'REBOOT_CAP' <<<\"\$STRIPPED\""

# --- AC4 MUTATION CONTROLS: prove each negative assert above can FAIL (non-vacuity) -------
# Each control appends the offending construct to the stripped view and shows the SAME predicate
# the negative assert uses WOULD then match — so the negative assert is meaningful, not vacuous.
echo "--- AC4 mutation controls: each negative assert is provably non-vacuous ---"
assert "MUT: a standalone 'reboot' line is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'reboot' | grep -qE '^[[:space:]]*reboot([[:space:]]|\$)'"
assert "MUT: 'CONVERGED_BY=reboot' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'CONVERGED_BY=reboot' | grep -q 'CONVERGED_BY=reboot'"
assert "MUT: 'DO_REBOOT' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'if [ \"\$DO_REBOOT\" = true ]; then' | grep -q 'DO_REBOOT'"
assert "MUT: '\$REBOOT_BIN' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'REBOOT_BIN=\$(command -v reboot)' | grep -q 'REBOOT_BIN'"
assert "MUT: 'REBOOT_CAP' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'REBOOT_CAP=2' | grep -q 'REBOOT_CAP'"
# And prove the standalone-reboot predicate does NOT fire on the emit's `reboot_count=0` (the exact
# false-positive the anchoring defends against) — so the negative asserts pass for the RIGHT reason.
assert "MUT: the predicate does NOT mis-fire on the emit's 'reboot_count=0'" \
  "! printf '%s\n' 'LINE=\"SOLEUR_PRIVATE_NIC reboot_count=0 boot_id=x\"' | grep -qE '^[[:space:]]*reboot([[:space:]]|\$)'"

# --- static drift-guard: doppler-auth unit-start contract (#6438 §3 unit-start fix) -------
# The guard runs `doppler run` as ROOT. Without Environment=HOME=/root the doppler CLI dies
# "$HOME is not defined" BEFORE it exec's the guard; without a DOPPLER_TOKEN in the per-host
# env file it cannot authenticate. Both gaps made the unit fail to start on web-1. Assert both,
# and that the fix does not re-open the #6536 /tmp/.doppler ownership clash surface.
echo "--- static: doppler-auth unit-start contract ---"
SVC="$SCRIPT_DIR/web-private-nic-guard.service"
SERVER_TF="$SCRIPT_DIR/server.tf"
assert "nic-guard .service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert "nic-guard .service does NOT source webhook-deploy (deploy-owned; imports /tmp/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'webhook-deploy'"
assert "nic-guard .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q 'DOPPLER_CONFIG_DIR'"
assert "nic-guard .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -q '/tmp/.doppler'"
assert "nic-guard .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -qE '^PrivateTmp=true' '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal (test-design review).
assert "server.tf private_nic_guard_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-private-nic-guard" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-private-nic-guard' '$SERVER_TF'"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
