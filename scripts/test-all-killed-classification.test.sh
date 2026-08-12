#!/usr/bin/env bash
# Regression suite for scripts/test-all.sh's THIRD result class (#7424).
#
# WHY THIS EXISTS. The runner had two result classes, `[ok]` and `[FAIL]`, and a suite
# TERMINATED BY A SIGNAL rendered byte-identically to one that FAILED AN ASSERTION — both
# incrementing the same counter. On 2026-08-10 that produced
#   [FAIL] tests/scripts/registry-gate-mutation-battery (560931ms)
# on a run where the battery caught every mutation and left no surviving mutant; the block
# simply ended with bash's `Terminated "$@"` notice. Read from the summary alone, that line
# says the mutation battery guarding an irreversible destroy of production's sole image store
# is failing. It was not. The runner supplied no way to reach the correct reading.
#
# WHAT IT DOES NOT CLAIM. Nothing here establishes WHAT terminated a suite. An OOM kill, a
# wrapper timeout and a stray signal from a concurrent session were never distinguished, and
# `$?` cannot tell a signal death from a literal `exit(128+N)` — `bash -c 'exit 143'` also
# yields 143. The class is "signal-shaped, therefore UNRESOLVED", never "was killed by X".
#
# HOW IT TESTS. Two parts, because the defect has two halves and a suite covering only one of
# them would be the same kind of partial evidence this PR exists to eliminate:
#
#   Part A  the classifier in isolation — extracted from the runner by anchored range and
#           table-driven over every boundary that a guard is responsible for.
#   Part B  the RUNNER — a sandbox copy with fixture suites, proving it renders [KILLED],
#           keeps it out of the failure total, and exits 3. Part B carries the mutation arms:
#           a classifier that always says `failed`, a deleted `exit 3` arm, a deleted `*)`
#           default. Each mutant MUST red, or the assertion covering it is decorative.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the suite can be pointed at a mutated copy and PROVED to red against it.
# A guard that has never been shown to fail is not evidence; this is how that gets shown.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
PASS=0; FAIL=0

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-all.sh KILLED-classification suite ==="
echo ""
echo "--- Part A: the classifier, in isolation ---"

# Extract suite_exit_class by ANCHORED RANGE. The anchor count is asserted first: a rename
# would otherwise yield an empty extraction, every row would fail identically, and the cause
# would read as a classifier bug rather than a missing function.
anchor_count=$(grep -c '^suite_exit_class() {' "$TARGET" || true)
if [[ "$anchor_count" == "1" ]]; then
  pass "suite_exit_class is defined exactly once at column 0"
else
  fail "expected exactly 1 '^suite_exit_class() {' in $TARGET, found $anchor_count"
  echo "FATAL: cannot extract the function under test." >&2
  exit 1
fi

FN="$TMP/suite_exit_class.sh"
sed -n '/^suite_exit_class() {/,/^}/p' "$TARGET" > "$FN"

# A silently-empty or truncated extraction would make every row fail for the wrong reason.
if [[ -s "$FN" ]] && bash -n "$FN" 2>/dev/null; then
  pass "the extracted block is non-empty and parses"
else
  fail "the extracted block is empty or does not parse"
  echo "FATAL: extraction produced nothing usable." >&2
  exit 1
fi

# Invoke one row in a subshell running PRODUCTION shell options, so a `set -e` abort inside
# the classifier is caught here rather than in the runner. `unset -f` before sourcing proves
# the definition comes from the extract and not from an inherited environment.
classify() {
  bash -c '
    set -euo pipefail
    unset -f suite_exit_class 2>/dev/null || true
    # shellcheck source=/dev/null
    source "$1"
    declare -F suite_exit_class >/dev/null 2>&1 || { printf "__NOFUNC__\n"; exit 9; }
    suite_exit_class "$2"
  ' _ "$FN" "$1" 2>/dev/null || printf '__ABORT__\n'
}

# The table. Each row is a boundary some guard is responsible for; the five called out below
# are individually load-bearing and each pins a specific guard.
#
#   128        pins `rc > 128`.  `kill -l 0` returns EXIT, so without the guard this
#              classifies `killed` with the signal name "EXIT".
#   160 / 161  pin `-n "$name"`. `kill -l 32` / `33` return rc 0 with EMPTY output
#              (glibc-internal SIGCANCEL/SIGSETXID). A blank `SIG` is a claim the runner
#              cannot make.
#   162        pins that the empty-name window is a NAME test, not a numeric range. Without
#              it, mutating `-n "$name"` to `(( rc < 160 || rc > 161 ))` survives the table.
#   "" / " " / abc  pin the numeric guard. Without it `(( rc == 0 ))` on an empty string
#              evaluates TRUE and returns `ok` — the one class that increments no counter
#              and emits no warning.
#   3          pins the top-level-only exit contract: a nested runner that adopted `exit 3`
#              returns 3 into run_suite, and this row is the executed assertion that it
#              classifies `failed`.
#
# 124 stays `failed` deliberately: GNU `timeout` returns it from its OWN exit, so it is an
# attributed verdict by a named tool. Folding it into the unattributed `killed` bucket would
# lose exactly the attribution this suite exists to add.
run_row() {
  local input="$1" expected="$2" label="$3"
  local got; got=$(classify "$input")
  if [[ "$got" == "$expected" ]]; then
    pass "suite_exit_class '$input' -> $got ($label)"
  else
    fail "suite_exit_class '$input' -> '$got', expected '$expected' ($label)"
  fi
}

run_row 0   ok     "clean exit"
run_row 1   failed "ordinary assertion failure"
run_row 2   failed "ordinary failure"
run_row 3   failed "TOP-LEVEL-ONLY: a nested runner's own exit-3 is a plain FAIL here"
run_row 124 failed "GNU timeout's own exit — an attributed verdict, not an unattributed kill"
run_row 126 failed "not executable"
run_row 127 failed "command not found — a verdict, not a termination"
run_row 128 failed "GUARD rc>128: kill -l 0 succeeds with EXIT"
run_row 129 killed "SIGHUP"
run_row 130 killed "SIGINT"
run_row 134 killed "SIGABRT"
run_row 136 killed "SIGFPE"
run_row 137 killed "SIGKILL"
run_row 139 killed "SIGSEGV"
run_row 141 killed "SIGPIPE"
run_row 143 killed "SIGTERM — the shape the incident produced"
run_row 159 killed "SIGSYS — top of the classic range"
run_row 160 failed "GUARD -n name: kill -l 32 succeeds with EMPTY output"
run_row 161 failed "GUARD -n name: kill -l 33 succeeds with EMPTY output"
run_row 162 killed "SIGRTMIN — proves the empty-name window is a NAME test, not a range"
run_row 192 killed "SIGRTMAX — inclusive upper bound"
run_row 193 failed "above the decodable range"
run_row 255 failed "not signal-shaped"
run_row ""    failed "GUARD numeric: empty string must not reach the rc==0 arm"
run_row " "   failed "GUARD numeric: whitespace must not reach the rc==0 arm"
run_row abc   failed "GUARD numeric: non-numeric input fails CLOSED"

echo ""
echo "--- Part B: does the RUNNER render, count and exit correctly? ---"

FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"
printf '#!/usr/bin/env bash\nexit 0\n'                     > "$FIXTURES/ok.sh"
printf '#!/usr/bin/env bash\nexit 1\n'                     > "$FIXTURES/assertfail.sh"
# Signals ITSELF, so there is no timing race with an external killer and no dependency
# on what any other process on this host happens to be doing.
printf '#!/usr/bin/env bash\nkill -TERM $$\nsleep 5\n'     > "$FIXTURES/selfterm.sh"
# ~50ms, deliberately not ~0ms: elapsed_ms is integer-divided, so a trivial fixture
# yields 0 and `0 > 0` is false — a 0ms fixture would red against a CORRECT budget
# implementation.
printf '#!/usr/bin/env bash\nsleep 0.05\n'                 > "$FIXTURES/slow.sh"

# Build a sandbox copy of the runner. $1 = out path, $2 = arm (fixture set), $3 = mutation.
# Every anchor is asserted to occur exactly once, so a rename fails LOUDLY here rather than
# silently no-op'ing and leaving the arm to pass against an unmutated file.
build_sandbox() {
  local out="$1" arm="$2" mutation="$3"
  cp "$TARGET" "$out" || return 1
  # The sandbox RELOCATES test-all.sh, so anything it resolves via ${BASH_SOURCE[0]} must be
  # relocated with it. The ADR-179 relevance-predicate data file is sourced FAIL-CLOSED (a
  # missing one exits 2, because empty predicates would decline every gated suite while the
  # summary still read green), so without this copy every arm below measures that guard firing
  # instead of the classifier under test. Safe unconditionally: the AC8 baseline arm builds from
  # origin/main:scripts/test-all.sh, where the extra file is simply inert.
  mkdir -p "$(dirname "$out")/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$(dirname "$out")/lib/" || return 1
  python3 - "$out" "$arm" "$mutation" "$FIXTURES" <<'PY'
import sys, re
path, arm, mutation, fixtures = sys.argv[1:5]
s = open(path).read()

def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)

# 1. Replace the whole suite-registration region with fixture calls. run_suite, the
#    summary block and the exit block stay INTACT and under test — they are the subject.
start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1, "start anchor not unique"
assert s.count(end_anchor) == 1, "end anchor not unique"
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)

calls = {
    "killed_only": [("selfterm", "selfterm.sh")],
    # TWO killed suites, deliberately. Every other arm instantiates exactly one,
    # and 1-of-1 cannot distinguish `killed=$((killed + 1))` from `killed=1`:
    # a saturating counter passes a single-kill table in full. It is not cosmetic
    # — the terminal marker computes `suites - failed - killed`, so under a
    # saturating counter a run with N kills OVERSTATES the passed count by N-1,
    # in exactly the multi-kill (OOM sweep) scenario this class exists for.
    "killed_two":  [("selfterm1", "selfterm.sh"), ("selfterm2", "selfterm.sh")],
    "mixed":       [("assertfail", "assertfail.sh"), ("selfterm", "selfterm.sh")],
    "clean":       [("okfixture", "ok.sh")],
    "budget_hit":  [("budgetfixture", "slow.sh")],
    "budget_miss": [("budgetfixture", "slow.sh")],
    "budget_undeclared": [("undeclared-label", "slow.sh")],
}[arm]
body = "\n" + "".join(
    f'run_suite "{label}" bash "{fixtures}/{script}"\n' for label, script in calls
)
s = s[:i] + body + s[j:]

# 2. Neuter the advisory lock and the contention preamble. Parallel worktrees are this
#    repo's documented workflow, so a sandbox arm that took the REAL lock would block on
#    whatever else is running and the arm's runtime would depend on the machine. Neither
#    is part of what Part B asserts.
s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)

# 3. Arm-specific budget declaration. Injected into the case, not hand-written into the
#    sandbox, so the emitter under test is the real one.
if arm == "budget_hit":
    s = sub_once(s, '    *) return 0 ;;',
                 '    budgetfixture) printf \'1\\n\' ;;\n    *) return 0 ;;', 'budget case default')
elif arm == "budget_miss":
    s = sub_once(s, '    *) return 0 ;;',
                 '    budgetfixture) printf \'3600000\\n\' ;;\n    *) return 0 ;;', 'budget case default')

# 4. Mutations. Each one neuters exactly ONE guard, so the arm that reds identifies it.
if mutation == "classifier_failed":
    m = re.search(r'^suite_exit_class\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate suite_exit_class"
    s = s[:m.start()] + "suite_exit_class() { printf 'failed\\n'; }" + s[m.end():]
elif mutation == "classifier_weird":
    m = re.search(r'^suite_exit_class\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate suite_exit_class"
    s = s[:m.start()] + "suite_exit_class() { printf 'weird\\n'; }" + s[m.end():]
elif mutation == "no_exit3":
    s = sub_once(s, 'elif (( killed > 0 )); then\n  exit 3\n', '', 'exit-3 arm')
elif mutation == "classifier_weird_no_default":
    m = re.search(r'^suite_exit_class\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate suite_exit_class"
    s = s[:m.start()] + "suite_exit_class() { printf 'weird\\n'; }" + s[m.end():]
    m2 = re.search(r'\n    \*\)      echo "WARNING: suite_exit_class returned.*?failed \+ 1\)\) ;;', s, re.S)
    assert m2, "could not locate the *) default arm"
    s = s[:m2.start()] + s[m2.end():]
elif mutation == "classifier_aborts":
    m = re.search(r'^suite_exit_class\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate suite_exit_class"
    s = s[:m.start()] + "suite_exit_class() { return 7; }" + s[m.end():]
elif mutation != "none":
    raise AssertionError(f"unknown mutation {mutation}")

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Run one arm -> sets ARM_OUT, ARM_RC. Output is captured 2>&1 because [FAIL]/[KILLED]
# go to stderr and the monitor reads a merged stream.
run_arm() {
  local arm="$1" mutation="${2:-none}" timing="${3:-}"
  local sb="$TMP/runner-${arm}-${mutation}.sh"
  # Clear BEFORE the build. Every call site is `|| true`, so returning early on a build
  # failure would leave the previous arm's capture in place and the following assertions
  # would grep it — reporting a second, misleading verdict about the wrong arm.
  ARM_OUT=""; ARM_RC=-1
  build_sandbox "$sb" "$arm" "$mutation" >/dev/null || { fail "sandbox build failed: $arm/$mutation"; return 1; }
  # SOLEUR_SUBAGENT / SOLEUR_ALLOW_FULL_GATE cleared for hermeticity: test-all.sh exits 4 under
  # the first BEFORE any registration, so an inherited value makes every arm measure a refusal
  # rather than the classifier — and a fan-out agent is exactly the environment that sets it.
  ARM_OUT=$(cd "$REPO_ROOT" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            TEST_TIMING_LOG="$timing" TEST_GROUP=all timeout 120 bash "$sb" 2>&1)
  ARM_RC=$?
  return 0
}

# Indent every line of captured child-runner output before printing it. NOT cosmetic:
# main-health-monitor.yml runs `bash scripts/test-all.sh 2>&1 | tee -a /tmp/tests-output.txt`
# and then greps that file, so ANY column-0 [KILLED] line in it is indistinguishable from
# the runner's own marker. A raw dump here would make this suite, on the runs where it REDS,
# file an operator issue naming a suite called "selfterm" that does not exist.
dump() { sed 's/^/    /' <<<"$1"; }

# --- A1: killed-only ------------------------------------------------------------------------
TIMING="$TMP/timing-a1.tsv"; : > "$TIMING"
run_arm killed_only none "$TIMING" || true
A1_OUT="$ARM_OUT"; A1_RC="$ARM_RC"

killed_lines=$(grep -cE '^\[KILLED\] selfterm ' <<<"$A1_OUT" || true)
if [[ "$killed_lines" == "1" ]]; then
  pass "AC1 — exactly one [KILLED] line naming the terminated fixture"
else
  fail "AC1 — expected 1 '^[KILLED] selfterm ' line, found $killed_lines"; dump "$A1_OUT"
fi

if grep -qE '^\[FAIL\] selfterm' <<<"$A1_OUT"; then
  fail "AC1 — the terminated suite ALSO rendered as [FAIL]"
else
  pass "AC1 — the terminated suite did not render as [FAIL]"
fi

if grep -qE '^=== 1 suites: 0 passed, 0 failed, 1 killed \(unresolved' <<<"$A1_OUT"; then
  pass "AC2 — the breakdown line reports 1 killed and 0 failed"
else
  fail "AC2 — breakdown line absent or wrong"; dump "$A1_OUT"
fi

if grep -qE '^=== 0/1 suites passed ===$' <<<"$A1_OUT"; then
  pass "AC2 — the killed suite counts as neither passed nor failed in the terminal marker"
else
  fail "AC2 — terminal marker did not read 0/1"; dump "$A1_OUT"
fi

if [[ "$A1_RC" == "3" ]]; then
  pass "AC3 — killed-only exits 3 (non-zero: NOT green)"
else
  fail "AC3 — killed-only exited $A1_RC, expected 3"
fi

# AC8b: the LAST ===-prefixed line must be the terminal marker, not the breakdown.
# `|| true`: no match is a normal answer here (it means the runner emitted no
# ===-line at all), and the assertion below distinguishes that from a wrong one.
last_eq=$(grep -E '^===' <<<"$A1_OUT" | tail -1 || true)
if [[ "$last_eq" =~ ^===\ [0-9]+/[0-9]+\ suites\ passed\ ===$ ]]; then
  pass "AC8b — the last ===-prefixed line is the terminal marker, not the breakdown"
else
  fail "AC8b — last ===-line was '$last_eq'"
fi

# AC20: the timing log's field 3 carries the class.
if grep -qE $'^selfterm\t[0-9]+\tKILLED' "$TIMING"; then
  pass "AC20 — TEST_TIMING_LOG field 3 records KILLED"
else
  fail "AC20 — no '<label>\\t<ms>\\tKILLED' record in the timing log"; dump "$(cat "$TIMING")"
fi

# The rendered line must state the ambiguity rather than name a cause.
if grep -qE '^\[KILLED\].*UNRESOLVED, not a failure' <<<"$A1_OUT" \
   && grep -qE '^\[KILLED\].*did not measure what terminated it' <<<"$A1_OUT"; then
  pass "the [KILLED] line states it is unresolved and names no cause"
else
  fail "the [KILLED] line does not carry the unresolved/no-cause wording"
fi

# --- A1c: EMITTER <-> CONSUMER parity -------------------------------------------------------
# The [KILLED] line's shape is asserted in two places that cannot see each other: the runner
# emits it, and main-health-monitor.yml greps it to decide whether a terminated suite gets
# named in the ci/main-broken issue. Nothing derived one from the other, so reformatting the
# parenthetical shipped a fully green suite while the monitor went permanently blind — every
# terminated suite silently routed to the generic "did not complete" arm, whose actions tell
# the operator to find the bad commit and revert it.
#
# This is not hypothetical: it happened while FIXING this file. A budget note was appended
# inside the parens, all assertions stayed green, and the monitor stopped matching.
#
# So: extract the consumer's regex from the workflow and run it against the line the runner
# actually emitted in A1. No hand-copied fixture — a copy drifts the same way the original did.
MHM_WF="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
if [[ -r "$MHM_WF" ]]; then
  killed_re=$(grep -oE "\^\\\\\[KILLED\\\\\][^']*ms\\\\\)" "$MHM_WF" | head -1 || true)
  if [[ -n "$killed_re" ]]; then
    pass "A1c — extracted the monitor's [KILLED] regex from the workflow"
    emitted=$(grep -E '^\[KILLED\] selfterm ' <<<"$A1_OUT" | head -1 || true)
    if [[ -n "$emitted" ]] && grep -qE "$killed_re" <<<"$emitted"; then
      pass "A1c — the monitor's own regex matches the line the runner actually emitted"
    else
      fail "A1c — EMITTER/CONSUMER DRIFT: the monitor's regex does not match the emitted [KILLED] line"
      dump "regex:   $killed_re"
      dump "emitted: $emitted"
    fi
    # Non-vacuity: the regex must be capable of rejecting something.
    if grep -qE "$killed_re" <<<'[KILLED] nope' ; then
      fail "A1c — the extracted regex matches a malformed line; it pins nothing"
    else
      pass "A1c — the extracted regex rejects a malformed [KILLED] line (non-vacuous)"
    fi
  else
    fail "A1c — could not extract the monitor's [KILLED] regex; the parity check did not run"
  fi
else
  fail "A1c — main-health-monitor.yml unreadable; the parity check did not run"
fi

# --- A1b: TWO killed suites — the counter must ACCUMULATE, not saturate ---------------------
run_arm killed_two none || true
k2=$(grep -cE '^\[KILLED\] selfterm[12] ' <<<"$ARM_OUT" || true)
if [[ "$k2" == "2" ]]; then
  pass "AC2/A1b — both terminated suites render their own [KILLED] line"
else
  fail "AC2/A1b — expected 2 '^[KILLED] selfterm[12] ' lines, found $k2"; dump "$ARM_OUT"
fi
if grep -qE '^=== 2 suites: 0 passed, 0 failed, 2 killed \(unresolved' <<<"$ARM_OUT"; then
  pass "AC2/A1b — the breakdown line accumulates to 2 killed"
else
  fail "AC2/A1b — breakdown did not report 2 killed (a saturating counter reports 1)"; dump "$ARM_OUT"
fi
if grep -qE '^=== 0/2 suites passed ===$' <<<"$ARM_OUT"; then
  pass "AC2/A1b — the terminal marker does not overstate the passed count"
else
  fail "AC2/A1b — terminal marker wrong; a saturating counter would read 1/2"; dump "$ARM_OUT"
fi
if [[ "$ARM_RC" == "3" ]]; then
  pass "AC3/A1b — a multi-kill run still exits 3"
else
  fail "AC3/A1b — exited $ARM_RC, expected 3"
fi

# --- A2: mixed — failure dominates ----------------------------------------------------------
run_arm mixed none || true
if grep -qE '^\[FAIL\] assertfail ' <<<"$ARM_OUT" && grep -qE '^\[KILLED\] selfterm ' <<<"$ARM_OUT"; then
  pass "AC4 — a mixed run emits BOTH markers"
else
  fail "AC4 — mixed run did not emit both markers"; dump "$ARM_OUT"
fi
if [[ "$ARM_RC" == "1" ]]; then
  pass "AC4 — failure dominates: mixed run exits 1, not 3"
else
  fail "AC4 — mixed run exited $ARM_RC, expected 1"
fi
# AC9, asserted from EMITTED OUTPUT rather than a source grep: a source grep is the
# spelling-assertion anti-pattern — it passes against any file that merely mentions the token.
if grep -qE '^\[FAIL\] assertfail \([0-9]+ms\)$' <<<"$ARM_OUT"; then
  pass "AC9 — the [FAIL] line's byte shape is unchanged"
else
  fail "AC9 — [FAIL] line shape drifted"; dump "$ARM_OUT"
fi

# --- A3: clean run is byte-identical to main ------------------------------------------------
run_arm clean none || true
A3_OUT="$ARM_OUT"; A3_RC="$ARM_RC"
if [[ "$A3_RC" == "0" ]]; then
  pass "a clean run still exits 0"
else
  fail "clean run exited $A3_RC, expected 0"; dump "$A3_OUT"
fi
if grep -qE '^\[ok\] okfixture \([0-9]+ms\)$' <<<"$A3_OUT"; then
  pass "AC9 — the [ok] line's byte shape is unchanged"
else
  fail "AC9 — [ok] line shape drifted"; dump "$A3_OUT"
fi
if grep -qE '^=== [0-9]+ suites: ' <<<"$A3_OUT"; then
  fail "AC8 — the breakdown line leaked onto a run with zero killed suites"
else
  pass "AC8 — no breakdown line when killed == 0"
fi

# AC8 proper: diff this arm's tail against the SAME tail produced by origin/main's runner
# through the SAME sandbox. The tail starts AT the terminal marker so tc_epilogue's
# nondeterministic scratch sample is excluded.
MAIN_TARGET="$TMP/test-all-main.sh"
if git -C "$REPO_ROOT" show origin/main:scripts/test-all.sh > "$MAIN_TARGET" 2>/dev/null && [[ -s "$MAIN_TARGET" ]]; then
  pass "origin/main:scripts/test-all.sh resolved for the byte-shape baseline"
  sb_main="$TMP/runner-clean-mainbaseline.sh"
  if TARGET="$MAIN_TARGET" build_sandbox "$sb_main" clean none >/dev/null; then
    MAIN_OUT=$(cd "$REPO_ROOT" && TEST_GROUP=all timeout 120 bash "$sb_main" 2>&1) || true
    tail_of() { sed -n '/^=== [0-9]*\/[0-9]* suites passed ===$/,$p' <<<"$1"; }
    main_tail=$(tail_of "$MAIN_OUT")
    new_tail=$(tail_of "$A3_OUT")
    # Assert the baseline is non-empty and marker-bearing BEFORE diffing — otherwise an
    # empty-vs-empty comparison passes and certifies nothing.
    if [[ -n "$main_tail" ]] && grep -qE '^=== [0-9]+/[0-9]+ suites passed ===$' <<<"$main_tail"; then
      pass "AC8 — the main-side baseline tail is non-empty and marker-bearing"
      if [[ "$main_tail" == "$new_tail" ]]; then
        pass "AC8 — clean-run tail is byte-identical to origin/main's"
      else
        fail "AC8 — clean-run tail DIFFERS from origin/main's"
        dump "$(diff <(printf '%s\n' "$main_tail") <(printf '%s\n' "$new_tail") || true)"
      fi
    else
      fail "AC8 — the main-side baseline tail is empty or carries no terminal marker"
    fi
  else
    fail "AC8 — could not build the main-side baseline sandbox"
  fi
else
  # A hard fail, never a skip: silently skipping would let the byte-shape guarantee lapse
  # exactly when the comparison stops working.
  fail "AC8 — could not resolve origin/main:scripts/test-all.sh for the baseline"
fi

# --- A5: mutation control — classifier always says `failed` ---------------------------------
run_arm killed_only classifier_failed || true
if grep -qE '^\[KILLED\] selfterm ' <<<"$ARM_OUT"; then
  fail "AC7/A5 — the mutant still emitted [KILLED]; the mutation did not land"
else
  pass "AC7/A5 — with the classifier forced to 'failed', no [KILLED] line is emitted (A1 would RED)"
fi
if [[ "$ARM_RC" == "1" ]]; then
  pass "AC7/A5 — the mutant exits 1, so A1's exit-3 assertion would RED"
else
  fail "AC7/A5 — mutant exited $ARM_RC, expected 1"
fi

# --- A7: mutation control — the exit-3 arm deleted ------------------------------------------
# This is the REAL false green. Plan v2 specified this mutation as "remove the killed) case
# arm", which does not work: with killed) gone the class falls to the fail-closed *) arm,
# which counts it FAILED and exits 1 — the mutant is caught for a reason the arm does not
# describe, so it would have proved nothing. The false green lives in the EXIT block.
run_arm killed_only no_exit3 || true
if [[ "$ARM_RC" == "0" ]]; then
  pass "AC7/A7 — deleting the exit-3 arm makes a killed-only run exit 0 (AC3 would RED)"
else
  fail "AC7/A7 — mutant exited $ARM_RC, expected 0; the mutation did not produce the false green"
fi
if grep -qE '^\[KILLED\] selfterm ' <<<"$ARM_OUT"; then
  pass "AC7/A7 — the mutant still RENDERS [KILLED], so only the exit contract regressed"
else
  fail "AC7/A7 — the mutant lost the marker too; the mutation was not isolated"
fi

# --- A8: an unrecognized class fails CLOSED -------------------------------------------------
run_arm killed_only classifier_weird || true
if grep -qE 'WARNING: suite_exit_class returned unrecognized class' <<<"$ARM_OUT"; then
  pass "T8b/A8 — an unrecognized class emits the WARNING"
else
  fail "T8b/A8 — no WARNING for an unrecognized class"; dump "$ARM_OUT"
fi
if [[ "$ARM_RC" == "1" ]]; then
  pass "T8b/A8 — an unrecognized class is counted FAILED and exits 1, never passed"
else
  fail "T8b/A8 — exited $ARM_RC, expected 1"
fi

# --- A8-control: the *) default arm deleted -------------------------------------------------
# Without this pair, the flagship "a false green a grep would never see" is pinned by nothing
# executed: a grep cannot establish a negative existential over control flow.
run_arm killed_only classifier_weird_no_default || true
if [[ "$ARM_RC" == "0" ]]; then
  pass "AC7/A8-control — deleting the *) arm makes an unrecognized class exit 0 (A8 would RED)"
else
  fail "AC7/A8-control — mutant exited $ARM_RC, expected 0"
fi
if grep -qE '^=== 1/1 suites passed ===$' <<<"$ARM_OUT"; then
  pass "AC7/A8-control — the mutant counts the unclassified suite as PASSED, naming the defect"
else
  fail "AC7/A8-control — expected the mutant to report 1/1 passed"; dump "$ARM_OUT"
fi

# --- T8c: a classifier that ABORTS is loud, not silently bucketed ---------------------------
# The plan prescribed `status="$(suite_exit_class …)" || status="failed"`, which contradicts
# its own T8c: an aborting classifier would land in the ordinary `failed` bucket with no
# warning, making a BROKEN CLASSIFIER — which can mis-bucket every subsequent suite —
# indistinguishable from one honest test failure.
run_arm killed_only classifier_aborts || true
if grep -qE 'WARNING: suite_exit_class .*classifier exit=7' <<<"$ARM_OUT"; then
  pass "T8c — an aborting classifier emits a WARNING naming the classifier and its exit"
else
  fail "T8c — an aborting classifier was absorbed silently"; dump "$ARM_OUT"
fi
if [[ "$ARM_RC" == "1" ]]; then
  pass "T8c — an aborting classifier is counted FAILED and exits 1, never passed"
else
  fail "T8c — exited $ARM_RC, expected 1"
fi
if grep -qE '^=== 0/1 suites passed ===$' <<<"$ARM_OUT"; then
  pass "T8c — the suite is not counted as passed when the classifier aborts"
else
  fail "T8c — expected 0/1 passed"; dump "$ARM_OUT"
fi

# --- A9: this suite's own output cannot be mistaken for the runner's -------------------------
# A1_OUT definitely carries a column-0 [KILLED] line. Push it through the dump helper and
# assert nothing survives at column 0.
dumped=$(dump "$A1_OUT")
stray=$(grep -cE '^(\[KILLED\]|\[FAIL\]|\[ok\]|=== [0-9]+/[0-9]+ suites passed ===$)' <<<"$dumped" || true)
if [[ "$stray" == "0" ]]; then
  pass "AC22/A9 — dumped child-runner output carries no column-0 runner markers"
else
  fail "AC22/A9 — $stray column-0 runner-marker line(s) survived the dump indent"
fi

# --- Budgets (T14 / T14b / T14c) ------------------------------------------------------------
run_arm budget_hit none || true
if grep -qE '^\[budget\] budgetfixture ran [0-9]+ms against its declared 1ms budget' <<<"$ARM_OUT"; then
  pass "T14 — an exceeded budget emits the advisory [budget] line"
else
  fail "T14 — no [budget] line for a fixture that exceeded its declared budget"; dump "$ARM_OUT"
fi
budget_ms=$(grep -oE '^\[budget\] budgetfixture ran [0-9]+ms' <<<"$ARM_OUT" | grep -oE '[0-9]+ms$' | tr -d 'ms' || true)
if [[ -n "$budget_ms" ]] && (( budget_ms >= 40 )); then
  pass "T14 — the reported elapsed (${budget_ms}ms) is a real measurement, not 0"
else
  fail "T14 — reported elapsed was '$budget_ms', expected >= 40"
fi
if [[ "$ARM_RC" == "0" ]]; then
  pass "T14 — a budget overrun does NOT change status or exit code"
else
  fail "T14 — budget overrun changed the exit code to $ARM_RC"
fi

run_arm budget_miss none || true
if grep -qE '^\[budget\]' <<<"$ARM_OUT"; then
  fail "T14b — a [budget] line fired for a suite well inside its budget"
else
  pass "T14b — no [budget] line when the suite is inside its declared budget"
fi

run_arm budget_undeclared none || true
if grep -qE '^\[budget\]' <<<"$ARM_OUT"; then
  fail "T14c — a [budget] line fired for a label with no declared budget"
else
  pass "T14c — no [budget] line for an undeclared label"
fi

# --- F6: every DECLARED budget label must be a label the runner actually uses ---------------
# `_suite_budget_ms` keys on the run_suite label string, 500+ lines away from the registration.
# Renaming the registration leaves `bash -n` clean, `lint-orphan-test-suites.sh` green and all
# other assertions passing, while the incident-motivated budget can never fire again — the
# advisory silently evaporates and nothing says so.
# Anchored on the case-arm CONSTRUCT (`<label>) printf`), not on any line containing a
# `)`. The first draft of this extraction matched a rationale COMMENT carrying
# "(TEST_TIMING_LOG)" and reported a false finding — the same body-grep-sees-comments
# class this suite exists to keep out of the runner. Comments are stripped first.
_budget_labels=$(sed -n '/^_suite_budget_ms() {/,/^}/p' "$TARGET" \
  | sed 's/[[:space:]]*#.*$//' \
  | grep -oE '^[[:space:]]*[^[:space:]]+\) printf' \
  | sed 's/) printf$//' | tr -d ' ' || true)
if [[ -z "$_budget_labels" ]]; then
  pass "F6: no declared budgets to reconcile"
else
  _bad=0
  while IFS= read -r _bl; do
    [[ -z "$_bl" ]] && continue
    grep -qE "^[[:space:]]*run_suite \"${_bl//\//\\/}\"" "$TARGET" || { _bad=$((_bad+1)); echo "    unmatched budget label: $_bl"; }
  done <<< "$_budget_labels"
  if [[ "$_bad" == "0" ]]; then
    pass "F6: every declared budget label matches a registered run_suite label"
  else
    fail "F6: $_bad declared budget label(s) match no run_suite registration — the budget can never fire"
  fi
fi

# --- Positive control: can this file REPORT a failure at all? --------------------------------
# The floor below counts PASS+FAIL, both of which are produced BY the helpers. So neutering
# `fail()` to a no-op costs only the delta between the floor and the real count — and with
# slack in the floor, an SUT mutation worth fewer assertions than that slack goes green.
# Measured before this control existed: `fail() { :; }` plus rewording the [KILLED] line to
# say the suite "FAILED and was terminated" reported 61 passed / 0 failed, exit 0 — the exact
# misreading this entire PR exists to eliminate, certified green by the suite that pins it.
# This control exercises both counters directly and exits non-zero itself, bypassing `fail()`.
_pc_pass_before="$PASS"; _pc_fail_before="$FAIL"
# A BRACE GROUP with a redirect, not `$( )`: command substitution runs in a SUBSHELL and the
# counter increments would be discarded, so the control would silently measure nothing — the
# very class it exists to catch. The redirect keeps the probe's own PASS/FAIL text out of the
# log, where a literal "FAIL:" line would read as a real failure to a human scanning output.
{ pass "positive-control probe"; fail "positive-control probe"; } >/dev/null 2>&1
if [[ "$PASS" -eq $((_pc_pass_before + 1)) && "$FAIL" -eq $((_pc_fail_before + 1)) ]]; then
  PASS="$_pc_pass_before"; FAIL="$_pc_fail_before"   # retract both; totals below stay honest
  echo "  [control] pass() and fail() both move their counters — failures are reportable"
else
  echo "FATAL: the assertion helpers do not move their counters — every verdict in this file is void." >&2
  exit 1
fi

# --- Anti-vacuity floor ---------------------------------------------------------------------
# Every assertion above is emitted from a helper. Strand the block — an early exit, a renamed
# TARGET, an extraction that silently produced nothing — and this file would report
# "0 passed, 0 failed / exit 0", which reads exactly like a clean run. A FLOOR, not equality:
# the count is developer-incremented and `-eq` turns every added assertion into a false red.
# Set to the CURRENT count, not a round number below it: slack in this floor is exactly the
# budget a neutered dispatcher has to work with (#7220's class).
MIN_ASSERTIONS=70
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "test-all-killed-classification.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
