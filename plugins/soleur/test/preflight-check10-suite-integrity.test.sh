#!/usr/bin/env bash
# Anti-vacuity floor for preflight Check 10's regression suites (#7393).
#
# WHY THIS LIVES OUTSIDE THE SUITE IT GUARDS. Every anti-vacuity mechanism inside
# a bun/vitest file — a per-assertion count, a non-vacuity anchor, a mutation
# battery — is defeated by the same move: not running the assertions. Measured on
# this branch:
#
#   perl -pi -e 's/^(\s*)test\(/$1test.skip(/' <both suites>
#   => "0 pass, 110 skip, 0 fail", exit code 0
#
# CI reads the exit code, so a suite that asserts nothing is indistinguishable
# from a suite that passed. Check 10 is a security boundary (it executes
# attacker-authorable commands on the operator's workstation), so "the tests
# silently stopped running" is not an acceptable failure mode.
#
# A floor written INSIDE the suite cannot close this: the guard would itself be
# skippable. Hence a separate registered gate — `plugins/soleur/test/*.test.sh`
# is auto-globbed by scripts/test-all.sh (see its `for f in` loop), so this runs
# in the `scripts` shard whether or not the bun suites execute at all.
#
# The floor is a FLOOR, never an equality: the counts grow as coverage is added,
# and `-eq` would turn every new test into a spurious failure. Derived from a
# green run, and it ratchets upward only.
set -uo pipefail

# /tmp is a machine-global RAM-backed tmpfs shared by every parallel worktree, and
# this repo's runners already banner when it drops below their headroom floor
# (observed at 143MB against a 1024MB floor while writing this). Default TMPDIR
# the same way scripts/test-all.sh does, so a DIRECT invocation of this gate --
# the documented inner loop -- does not add to that pressure.
export TMPDIR="${TMPDIR:-/var/tmp}"

cd "$(git rev-parse --show-toplevel)" || exit 1

SUITES=(
  plugins/soleur/test/preflight-discoverability-test.test.ts
  plugins/soleur/test/observability-schema-parity.test.ts
)

# Derived from a green run at the time of writing. Raise when coverage grows;
# never lower without saying why in the commit message.
MIN_TESTS=110
MIN_ASSERTIONS=380

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }

echo "=== preflight Check 10 suite integrity ==="

# --- 1. No suppressed tests -------------------------------------------------
# `.skip`/`.only`/`.todo` silently remove coverage while the runner still exits 0.
for f in "${SUITES[@]}"; do
  if [[ ! -f "$f" ]]; then
    fail "suite missing: $f"
    continue
  fi
  # Anchor on the call form so prose/comments mentioning ".skip" cannot trip it,
  # and so a future `describe.skip` is caught as well as `test.skip`.
  if grep -nE '^[[:space:]]*(test|it|describe)\.(skip|only|todo)\(' "$f"; then
    fail "$f contains a suppressed or exclusive test (see lines above)"
  else
    pass "$f has no .skip/.only/.todo"
  fi
done

# --- 2. The suites actually execute, and clear the floor --------------------
# Reading the runner's own summary rather than trusting its exit code: a suite
# that skipped everything exits 0 too.
#
# The trap OWNS the tempfile (ADR-129, enforced by
# scripts/lint-trap-tempfile-ownership.py): without it, a die between allocation
# and the `rm` at the end leaks the log into a /tmp that is already the
# contended resource this repo's runners warn about. Registered BEFORE the
# assignment so there is no window where the file exists and the trap does not.
LOG=""
cleanup() { [[ -n "$LOG" ]] && rm -f "$LOG"; }
trap cleanup EXIT
LOG="$(mktemp -t check10-integrity.XXXXXXXX.log)"
bun test "${SUITES[@]}" >"$LOG" 2>&1
RC=$?

if [[ "$RC" -ne 0 ]]; then
  fail "bun test exited $RC — see $LOG"
else
  pass "bun test exited 0"
fi

# `N pass` / `N fail` / `N expect() calls` come from bun's summary block.
n_pass=$(grep -oE '^[[:space:]]*([0-9]+) pass' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_fail=$(grep -oE '^[[:space:]]*([0-9]+) fail' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_skip=$(grep -oE '^[[:space:]]*([0-9]+) skip' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_expect=$(grep -oE '([0-9]+) expect\(\) calls' "$LOG" | grep -oE '^[0-9]+' | tail -1)
: "${n_pass:=0}" "${n_fail:=0}" "${n_skip:=0}" "${n_expect:=0}"

echo "  (measured: pass=$n_pass fail=$n_fail skip=$n_skip expect=$n_expect)"

if [[ "$n_skip" -gt 0 ]]; then
  fail "$n_skip test(s) were SKIPPED — coverage silently removed"
else
  pass "no tests skipped at runtime"
fi

if [[ "$n_pass" -lt "$MIN_TESTS" ]]; then
  fail "only $n_pass tests passed, floor is $MIN_TESTS (coverage removed?)"
else
  pass "test count $n_pass >= floor $MIN_TESTS"
fi

if [[ "$n_expect" -lt "$MIN_ASSERTIONS" ]]; then
  fail "only $n_expect expect() calls, floor is $MIN_ASSERTIONS (assertions gutted?)"
else
  pass "assertion count $n_expect >= floor $MIN_ASSERTIONS"
fi

# (the EXIT trap removes $LOG)

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
