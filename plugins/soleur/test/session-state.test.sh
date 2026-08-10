#!/usr/bin/env bash
# Tests for plugins/soleur/scripts/lib/session-state.sh.
#
# T1-T8 per plan 2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md.
# Run via:  bash plugins/soleur/test/session-state.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../scripts/lib/session-state.sh"

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
# CONTRACT CHANGED 2026-08-06 (#5454). This assertion was inverted: it used to
# require INACTIVE for a dead pid, and that requirement is what reaped two live
# worktrees in one afternoon.
#
# The fixture above kills a LONG-RUNNING acquirer, which is the only shape where
# pid-liveness is real orphan evidence. But `is_lease_active` cannot see the
# shape — it sees only "pid is dead", and that is ALSO what every documented CLI
# entry point produces on the happy path, because `acquire_lease` records `pid=$$`
# and those processes exit within milliseconds by design:
#
#     bash <plugin-root>/scripts/lib/session-state.sh acquire_lease <worktree>
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
  fail "T4: lease reads inactive purely because its pid is dead — the #5454 reaper is back"
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
# This is the defect that reaped two live worktrees on 2026-08-06 (#5454).
# `acquire_lease` records `pid=$$`. The DOCUMENTED entry points are
# short-lived processes:
#
#     bash <plugin-root>/scripts/lib/session-state.sh acquire_lease <worktree>
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
echo "T9: a lease outlives the process that acquired it (#5454 reaper)"
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

# T10b: the sweep must actually DELETE it. Nothing covered this branch before —
# T9b covers preserve-inside-window and T5 returns at the 24h mtime cap before
# ever reaching it, so flipping `>=` to `<` in sweep_orphan_leases left the whole
# suite green on precisely the immortality axis this change promises to defend.
sweep_orphan_leases
if [[ -f "$ROOT/leases/$T10_WT.lease" ]]; then
  fail "T10b: sweep_orphan_leases kept a dead-pid lease 30h past its window"
else
  pass "T10b: sweep_orphan_leases deletes a dead-pid lease past its window"
fi

# ------------------------------------------------------------------------
# T12: a CORRUPT expected_duration_min must fail CLOSED (lease still honoured),
# never open.
#
# `$(( abc * 60 ))` under `set -u` treats `abc` as an unset variable name and
# ERRORS. is_lease_active is called from inside an `if` in worktree-manager, so
# `set -e` is suspended and that error read as "no active lease" — a FRESH lease
# with one corrupt field became reapable. Measured before the fix.
# ------------------------------------------------------------------------
echo "T12: a corrupt expected_duration_min fails closed"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T12_WT="wt-corrupt-dur-$$"
cat > "$ROOT/leases/$T12_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=abc
hostname=$HOSTNAME
EOF

if ( set -euo pipefail; is_lease_active "$T12_WT" ) 2>/dev/null; then
  pass "T12: a fresh lease with a corrupt duration is still ACTIVE (fails closed)"
else
  fail "T12: a corrupt duration field made a fresh lease reapable — fail-open on a destructive path"
fi

# T12b: the input the regex ACCEPTS but bash arithmetic rejects. `^[0-9]+$`
# admits a leading zero; bash then reads it as OCTAL, where 8 and 9 are invalid
# digits, so the arithmetic ERRORS and the window comes back empty. Measured
# before the `10#` fix: a 0-second-old lease read INACTIVE *and* was swept in
# the same pass. T12's `abc` cannot reach this — it is rejected by the regex.
for T12B_DUR in 08 09 090; do
  T12B_WT="wt-octal-${T12B_DUR}-$$"
  cat > "$ROOT/leases/$T12B_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=$T12B_DUR
hostname=$HOSTNAME
EOF
  if ( set -euo pipefail; is_lease_active "$T12B_WT" ) 2>/dev/null; then
    pass "T12b: a fresh lease with expected_duration_min=$T12B_DUR is ACTIVE (octal-safe)"
  else
    fail "T12b: expected_duration_min=$T12B_DUR made a FRESH lease reapable (octal arithmetic error)"
  fi
  sweep_orphan_leases
  if [[ -f "$ROOT/leases/$T12B_WT.lease" ]]; then
    pass "T12b: sweep preserves the expected_duration_min=$T12B_DUR lease"
  else
    fail "T12b: sweep DELETED a 0-second-old lease because of expected_duration_min=$T12B_DUR"
  fi
done

# T12c: a leading zero must not silently SHRINK the window either. `0700` does
# not error — octal 0700 is 448, so the lease would be honoured 7.5h instead of
# the 11.7h it declares. Quiet under-protection is still under-protection.
if [[ "$(_lease_window_seconds 0700)" == "42000" ]]; then
  pass "T12c: expected_duration_min=0700 yields 42000s (decimal 700min), not octal 448min"
else
  fail "T12c: expected_duration_min=0700 yielded $(_lease_window_seconds 0700)s — octal shrank the window"
fi

# ------------------------------------------------------------------------
# T13: an unbounded expected_duration_min must NOT create an immortal lease.
#
# The field is operator-supplied via SOLEUR_EXPECTED_DURATION_MIN and validated
# only as digits. Unclamped, a typo (240000 for 240) silently disables
# cleanup-merged for months. Measured before the clamp: a 20-day-old lease with
# expected_duration_min=525600 read ACTIVE.
# ------------------------------------------------------------------------
echo "T13: an absurd duration cannot outlive the 24h ceiling"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T13_WT="wt-immortal-$$"
cat > "$ROOT/leases/$T13_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u -d '20 days ago' +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=525600
hostname=$HOSTNAME
EOF

if is_lease_active "$T13_WT"; then
  fail "T13: a 20-day-old lease with a 1-year declared duration reads ACTIVE — cleanup-merged is disabled indefinitely"
else
  pass "T13: the 24h ceiling bounds an absurd declared duration"
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
# T14: sweep_orphan_leases must return 0 on a malformed / racing lease.
#
# cleanup_merged_worktrees calls it BARE under `set -euo pipefail`, so a
# non-zero return aborts every maintenance step after it — fetch-prune, the
# whole reap loop, orphan-dir cleanup, tmp reclamation, runaway-kill. The
# failure direction is safe (nothing is reaped) which is precisely what makes
# it a SILENT disable. `_lease_read_field` returns 1 for a missing field and
# for a vanished file, and a sibling releasing its lease mid-sweep is an
# ordinary race — no corruption required.
# ------------------------------------------------------------------------
echo "T14: the sweep survives malformed and racing leases under set -e"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

# Each fixture omits exactly one field.
printf 'ppid=1\nskill=one-shot\nstarted_at=%s\nexpected_duration_min=240\nhostname=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HOSTNAME" > "$ROOT/leases/no-pid-$$.lease"
printf 'pid=999999\nppid=1\nskill=one-shot\nexpected_duration_min=240\nhostname=%s\n' \
  "$HOSTNAME" > "$ROOT/leases/no-started-$$.lease"
printf 'pid=999999\nppid=1\nskill=one-shot\nstarted_at=%s\nhostname=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HOSTNAME" > "$ROOT/leases/no-dur-$$.lease"
printf 'pid=999999\nppid=1\nskill=one-shot\nstarted_at=%s\nexpected_duration_min=240\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ROOT/leases/no-host-$$.lease"
: > "$ROOT/leases/empty-$$.lease"

# `bash -c`, NOT a `( … )` subshell. Measured: the subshell form does NOT
# reproduce the abort — it inherits this suite's already-relaxed option state and
# the mutation (dropping `|| true`) survived it, reporting coverage that did not
# exist. A fresh process entered with `set -euo pipefail` is the shape
# worktree-manager.sh actually has, and it reds correctly.
t14_rc=0
bash -c "
  set -euo pipefail
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  # shellcheck source=/dev/null
  source '$HELPER'
  sweep_orphan_leases
" >/dev/null 2>&1 || t14_rc=$?

if [[ "$t14_rc" -eq 0 ]]; then
  pass "T14: sweep returns 0 on malformed leases under set -euo pipefail"
else
  fail "T14: sweep returned $t14_rc — cleanup-merged would abort here, silently skipping every step after it"
fi

# ------------------------------------------------------------------------
# T15: the release trap must NOT fire on normal process exit.
#
# This is ONE OF TWO defects that made every other protection in this file dead
# code for the path that matters. A worktree-creating function acquires the
# lease and registers the trap IN THE SAME PROCESS, and that process exits
# normally on success — so with EXIT armed the lease was deleted before the
# command returned, and `is_lease_active` never got past its
# `[[ -f "$lease_file" ]]` guard. Measured before the fix: the leases directory
# is EMPTY the instant create returns.
#
# That measurement had TWO independent causes and this header originally named
# only one. The second: `create_worktree` — the function `create` dispatches to,
# and the one the autonomous pipeline actually invokes — did not acquire a lease
# AT ALL until PR #7373. An empty leases directory looks identical under both
# causes, which is exactly how the second survived the fix for the first. This
# arm pins the trap half only; scenarios 3-4 of
# plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh pin the
# acquisition half.
#
# Both directions are pinned: normal exit must PRESERVE, an abnormal signal must
# still RELEASE (that genuinely means the holder died).
# ------------------------------------------------------------------------
echo "T15: the release trap fires on signals, not on normal exit"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  # shellcheck source=/dev/null
  source '$HELPER'
  acquire_lease t15-normal one-shot 240
  _register_lease_release_trap t15-normal
" >/dev/null 2>&1
if [[ -f "$ROOT/leases/t15-normal.lease" ]]; then
  pass "T15a: a lease survives the acquiring process exiting NORMALLY"
else
  fail "T15a: the EXIT trap deleted the lease on normal exit — every guard below the file check is dead code"
fi

bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  # shellcheck source=/dev/null
  source '$HELPER'
  acquire_lease t15-signal one-shot 240
  _register_lease_release_trap t15-signal
  kill -TERM \$\$
  sleep 5
" >/dev/null 2>&1
if [[ -f "$ROOT/leases/t15-signal.lease" ]]; then
  fail "T15b: SIGTERM left the lease behind — an abnormal exit does mean the holder died, and should release"
else
  pass "T15b: SIGTERM still releases the lease"
fi

# ------------------------------------------------------------------------
# T16: the documented CLI release must actually release.
#
# Measured before the fix: `bash session-state.sh release_lease <wt>` — the call
# one-shot and work both instruct at end-of-work — returned rc=0 and deleted
# NOTHING, because a fresh process has a different `$$` and an empty
# `_LEASE_ACQUIRED_STARTED_AT`. It reported success while leaking the lease.
# With the trap no longer firing on normal exit, this is the ONLY clean release
# path, so an unreachable guard here would make every lease live its full window.
# ------------------------------------------------------------------------
echo "T16: the documented post-exit release works"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$ROOT'
  # shellcheck source=/dev/null
  source '$HELPER'
  acquire_lease t16-wt one-shot 240
" >/dev/null 2>&1
if [[ ! -f "$ROOT/leases/t16-wt.lease" ]]; then
  fail "T16 setup: no lease to release"
else
  SOLEUR_SESSION_STATE_ROOT="$ROOT" bash "$HELPER" release_lease t16-wt >/dev/null 2>&1
  if [[ -f "$ROOT/leases/t16-wt.lease" ]]; then
    fail "T16a: the documented release_lease call is a silent no-op — leases would never be released"
  else
    pass "T16a: a fresh process can release a lease whose acquirer has exited"
  fi
fi

# T16b: it must NOT release a lease held by a different, still-LIVE process.
sleep 300 &
T16_LIVE=$!
cat > "$ROOT/leases/t16-live.lease" <<EOF
pid=$T16_LIVE
ppid=1
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=240
hostname=$HOSTNAME
EOF
SOLEUR_SESSION_STATE_ROOT="$ROOT" bash "$HELPER" release_lease t16-live >/dev/null 2>&1
if [[ -f "$ROOT/leases/t16-live.lease" ]]; then
  pass "T16b: a lease held by a different LIVE process is refused"
else
  fail "T16b: released another live session's lease — the ownership guard is gone"
fi
kill "$T16_LIVE" 2>/dev/null || true

# ------------------------------------------------------------------------
# T17: the floor and ceiling are pinned AS VALUES, not just behaviourally.
#
# T13 proves a 20-day-old lease is inactive, but it passes for ANY ceiling under
# 20 days — widening 86400 to 604800 (7d) left the whole suite green. A constant
# whose only test is a fixture far outside it is not pinned. These assert the
# function's output directly, so changing either literal reds immediately.
# ------------------------------------------------------------------------
echo "T17: _lease_window_seconds pins both bounds as values"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

t17() { # label, input, expected
  local got; got=$(_lease_window_seconds "$2")
  if [[ "$got" == "$3" ]]; then pass "T17: $1 ($2 -> $3)"; else fail "T17: $1 — expected $3, got $got"; fi
}
t17 "floor binds below 4h"            1        14400
t17 "floor binds at the default"      240      14400
t17 "declared duration passes through" 700     42000
t17 "ceiling binds above 24h"         525600   86400
t17 "ceiling binds on overflow"       99999999999999999999 86400

# T17b: the ceiling and the sweep's mtime cap MUST be the same number. The
# comment on the ceiling claims pinning them together is "what makes 'the 24h
# sweep is the backstop' TRUE rather than merely claimed" — nothing verified
# that, so the two 86400s could drift apart silently.
T17_CEIL=$(_lease_window_seconds 525600)
T17_MTIME=$(grep -oE '\(\( age > [0-9]+ \)\)' "$HELPER" | grep -oE '[0-9]+' | head -1)
if [[ "$T17_CEIL" == "$T17_MTIME" ]]; then
  pass "T17b: window ceiling ($T17_CEIL) == sweep mtime cap ($T17_MTIME) — the backstop claim holds"
else
  fail "T17b: ceiling $T17_CEIL != mtime cap $T17_MTIME — 'the 24h sweep is the backstop' is no longer true"
fi

# ------------------------------------------------------------------------
# T18: worktree-manager must actually CALL the sweep inside cleanup, and must
# fail CLOSED when the lease library is missing.
#
# Both were unpinned: reverting the stub to `return 1` (the pre-fix fail-open
# that is half this branch's point) and deleting the sweep call each left every
# suite green. Anchored on the call/return syntax, not a bare token — the
# explanatory comments above both sites name them, so a bare grep would be
# satisfied by the prose.
# ------------------------------------------------------------------------
echo "T18: the worktree-manager wiring is pinned"
# `../../..` reaches the repo root from plugins/soleur/test/ — the same depth it
# reached from the pre-#7409 home at .claude/hooks/lib/, so this line survived the
# move by COINCIDENCE rather than by design. Stated explicitly so a future
# relocation does not silently point it at the wrong tree.
WM="$(cd "$SCRIPT_DIR/../../.." && pwd)/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

if [[ ! -f "$WM" ]]; then
  fail "T18 setup: worktree-manager.sh not found at $WM"
else
  # The sweep call must appear INSIDE cleanup_merged_worktrees, at the start of
  # a line (a comment line starts with '#', so this cannot match the prose).
  if awk '/^cleanup_merged_worktrees\(\)/,/^}/' "$WM" | grep -qE '^[[:space:]]*sweep_orphan_leases'; then
    pass "T18a: cleanup_merged_worktrees invokes sweep_orphan_leases"
  else
    fail "T18a: the sweep call is gone from cleanup_merged_worktrees — the 24h backstop never runs during cleanup"
  fi

  # The missing-library stub must fail CLOSED.
  if grep -qE '^[[:space:]]*is_lease_active\(\)[[:space:]]*\{[[:space:]]*return 0;' "$WM"; then
    pass "T18b: the missing-library stub fails CLOSED (is_lease_active returns 0)"
  else
    fail "T18b: the stub no longer returns 0 — with no lease library, cleanup would reap every worktree"
  fi
fi

# ------------------------------------------------------------------------
# T19: is_lease_active and the sweep must AGREE in the middle of the window.
#
# `_lease_window_seconds` was extracted so the two callers agree exactly, and
# nothing asserted that they do: quartering ONLY the sweep's threshold survived
# the whole suite. That mutant reproduces #5454's mechanism precisely — at ~3h a
# lease reads ACTIVE while the sweep deletes its file, so the reap loop finds no
# lease and destroys a live worktree.
#
# Every other fixture samples age ~0 or age ~30h/20d — never a value where a
# disagreement is observable. This one sits deliberately in between.
# ------------------------------------------------------------------------
echo "T19: the two window consumers agree mid-window (desync guard)"
ROOT=$(make_root); ROOTS+=("$ROOT")
source_helper "$ROOT"

T19_WT="wt-midwindow-$$"
cat > "$ROOT/leases/$T19_WT.lease" <<EOF
pid=999999
ppid=1
skill=one-shot
started_at=$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=240
hostname=$HOSTNAME
EOF

if is_lease_active "$T19_WT"; then
  pass "T19a: a 3h-old lease inside a 4h window is ACTIVE"
else
  fail "T19a: a 3h-old lease read INACTIVE inside its own window"
fi

sweep_orphan_leases
if [[ -f "$ROOT/leases/$T19_WT.lease" ]]; then
  pass "T19b: the sweep agrees — it preserves the same 3h-old lease"
else
  fail "T19b: the sweep DELETED a lease is_lease_active considers active — the two consumers have desynced (#5454's mechanism)"
fi

# ------------------------------------------------------------------------
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

# ANTI-VACUITY FLOOR. `[[ "$FAIL" -eq 0 ]]` alone is a pure zero-check with no
# lower bound on PASS, so anything that stops assertions from being REACHED is
# green by construction. Measured on a sandbox copy: replacing pass() and fail()
# with no-ops ran every fixture, asserted nothing, printed `PASS: 0 / FAIL: 0`
# and exited 0. A `continue`, an early `return`, a renamed helper or a setup
# ladder silently taking a third branch all produce the same shape.
#
# A FLOOR, never `-eq`: equality turns every added assertion into a spurious
# failure, which is how a floor gets deleted rather than maintained. Raise it
# when you add assertions; the number below is the count on a green run.
MIN_ASSERTIONS=39
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $PASS assertions ran, expected >= $MIN_ASSERTIONS — the suite did not execute what it claims to cover."
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
