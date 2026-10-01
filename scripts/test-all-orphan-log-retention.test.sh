#!/usr/bin/env bash
# scripts/test-all-orphan-log-retention.test.sh — Guard 2 + Guard 3 for
# #8993 (orphaned run holds the repo flock forever) and #8940 (suite output
# lost when the scratch root is cleaned on run exit).
#
# HOW IT TESTS. Sandbox copies of the runner, spliced the same way as
# test-all-killed-classification.test.sh: fixture run_suite calls replace the
# registration region between the acquire statement and the epilogue call
# (both uniqueness-asserted anchors), with tc_acquire and tc_preamble
# neutered. The behaviours under test — a watchdog subshell polling a real
# parent, a tee'd suite log retained durably — are exercised against LIVE
# processes and REAL signals, not mocks: #8993's fix is wrong if the poll
# does not observe an actual reparenting event.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
PASS=0; FAIL=0

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-all.sh orphan watchdog (#8993) + failure-output retention (#8940) ==="

# ---------------------------------------------------------------------------
# Source-level pins (mutation anchors). Every row states what a mutant would
# have to remove and stay green against.
# ---------------------------------------------------------------------------

# The run-path watchdog arm exists exactly once, sits AFTER flag parsing and
# BEFORE the lock acquisition, and arms only on the non-enumerate path.
arm_count=$(grep -c '_RUN_WD_PID=$!' "$TARGET" || true)
if [[ "$arm_count" == "1" ]]; then
  pass "watchdog armed exactly once (_RUN_WD_PID=\$! occurs once)"
else
  fail "expected exactly one run-path watchdog arm, found $arm_count"
fi

# Ordering: the arm precedes `tc_acquire "test-all"` — an orphan QUEUED on the
# lock must already be watched (the incident's queue-holding shape).
arm_line=$(grep -n '_RUN_WD_PID=$!' "$TARGET" | cut -d: -f1)
acq_line=$(grep -n 'tc_acquire "test-all"' "$TARGET" | cut -d: -f1)
if [[ -n "$arm_line" && -n "$acq_line" && "$arm_line" -lt "$acq_line" ]]; then
  pass "watchdog arm precedes the lock acquisition"
else
  fail "watchdog arm must precede the lock acquisition (arm=${arm_line:-none} acq=${acq_line:-none})"
fi

# Kill ordering inside the watchdog block: the in-flight suite children are
# signalled BEFORE the runner itself. Extracted by anchored range so a rename
# of either kill line fails loudly here.
wd_block="$(sed -n '/_RUN_WD_TOP_PID=\$\$/,/^fi$/p' "$TARGET")"
kid_kill_line="$(printf '%s\n' "$wd_block" | grep -n 'kill -TERM "$_wd_kid"' | head -1 | cut -d: -f1)"
top_kill_line="$(printf '%s\n' "$wd_block" | grep -n 'kill -TERM "$_RUN_WD_TOP_PID"' | head -1 | cut -d: -f1)"
if [[ -n "$kid_kill_line" && -n "$top_kill_line" && "$kid_kill_line" -lt "$top_kill_line" ]]; then
  pass "watchdog kills in-flight suite children before the runner (TERM order)"
else
  fail "expected child-TERM loop before runner-TERM inside the watchdog block (kid=${kid_kill_line:-none} top=${top_kill_line:-none})"
fi

# The poll loop actually polls: a `sleep` inside a `while` in the watchdog
# subshell is what makes liveness re-checked rather than evaluated once.
if printf '%s\n' "$wd_block" | grep -q 'while :; do' \
   && printf '%s\n' "$wd_block" | grep -q 'sleep "$_RUN_WD_POLL_S"'; then
  pass "watchdog liveness loop polls on _RUN_WD_POLL_S"
else
  fail "watchdog block must contain a polling loop (while + sleep _RUN_WD_POLL_S)"
fi

# The reparented/zombie-parent arm: the poll checks `ps -o stat=` for Z and
# re-reads the parent's lstart (pid-reuse). Removing either leaves a live
# corpse or a recycled pid reading as a live parent.
if printf '%s\n' "$wd_block" | grep -q 'stat= -p "\$_RUN_WD_PARENT_PID"' \
   && printf '%s\n' "$wd_block" | grep -q '_RUN_WD_PARENT_LSTART'; then
  pass "watchdog guards zombie-parent AND pid-reuse (stat check + lstart compare)"
else
  fail "watchdog must check zombie stat and parent lstart identity"
fi

# Disarm is spliced into the single EXIT trap (one trap per script, ADR-129).
if grep -q 'trap .*_run_wd_disarm.* EXIT' "$TARGET"; then
  pass "run watchdog disarm is spliced into the EXIT trap"
else
  fail "expected _run_wd_disarm inside the EXIT trap line"
fi

# Retention ordering in the trap: _run_log_retain MUST precede
# _soleur_scratch_cleanup — the source file lives inside the scratch root the
# cleanup deletes.
trap_line="$(grep -n '^trap .*EXIT$' "$TARGET" | head -1 | cut -d' ' -f2-)"
retain_pos="$(printf '%s' "$trap_line" | grep -bo '_run_log_retain' | head -1 | cut -d: -f1)"
scratch_pos="$(printf '%s' "$trap_line" | grep -bo '_soleur_scratch_cleanup' | head -1 | cut -d: -f1)"
if [[ -n "$retain_pos" && -n "$scratch_pos" && "$retain_pos" -lt "$scratch_pos" ]]; then
  pass "EXIT trap retains the in-flight log BEFORE scratch cleanup deletes it"
else
  fail "expected _run_log_retain before _soleur_scratch_cleanup in the EXIT trap (retain=${retain_pos:-none} scratch=${scratch_pos:-none})"
fi

# ---------------------------------------------------------------------------
# Sandbox builder — same splice discipline as killed-classification: fixture
# registrations replace the region between the acquire statement and the
# epilogue call; acquire + preamble are neutered. Plus scratch-root.sh — the
# tee'd suite logs live under the session root, so the lib must resolve.
# ---------------------------------------------------------------------------
FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"
printf '#!/usr/bin/env bash\nexit 0\n'                              > "$FIXTURES/ok.sh"
printf '#!/usr/bin/env bash\necho MARKER-FAIL-FX\nexit 1\n'         > "$FIXTURES/failfx.sh"
printf '#!/usr/bin/env bash\necho MARKER-KILLED-FX\nkill -TERM $$\n' > "$FIXTURES/killedfx.sh"
# The sleep duration is a UNIQUE-per-run token ($$-suffixed) so
# fixture-process sweeps can match it without touching an unrelated
# `sleep 60` on a shared box OR a parallel run of this same test in a
# sibling worktree — the bare `sleep <secs>` cmdline carries no fixture
# path, so the token is the only discriminator.
SLEEPTOK="617.$$"
printf '#!/usr/bin/env bash\necho MARKER-SLEEP-FX\nsleep %s\n' "$SLEEPTOK" > "$FIXTURES/sleepfx.sh"

build_sandbox() {  # build_sandbox <out-dir> <arm>
  local dir="$1" arm="$2"
  mkdir -p "$dir/lib"
  cp "$TARGET" "$dir/test-all.sh" || return 1
  # The boundary lib is an EXPLICIT cp — the repo-write-boundary census
  # (row 28) enumerates runner-relocating suites by this literal shape and a
  # loop-carried copy reads as an undeclared sandbox.
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$dir/lib/" || return 1
  for lib in test-relevance-paths.sh scratch-root.sh test-contention.sh; do
    [[ -f "$REPO_ROOT/scripts/lib/$lib" ]] && cp "$REPO_ROOT/scripts/lib/$lib" "$dir/lib/" || true
  done
  python3 - "$dir/test-all.sh" "$arm" "$FIXTURES" <<'PY'
import sys
path, arm, fixtures = sys.argv[1:4]
s = open(path).read()

start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1, "start anchor not unique"
assert s.count(end_anchor) == 1, "end anchor not unique"
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)

calls = {
    "clean":  [("okfx", "ok.sh")],
    "fail":   [("failfx", "failfx.sh")],
    "killed": [("killedfx", "killedfx.sh")],
    "sleep":  [("sleepfx", "sleepfx.sh")],
}[arm]
body = "\n" + "".join(
    f'run_suite "{label}" bash "{fixtures}/{script}"\n' for label, script in calls
)
s = s[:i] + body + s[j:]
s = s.replace('tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 1)
import re
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
open(path, "w").write(s)
PY
}

echo ""
echo "--- Part A: #8940 durable failure-output retention ---"

DURABLE="$TMP/durable-a"
SBX_A="$TMP/sbx-a"
build_sandbox "$SBX_A" fail || { echo "FATAL: sandbox build failed"; exit 2; }
out="$TMP/out-a.log"
rc=0
# env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE: under an agent-run gate the refusal guard would
# bounce the sandbox run to exit 4 before any suite executes.
env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_LOG_DIR="$DURABLE" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_A/test-all.sh" >"$out" 2>&1 || rc=$?

if [[ "$rc" != "0" ]]; then
  pass "failing-suite run exits non-zero (rc=$rc)"
else
  fail "failing-suite run should exit non-zero, got 0"
fi

# The [FAIL] summary line carries the durable path; the file exists OUTSIDE
# the scratch root and contains the suite's own marker.
fail_line="$(grep -E '^\[FAIL\] failfx' "$out" | head -1)"
if printf '%s' "$fail_line" | grep -q 'log='; then
  pass "[FAIL] line prints a durable log= path"
else
  fail "[FAIL] line missing log= path — got: ${fail_line:-<no FAIL line>}"
fi
durable_path="$(printf '%s' "$fail_line" | grep -o 'log=[^ ]*' | head -1 | cut -d= -f2-)"
if [[ -n "$durable_path" && -f "$durable_path" ]]; then
  pass "durable artifact exists at the printed path"
else
  fail "durable artifact missing at printed path '${durable_path:-<none>}'"
fi
if [[ -n "$durable_path" ]] && grep -q 'MARKER-FAIL-FX' "$durable_path" 2>/dev/null; then
  pass "durable artifact contains the suite's own marker"
else
  fail "durable artifact lacks MARKER-FAIL-FX"
fi
# The durable path is outside the scratch root — survives cleanup.
if [[ -n "$durable_path" && "$durable_path" == "$DURABLE/"* ]]; then
  pass "durable path resolves under SOLEUR_TEST_ALL_LOG_DIR (outside scratch root)"
else
  fail "durable path '${durable_path:-<none>}' not under $DURABLE"
fi

# Mid-suite termination: TERM the runner while a suite sleeps; the EXIT-trap
# arm must retain the in-flight tee'd log.
DURABLE_B="$TMP/durable-b"
SBX_B="$TMP/sbx-b"
build_sandbox "$SBX_B" sleep || { echo "FATAL: sandbox build failed"; exit 2; }
out="$TMP/out-b.log"
env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_LOG_DIR="$DURABLE_B" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_B/test-all.sh" >"$out" 2>&1 &
RUNNER_PID=$!
deadline=$(( SECONDS + 15 ))
while ! grep -q 'MARKER-SLEEP-FX' "$out" 2>/dev/null && (( SECONDS < deadline )); do
  sleep 0.2
done
kill -TERM "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true
if grep -q 'mid-termination retention:' "$out"; then
  pass "mid-suite termination emits the retention line"
else
  fail "no '[suite-log] mid-termination retention' line on TERM'd run"
fi
retained="$(ls "$DURABLE_B"/*/sleepfx.log 2>/dev/null | head -1)"
if [[ -n "$retained" ]] && grep -q 'MARKER-SLEEP-FX' "$retained"; then
  pass "mid-suite termination retains a durable log containing the marker"
else
  fail "mid-suite termination produced no durable sleepfx.log with the marker"
fi
# A TERM'd runner exits without reaping its in-flight suite children (they
# reparent) — that is pre-existing behaviour the #8993 watchdog addresses only
# on the parent-death path. Clean the fixture's leftovers HERE so the
# Part-B sweep below cannot match a process this arm left behind.
for leftover in $(pgrep -f "$FIXTURES/sleepfx\.sh" 2>/dev/null); do
  kill -KILL "$leftover" 2>/dev/null || true
done
pkill -f "sleep $SLEEPTOK" 2>/dev/null || true

# Clean run: no durable artifacts.
DURABLE_C="$TMP/durable-c"
SBX_C="$TMP/sbx-c"
build_sandbox "$SBX_C" clean || { echo "FATAL: sandbox build failed"; exit 2; }
out="$TMP/out-c.log"
rc=0
env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_LOG_DIR="$DURABLE_C" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_C/test-all.sh" >"$out" 2>&1 || rc=$?
if [[ "$rc" == "0" ]]; then
  pass "clean run exits 0"
else
  fail "clean run should exit 0, got $rc"
fi
if [[ -n "$(find "$DURABLE_C" -type f 2>/dev/null | head -1)" ]]; then
  fail "clean run left durable artifacts under $DURABLE_C"
else
  pass "clean run creates no durable artifacts"
fi

echo ""
echo "--- Part B: #8993 orphan watchdog ---"

# B1: a run whose PARENT dies mid-suite is terminated by the watchdog —
# runner AND in-flight suite children gone within ~2 polls + the TERM grace.
DURABLE_D="$TMP/durable-d"
SBX_D="$TMP/sbx-d"
build_sandbox "$SBX_D" sleep || { echo "FATAL: sandbox build failed"; exit 2; }
out="$TMP/out-d.log"
# A wrapping subshell is the runner's killable parent. The trailing `wait`
# is LOAD-BEARING: a `( cmd )` subshell whose body is a single command is
# exec-optimised by bash — the subshell process would BECOME the runner, so
# killing "the parent" would TERM the runner directly and the watchdog's
# parent-death path would never be exercised (measured: the runner died and
# the watchdog never printed, because it had been disarmed by the runner's
# own EXIT trap).
( env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_LOG_DIR="$DURABLE_D" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_D/test-all.sh" >"$out" 2>&1; wait ) &
WRAP_PID=$!
deadline=$(( SECONDS + 15 ))
while ! grep -q 'MARKER-SLEEP-FX' "$out" 2>/dev/null && (( SECONDS < deadline )); do
  sleep 0.2
done
# Resolve the runner pid (the subshell's only child) and its suite children.
RUNNER_PID="$(pgrep -P "$WRAP_PID" 2>/dev/null | head -1)"
if [[ -z "$RUNNER_PID" ]]; then
  fail "could not resolve the sandbox runner pid under the wrapper"
else
  SUITE_CHILD="$(pgrep -P "$RUNNER_PID" 2>/dev/null | wc -l | tr -d ' ')"
  kill -TERM "$WRAP_PID" 2>/dev/null
  # Parent dead → watchdog fires within ~1 poll + TERM + grace(~5s) + KILL.
  deadline=$(( SECONDS + 12 ))
  while kill -0 "$RUNNER_PID" 2>/dev/null && (( SECONDS < deadline )); do
    sleep 0.2
  done
  if kill -0 "$RUNNER_PID" 2>/dev/null; then
    fail "orphaned runner survived parent death (still alive after ${deadline}s window)"
  else
    pass "orphaned runner is terminated after parent death"
  fi
  # Children were killed too — no suite/tee survives reparented.
  leftover="$(pgrep -f "$FIXTURES/sleepfx.sh" 2>/dev/null | head -1)"
  if [[ -n "$leftover" ]]; then
    fail "in-flight suite child survived the orphan reap (pid $leftover)"
    kill -KILL "$leftover" 2>/dev/null || true
  else
    pass "in-flight suite children are terminated with the orphaned run"
  fi
  if grep -q '#8993' "$out"; then
    pass "orphan reap is announced on stderr"
  else
    fail "no '#8993' orphan line in runner output"
  fi
fi
# The watchdog sweeps TRANSITIVE descendants (the _wd_descendants awk
# walk): the suite's own `sleep $SLEEPTOK` grandchild should already be
# reaped — sweep anyway, belt-and-braces on a shared box.
pkill -f "sleep $SLEEPTOK" 2>/dev/null || true

# B2: a live parent is never reaped — the run completes normally.
SBX_E="$TMP/sbx-e"
build_sandbox "$SBX_E" clean || { echo "FATAL: sandbox build failed"; exit 2; }
out="$TMP/out-e.log"
rc=0
env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable-e" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_E/test-all.sh" >"$out" 2>&1 || rc=$?
if [[ "$rc" == "0" ]] && ! grep -q 'orphaned' "$out"; then
  pass "live-parent run completes normally — watchdog never fires"
else
  fail "live-parent run broke (rc=$rc) or emitted an orphan line"
fi

# B3: the documented opt-out skips the arm and SAYS SO — a silent skip would
# make "fired" and "never armed" indistinguishable.
out="$TMP/out-e2.log"
rc=0
env -u SOLEUR_SUBAGENT -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable-e2" SOLEUR_TEST_ALL_WD_POLL_S=1 bash "$SBX_E/test-all.sh" >"$out" 2>&1 || rc=$?
if grep -q 'SOLEUR_TEST_ALL_ORPHAN_WATCHDOG_DISABLED' "$out"; then
  pass "opt-out emits the named DISABLED banner"
else
  fail "SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 produced no opt-out banner"
fi
# ...and the watchdog subshell is disarmed on exit — no stray poll survives.
stray="$(pgrep -f "$SBX_E/test-all.sh" 2>/dev/null | head -1)"
if [[ -z "$stray" ]]; then
  pass "watchdog disarms on normal exit (no stray sandbox processes)"
else
  fail "a sandbox process outlived the run (pid $stray)"
  kill -KILL "$stray" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Durable-log age GC (#9117). `_gc_durable_logs` is defined beside the other
# durable-log state (outside the spliced window) and CALLED after tc_acquire
# (inside it), so sandbox copies never run it against a real /var/tmp. The arms
# below extract the function by anchored range and drive it directly against a
# fixture namespace — nothing outside $TMP is ever a candidate.
# ---------------------------------------------------------------------------
echo "--- durable-log GC (#9117) ---"
gc_fn="$(sed -n '/^_gc_durable_logs() {/,/^}/p' "$TARGET")"
if [[ -n "$gc_fn" ]]; then
  pass "_gc_durable_logs is defined in test-all.sh"
else
  fail "_gc_durable_logs is missing from test-all.sh (no age reap for the durable log namespace)"
fi

GCNS="$TMP/gc/soleur-test-all-logs"; GCOTHER="$TMP/gc/other-logs"
mkdir -p "$GCNS" "$GCOTHER" "$TMP/gc/victim"; : > "$TMP/gc/victim/keep"
mk_gc_dir() { # <ns> <name> <age-days>
  mkdir -p "$1/$2"; : > "$1/$2/suite.log"
  touch -d "-$3 days" "$1/$2/suite.log" "$1/$2"
}
mk_gc_dir "$GCNS" "repo-111-1700000000" 20    # old, shaped like a run dir  -> reaped
mk_gc_dir "$GCNS" "repo-222-1700000001" 0     # fresh                       -> kept
mk_gc_dir "$GCNS" "repo-333-1700000002" 13    # inside the 14-day window    -> kept
mk_gc_dir "$GCNS" "notarun"                  20   # old, wrong shape         -> kept
mk_gc_dir "$GCNS" "repo-444-17x"              20  # old, non-numeric epoch   -> kept
: > "$GCNS/stray-1-2"; touch -d '-20 days' "$GCNS/stray-1-2"                  # old FILE -> kept
ln -s "$TMP/gc/victim" "$GCNS/repo-555-1700000003"                            # symlink to a dir -> kept, target untouched
touch -h -d '-20 days' "$GCNS/repo-555-1700000003"
mk_gc_dir "$GCOTHER" "repo-666-1700000004" 20 # same shape, WRONG namespace  -> kept

gc_run() { bash -c "set -uo pipefail; $gc_fn; _gc_durable_logs \"\$1\" \"\$2\"" _ "$1" "$2"; }
if [[ -n "$gc_fn" ]]; then
  gc_rc=0; gc_run "$GCNS" 14 >/dev/null 2>&1 || gc_rc=$?
  [[ "$gc_rc" == "0" && ! -e "$GCNS/repo-111-1700000000" ]] \
    && pass "GC reaps a run dir untouched for more than 14 days" || fail "old run dir not reaped (rc=$gc_rc)"
  [[ -d "$GCNS/repo-222-1700000001" && -d "$GCNS/repo-333-1700000002" ]] \
    && pass "GC keeps fresh and 13-day-old run dirs (window honoured)" || fail "GC reaped a dir inside the window"
  [[ -d "$GCNS/notarun" && -d "$GCNS/repo-444-17x" && -f "$GCNS/stray-1-2" ]] \
    && pass "GC keeps old entries that are not <label>-<pid>-<epoch> directories" || fail "GC reaped an entry outside the run-dir shape"
  [[ -L "$GCNS/repo-555-1700000003" && -f "$TMP/gc/victim/keep" ]] \
    && pass "GC never follows or removes a symlink (target untouched)" || fail "GC touched a symlinked entry"
  gc_run "$GCOTHER" 14 >/dev/null 2>&1 || true
  [[ -d "$GCOTHER/repo-666-1700000004" ]] \
    && pass "GC refuses any namespace not named soleur-test-all-logs" || fail "GC reaped outside the dedicated namespace"
  mk_gc_dir "$GCNS" "repo-777-1700000005" 20   # old + well-shaped: only an invalid window protects it
  gc_run "$GCNS" "x14" >/dev/null 2>&1 || true
  gc_run "$GCNS" "0" >/dev/null 2>&1 || true
  [[ -d "$GCNS/repo-777-1700000005" ]] \
    && pass "GC with a non-numeric or zero window reaps nothing (fail closed)" || fail "GC reaped on an invalid window"
fi
gc_call_line="$(grep -n '_gc_durable_logs "' "$TARGET" | head -1 | cut -d: -f1)"
acq_line2="$(grep -n 'tc_acquire "test-all"' "$TARGET" | head -1 | cut -d: -f1)"
if [[ -n "$gc_call_line" && -n "$acq_line2" && "$gc_call_line" -gt "$acq_line2" ]] \
   && grep -F '_gc_durable_logs "' "$TARGET" | grep -qF '${SOLEUR_SCRATCH_BASE:-/var/tmp}/soleur-test-all-logs'; then
  pass "GC runs after the lock acquisition, on the default namespace only (never SOLEUR_TEST_ALL_LOG_DIR)"
else
  fail "GC call must follow tc_acquire and target the default soleur-test-all-logs namespace (call=${gc_call_line:-none} acq=${acq_line2:-none})"
fi

echo ""
echo "=== RESULT: $PASS passed, $FAIL failed ==="
[[ "$FAIL" == "0" ]]
