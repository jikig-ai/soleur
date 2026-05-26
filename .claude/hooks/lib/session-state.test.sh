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
if [[ "$rc" == "0" ]]; then
  fail "T4: is_lease_active returned 0 (active) for dead PID"
else
  pass "T4"
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
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
