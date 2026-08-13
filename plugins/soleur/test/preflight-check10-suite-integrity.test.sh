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
  plugins/soleur/test/fullsuite-merge-gate.test.ts
)

# QUANTITY floors are a secondary tripwire only. On their own they were defeated
# three ways at 9 tests / 97 assertions of slack: deleting two whole describes
# stayed green; neutering seven tests with an early `return` plus padding kept the
# test count identical and RAISED the assertion count above the floor; and a
# line-broken `test\n.todo(` evaded the grep while bun counts todo separately from
# skip. Quantity measures the size of the input, not the work performed -- the
# same vacuity shape this gate exists to prevent, one level up.
#
# The primary control is now the NAMED-TEST MANIFEST: a committed list of every
# test name, asserted as a subset of what the sources declare. A deleted describe,
# a renamed test, or a `.todo` all become explicit diff lines.
MANIFEST="plugins/soleur/test/fixtures/check10-test-manifest.txt"
# Ratcheted to the MEASURED green value, with no slack. The previous 113/460 sat
# 7 tests and 37 assertions below the real counts, and that gap was not padding —
# it was the budget an attacker spends: gutting a manifest-listed test's BODY to
# `expect(true).toBe(true)` (name intact, so the manifest is satisfied) and
# deleting the 6 generated fold-indicator tests both landed inside it while all
# every check stayed green. These suites have no environment-conditional
# branching, so the counts are deterministic and an exact floor is safe.
# Ratchet both UPWARD when coverage is added; never widen the gap.
# All THREE floors live here, together, under one contract: absolute, ratcheted to
# the measured value, upward only. MIN_MANIFEST_LINES used to sit buried inside the
# manifest block's else-branch, which is how a reader misses that it carries the
# same rule. An EMPTY manifest previously passed vacuously as
# "[ok] all 0 manifest tests still declared", so this floor is what makes the
# primary identity control non-vacuous.
MIN_TESTS=131
MIN_ASSERTIONS=537
MIN_MANIFEST_LINES=126

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }

# ONE cleanup, ONE trap, registered before ANY tempfile is allocated. Bash EXIT
# traps are not additive: the previous form registered `rm -f $DECLARED` in the
# manifest block and then had it silently REPLACED by a later `trap cleanup EXIT`,
# so $DECLARED leaked on every single run. Measured in the real worktree: 21
# orphaned check10-declared.*.txt in TMPDIR, 0 orphaned logs — the exact tmpdir
# pressure this file's own ADR-129 commentary exists to prevent, caused by the
# ownership mechanism it was citing. Both names are declared empty up front so
# the handler is safe to fire at any point.
DECLARED=""
LOG=""
KEEP_LOG=0
cleanup() {
  [[ -n "$DECLARED" ]] && rm -f "$DECLARED"
  if [[ "$KEEP_LOG" == "1" ]]; then
    [[ -n "$LOG" ]] && echo "  (log retained: $LOG)"
    return 0
  fi
  [[ -n "$LOG" ]] && rm -f "$LOG"
  return 0
}
trap cleanup EXIT

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
  # Newline-tolerant: `test\n    .todo("…")` is valid JS and evaded a line-anchored
  # grep, while bun classifies `todo` separately from `skip` so the runtime
  # counter could not see it either. Collapse whitespace before matching.
  # The `(skip|only|todo)` + immediate `(` form missed the CONDITIONAL variants:
  # `describe.todoIf(true)("…")` suppressed four whole tests while all seven
  # checks stayed green and this gate printed "no tests skipped at runtime" — bun
  # counts those as `todo`, which the runtime counter below never parsed either.
  # `[A-Za-z]*` admits the If-suffixed forms; the bracket alternative admits
  # `test["todo"](…)`. The trailing `\(` anchor is DELIBERATELY kept so that
  # prose and comments naming `.skip` still cannot trip the gate.
  SUPPRESS_RE='(test|it|describe)[[:space:]]*(\.[[:space:]]*(skip|only|todo|failing)[A-Za-z]*[[:space:]]*\(|\[[[:space:]]*["'"'"'](skip|only|todo|failing)[A-Za-z]*["'"'"'][[:space:]]*\][[:space:]]*\()'
  if tr '\n' ' ' < "$f" | grep -qE "$SUPPRESS_RE"; then
    # Braces are required: `$SUPPRESS_RE[` parses as array-index syntax (SC1087).
    tr '\n' ' ' < "$f" | grep -oE "${SUPPRESS_RE}[^)]{0,80}" | head -5
    fail "$f contains a suppressed or exclusive test (see above)"
  else
    pass "$f has no .skip/.only/.todo"
  fi

  # REBINDING GUARD. `test`, `it` and `describe` are ordinary JS bindings, and
  # SUPPRESS_RE anchors on those literal identifiers followed by a call form.
  # `const it = test.failing;` has no `(` after `.failing`, so the pattern misses
  # it entirely — and `.failing` is the ONE member of the suppression family the
  # runtime counters cannot see: bun scores a failing `.failing` test as a PASS
  # (measured: 2 pass / 0 fail), so n_skip and n_todo both stay 0. Measured
  # end-to-end: delete `env -i` from the runtime of record, alias one test to the
  # rebound `it`, and this gate reported a full green with pass=121.
  # Adds no expect() calls, so MIN_ASSERTIONS is unaffected.
  REBIND_RE='(^|[;{}[:space:]])(const|let|var|function)[[:space:]]+(test|it|describe)([[:space:]]|=|;|\()'
  if tr '\n' ' ' < "$f" | grep -qE "$REBIND_RE"; then
    tr '\n' ' ' < "$f" | grep -oE "${REBIND_RE}[^;]{0,60}" | head -5
    fail "$f REBINDS test/it/describe — the source-pattern gate can be aliased around"
  else
    pass "$f does not rebind test/it/describe"
  fi
done

# --- 1b. Named-test manifest ------------------------------------------------
# Identity, not quantity. Every name in the committed manifest must still be
# declared by the sources; a deletion or rename is then a diff line rather than a
# silent count change absorbed by the floor's slack.
if [[ ! -f "$MANIFEST" ]]; then
  fail "manifest missing at $MANIFEST"
else
  DECLARED="$(mktemp -t check10-declared.XXXXXXXX.txt)"
  # Collation must be PINNED and IDENTICAL on both sides. `comm` compares with
  # strcoll only, while GNU `sort` applies a last-resort byte tie-break, so an
  # unpinned pipeline can hand `comm` input it considers unsorted: measured, that
  # emits "file N is not in sorted order", EXITS 0, and prints a wall of spurious
  # `missing:` lines under LC_ALL=C (a common CI default). Loud rather than
  # silent, but it leaves the primary control one locale change from being
  # disabled-by-noise. The manifest is committed in C collation to match.
  #
  # Backtick-named declarations are extracted too. The double-quote-only form was
  # structurally blind to `test(\`${id} …\`)`, leaving 6 generated tests (120
  # runtime vs 114 manifest) outside the "identity, not quantity" guarantee — and
  # deleting all 5 stayed green inside MIN_TESTS' slack. The literal source text
  # is a stable identity for them even though the runtime name interpolates.
  { grep -hoE '^[[:space:]]*(test|it)\([[:space:]]*"[^"]+"' "${SUITES[@]}" \
      | sed -E 's/^[[:space:]]*(test|it)\([[:space:]]*"//; s/"$//'
    # shellcheck disable=SC2016  # backticks are regex literals here; expansion is exactly what we do NOT want
    grep -hoE '^[[:space:]]*(test|it)\([[:space:]]*`[^`]+`' "${SUITES[@]}" \
      | sed -E 's/^[[:space:]]*(test|it)\([[:space:]]*`//; s/`$//'
  } | LC_ALL=C sort -u > "$DECLARED"

  # An EMPTY manifest made this control pass VACUOUSLY — `comm -23 <empty> …`
  # is empty, so it printed "[ok] all 0 manifest tests still declared" while four
  # sandbox-boundary tests were deleted and a writable --bind /home added. The
  # floor reasoning applied to the test counts was never applied to the manifest
  # itself. Ratchets upward with the manifest.
  # The delta pinned LC_ALL=C on the sort that builds $DECLARED and on comm, but
  # NOT on the committed manifest. Measured: this manifest passes `LC_ALL=C sort -c`
  # and FAILS `en_US.UTF-8 sort -c` at line 30 — so regenerating it the obvious way
  # (`sort -u` in a normal UTF-8 locale) desorts it relative to comm, which then
  # emits 81 spurious "no longer declared" lines accusing a deletion that never
  # happened. A gate that cries wolf gets bypassed, so name the remedy in the message.
  if ! LC_ALL=C sort -c "$MANIFEST" 2>/dev/null; then
    fail "$MANIFEST is not in C collation — regenerate with: LC_ALL=C sort -u -o $MANIFEST $MANIFEST"
  else
    pass "manifest is in C collation (comm's operands agree)"
  fi
  # Count ENTRIES, not newlines: `wc -l` under-counts a file whose last line lost
  # its terminator, turning a formatting nit into a "gutted?" accusation, and it
  # counts duplicates — so 116 copies of one name would satisfy a raw line floor.
  n_manifest=$(LC_ALL=C sort -u "$MANIFEST" | wc -l | tr -d ' ')
  n_declared=$(wc -l < "$DECLARED" | tr -d ' ')
  if [[ "$n_manifest" -lt "$MIN_MANIFEST_LINES" ]]; then
    fail "manifest has only $n_manifest entries, floor is $MIN_MANIFEST_LINES (manifest gutted?)"
  elif [[ "$n_declared" -eq 0 ]]; then
    fail "extracted ZERO declared test names — extraction is broken, treating as UNMEASURED"
  else
    MISSING="$(LC_ALL=C comm -23 "$MANIFEST" "$DECLARED" | head -20)"
    if [[ -n "$MISSING" ]]; then
      printf '%s\n' "$MISSING" | sed 's/^/      missing: /'
      fail "$(printf '%s\n' "$MISSING" | wc -l | tr -d ' ') manifest test(s) no longer declared — deleted or renamed"
    else
      pass "all $n_manifest manifest tests still declared"
    fi
  fi
fi

# --- 2. The suites actually execute, and clear the floor --------------------
# Reading the runner's own summary rather than trusting its exit code: a suite
# that skipped everything exits 0 too.
#
# The trap OWNS the tempfile (ADR-129, enforced by
# scripts/lint-trap-tempfile-ownership.py): without it, a die between allocation
# and the `rm` at the end leaks the log into a /tmp that is already the
# contended resource this repo's runners warn about. Registered BEFORE the
# assignment so there is no window where the file exists and the trap does not.
# $LOG is owned by the single cleanup()/trap registered near the top of this
# file (ADR-129), which also owns $DECLARED. KEEP_LOG is set by any diagnostic
# path that tells the reader to open the log, so the evidence outlives the run.
LOG="$(mktemp -t check10-integrity.XXXXXXXX.log)"
bun test "${SUITES[@]}" >"$LOG" 2>&1
RC=$?

if [[ "$RC" -ne 0 ]]; then
  fail "bun test exited $RC — see $LOG"
  KEEP_LOG=1
else
  pass "bun test exited 0"
fi

# `N pass` / `N fail` / `N expect() calls` come from bun's summary block.
n_pass=$(grep -oE '^[[:space:]]*([0-9]+) pass' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_fail=$(grep -oE '^[[:space:]]*([0-9]+) fail' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_skip=$(grep -oE '^[[:space:]]*([0-9]+) skip' "$LOG" | grep -oE '[0-9]+' | tail -1)
# bun classifies `todo` SEPARATELY from `skip`, so a suite suppressed via
# `.todoIf(...)` reported 0 skip and this gate called it "no tests skipped at
# runtime". Parsing it here is what makes the whole suppression family visible by
# MEASUREMENT rather than by source pattern-matching — the source grep above can
# always be out-spelled, this cannot. Absent from bun's summary when zero, so it
# legitimately defaults to 0 (unlike pass/expect, whose absence means UNMEASURED).
n_todo=$(grep -oE '^[[:space:]]*([0-9]+) todo' "$LOG" | grep -oE '[0-9]+' | tail -1)
n_expect=$(grep -oE '([0-9]+) expect\(\) calls' "$LOG" | grep -oE '^[0-9]+' | tail -1)
# An UNPARSED summary must not read as "measured zero". Without this, a run that
# never produced a summary block still printed "[ok] no tests skipped at runtime".
if [[ -z "${n_pass:-}" || -z "${n_expect:-}" ]]; then
  fail "could not parse bun's summary block — treating as UNMEASURED, not as zero (log: $LOG)"
  KEEP_LOG=1
fi
: "${n_pass:=0}" "${n_fail:=0}" "${n_skip:=0}" "${n_todo:=0}" "${n_expect:=0}"

echo "  (measured: pass=$n_pass fail=$n_fail skip=$n_skip todo=$n_todo expect=$n_expect)"

if [[ "$n_fail" -gt 0 ]]; then
  fail "$n_fail test(s) FAILED per bun's own summary"
  KEEP_LOG=1
else
  pass "bun's summary reports no failing tests"
fi

if [[ "$n_skip" -gt 0 || "$n_todo" -gt 0 ]]; then
  fail "$n_skip skipped + $n_todo todo test(s) — coverage silently removed"
else
  pass "no tests skipped or todo'd at runtime"
fi

if [[ "$n_pass" -lt "$MIN_TESTS" ]]; then
  fail "only $n_pass tests passed, floor is $MIN_TESTS (coverage removed? — if 'bun test exited 0' also failed, this is a consequence of that, not a cause)"
else
  pass "test count $n_pass >= floor $MIN_TESTS"
fi

if [[ "$n_expect" -lt "$MIN_ASSERTIONS" ]]; then
  fail "only $n_expect expect() calls, floor is $MIN_ASSERTIONS (assertions gutted? — if 'bun test exited 0' also failed, this is a consequence of that, not a cause)"
else
  pass "assertion count $n_expect >= floor $MIN_ASSERTIONS"
fi

# (the EXIT trap removes $LOG)

# THE GATE'S OWN ANTI-VACUITY FLOOR. Every control above routes through pass()/fail(),
# so both are a single point of silence: neutering them to no-ops printed
# "=== 0 passed, 0 failed ===" and exited 0, and the realistic half-mutation
# (fail() still prints, stops counting) printed "[FAIL] manifest has only 0 entries"
# and STILL exited 0, because the only terminal below reads $FAIL. CI reads the exit
# code. This file's whole thesis is that a suite asserting nothing is
# indistinguishable from one that passed — that applies to this file too.
# Ratchet with the check count, exactly like MIN_TESTS.
MIN_CHECKS=11
if [[ "$((PASS + FAIL))" -lt "$MIN_CHECKS" ]]; then
  printf '  [FAIL] only %d checks dispatched, floor is %d — the gate itself went silent\n' \
    "$((PASS + FAIL))" "$MIN_CHECKS"
  FAIL=$((FAIL + 1))
fi

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
