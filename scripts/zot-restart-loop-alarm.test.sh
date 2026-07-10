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
#   - contains "24h"            → the 24h producer-liveness lookback  → $ZOT_FIX_LOOKBACK / _RC
#   - contains "SOLEUR_ZOT_DISK" → the recent-window main query        → $ZOT_FIX_MAIN / _RC
#   - otherwise (bare --limit 1) → the control reachability probe      → $ZOT_FIX_CONTROL / _RC
STUB="$TMP/bq-stub.sh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
argv="$*"
if [[ "$argv" == *"24h"* ]]; then
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
}

# Optionally assert the decoded cause substring (2nd-order signal beyond the verdict).
assert_cause_contains() {
  local name="$1" needle="$2" out
  CASES=$((CASES + 1))
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || true
  if printf '%s\n' "$out" | grep -qiF "$needle"; then
    PASS=$((PASS + 1)); printf 'ok   - %s (cause ~ "%s")\n' "$name" "$needle"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL - %s: cause did not contain "%s"\n' "$name" "$needle"
    printf '%s\n' "$out" | sed 's/^/       /'
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

# --- Minimum-cardinality guard -----------------------------------------------------------
EXPECTED_MIN=15
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
