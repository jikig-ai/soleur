#!/usr/bin/env bash
# Synthesized-fixture unit tests for scripts/zot-restart-loop-alarm.sh (#6291).
#
# cq-test-fixtures-synthesized-only: every fixture below is hand-crafted here — NO live
# Better Stack rows are captured into the test. Fixtures are fed to the checker through the
# ZOT_BQ_OVERRIDE seam (a stub betterstack-query.sh that returns per-query-shape canned rows),
# mirroring the #6288 soak-probe override seam.
#
# Covers Test Scenarios 1-10 in the plan + the exit-3 PRODUCER-SILENT vs exit-2 fresh-host
# discrimination, and asserts the checker distinguishes a *climb* (condition B) from an
# isolated single restart delta.
#
# .test.sh foot-guns (work conventions): `set -uo pipefail` (NOT -e — the checker exits
# non-zero by contract; a bare call under -e would abort the whole suite). Every checker call
# captures rc via `|| rc=$?`. A minimum-cardinality guard at the end fails the suite if fewer
# cases ran than expected (guards against a silent skip).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/zot-restart-loop-alarm.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- The stub betterstack-query.sh (ZOT_BQ_OVERRIDE) ------------------------------------
# Branches on the query SHAPE the checker issues:
#   - SOLEUR_PRIVATE_NIC + "24h" → the NIC 24h liveness lookback      → $NIC_FIX_LOOKBACK / _RC
#   - SOLEUR_PRIVATE_NIC         → the NIC recent-window query        → $NIC_FIX_MAIN / _RC
#   - contains "24h"             → the zot 24h producer lookback      → $ZOT_FIX_LOOKBACK / _RC
#   - contains "SOLEUR_ZOT_DISK" → the zot recent-window main query   → $ZOT_FIX_MAIN / _RC
#   - otherwise (bare --limit 1) → the control reachability probe     → $ZOT_FIX_CONTROL / _RC
#
# ORDER IS LOAD-BEARING: the NIC lookback query carries BOTH "24h" and "SOLEUR_PRIVATE_NIC", so
# a "24h"-first ladder would hand it the ZOT lookback fixture and silently mis-verdict the NIC
# stream. NIC is matched first.
STUB="$TMP/bq-stub.sh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
argv="$*"
if [[ "$argv" == *"SOLEUR_PRIVATE_NIC"* ]]; then
  if [[ "$argv" == *"24h"* ]]; then
    [[ -n "${NIC_FIX_LOOKBACK:-}" && -f "${NIC_FIX_LOOKBACK:-}" ]] && cat "$NIC_FIX_LOOKBACK"
    exit "${NIC_FIX_LOOKBACK_RC:-0}"
  fi
  [[ -n "${NIC_FIX_MAIN:-}" && -f "${NIC_FIX_MAIN:-}" ]] && cat "$NIC_FIX_MAIN"
  exit "${NIC_FIX_MAIN_RC:-0}"
elif [[ "$argv" == *"24h"* ]]; then
  [[ -n "${ZOT_FIX_LOOKBACK:-}" && -f "${ZOT_FIX_LOOKBACK:-}" ]] && cat "$ZOT_FIX_LOOKBACK"
  exit "${ZOT_FIX_LOOKBACK_RC:-0}"
elif [[ "$argv" == *"SOLEUR_ZOT_DISK"* ]]; then
  [[ -n "${ZOT_FIX_MAIN:-}" && -f "${ZOT_FIX_MAIN:-}" ]] && cat "$ZOT_FIX_MAIN"
  exit "${ZOT_FIX_MAIN_RC:-0}"
else
  [[ -n "${ZOT_FIX_CONTROL:-}" && -f "${ZOT_FIX_CONTROL:-}" ]] && cat "$ZOT_FIX_CONTROL"
  exit "${ZOT_FIX_CONTROL_RC:-0}"
fi
STUB_EOF
chmod +x "$STUB"

# Hex-only boot ids (the parser scopes via `boot_id=[0-9a-fA-F-]+`, so non-hex letters would
# be truncated). NEW = the newest host; OLD = a prior immutable-replace boot.
BOOT_NEW="aaaaaaaa-0000-0000-0000-000000000002"
BOOT_OLD="bbbbbbbb-0000-0000-0000-000000000001"

# zline <dt> <boot> <restarts> <exit_code> <oom5m> <oomkilled> <lasterr>
# Emits one JSONEachRow-shaped SOLEUR_ZOT_DISK row (dt-prefixed for lexical sort). zot_last_err
# is LAST (free-text), matching the real emit so the trusted-region strip is exercised.
zline() {
  printf '{"dt":"%s","raw":"SOLEUR_ZOT_DISK pcent=1 zot_restarts=%s ping_rc=0 mem_total_mb=7751 zot_anon_mb=35 zot_oom_kills=0 state_status=running oom_killed=%s exit_code=%s oom_kills_5m=%s boot_id=%s host=soleur-registry zot_last_err=%s"}\n' \
    "$1" "$3" "$6" "$4" "$5" "$2" "$7"
}

PASS=0; FAIL=0; CASES=0

# assert_case <name> <expect_rc> <expect_verdict>
# Reads fixture env from the caller's exported ZOT_FIX_* vars; runs the checker via the stub.
assert_case() {
  local name="$1" xrc="$2" xverdict="$3"
  CASES=$((CASES + 1))
  local rc=0 out verdict
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || rc=$?
  verdict="$(printf '%s\n' "$out" | grep -oE 'ZOT_ALARM_VERDICT=[A-Z_]+' | head -1 | cut -d= -f2 || true)"
  if [[ "$rc" == "$xrc" && "$verdict" == "$xverdict" ]]; then
    PASS=$((PASS + 1)); printf 'ok   - %s (rc=%s verdict=%s)\n' "$name" "$rc" "$verdict"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL - %s: expected rc=%s verdict=%s, got rc=%s verdict=%s\n' "$name" "$xrc" "$xverdict" "$rc" "$verdict"
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
}

# Reset fixture env to a clean slate before each case (avoid cross-case leakage).
reset_fix() {
  export ZOT_FIX_MAIN="" ZOT_FIX_MAIN_RC=0
  export ZOT_FIX_CONTROL="" ZOT_FIX_CONTROL_RC=0
  export ZOT_FIX_LOOKBACK="" ZOT_FIX_LOOKBACK_RC=0
  export NIC_FIX_MAIN="" NIC_FIX_MAIN_RC=0
  export NIC_FIX_LOOKBACK="" NIC_FIX_LOOKBACK_RC=0
}

# nline <dt> <boot> <nic_ok> <converged_by> <imds_rc> <imds_nets> <reboot_count> <uptime> <lasterr> [store_mounted]
# One JSONEachRow-shaped SOLEUR_PRIVATE_NIC row (#6415), mirroring the real emit: zot_last_err is
# LAST and free-text, so the shared trusted-region strip is exercised on this stream too.
# store_mounted is PARAMETERIZED (defaults true): hardcoding it would make the store-unmounted
# fault — the one that 404s the whole fleet while nic_ok=true — inexpressible as a fixture.
nline() {
  printf '{"dt":"%s","raw":"SOLEUR_PRIVATE_NIC nic_ok=%s converged_by=%s imds_rc=%s imds_nets=%s reboot_count=%s zot_store_mounted=%s uptime_s=%s boot_id=%s zot_last_err=%s"}\n' \
    "$1" "$3" "$4" "$5" "$6" "$7" "${10:-true}" "$8" "$2" "$9"
}

# assert_nic_case <name> <expect_nic_verdict>. The NIC verdict is INDEPENDENT of the exit code.
assert_nic_case() {
  local name="$1" xverdict="$2" out verdict
  CASES=$((CASES + 1))
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || true
  verdict="$(printf '%s\n' "$out" | grep -oE 'NIC_ALARM_VERDICT=[A-Z_]+' | head -1 | cut -d= -f2 || true)"
  if [[ "$verdict" == "$xverdict" ]]; then
    PASS=$((PASS + 1)); printf 'ok   - %s (nic_verdict=%s)\n' "$name" "$verdict"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL - %s: expected nic_verdict=%s, got %s\n' "$name" "$xverdict" "$verdict"
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
}

# assert_nic_cause_contains <name> <needle>
assert_nic_cause_contains() {
  local name="$1" needle="$2" out cause
  CASES=$((CASES + 1))
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || true
  cause="$(printf '%s\n' "$out" | sed -n 's/^NIC_ALARM_CAUSE=//p' | head -1)"
  if printf '%s\n' "$cause" | grep -qiF "$needle"; then
    PASS=$((PASS + 1)); printf 'ok   - %s (nic cause ~ "%s")\n' "$name" "$needle"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL - %s: nic cause did not contain "%s" (got: %s)\n' "$name" "$needle" "$cause"
  fi
}

# A healthy zot fixture, for NIC cases that must not be confounded by the zot verdict.
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 0 0 false none
} > "$TMP/zot-healthy.json"

# Optionally assert the decoded cause substring (2nd-order signal beyond the verdict).
# Scoped to the ZOT_ALARM_CAUSE= field, mirroring assert_nic_cause_contains. Grepping the WHOLE
# output would pass on a needle that only appears in DETAIL (or in an echoed fixture) — the
# assertion would then be weaker than its name.
assert_cause_contains() {
  local name="$1" needle="$2" out cause
  CASES=$((CASES + 1))
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || true
  cause="$(printf '%s\n' "$out" | sed -n 's/^ZOT_ALARM_CAUSE=//p' | head -1)"
  if printf '%s\n' "$cause" | grep -qiF "$needle"; then
    PASS=$((PASS + 1)); printf 'ok   - %s (cause ~ "%s")\n' "$name" "$needle"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL - %s: cause did not contain "%s" (got: %s)\n' "$name" "$needle" "$cause"
  fi
}

# --- Scenario 1: climbing restarts across 3 consecutive newest-boot events → FIRE(B) -----
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 88  0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 120 0 0 false none
  zline "2026-07-10 10:10:00" "$BOOT_NEW" 180 0 0 false none
} > "$TMP/s1.json"
export ZOT_FIX_MAIN="$TMP/s1.json"
assert_case "S1 climbing 88->120->180 (>=CLIMB_N consecutive)" 1 FIRE

# --- Scenario 2: flat restarts (5,5,5) → GREEN -------------------------------------------
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:10:00" "$BOOT_NEW" 5 0 0 false none
} > "$TMP/s2.json"
export ZOT_FIX_MAIN="$TMP/s2.json"
assert_case "S2 flat 5,5,5" 0 GREEN

# --- Scenario 3: exit_code=137 on newest boot → FIRE(A); with oom_kills_5m=1 → host/kernel OOM
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0   0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 137 1 false none
} > "$TMP/s3.json"
export ZOT_FIX_MAIN="$TMP/s3.json"
assert_case      "S3 exit_code=137 + oom_kills_5m=1" 1 FIRE
assert_cause_contains "S3 cause = host/kernel OOM" "host/kernel OOM"

# --- Scenario 4: oom_kills_5m=2 on newest boot → FIRE(C) ---------------------------------
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 0 2 false none
} > "$TMP/s4.json"
export ZOT_FIX_MAIN="$TMP/s4.json"
assert_case "S4 oom_kills_5m=2 (condition C)" 1 FIRE

# --- Scenario 5: oom_killed=true on a fired event → cause "cgroup --memory cap contained" -
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0   0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 137 0 true  none
} > "$TMP/s5.json"
export ZOT_FIX_MAIN="$TMP/s5.json"
assert_case      "S5 oom_killed=true fired event" 1 FIRE
assert_cause_contains "S5 cause = cgroup cap contained" "cgroup"

# --- Scenario 6: stale OLD-boot 137, newest boot clean → GREEN (newest-boot scoping) ------
reset_fix
{
  zline "2026-07-10 09:00:00" "$BOOT_OLD" 200 137 3 true  none
  zline "2026-07-10 09:05:00" "$BOOT_OLD" 260 137 4 true  none
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 0   0   0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 0   0   0 false none
} > "$TMP/s6.json"
export ZOT_FIX_MAIN="$TMP/s6.json"
assert_case "S6 stale old-boot 137, new boot clean" 0 GREEN

# --- Scenario 7: single isolated restart bump (NOT CLIMB_N-consecutive) → GREEN ----------
# 5,5,6,6 → longest strictly-increasing run is 2 (5->6), below CLIMB_N=3. Proves condition B
# tests the CLIMB, not a bare max-min delta.
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 10:10:00" "$BOOT_NEW" 6 0 0 false none
  zline "2026-07-10 10:15:00" "$BOOT_NEW" 6 0 0 false none
} > "$TMP/s7.json"
export ZOT_FIX_MAIN="$TMP/s7.json"
assert_case "S7 isolated single restart 5,5,6,6" 0 GREEN

# --- Scenario 7b: single LARGE jump (huge max-min, but climb run < CLIMB_N) → GREEN --------
# 5,5,200 → longest strictly-increasing consecutive run is 2 (5->200), below CLIMB_N=3, BUT
# max-min=195. This is the fixture that DISTINGUISHES the consecutive-climb model from a
# `max-min>tol` model: the sibling soak probe's `max-min<=tol` algorithm would FIRE here, the
# alarm's consecutive-climb model stays GREEN. Without this case a max-min refactor ships uncaught.
reset_fix
{
  zline "2026-07-10 11:00:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 11:05:00" "$BOOT_NEW" 5 0 0 false none
  zline "2026-07-10 11:10:00" "$BOOT_NEW" 200 0 0 false none
} > "$TMP/s7b.json"
export ZOT_FIX_MAIN="$TMP/s7b.json"
assert_case "S7b single large jump 5,5,200 (max-min high, climb<N)" 0 GREEN

# --- Scenario 8: all-'-1' sentinel restarts, no 137/oom → TRANSIENT (no false PASS/FIRE) --
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" -1 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" -1 0 0 false none
} > "$TMP/s8.json"
export ZOT_FIX_MAIN="$TMP/s8.json"
assert_case "S8 all -1 sentinel restarts" 2 TRANSIENT

# --- Scenario 9: empty window + control empty → TRANSIENT(2) (never a recurrence page) ----
reset_fix
export ZOT_FIX_MAIN="" ZOT_FIX_CONTROL=""   # both empty; control_rc 0
assert_case "S9 empty window + empty control" 2 TRANSIENT

# --- Scenario 9b: main query FAILS (rc!=0) → TRANSIENT ------------------------------------
reset_fix
export ZOT_FIX_MAIN="" ZOT_FIX_MAIN_RC=3    # betterstack-query creds-unset exit
assert_case "S9b main query rc=3 (creds unset)" 2 TRANSIENT

# --- Scenario 10: crafted zot_last_err="...exit_code=137..." on clean newest boot → GREEN -
# Spoof-resistance: the 137 lives ONLY in the free-text tail, which is stripped before parse.
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" 0 0 0 false "boom exit_code=137 oom_kills_5m=9 boot_id=deadbeef crash"
  zline "2026-07-10 10:05:00" "$BOOT_NEW" 0 0 0 false "boom exit_code=137 oom_kills_5m=9 crash"
} > "$TMP/s10.json"
export ZOT_FIX_MAIN="$TMP/s10.json"
assert_case "S10 crafted zot_last_err spoof (137 in tail only)" 0 GREEN

# --- Scenario 11: control present + 24h had rows + 3h empty → PRODUCER-SILENT(3) ----------
reset_fix
export ZOT_FIX_MAIN=""                       # 3h SOLEUR window empty
printf '{"dt":"2026-07-10 09:59:00","raw":"some unrelated app log row"}\n' > "$TMP/ctl.json"
export ZOT_FIX_CONTROL="$TMP/ctl.json"       # BS reachable (control returns a row)
{ zline "2026-07-09 20:00:00" "$BOOT_NEW" 5 0 0 false none; } > "$TMP/look.json"
export ZOT_FIX_LOOKBACK="$TMP/look.json"     # reporter WAS alive in the last 24h
assert_case "S11 producer-silent (24h had rows, 3h empty)" 3 PRODUCER_SILENT

# --- Scenario 12: fresh host (no rows in 24h) + 3h empty → TRANSIENT (NOT producer-silent) -
reset_fix
export ZOT_FIX_MAIN=""                       # 3h empty
export ZOT_FIX_CONTROL="$TMP/ctl.json"       # BS reachable
export ZOT_FIX_LOOKBACK=""                   # 24h ALSO empty → never-installed host
assert_case "S12 fresh host (24h empty, 3h empty)" 2 TRANSIENT

# =========================================================================================
# Private-NIC stream (#6415). The NIC verdict is INDEPENDENT of the exit code — see the
# checker's EXIT CONTRACT header for why it is not folded in (a new exit 4 would be mapped to
# a Sentry 'error' by the workflow, reporting a fire as a probe fault).
# =========================================================================================

# --- N1: newest boot healthy → NIC GREEN --------------------------------------------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{
  nline "2026-07-10 10:00:00" "$BOOT_NEW" true already 0 1 0 99999 "enp7s0:10.0.1.30/32"
  nline "2026-07-10 10:05:00" "$BOOT_NEW" true already 0 1 0 99999 "enp7s0:10.0.1.30/32"
} > "$TMP/n1.json"
export NIC_FIX_MAIN="$TMP/n1.json"
assert_nic_case "N1 nic_ok=true converged_by=already reboot_count=0" GREEN

# --- N2: nic_ok=false, imds unreachable → FIRE, decoded as H1 -----------------------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false none 7 0 0 99999 "eth0:203.0.113.10/32"; } > "$TMP/n2.json"
export NIC_FIX_MAIN="$TMP/n2.json"
assert_nic_case           "N2 nic_ok=false imds_rc=7" FIRE
assert_nic_cause_contains "N2 decoded as H1 (metadata service unreachable)" "H1"

# --- N3: nic_ok=false, imds reachable but zero nets → FIRE, decoded as H2 ------------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false none 0 0 0 99999 "eth0:203.0.113.10/32"; } > "$TMP/n3.json"
export NIC_FIX_MAIN="$TMP/n3.json"
assert_nic_case           "N3 nic_ok=false imds_rc=0 imds_nets=0" FIRE
assert_nic_cause_contains "N3 decoded as H2 (the additive online-attach race)" "H2"

# --- N4: attach landed but guest never configured it → FIRE, decoded as the third mode -----
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false none 0 1 2 99999 "eth0:203.0.113.10/32"; } > "$TMP/n4.json"
export NIC_FIX_MAIN="$TMP/n4.json"
assert_nic_case           "N4 nic_ok=false imds_nets=1 reboot_count=2 (budget spent)" FIRE
assert_nic_cause_contains "N4 decoded as the third mode (attach landed, guest did not configure)" "third mode"

# --- N5: successful self-heal → ADVISORY, NOT GREEN and NOT FIRE (the lost ceiling) --------
# This is the case the terminal branch structurally CANNOT see: a self-heal emits nic_ok=true.
# Without the advisory the race self-heals silently forever and is never reported.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" true already 0 1 1 99999 "enp7s0:10.0.1.30/32"; } > "$TMP/n5.json"
export NIC_FIX_MAIN="$TMP/n5.json"
assert_nic_case           "N5 self-healed (nic_ok=true, reboot_count=1) → advisory not green" ADVISORY
assert_nic_cause_contains "N5 advisory confirms H2 empirically" "H2 confirmed"

# --- N6 (AC7 REGRESSION): NIC guard silent WHILE SOLEUR_ZOT_DISK still flows → SILENT ------
# The zot PRODUCER_SILENT branch is computed ONLY when the zot window is empty. Here it is NOT
# empty (the disk heartbeat is alive), so that branch never evaluates. A NIC absence check that
# leaned on it would read GREEN — the exact blind spot #6415 exists to kill, one layer up.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"      # disk heartbeat ALIVE
printf '{"dt":"2026-07-10 09:59:00","raw":"some unrelated app log row"}\n' > "$TMP/ctl2.json"
export ZOT_FIX_CONTROL="$TMP/ctl2.json"          # Better Stack reachable
export NIC_FIX_MAIN=""                           # NIC window EMPTY
{ nline "2026-07-09 20:00:00" "$BOOT_NEW" true already 0 1 0 99999 none; } > "$TMP/n6look.json"
export NIC_FIX_LOOKBACK="$TMP/n6look.json"       # guard WAS alive in the last 24h
assert_nic_case "N6 NIC silent while SOLEUR_ZOT_DISK flows (AC7 regression)" SILENT

# --- N7 (AC8 REGRESSION): a zot early-exit must NOT skip the NIC check ---------------------
# All-'-1' zot sentinels → the zero-evidence leg → exit 2, which terminates BEFORE anything
# appended. The NIC verdict must still be present and correct, and the exit code must stay
# within the {0,1,2,3} contract (no exit 4 — the workflow maps anything else to a Sentry error).
reset_fix
{
  zline "2026-07-10 10:00:00" "$BOOT_NEW" -1 0 0 false none
  zline "2026-07-10 10:05:00" "$BOOT_NEW" -1 0 0 false none
} > "$TMP/n7zot.json"
export ZOT_FIX_MAIN="$TMP/n7zot.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false none 0 1 0 99999 "eth0:203.0.113.10/32"; } > "$TMP/n7.json"
export NIC_FIX_MAIN="$TMP/n7.json"
assert_case     "N7 zot zero-evidence still exits 2 (contract unchanged, no exit 4)" 2 TRANSIENT
assert_nic_case "N7 NIC still evaluated despite the zot early-exit (AC8 regression)" FIRE

# --- N8: newest-boot scoping — an old failed boot must not page after a healthy replace ----
# The window is 3h; an any-in-window read would fire for up to 3h after every recovery.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{
  nline "2026-07-10 09:00:00" "$BOOT_OLD" false none 0 0 0 99999 "eth0:203.0.113.10/32"
  nline "2026-07-10 10:00:00" "$BOOT_NEW" true already 0 1 0 99999 "enp7s0:10.0.1.30/32"
} > "$TMP/n8.json"
export NIC_FIX_MAIN="$TMP/n8.json"
assert_nic_case "N8 stale old-boot nic_ok=false, newest boot healthy" GREEN

# --- N9: spoof-resistance — crafted zot_last_err cannot forge a NIC verdict ----------------
# The nic_ok=false lives ONLY in the free-text tail, which zot_trusted_region strips before any
# key=value parse. This is why the field had to be named zot_last_err (the lib strips that
# LITERAL): a `last_err=` would sail straight through and this fixture would FIRE.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{
  nline "2026-07-10 10:00:00" "$BOOT_NEW" true already 0 1 0 99999 "boom nic_ok=false converged_by=none imds_nets=0 crash"
  nline "2026-07-10 10:05:00" "$BOOT_NEW" true already 0 1 0 99999 "boom nic_ok=false converged_by=none imds_nets=0 crash"
} > "$TMP/n9.json"
export NIC_FIX_MAIN="$TMP/n9.json"
assert_nic_case "N9 crafted zot_last_err spoof (nic_ok=false in tail only)" GREEN

# --- N10: NIC query probe fault → TRANSIENT, never a page ---------------------------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
export NIC_FIX_MAIN="" NIC_FIX_MAIN_RC=3
assert_nic_case "N10 NIC query rc=3 (creds unset) → transient, not a page" TRANSIENT

# --- N11: SUPERSEDED by N18/N19 -----------------------------------------------------------
# This case originally asserted "never emitted → TRANSIENT (fresh host, don't page)". That is
# the defect, not the contract: a guard that never emits is INVISIBLE FOREVER under that reading
# — no issue, and Sentry green because it keys only on the zot exit code. And "never emitted" is
# the ROLLOUT path (registry-host-replace births a fresh host). The sibling cross-check now
# discriminates the two real cases, covered by N18 (sibling alive ⇒ the guard is broken ⇒ SILENT)
# and N19 (sibling dark ⇒ the whole host is dark ⇒ TRANSIENT). Kept as a comment so the reversal
# is legible rather than looking like a deleted test.

# --- N12: store unmounted => FIRE, even though every NIC field is green --------------------
# zot bind-mounts an EMPTY root-disk dir and 404s the whole fleet while nic_ok=true. Before this
# branch existed the field was emitted with NO reader and this state read GREEN — the exact
# "emit with no reader is decoration" sin the plan criticises v1 for.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" true already 0 1 0 99999 "enp7s0:10.0.1.30/32" false; } > "$TMP/n12.json"
export NIC_FIX_MAIN="$TMP/n12.json"
assert_nic_case           "N12 zot_store_mounted=false with nic_ok=true → fire, not green" FIRE
assert_nic_cause_contains "N12 cause names the empty-dir 404, not a NIC fault" "404"

# --- N13: probe-fault => never decoded as a NIC absence -----------------------------------
# `ip` unresolvable (the cron-PATH class). nic_ok=false here means UNKNOWN, not absent.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false probe-fault 0 1 0 99999 "none"; } > "$TMP/n13.json"
export NIC_FIX_MAIN="$TMP/n13.json"
assert_nic_case           "N13 converged_by=probe-fault → fire" FIRE
assert_nic_cause_contains "N13 decoded as a probe fault, NOT H1/H2" "probe fault"

# --- N14: counter-unwritable => decoded as a broken root fs, not a NIC fault ---------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:05:00" "$BOOT_NEW" false counter-unwritable 0 1 0 99999 "none"; } > "$TMP/n14.json"
export NIC_FIX_MAIN="$TMP/n14.json"
assert_nic_case           "N14 converged_by=counter-unwritable → fire" FIRE
assert_nic_cause_contains "N14 cause names the unwritable budget" "unwritable"

# --- N15 (REGRESSION): self-heal WITHOUT a reboot, same boot → ADVISORY, not FIRE ----------
# The guard's MOST LIKELY success path: the boot invocation emits nic_ok=false at ~100s (attach
# not landed, uptime gate shut), the 5-min cron then emits nic_ok=true under the SAME boot_id.
# An any-row `grep -q nic_ok=false` pages "no private NIC — terminal" on a host that healed
# itself, with a cause computed from the HEALED row. That is paging on the happy path.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{
  nline "2026-07-10 10:00:00" "$BOOT_NEW" false none 0 0 0 100 "eth0:203.0.113.10/32"
  nline "2026-07-10 10:05:00" "$BOOT_NEW" true already 0 1 0 400 "enp7s0:10.0.1.30/32"
} > "$TMP/n15.json"
export NIC_FIX_MAIN="$TMP/n15.json"
assert_nic_case           "N15 nic_ok false→true within one boot → advisory, not fire" ADVISORY
assert_nic_cause_contains "N15 advisory says it healed with NO reboot" "without a reboot"

# --- N16: fresh boot, uptime gate not open yet → decode must not say 'terminal' ------------
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
{ nline "2026-07-10 10:01:00" "$BOOT_NEW" false none 0 1 0 120 "eth0:203.0.113.10/32"; } > "$TMP/n16.json"
export NIC_FIX_MAIN="$TMP/n16.json"
assert_nic_case           "N16 attach landed, uptime_s<600 → fire (the NIC IS down)" FIRE
assert_nic_cause_contains "N16 cause says NOT terminal — the uptime gate has not opened" "NOT terminal"

# --- N17 (REGRESSION): a zot row whose free-text tail carries the NIC marker ---------------
# --grep is an UNANCHORED `raw LIKE '%SOLEUR_PRIVATE_NIC%'` over a source EVERY host multiplexes
# into, and SOLEUR_ZOT_DISK's zot_last_err carries `docker logs` output — so a pull of
# /v2/SOLEUR_PRIVATE_NIC/manifests/x puts this marker into a zot row. Without the membership
# re-assert that row survives the strip, carries no nic_ok, and the function falls through to
# GREEN — fabricating a verdict from ZERO real rows, exactly when the guard is dark, and then
# AUTO-CLOSING a live issue.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"
export ZOT_FIX_CONTROL="$TMP/ctl2.json"
{ zline "2026-07-10 10:05:00" "$BOOT_NEW" 5 0 0 false "GET /v2/SOLEUR_PRIVATE_NIC/manifests/x 404"; } > "$TMP/n17.json"
export NIC_FIX_MAIN="$TMP/n17.json"          # the ONLY 'NIC' row is a contaminated zot row
{ nline "2026-07-09 20:00:00" "$BOOT_NEW" true already 0 1 0 99999 none; } > "$TMP/n17look.json"
export NIC_FIX_LOOKBACK="$TMP/n17look.json"  # the guard WAS alive in the last 24h
assert_nic_case "N17 contaminated zot row is not a NIC row → silent, not a fabricated green" SILENT

# --- N18 (REGRESSION): never-emitted while the SIBLING producer is alive → SILENT ----------
# The rollout path: registry-host-replace births a FRESH host. If the guard never emits (bad
# render, doppler scope miss, cron not installed) the 24h lookback is empty too, so without the
# sibling cross-check this reads TRANSIENT forever: no issue, and Sentry stays green because it
# keys only on the zot exit code. #6400's own shape, on the box built to end it.
reset_fix
export ZOT_FIX_MAIN="$TMP/zot-healthy.json"   # sibling ALIVE: host up, cron runs, token resolves
export ZOT_FIX_CONTROL="$TMP/ctl2.json"
export NIC_FIX_MAIN="" NIC_FIX_LOOKBACK=""    # NIC guard has NEVER emitted
assert_nic_case           "N18 never-emitted while the sibling flows → silent, not transient" SILENT
assert_nic_cause_contains "N18 cause names the not-deployed / install-failed reading" "never deployed"

# --- N19: the whole host is dark → TRANSIENT (the zot legs own that verdict) ---------------
reset_fix
export ZOT_FIX_MAIN="" ZOT_FIX_CONTROL="$TMP/ctl2.json"
export NIC_FIX_MAIN="" NIC_FIX_LOOKBACK=""
assert_nic_case "N19 both producers silent → transient (not a NIC-specific page)" TRANSIENT

# --- Minimum-cardinality guard -----------------------------------------------------------
EXPECTED_MIN=45
echo "----"
printf 'cases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
if [[ "$CASES" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL - cardinality guard: only $CASES cases ran (expected >= $EXPECTED_MIN) — a case was silently skipped" >&2
  exit 1
fi
if [[ "$FAIL" -ne 0 ]]; then
  echo "RESULT: FAIL ($FAIL failing case(s))" >&2
  exit 1
fi
echo "RESULT: PASS ($PASS/$CASES assertions)"
