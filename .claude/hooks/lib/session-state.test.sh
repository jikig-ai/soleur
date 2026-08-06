#!/usr/bin/env bash
# Tests for .claude/hooks/lib/session-state.sh.
#
# T1-T8 per plan 2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md.
# Run via:  bash .claude/hooks/lib/session-state.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/session-state.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

ROOTS=()
cleanup() {
  for r in "${ROOTS[@]}"; do
    rm -rf "$r" 2>/dev/null || true
  done
}
trap cleanup EXIT

make_root() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/locks" "$dir/leases" "$dir/logs"
  echo "$dir"
}

# Isolate state dirs per-test by overriding before sourcing.
# session-state.sh consults SOLEUR_SESSION_STATE_ROOT for tests.
source_helper() {
  local root="$1"
  export SOLEUR_SESSION_STATE_ROOT="$root"
  # shellcheck source=/dev/null
  source "$HELPER"
}

# ------------------------------------------------------------------------
# T1: Three parallel acquire_lock invocations are mutually exclusive
# ------------------------------------------------------------------------
echo "T1: mutual exclusion under contention"
ROOT=$(make_root); ROOTS+=("$ROOT")
TS_FILE="$ROOT/timestamps"
: > "$TS_FILE"

worker() {
  bash -c "
    export SOLEUR_SESSION_STATE_ROOT='$ROOT'
    source '$HELPER'
    if acquire_lock t1 5; then
      printf '%s START\n' \"\$(date +%s%N)\" >> '$TS_FILE'
      sleep 0.2
      printf '%s END\n' \"\$(date +%s%N)\" >> '$TS_FILE'
      release_lock t1
    fi
  "
}

worker & worker & worker &
wait
# Each START must be followed by its END (no interleave); 3 START + 3 END.
starts=$(grep -c START "$TS_FILE" || true)
ends=$(grep -c END "$TS_FILE" || true)
lines=$(wc -l < "$TS_FILE")
ok=1
if [[ "$starts" -ne 3 || "$ends" -ne 3 ]]; then
  fail "T1: expected 3 START + 3 END, got starts=$starts ends=$ends"
  ok=0
fi
# Verify interleave invariant: in order, each START must be immediately followed by END.
awk '{print $2}' "$TS_FILE" | awk '
  /START/ { if (prev=="START") { exit 1 } prev="START"; next }
  /END/ { if (prev!="START") { exit 1 } prev="END"; next }
' || { fail "T1: START/END interleaved — mutual exclusion violated"; ok=0; }
[[ "$ok" == "1" ]] && pass "T1"

# ------------------------------------------------------------------------
# T2: acquire_lock returns 99 within timeout+1s when contended
# ------------------------------------------------------------------------
echo "T2: timeout returns 99"
ROOT=$(make_root); ROOTS+=("$ROOT")
HOLDER_OUT="$ROOT/holder.out"

# Background holder holds for 4s
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  source '$HELPER'
  acquire_lock t2 5
  sleep 4
  release_lock t2
" &
HOLDER_PID=$!
sleep 0.3  # let holder acquire

# Contender with 1s timeout
START_S=$(date +%s)
set +e
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  source '$HELPER'
  acquire_lock t2 1
  echo \$?
" > "$HOLDER_OUT"
set -e
END_S=$(date +%s)
rc=$(cat "$HOLDER_OUT" | tail -1)

elapsed=$((END_S - START_S))
if [[ "$rc" != "99" ]]; then
  fail "T2: expected rc=99 on timeout, got rc=$rc"
elif (( elapsed > 2 )); then
  fail "T2: contender took ${elapsed}s, expected <=2s"
else
  pass "T2"
fi
wait "$HOLDER_PID" 2>/dev/null || true

# ------------------------------------------------------------------------
# T3: Lease roundtrip
# ------------------------------------------------------------------------
echo "T3: lease acquire/release roundtrip"
ROOT=$(make_root); ROOTS+=("$ROOT")
(
  export SOLEUR_SESSION_STATE_ROOT="$ROOT"
  source "$HELPER"
  acquire_lease test-wt one-shot 240
)
LEASE_FILE="$ROOT/leases/test-wt.lease"
if [[ ! -f "$LEASE_FILE" ]]; then
  fail "T3: lease file not created at $LEASE_FILE"
elif ! grep -q '^pid=' "$LEASE_FILE" || ! grep -q '^skill=one-shot$' "$LEASE_FILE"; then
  fail "T3: lease file missing expected key=value pairs (contents: $(cat "$LEASE_FILE"))"
else
  # Release must remove only when same pid+hostname+started_at.
  # We acquired in a subshell so $$ differs. Test the same-pid path via single shell:
  (
    export SOLEUR_SESSION_STATE_ROOT="$ROOT"
    source "$HELPER"
    acquire_lease test-wt-2 work 240
    release_lease test-wt-2
  )
  if [[ -f "$ROOT/leases/test-wt-2.lease" ]]; then
    fail "T3: release_lease did not remove same-pid lease"
  else
    pass "T3"
  fi
fi

# ------------------------------------------------------------------------
# T4: is_lease_active returns 1 for dead PID
# ------------------------------------------------------------------------
echo "T4: dead-PID lease not active"
ROOT=$(make_root); ROOTS+=("$ROOT")

# Spawn a short-lived process, acquire lease using its PID, kill it, then check.
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  source '$HELPER'
  acquire_lease dead-wt one-shot 240
  echo \$\$ > '$ROOT/bg.pid'
  sleep 60
" &
BG_PID=$!
# Wait for lease file
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$ROOT/leases/dead-wt.lease" ]] && break
  sleep 0.1
done
kill -9 "$BG_PID" 2>/dev/null || true
wait "$BG_PID" 2>/dev/null || true

# Now check is_lease_active reports inactive.
set +e
(
  export SOLEUR_SESSION_STATE_ROOT="$ROOT"
  source "$HELPER"
  is_lease_active dead-wt
)
rc=$?
set -e
# CONTRACT CHANGED 2026-08-06 (#7278). This assertion was inverted: it used to
# require INACTIVE for a dead pid, and that requirement is what reaped two live
# worktrees in one afternoon.
#
# The fixture above kills a LONG-RUNNING acquirer, which is the only shape where
# pid-liveness is real orphan evidence. But `is_lease_active` cannot see the
# shape — it sees only "pid is dead", and that is ALSO what every documented CLI
# entry point produces on the happy path, because `acquire_lease` records `pid=$$`
# and those processes exit within milliseconds by design:
#
#     bash .claude/hooks/lib/session-state.sh acquire_lease <worktree>
#     bash .../worktree-manager.sh --yes create <branch>
#
# One signal, two indistinguishable causes — so the old rule could not be right in
# both. It optimised for the rare case (crash) and mis-served the common one
# (normal CLI exit), which meant NO CLI-acquired lease was ever honoured: the file
# existed, showed four hours remaining, and cleanup-merged removed the worktree,
# deleted the branch local AND remote, and closed the PR anyway.
#
# The window is now the authority. A killed session still holds its worktree until
# its window closes — bounded by max(expected_duration, 4h) and by the 24h mtime
# sweep (T5) — which is the correct direction to fail: a worktree released a little
# late is recoverable; one reaped mid-run is not.
if [[ "$rc" == "0" ]]; then
  pass "T4: a killed acquirer's lease is still honoured INSIDE its window (window is the authority, not pid liveness)"
else
  fail "T4: lease reads inactive purely because its pid is dead — the #7278 reaper is back"
fi

# ------------------------------------------------------------------------
# T5: Orphan sweep — 25h-mtime removed, 1h preserved
# ------------------------------------------------------------------------
echo "T5: orphan sweep removes 25h, preserves 1h"
ROOT=$(make_root); ROOTS+=("$ROOT")
# Create two fake leases, both with our own pid (alive) so PID-liveness doesn't trigger removal.
mkdir -p "$ROOT/leases"
cat > "$ROOT/leases/old.lease" <<EOF
pid=$$
ppid=$PPID
skill=one-shot
started_at=2020-01-01T00:00:00Z
expected_duration_min=60
hostname=$HOSTNAME
EOF
cat > "$ROOT/leases/fresh.lease" <<EOF
pid=$$
ppid=$PPID
skill=one-shot
started_at=2020-01-01T00:00:00Z
expected_duration_min=60
hostname=$HOSTNAME
EOF
touch -d "25 hours ago" "$ROOT/leases/old.lease"
touch -d "1 hour ago" "$ROOT/leases/fresh.lease"

(
  export SOLEUR_SESSION_STATE_ROOT="$ROOT"
  source "$HELPER"
  sweep_orphan_leases
)

if [[ -f "$ROOT/leases/old.lease" ]]; then
  fail "T5: 25h-mtime lease still present"
elif [[ ! -f "$ROOT/leases/fresh.lease" ]]; then
  fail "T5: 1h-mtime lease wrongly removed"
else
  pass "T5"
fi

# ------------------------------------------------------------------------
# T6: Hard-fail when flock missing
# ------------------------------------------------------------------------
echo "T6: hard-fail when flock absent"
ROOT=$(make_root); ROOTS+=("$ROOT")
# Build a sandbox PATH that contains all standard tools EXCEPT flock so
# `command -v flock` returns false but everything else still resolves.
SANDBOX_BIN=$(mktemp -d); ROOTS+=("$SANDBOX_BIN")
for t in bash date mkdir stat rm mv cat basename dirname grep head cut printf sleep ln mktemp git kill touch wc awk tr sh; do
  src=$(command -v "$t" 2>/dev/null || true)
  [[ -n "$src" ]] && ln -s "$src" "$SANDBOX_BIN/$t"
done
# Intentionally omit flock.
set +e
OUT=$(PATH="$SANDBOX_BIN" bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  source '$HELPER'
  acquire_lock t6 1
" 2>&1)
rc=$?
set -e
if [[ "$rc" != "99" ]]; then
  fail "T6: expected rc=99 when flock missing, got rc=$rc (out: $OUT)"
elif ! echo "$OUT" | grep -qi flock; then
  fail "T6: error message did not mention flock (got: $OUT)"
else
  pass "T6"
fi

# ------------------------------------------------------------------------
# T7: Multi-signal trap releases lease on SIGTERM
# ------------------------------------------------------------------------
echo "T7: multi-signal trap releases lease"
ROOT=$(make_root); ROOTS+=("$ROOT")

bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  source '$HELPER'
  acquire_lease trap-wt work 240
  _register_lease_release_trap trap-wt
  # sleep&wait so bash itself receives the signal and runs the trap; a
  # foreground 'sleep' would block bash and SIGTERM would skip the trap.
  sleep 30 & wait
" &
TRAP_PID=$!
# Wait for lease file to appear
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [[ -f "$ROOT/leases/trap-wt.lease" ]] && break
  sleep 0.1
done
if [[ ! -f "$ROOT/leases/trap-wt.lease" ]]; then
  fail "T7: lease file never created"
else
  kill -TERM "$TRAP_PID" 2>/dev/null || true
  # Allow trap to run
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -f "$ROOT/leases/trap-wt.lease" ]] || break
    sleep 0.1
  done
  if [[ -f "$ROOT/leases/trap-wt.lease" ]]; then
    fail "T7: lease file remained after SIGTERM"
  else
    pass "T7"
  fi
fi
wait "$TRAP_PID" 2>/dev/null || true

# ------------------------------------------------------------------------
# T8: headless_or_stderr branches on TTY + CLAUDECODE
# ------------------------------------------------------------------------
echo "T8: headless_or_stderr branches correctly"
ROOT=$(make_root); ROOTS+=("$ROOT")

# Headless branch: no TTY on fd 2, CLAUDECODE set → write to log file
ERR_OUT="$ROOT/h.err"
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  export CLAUDECODE=1
  source '$HELPER'
  headless_or_stderr warn 'headless test message'
" 2>"$ERR_OUT" </dev/null

LOG_GLOB="$ROOT/logs/"*.log
log_match=$(grep -l "headless test message" "$ROOT/logs/"*.log 2>/dev/null || true)
if [[ -z "$log_match" ]]; then
  fail "T8: headless branch did not write to log file under $ROOT/logs/"
elif [[ -s "$ERR_OUT" ]]; then
  fail "T8: headless branch wrote to stderr (expected silent): $(cat "$ERR_OUT")"
else
  pass "T8 (headless branch)"
fi

# Foreground branch: stderr should receive the message when a TTY is present.
# Use `script` to fake a pty on fd 2; capture full pty output via the
# typescript file (NOT a per-call redirect — that would replace the pty
# with a regular file and defeat the test).
if command -v script >/dev/null; then
  TYPESCRIPT="$ROOT/typescript.out"
  script -q -c "
    export SOLEUR_SESSION_STATE_ROOT='$ROOT'
    export CLAUDECODE=1
    source '$HELPER'
    headless_or_stderr warn 'foreground test message'
  " "$TYPESCRIPT" >/dev/null
  if grep -q "foreground test message" "$TYPESCRIPT"; then
    pass "T8 (foreground branch)"
  else
    fail "T8: foreground branch did not write to stderr (typescript: $(cat "$TYPESCRIPT"))"
  fi
else
  echo "  skip: script(1) not available"
fi

# ------------------------------------------------------------------------
# T9: a lease whose ACQUIRING PROCESS HAS EXITED is still active inside its
# expected duration.
#
# This is the defect that reaped two live worktrees on 2026-08-06 (#7278).
# `acquire_lease` records `pid=$$`. The DOCUMENTED entry points are
# short-lived processes:
#
#     bash .claude/hooks/lib/session-state.sh acquire_lease <worktree>
#     bash .../worktree-manager.sh --yes create <branch>
#
# so `$$` belongs to a bash that exits within milliseconds. `is_lease_active`
# then hit `kill -0 <dead pid> || return 1` and reported INACTIVE, and
# `sweep_orphan_leases` deleted the file outright. Every CLI-acquired lease
# was therefore DEAD ON ARRIVAL: the file existed, carried four hours of
# remaining duration, and protected nothing. cleanup-merged reaped the
# worktree, deleted the branch local AND remote, and closed the PR.
#
# A lease is a TIME-BOXED RESERVATION. PID liveness is an optimisation that
# lets a finished session release early — it is not the authority, and it
# must not be able to expire a lease that is still inside its window.
# ------------------------------------------------------------------------
echo "T9: a lease outlives the process that acquired it (#7278 reaper)"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T9_WT="wt-dead-acquirer-$$"
# Acquire from a SEPARATE process which then exits — the real CLI shape.
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  # shellcheck source=/dev/null
  source '$HELPER'
  acquire_lease '$T9_WT' one-shot 240
" >/dev/null 2>&1
t9_acq_rc=$?

if [[ "$t9_acq_rc" -ne 0 ]]; then
  fail "T9 setup: child could not acquire the lease (rc=$t9_acq_rc)"
elif [[ ! -f "$ROOT/leases/$T9_WT.lease" ]]; then
  fail "T9 setup: no lease file was written"
else
  t9_pid=$(grep '^pid=' "$ROOT/leases/$T9_WT.lease" | cut -d= -f2)
  # PRECONDITION, asserted rather than assumed: if the recorded pid were
  # somehow still alive this fixture would exercise the happy path and pass
  # vacuously against the very bug it exists to pin.
  if [[ -z "$t9_pid" ]] || kill -0 "$t9_pid" 2>/dev/null; then
    fail "T9 precondition: recorded pid '$t9_pid' is alive or empty — fixture cannot reach the dead-pid path"
  else
    pass "T9 precondition: the acquiring process has exited (pid $t9_pid is dead)"

    if is_lease_active "$T9_WT"; then
      pass "T9a: a lease whose acquirer exited is ACTIVE inside its duration"
    else
      fail "T9a: lease reads INACTIVE inside its window — cleanup-merged would reap live work"
    fi

    # The sweep must not delete it either: worktree-manager runs
    # sweep_orphan_leases BEFORE it consults is_lease_active, so a sweep that
    # reaps on a dead pid alone defeats the check downstream of it.
    sweep_orphan_leases
    if [[ -f "$ROOT/leases/$T9_WT.lease" ]]; then
      pass "T9b: sweep_orphan_leases preserves a dead-acquirer lease inside its window"
    else
      fail "T9b: sweep_orphan_leases deleted a lease that is still inside its window"
    fi
  fi
fi

# ------------------------------------------------------------------------
# T10: the fix must NOT make leases immortal. A lease past its window is
# still inactive and still sweepable, dead pid or not — otherwise a crashed
# session would block cleanup forever, which is the opposite failure.
# ------------------------------------------------------------------------
echo "T10: an EXPIRED lease is still inactive (the fix is time-boxed, not immortal)"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T10_WT="wt-expired-$$"
# started_at well beyond the 4h floor; pid 999999 is not running.
cat > "$ROOT/leases/$T10_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u -d '30 hours ago' +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=240
hostname=$HOSTNAME
EOF

if is_lease_active "$T10_WT"; then
  fail "T10a: a lease 30h past a 4h window reads ACTIVE — cleanup could never reap"
else
  pass "T10a: a lease past its window is inactive"
fi

# ------------------------------------------------------------------------
# T11: a lease from ANOTHER host is not active here (unchanged invariant,
# pinned because T9 loosens the pid check and must not loosen this one).
# ------------------------------------------------------------------------
echo "T11: a foreign-host lease is inactive"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T11_WT="wt-foreign-$$"
cat > "$ROOT/leases/$T11_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=240
hostname=some-other-machine
EOF

if is_lease_active "$T11_WT"; then
  fail "T11: a lease owned by another host reads ACTIVE on this one"
else
  pass "T11: a foreign-host lease is inactive"
fi

# ------------------------------------------------------------------------
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
