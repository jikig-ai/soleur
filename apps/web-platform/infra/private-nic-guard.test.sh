#!/usr/bin/env bash
# Tests the registry-host private-NIC boot converger + its SOLEUR_PRIVATE_NIC self-report
# (#6415 / ADR-115, cloud-init-registry.yml).
#
# WHY THIS SHAPE. The 2026-07-14 zot outage (#6400): the host booted with only its public
# eth0, held no 10.0.1.30, and every health signal stayed GREEN for ~14 days (public egress
# works NIC-less; the boot readiness poll hits localhost:5000). The guard converges the NIC
# and emits a discriminating event. Its two dangerous failure modes are (a) rebooting a
# HEALTHY host and (b) a reboot loop — so the behavioral layer below is mostly negative
# space: proving the guard does NOT mutate.
#
# NON-VACUITY: every negative assert is paired with a positive emit assert from the SAME run,
# and the emit happens strictly BEFORE the reboot. T4 is the positive control for the reboot
# arm itself. So "NO reboot" can never pass because the script died at line 1.
#
# TWO layers (mirrors registry-boot-guard.test.sh:20-60):
#   1. BEHAVIORAL: RENDER the guard out of the Terraform template and EXECUTE it against
#      synthesized fixtures + PATH stubs (cq-test-fixtures-synthesized-only).
#      NOTE (kieran P1-6): unlike registry-boot-guard.test.sh — which extracts only SCALARS
#      (a regex + an integer, :38-42) — the guard BODY is a templatefile: `$${...}` is
#      TF-escaped and `${private_ip}` is unrendered, so extracted bytes are NOT executable
#      bash. The render step below (un-indent -> substitute TF vars -> un-escape $${) is
#      what makes "the same bytes the host boots" true rather than rhetorical. It is verified
#      byte-identical against terraform's own `templatefile` render.
#   2. STRUCTURAL grep assertions: counter-before-reboot, the POSITIVE counter path
#      (/var/lib/soleur — asserting "not /var/lib/zot" would NOT exclude a tmpfs path),
#      literal cap 2, flock on BOTH cron and boot, `|| true` on boot, boot invocation after
#      the Doppler token file, zot_last_err trailing, and the `doppler run` wrapper.
#
# Static + pure-bash — no docker, no network, no doppler, no root.
#
# Run: bash apps/web-platform/infra/private-nic-guard.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"
GUARD_PATH="/usr/local/bin/soleur-private-nic-guard.sh"
TEST_IP="10.0.1.30"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Resolved BEFORE any fixture strips PATH (see run_guard's STUB_HIDE_IP arm).
TIMEOUT_BIN="$(command -v timeout || true)"

echo "=== registry private-NIC boot converger (#6415) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"
assert "the timeout binary is available (bounds the stubbed-sleep spin)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- RENDER: template -> executable bash -------------------------------------------------
RENDERED="$TMP/guard.sh"
awk -v want="  - path: $GUARD_PATH" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent {
    if ($0 ~ /^      /) { print substr($0, 7); next }
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    exit
  }
' "$CI" > "$RENDERED"

assert "guard block extracted from the template (non-empty)" "[[ -s '$RENDERED' ]]"
assert "extracted block is the guard (has a shebang)" "head -1 '$RENDERED' | grep -q '^#!'"

# Substitute every terraform variable the guard interpolates, then un-escape the TF-escaped
# shell expansions ($${VAR} -> ${VAR}). BOTH are required: a missed TF var survives into the
# rendered bash as a literal `${name}` that `set -u` then kills the script on — silently,
# mid-emit. The assert below is what makes that loud instead of a mysteriously empty event.
sed -i "s|\${private_ip}|$TEST_IP|g" "$RENDERED"
sed -i "s|\${betterstack_ingest_url}|https://synthetic.invalid/ingest|g" "$RENDERED"
sed -i 's|\$\${|${|g' "$RENDERED"

# `[A-Za-z0-9_.]+`, NOT `[a-z_]+`: TF var names routinely carry digits (`ip_v4`, `url_v2`), and
# a missed digit-bearing var never trips `set -u` if it sits inside quotes — so the suite would
# silently execute a broken guard. This assert's whole job is to make that loud, so its charset
# must be at least as wide as Terraform's. The shell seams `${SOLEUR_NIC_TEST_ROOT:-}` /
# `${BETTERSTACK_LOGS_TOKEN:-}` fail the `\}` anchor on their `:`, so they are not false hits.
assert "render left no unrendered TF interpolation" "! grep -qE '\\\$\{[A-Za-z0-9_.]+\}' '$RENDERED'"
assert "rendered guard is syntactically valid bash" "bash -n '$RENDERED'"
chmod +x "$RENDERED"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# STUB_IP_FLIP_AFTER models H2 — the attach landing DURING the bounded wait. Without it the stub
# is a constant, so the wait could never be observed SUCCEEDING and a regression that loses
# ip_present=true inside the loop would pass. The counter file makes the flip observable across
# the guard's separate `ip` invocations.
cat > "$BIN/ip" <<'EOS'
#!/usr/bin/env bash
if [[ -n "${STUB_IP_FLIP_AFTER:-}" ]]; then
  n=0; [[ -f "$STUB_IP_CALLS" ]] && n=$(cat "$STUB_IP_CALLS")
  n=$((n + 1)); echo "$n" > "$STUB_IP_CALLS"
  if (( n > STUB_IP_FLIP_AFTER )); then printf '%s\n' "${STUB_IP_OUT_AFTER:-}"; exit 0; fi
fi
printf '%s\n' "${STUB_IP_OUT:-}"
EOS

# curl serves two callers: the IMDS probe (private-networks) and the Better Stack POST.
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *private-networks*)
      printf '%s' "${STUB_IMDS_BODY:-}"
      exit "${STUB_IMDS_RC:-0}"
      ;;
  esac
done
prev=""
for a in "$@"; do
  if [[ "$prev" == "--data-raw" ]]; then printf '%s\n' "$a" >> "$STUB_EMIT"; fi
  prev="$a"
done
exit 0
EOS

cat > "$BIN/mountpoint" <<'EOS'
#!/usr/bin/env bash
# A successful `mount -a` drops the heal flag, flipping this probe green.
[[ -n "${STUB_MOUNT_FLAG:-}" && -f "${STUB_MOUNT_FLAG}" ]] && exit 0
exit "${STUB_MOUNTPOINT_RC:-0}"
EOS

cat > "$BIN/mount" <<'EOS'
#!/usr/bin/env bash
echo "mount $*" >> "$STUB_TRACE"
[[ -n "${STUB_MOUNT_HEALS:-}" ]] && touch "$STUB_MOUNT_FLAG"
exit 0
EOS

cat > "$BIN/docker" <<'EOS'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_TRACE"
exit "${STUB_DOCKER_RC:-0}"
EOS

cat > "$BIN/reboot" <<'EOS'
#!/usr/bin/env bash
echo "reboot" >> "$STUB_TRACE"
EOS

# The guard's bounded wait is ~30 x 2s. Stub sleep so the absent-IP fixtures run instantly —
# this keeps the wait a REAL 60s in production (no test-only timing seam in the guard) while
# the suite stays fast. See the `timeout` in run_guard: stubbing sleep turns a lost wait-bound
# into an infinite TIGHT SPIN, so the bound must be enforced from outside.
cat > "$BIN/sleep" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS

chmod +x "$BIN"/*

# --- Fixture harness ---------------------------------------------------------------------
# run_guard <ip_present:true|false> <imds_rc> <imds_nets> <uptime_s> <reboot_count> <store_mounted:true|false>
run_guard() {
  local ip_present="$1" imds_rc="$2" imds_nets="$3" uptime_s="$4" rc_count="$5" store="$6"
  local root="$TMP/root.$$.$RANDOM"
  rm -rf "$root"; mkdir -p "$root/proc/sys/kernel/random" "$root/var/lib/cloud/data" "$root/var/lib/soleur"

  printf '%s.00 0.00\n' "$uptime_s" > "$root/proc/uptime"
  printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n' > "$root/proc/sys/kernel/random/boot_id"
  printf 'i-synthetic-0001\n' > "$root/var/lib/cloud/data/instance-id"
  if [[ "$rc_count" != "0" ]]; then
    printf 'instance_id=i-synthetic-0001\ncount=%s\n' "$rc_count" > "$root/var/lib/soleur/private-nic-reboots"
  fi

  # Synthesized `ip -4 -o addr show` output — verified byte-identical to the real tool's output
  # through BOTH consumers (the `grep -qwF` predicate and the `awk '{print $2":"$4}'` payload).
  # Public eth0 is ALWAYS present: that is the #6400 shape — the host is reachable and green
  # while the private NIC is missing.
  if [[ "$ip_present" == "true" ]]; then
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0
3: enp7s0    inet ${TEST_IP}/32 scope global enp7s0"
  else
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0"
  fi

  # Synthesized Hetzner IMDS private-networks YAML (a faithful subset of the documented shape:
  # `- ip:` then a 2-space `network_id:`). The address line is what the reboot gate corroborates
  # on; network_id is the emit field. STUB_IMDS_WRONG_IP models the drift case: networks ARE
  # attached, but not at EXPECTED_IP.
  local imds_ip="$TEST_IP"
  [[ -n "${STUB_IMDS_WRONG_IP:-}" ]] && imds_ip="10.0.1.99"
  STUB_IMDS_BODY=""
  local i
  for ((i = 0; i < imds_nets; i++)); do
    STUB_IMDS_BODY+="- ip: ${imds_ip}
  network_id: 100${i}
  network_name: soleur-private
"
  done
  export STUB_IMDS_BODY
  export STUB_IMDS_RC="$imds_rc"
  local mp_rc; mp_rc=$([[ "$store" == "true" ]] && echo 0 || echo 1)
  export STUB_MOUNTPOINT_RC="$mp_rc"
  export STUB_TRACE="$root/trace"
  export STUB_EMIT="$root/emit"
  export STUB_MOUNT_FLAG="$root/mount-healed"
  export STUB_IP_CALLS="$root/ip-calls"
  export STUB_IP_OUT_AFTER="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0
3: enp7s0    inet ${TEST_IP}/32 scope global enp7s0"
  rm -f "$STUB_MOUNT_FLAG" "$STUB_IP_CALLS"
  : > "$STUB_TRACE"; : > "$STUB_EMIT"

  # STUB_HIDE_IP models the cron-PATH class: `ip` unresolvable while curl still resolves. The
  # stub PATH is used ALONE (not prepended to the harness PATH) so the real /usr/sbin/ip cannot
  # leak in and mask the fault — prepending is exactly what made this defect invisible.
  local run_path="$BIN:$PATH"
  if [[ -n "${STUB_HIDE_IP:-}" ]]; then
    local nobin="$root/nobin"; mkdir -p "$nobin"
    local b p
    for b in curl mountpoint mount docker reboot sleep; do cp "$BIN/$b" "$nobin/$b"; done
    for b in bash awk grep cat sed head cut tr tail sort seq mkdir mv sync; do
      p="$(command -v "$b" 2>/dev/null || true)"; [[ -n "$p" ]] && ln -sf "$p" "$nobin/$b" 2>/dev/null || true
    done
    run_path="$nobin"
  fi
  if [[ -n "${STUB_RO_COUNTER:-}" ]]; then chmod 500 "$root/var/lib/soleur"; fi

  # `timeout` is load-bearing BECAUSE sleep is stubbed: that turns a lost wait-bound
  # (`for i in $(seq 1 30)` -> `while true`) from "slow" into an infinite TIGHT SPIN, which would
  # burn the CI job's whole timeout with no failure message. Resolved ABSOLUTE: `PATH=x timeout …`
  # would look `timeout` up through the STRIPPED PATH above and silently not run the guard.
  PATH="$run_path" SOLEUR_NIC_TEST_ROOT="$root" BETTERSTACK_LOGS_TOKEN=synthetic-token \
    "$TIMEOUT_BIN" 10 bash "$RENDERED" >/dev/null 2>&1

  if [[ -n "${STUB_RO_COUNTER:-}" ]]; then chmod 700 "$root/var/lib/soleur"; fi

  # Consumed by the assert() conditions below via eval — shellcheck cannot see through that.
  # shellcheck disable=SC2034
  TRACE="$(cat "$root/trace" 2>/dev/null || true)"
  EMIT="$(cat "$root/emit" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  COUNTER="$(cat "$root/var/lib/soleur/private-nic-reboots" 2>/dev/null || true)"
}

field() { printf '%s' "$EMIT" | grep -oE "$1=[^ \"]+" | head -1 | cut -d= -f2; }

# --- BEHAVIORAL: T1 healthy => ZERO mutation (AC3) ---------------------------------------
echo "--- behavioral: T1 healthy (ip present, store mounted) => zero mutation ---"
run_guard true 0 1 99999 0 true
assert "T1 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T1 nic_ok=true" "[[ \"\$(field nic_ok)\" == true ]]"
assert "T1 converged_by=already" "[[ \"\$(field converged_by)\" == already ]]"
assert "T1 NO reboot" "! grep -q reboot <<<\"\$TRACE\""
assert "T1 NO mount -a (zero mutation)" "! grep -q '^mount' <<<\"\$TRACE\""
assert "T1 NO docker restart (zero mutation)" "! grep -q docker <<<\"\$TRACE\""
assert "T1 zot_store_mounted=true" "[[ \"\$(field zot_store_mounted)\" == true ]]"

# --- BEHAVIORAL: T2 H1 imds unreachable => NO reboot (no corroboration) -------------------
echo "--- behavioral: T2 imds_rc!=0 (H1) => no reboot ---"
run_guard false 7 0 99999 0 true
assert "T2 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T2 NO reboot on zero corroboration" "! grep -q reboot <<<\"\$TRACE\""
assert "T2 converged_by=none" "[[ \"\$(field converged_by)\" == none ]]"
assert "T2 imds_rc is carried (discriminates H1)" "[[ \"\$(field imds_rc)\" == 7 ]]"

# --- BEHAVIORAL: T3 H2 imds reachable but zero nets => NO reboot --------------------------
echo "--- behavioral: T3 imds_rc=0, imds_nets=0 (H2) => no reboot ---"
run_guard false 0 0 99999 0 true
assert "T3 NO reboot (attach not yet landed)" "! grep -q reboot <<<\"\$TRACE\""
assert "T3 imds_nets=0 (discriminates H2)" "[[ \"\$(field imds_nets)\" == 0 ]]"

# --- BEHAVIORAL: T4 corroborated + unexhausted => counter THEN exactly one reboot ---------
# This is the POSITIVE CONTROL for the whole negative-space suite: it proves the reboot stub,
# the trace mechanism and the gate are all live, so every "NO reboot" above means something.
echo "--- behavioral: T4 corroborated, uptime>600, budget left => one reboot ---"
run_guard false 0 1 99999 0 true
assert "T4 rebooted" "grep -q reboot <<<\"\$TRACE\""
assert "T4 exactly ONE reboot" "[[ \"\$(grep -c '^reboot$' <<<\"\$TRACE\")\" == 1 ]]"
assert "T4 counter incremented to 1" "grep -q '^count=1$' <<<\"\$COUNTER\""
assert "T4 counter keyed by instance-id" "grep -q '^instance_id=i-synthetic-0001$' <<<\"\$COUNTER\""
assert "T4 converged_by=reboot" "[[ \"\$(field converged_by)\" == reboot ]]"
assert "T4 emitted BEFORE the reboot (event ships)" "[[ -n \"\$EMIT\" ]]"

# --- BEHAVIORAL: T5 counter exhausted => NO reboot (R1 bound) -----------------------------
echo "--- behavioral: T5 counter exhausted (cap 2) => no reboot, terminal ---"
run_guard false 0 1 99999 2 true
assert "T5 NO reboot at cap" "! grep -q reboot <<<\"\$TRACE\""
assert "T5 converged_by=none (terminal)" "[[ \"\$(field converged_by)\" == none ]]"
assert "T5 reboot_count=2 carried" "[[ \"\$(field reboot_count)\" == 2 ]]"
assert "T5 nic_ok=false (terminal alarm fires on this)" "[[ \"\$(field nic_ok)\" == false ]]"

# --- BEHAVIORAL: T6 just booted => NO reboot ---------------------------------------------
echo "--- behavioral: T6 uptime_s<600 => no reboot regardless of corroboration ---"
run_guard false 0 1 120 0 true
assert "T6 NO reboot on a just-booted host" "! grep -q reboot <<<\"\$TRACE\""
assert "T6 uptime_s carried" "[[ \"\$(field uptime_s)\" == 120 ]]"

# --- BEHAVIORAL: T7 store unmounted => mount -a + docker restart (R4, pre-existing bug) ---
echo "--- behavioral: T7 store unmounted => mount -a + docker restart zot ---"
export STUB_MOUNT_HEALS=1
run_guard true 0 1 99999 0 false
assert "T7 ran mount -a" "grep -q '^mount -a' <<<\"\$TRACE\""
assert "T7 restarted zot (bind would else point at an empty dir)" "grep -q 'docker restart zot' <<<\"\$TRACE\""
assert "T7 reports the store mounted once the restart re-resolved the bind" \
  "[[ \"\$(field zot_store_mounted)\" == true ]]"
unset STUB_MOUNT_HEALS

# --- BEHAVIORAL: T7b heal FAILS => zot_store_mounted MUST stay false ----------------------
# The alarm FIREs on this. Reporting true here is a green signal over a dead pull path — the
# #6400 shape reintroduced through the very field added to prevent it.
echo "--- behavioral: T7b store unmounted, mount -a does NOT heal => stays false ---"
run_guard true 0 1 99999 0 false
assert "T7b zot_store_mounted=false when the heal fails" "[[ \"\$(field zot_store_mounted)\" == false ]]"
assert "T7b did NOT restart zot (nothing to re-resolve)" "! grep -q 'docker restart' <<<\"\$TRACE\""

# --- BEHAVIORAL: T7c mount heals but `docker restart` FAILS => must NOT claim true --------
# Bind mounts are rprivate: without a successful restart zot is still bound to the empty dir.
echo "--- behavioral: T7c mount heals but docker restart fails => stays false ---"
export STUB_MOUNT_HEALS=1 STUB_DOCKER_RC=1
run_guard true 0 1 99999 0 false
assert "T7c zot_store_mounted=false when the restart fails" "[[ \"\$(field zot_store_mounted)\" == false ]]"
unset STUB_MOUNT_HEALS STUB_DOCKER_RC

# --- BEHAVIORAL: T8 the `ip` probe is UNRESOLVABLE => zero evidence, NO reboot ------------
# The cron-PATH class: `ip`/`reboot` live in /usr/sbin, off cron's default PATH, while curl (in
# /usr/bin) still resolves and IMDS still corroborates. Without the probe-fault arm the guard
# reads a HEALTHY host as NIC-absent, burns the budget, and pages terminal forever.
echo "--- behavioral: T8 ip binary absent => probe-fault, no reboot ---"
export STUB_HIDE_IP=1
run_guard false 0 1 99999 0 true
assert "T8 NO reboot when the probe never ran (zero evidence)" "! grep -q reboot <<<\"\$TRACE\""
assert "T8 converged_by=probe-fault (not a NIC diagnosis)" "[[ \"\$(field converged_by)\" == probe-fault ]]"
assert "T8 still emits (the fault is observable off-box)" "[[ -n \"\$EMIT\" ]]"
unset STUB_HIDE_IP

# --- BEHAVIORAL: T9 counter unwritable => withhold the reboot (fail CLOSED) ---------------
# An unchecked write on a read-only root fs never persists => the cap never binds => unbounded
# power-cycle on a no-SSH box.
echo "--- behavioral: T9 counter dir unwritable => no reboot ---"
export STUB_RO_COUNTER=1
run_guard false 0 1 99999 0 true
assert "T9 NO reboot when the budget cannot be persisted" "! grep -q reboot <<<\"\$TRACE\""
assert "T9 converged_by=counter-unwritable" "[[ \"\$(field converged_by)\" == counter-unwritable ]]"
unset STUB_RO_COUNTER

# --- BEHAVIORAL: T10 IMDS reports networks but NOT the expected address => NO reboot ------
# The drift case: a wrong EXPECTED_IP would be "corroborated" by a bare network count and the
# guard would reboot a HEALTHY host to its cap. Corroborating on the address makes it unreachable.
echo "--- behavioral: T10 imds_nets>0 but the expected IP is absent from IMDS => no reboot ---"
export STUB_IMDS_WRONG_IP=1
run_guard false 0 1 99999 0 true
assert "T10 NO reboot when IMDS does not list the EXPECTED address" "! grep -q reboot <<<\"\$TRACE\""
assert "T10 imds_nets is still carried for H1/H2 discrimination" "[[ \"\$(field imds_nets)\" == 1 ]]"
unset STUB_IMDS_WRONG_IP

# --- BEHAVIORAL: T11 the attach lands DURING the bounded wait (H2's happy path) -----------
# The wait's entire reason to exist. With a constant `ip` stub this path is unreachable, so a
# regression that loses ip_present=true inside the loop (e.g. to a subshell) would pass.
echo "--- behavioral: T11 attach lands during the bounded wait => already, no reboot ---"
export STUB_IP_FLIP_AFTER=3
run_guard false 0 1 99999 0 true
assert "T11 the wait observed the attach land" "[[ \"\$(field nic_ok)\" == true ]]"
assert "T11 converged_by=already (no mutation was needed)" "[[ \"\$(field converged_by)\" == already ]]"
assert "T11 NO reboot — the wait healed it" "! grep -q reboot <<<\"\$TRACE\""
unset STUB_IP_FLIP_AFTER

# --- BEHAVIORAL: emit field contract ------------------------------------------------------
echo "--- behavioral: emit field contract ---"
run_guard true 0 1 99999 0 true
assert "emit marker is SOLEUR_PRIVATE_NIC" "grep -q 'SOLEUR_PRIVATE_NIC' <<<\"\$EMIT\""
for f in nic_ok converged_by imds_rc imds_nets reboot_count zot_store_mounted uptime_s boot_id zot_last_err; do
  assert "emit carries $f" "grep -qE '(^| )$f=' <<<\"\$EMIT\""
done
assert "emit does NOT carry host= (lib says boot_id, not host, separates hosts)" \
  "! grep -qE '(^| )host=' <<<\"\$EMIT\""
# NEGATIVE form. The obvious `grep -qE 'zot_last_err=[^"]*$'` is DEAD: `[^"]*` greedily eats any
# appended field, so it holds iff `zot_last_err=` exists at all and can never fail. A field
# appended after it would ship silently and then be silently eaten by zot_trusted_region's
# `sed 's/ zot_last_err=.*//'` — never reaching any verdict.
assert "zot_last_err is the TRAILING field (no key= may follow; the lib's strip bounds the trusted region)" \
  "! grep -qE 'zot_last_err=.* [a-z_]+=' <<<\"\$EMIT\""

# --- STRUCTURAL --------------------------------------------------------------------------
echo "--- structural: reboot bounding + wiring ---"
GUARD_BLOCK="$(cat "$RENDERED")"

assert "counter path is the POSITIVE /var/lib/soleur (root disk, not tmpfs, not /var/lib/zot)" \
  "grep -q '/var/lib/soleur/private-nic-reboots' <<<\"\$GUARD_BLOCK\""
assert "counter is NOT under /var/lib/zot (survives replace => inherited exhausted budget)" \
  "! grep -q '/var/lib/zot/private-nic-reboots' <<<\"\$GUARD_BLOCK\""
assert "counter is NOT on tmpfs (/run or /tmp => rotates per boot => infinite-reboot trap)" \
  "! grep -qE '(/run|/tmp)/[a-z-]*(nic|reboot)' <<<\"\$GUARD_BLOCK\""
# ANCHORED: an unanchored 'REBOOT_CAP=2' is satisfied by REBOOT_CAP=25.
assert "reboot cap is a LITERAL 2 (T5/T6 unwritable against a range)" \
  "grep -qxE 'REBOOT_CAP=2' <<<\"\$GUARD_BLOCK\""
assert "reboot authority is gated on a VERIFIED durable counter write" \
  "grep -qE 'grep -qxF \"count=\\\$REBOOT_COUNT\"' <<<\"\$GUARD_BLOCK\""
assert "the counter write is atomic (rename(2), so a reader never sees a torn file)" \
  "grep -qE 'mv -f \"\\\$COUNTER_FILE.tmp\" \"\\\$COUNTER_FILE\"' <<<\"\$GUARD_BLOCK\""
assert "an unwritable counter withholds the reboot (fails CLOSED)" \
  "grep -qE 'CONVERGED_BY=counter-unwritable' <<<\"\$GUARD_BLOCK\""

COUNTER_WRITE_LN="$(grep -n '> "\$COUNTER_FILE.tmp"' "$RENDERED" | head -1 | cut -d: -f1)"
REBOOT_LN="$(grep -nE '^[[:space:]]*reboot[[:space:]]*$' "$RENDERED" | head -1 | cut -d: -f1)"
assert "the counter write was located" "[[ -n '$COUNTER_WRITE_LN' ]]"
assert "the reboot call was located" "[[ -n '$REBOOT_LN' ]]"
assert "counter is written BEFORE the reboot (fail-safe ordering)" \
  "[[ '$COUNTER_WRITE_LN' -lt '$REBOOT_LN' ]]"
assert "the emit precedes the reboot (a converge is never silent)" \
  "[[ \"\$(grep -n 'SOLEUR_PRIVATE_NIC nic_ok=' '$RENDERED' | head -1 | cut -d: -f1)\" -lt '$REBOOT_LN' ]]"

# ALL-MEMBERS, not first-member. The guard greps for EXPECTED_IP twice — the initial predicate
# AND the re-check inside the bounded wait. A `grep -q` any-occurrence assert stays green when
# only ONE is weakened, and the wait's copy is the one that runs inside the actual race window.
TRIGGER_GREPS="$(grep -cE 'grep -qwF -- "\$EXPECTED_IP"' "$RENDERED" || true)"
assert "BOTH trigger greps are exact-word + fixed-string (10.0.1.3 must not match 10.0.1.30)" \
  "[[ '$TRIGGER_GREPS' == '2' ]]"
assert "the predicate reads the LOCAL fact via the resolved ip binary" \
  "grep -qE '\"\\\$IP_BIN\" -4 -o addr show' <<<\"\$GUARD_BLOCK\""
assert "the guard resolves its ip probe explicitly and fails safe" \
  "grep -qE 'IP_BIN=\\\$\(command -v ip' <<<\"\$GUARD_BLOCK\""
assert "an unresolvable probe is zero evidence, not absence (probe-fault arm exists)" \
  "grep -qE 'CONVERGED_BY=probe-fault' <<<\"\$GUARD_BLOCK\""
assert "the reboot gate corroborates on the expected ADDRESS, not just a network count" \
  "grep -qE 'IMDS_HAS_EXPECTED\" = true \\]' <<<\"\$GUARD_BLOCK\""
# Pin the wait BOUND. With sleep stubbed, an unbounded wait is an infinite spin rather than a
# slow test — the `timeout` in run_guard turns that into a failure; this makes the intent explicit.
assert "the bounded wait is bounded by a literal iteration count" \
  "grep -qE 'for i in \\\$\(seq 1 30\); do' <<<\"\$GUARD_BLOCK\""

echo "--- structural: cron + boot invocation wiring ---"
CRON_LINE="$(grep -F '/usr/local/bin/soleur-private-nic-guard.sh' "$CI" | grep -F '* * * *' || true)"
BOOT_LINE="$(grep -F '/usr/local/bin/soleur-private-nic-guard.sh' "$CI" | grep -F '|| true' || true)"
CRON_BLOCK="$(awk '/- path: \/etc\/cron.d\/soleur-private-nic-guard/,/permissions/' "$CI")"

assert "a 5-min cron invokes the guard (offset from the disk heartbeat's */5)" \
  "grep -qE '^\s*2-59/5 \* \* \* \*' <<<\"\$CRON_LINE\""
# PATH is why the cron block is more than one line: `ip` and `reboot` live in /usr/sbin, which
# cron's default PATH (/usr/bin:/bin) omits, while curl does not — so an undeclared PATH makes
# the guard read a HEALTHY host as NIC-absent while IMDS corroborates.
assert "the cron.d block declares a PATH (cron's default omits /usr/sbin)" \
  "grep -qE '^\s*PATH=' <<<\"\$CRON_BLOCK\""
assert "that PATH includes /usr/sbin, where ip and reboot live" \
  "grep -E '^\s*PATH=' <<<\"\$CRON_BLOCK\" | grep -q '/usr/sbin'"
assert "the cron takes the flock" "grep -q 'flock' <<<\"\$CRON_LINE\""
assert "the cron wraps in doppler run --project soleur-registry --config prd" \
  "grep -q 'doppler run --project soleur-registry --config prd' <<<\"\$CRON_LINE\""
assert "the boot invocation takes the SAME flock (else boot and cron race)" \
  "grep -q 'flock' <<<\"\$BOOT_LINE\""
assert "the boot invocation is fail-open (|| true)" "grep -q '|| true' <<<\"\$BOOT_LINE\""
assert "cron and boot take the same lock path" \
  "[[ \"\$(grep -oE '/run/lock/[a-z.-]+' <<<\"\$CRON_LINE\" | head -1)\" == \"\$(grep -oE '/run/lock/[a-z.-]+' <<<\"\$BOOT_LINE\" | head -1)\" ]]"

# The boot invocation MUST follow the Doppler token file: anywhere earlier has no token, so
# `doppler run` resolves nothing, the POST dies, and `|| true` swallows it SILENTLY — a silent
# failure inside the control built to end silent failures (kieran P1-3).
TOKEN_LINE="$(grep -n 'registry-doppler$' "$CI" | grep -F 'printf' | head -1 | cut -d: -f1)"
BOOT_LINE_NO="$(grep -n 'soleur-private-nic-guard.sh' "$CI" | grep -F '|| true' | head -1 | cut -d: -f1)"
assert "the Doppler token file write was located" "[[ -n '$TOKEN_LINE' ]]"
assert "the boot invocation was located" "[[ -n '$BOOT_LINE_NO' ]]"
assert "the boot invocation comes AFTER the Doppler token file is written" \
  "[[ '$BOOT_LINE_NO' -gt '$TOKEN_LINE' ]]"
assert "the boot invocation sources the env file first (the disk-heartbeat precedent)" \
  "grep -q 'registry-doppler' <<<\"\$BOOT_LINE\""

# The test seam must never be armed in production.
assert "neither the cron nor the boot invocation sets the test-root seam" \
  "! grep -qE 'SOLEUR_NIC_TEST_ROOT=[^ ]' <<<\"\$CRON_LINE\$BOOT_LINE\""
assert "the state root defaults to the real FS when the seam is unset" \
  "grep -qE 'SOLEUR_NIC_TEST_ROOT:-\}?' <<<\"\$GUARD_BLOCK\""

echo "--- structural: terraform single-sourcing ---"
TF="$SCRIPT_DIR/zot-registry.tf"
NET="$SCRIPT_DIR/network.tf"
assert "zot-registry.tf passes private_ip into templatefile (asserts the ARGUMENT, not a bare grep)" \
  "grep -qE '^\s*private_ip\s*=\s*local\.registry_private_ip\s*\$' '$TF'"
# AC6 (corrected at /work): the plan's literal "exactly once across infra/*.tf" cannot pass — the
# IP also appears in comments (tunnel.tf, dns.tf, server.tf) and in server.tf's
# `docker info | grep '10.0.1.30:5000'` probe string. The invariant that matters is that the
# address is ASSIGNED from one place, so assert the assignment shape. NOTE the scope is
# deliberately narrow: `:5000`-suffixed endpoint copies (docker-daemon.json, cloud-init.yml,
# server.tf) are a SEPARATE pre-existing surface — see the tracking issue in the PR body.
ASSIGNS="$(grep -rhoE '^\s*ip\s*=\s*"10\.0\.1\.30"' "$SCRIPT_DIR"/*.tf | wc -l | tr -d ' ')"
assert "no .tf hardcodes 'ip = \"10.0.1.30\"' any more (single-sourced via local)" \
  "[[ '$ASSIGNS' == '0' ]]"
assert "network.tf attaches the registry at local.registry_private_ip" \
  "grep -qE '^\s*ip\s*=\s*local\.registry_private_ip\s*\$' '$NET'"
# Count only NON-COMMENT bare-literal occurrences. `^[^#]*` cannot cross a `#`, so commented
# hits (tunnel.tf:61 quotes the assignment inside prose) never match.
LIVE_LITERALS="$(grep -rhE '^[^#]*"10\.0\.1\.30"' "$SCRIPT_DIR"/*.tf | wc -l | tr -d ' ')"
assert "the bare IP literal is defined exactly once in live HCL (the local; comments excluded)" \
  "[[ '$LIVE_LITERALS' == '1' ]]"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
