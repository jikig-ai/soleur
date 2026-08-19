#!/usr/bin/env bash
# Regression suite for Item 6 of the 2026-08-11 test-pipeline post-mortem: spawned subagents
# must not run a full-gate runner.
#
# WHY THIS EXISTS. Three review agents running lints and suites concurrently inflated a
# measurement of the registry mutation battery by 1.9x (860 s -> 1675 s). The battery did not
# get slower; the machine did. A timing figure taken under that contention is not a measurement
# of the code, and the whole point of the work this suite ships alongside is to decide what to
# gate on measured suite cost.
#
# WHY THE BEHAVIOURAL ARM IS LOAD-BEARING. The obvious fix is a paragraph in the fan-out
# instructions telling agents not to do it. That paragraph IS agent discretion — a grep
# asserting it exists certifies the instruction was WRITTEN, never that it was obeyed. So the
# mechanical refusal is the actual guard and the prose is the explanation, and this suite
# asserts both, in that order of importance.
#
# HOW IT TESTS. `run_suite` is replaced with a RECORDER in a sandbox copy of test-all.sh (the
# same technique scripts/test-all-infra-coverage-notice.test.sh uses), so a full "run" costs
# milliseconds and the assertions are about what the runner DECIDED. The refusal arm asserts
# ZERO suites were recorded — that is what distinguishes "refused before doing any work" from
# "ran everything and then complained", and only the former protects the measurement.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Overridable so the suite can be pointed at an older or mutated copy and PROVED to red against
# it. A guard that has never been shown to fail is not evidence.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
WORK_SKILL="$REPO_ROOT/plugins/soleur/skills/work/SKILL.md"
REVIEW_SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# Build a sandbox copy of test-all.sh whose run_suite records instead of running, and whose
# contention hooks are stubbed. Stubbing tc_acquire is not cosmetic: it takes a 900 s flock, so
# an unstubbed sandbox would block this suite behind whatever else is running on the machine —
# the exact class of cross-session interference this file exists to stop.
build_sandbox() {
  local out="$1"
  cp "$TARGET" "$out" || return 1
  # The sandbox RELOCATES test-all.sh, so anything it resolves via ${BASH_SOURCE[0]} must be
  # relocated with it. The relevance-predicate data file is sourced fail-CLOSED (a missing one
  # exits 2 rather than declining every gated suite behind a green summary), so without this
  # copy every arm below would measure that guard firing instead of the refusal under test.
  mkdir -p "$(dirname "$out")/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$(dirname "$out")/lib/" || return 1
  # test-contention.sh must be relocated too. Without it test-all.sh finds no lib, installs its
  # no-op stubs (tc_preamble() { :; }), and TC_SIBLING_RUN_COUNT is never exported — so the
  # sibling refusal (#7553) could not fire and every arm asserting it would measure the stub
  # rather than the guard. That is the fail-open this suite exists to prevent, one level up.
  cp "$REPO_ROOT/scripts/lib/test-contention.sh" "$(dirname "$out")/lib/" || return 1
  python3 - "$out" <<'PY' || exit 2
import re, sys
path = sys.argv[1]
s = open(path).read()

m = re.search(r'^run_suite\(\) \{.*?^\}', s, re.S | re.M)
assert m, "could not locate run_suite() definition"
s = s[:m.start()] + 'run_suite() { echo "RECORDED_SUITE:$1" >> "$SANDBOX_RECORD"; }' + s[m.end():]

# Neuter tc_acquire only. tc_preamble USED to be neutered here too, and that made the sibling
# refusal (#7553) structurally untestable: tc_preamble is what resolves the sibling count and
# exports TC_SIBLING_RUN_COUNT, so stubbing it meant the refusal could never fire and any arm
# asserting it fires would have been measuring the stub. Determinism is preserved a better way --
# run_arm pins TC_PROC_ROOT at a SYNTHETIC procfs for every arm, so tc_preamble reads a fixture
# rather than the machine, and a sibling worktree running its own battery cannot flip these arms.
for call in ('tc_acquire "test-all"\n',):
    assert s.count(call) == 1, f"expected exactly one {call!r}, found {s.count(call)}"
    s = s.replace(call, ':\n')

open(path, 'w').write(s)
PY
}

SANDBOX="$TMP/test-all-sandbox.sh"
build_sandbox "$SANDBOX" || { echo "FATAL: sandbox build failed" >&2; exit 2; }

CLK_TCK_F=$(getconf CLK_TCK 2>/dev/null || echo 100)
make_fake_proc_f() { # <root> <pid> <cwd> <elapsed_s> <cmd>
  local root="$1" pid="$2" cwd="$3" elapsed_s="$4" cmd="$5" uptime=100000 i filler
  local starttime=$(( (uptime - elapsed_s) * CLK_TCK_F ))
  mkdir -p "$root/$pid"
  printf '%s 0.00\n' "$uptime" > "$root/uptime"
  printf '%s\0%s\0' "bash" "$cmd" > "$root/$pid/cmdline"
  filler="S 0 0"
  for (( i = 4; i <= 19; i++ )); do filler+=" 0"; done
  printf '%s (te) st) %s %s 0 0\n' "$pid" "$filler" "$starttime" > "$root/$pid/stat"
  [[ -n "$cwd" ]] && ln -sfn "$cwd" "$root/$pid/cwd"
  printf 'MemAvailable:    7000000 kB\n' > "$root/meminfo"
  printf '3.96 9.72 14.60 2/2934 572235\n' > "$root/loadavg"
}

SIB_WT_F="$TMP/worktrees/feat-a-sibling-worktree"; mkdir -p "$SIB_WT_F"
SIB_PROC_F="$TMP/proc-with-sibling"
make_fake_proc_f "$SIB_PROC_F" 424242 "$SIB_WT_F" 620 "scripts/test-all.sh"

# An EMPTY procfs: uptime/meminfo/loadavg present, no processes. The negative control.
SOLO_PROC_F="$TMP/proc-solo"; mkdir -p "$SOLO_PROC_F"
printf '100000 0.00\n' > "$SOLO_PROC_F/uptime"
printf 'MemAvailable:    7000000 kB\n' > "$SOLO_PROC_F/meminfo"
printf '3.96 9.72 14.60 2/2934 572235\n' > "$SOLO_PROC_F/loadavg"

# Run the sandbox under a given environment. $1 = arm label; remaining args are VAR=VALUE pairs.
# Sets ARM_OUT / ARM_RC / ARM_SUITES.
run_arm() {
  local label="$1"; shift
  export SANDBOX_RECORD="$TMP/record-$label.txt"
  : > "$SANDBOX_RECORD"
  # Both refusal variables are CLEARED before "$@", so an arm that wants either still wins.
  # An INHERITED SOLEUR_ALLOW_FULL_GATE=1 would make the refusal arm pass vacuously, and an
  # inherited SOLEUR_SUBAGENT=1 would break the negative control -- and the environment that
  # sets these is precisely a spawned-agent shell, i.e. the one this suite exists to describe.
  # TEST_TIMING_LOG redirected per-arm, never inherited: skip_suite and the run-boundary bytes
  # probe append to whatever it names, so an inherited path puts this suite's sandbox rows into
  # the operator's real timing log -- the artifact a gate run's measurement is read from.
  ARM_OUT=$(cd "$REPO_ROOT" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            TEST_TIMING_LOG="$TMP/arm-timing-$label.tsv" \
            TC_PROC_ROOT="$SOLO_PROC_F" \
            "$@" timeout 120 bash "$SANDBOX" 2>&1)
  ARM_RC=$?
  ARM_SUITES=$(wc -l < "$SANDBOX_RECORD" | tr -d '[:space:]')
}

echo "=== fan-out suite-scope suite ==="

# --- Arm 1: the refusal fires, and fires BEFORE any work ------------------------------------
run_arm refuse SOLEUR_SUBAGENT=1
# rc 3 exactly, not merely non-zero: 1 is an ordinary suite failure and 2 is a bad TEST_GROUP,
# Each code is a distinct claim: 1 = a suite failed, 2 = a bad TEST_GROUP, 3 = a suite was
# TERMINATED (#7424 -- unresolved, coverage not obtained), 4 = refused before anything ran.
# A wrapper, CI step or agent branching on the code cannot tell a refusal from a genuine RED --
# or, worse, from a killed suite -- unless the value is pinned, and swapping `exit 4` for any
# of the others satisfies a `-ne 0` assertion while destroying that distinction.
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "SOLEUR_SUBAGENT=1 makes a full-gate invocation exit 4 (the refusal code)"
else
  fail "SOLEUR_SUBAGENT=1 did not refuse with rc=4 — got rc=$ARM_RC"
fi
if [[ "$ARM_SUITES" -eq 0 ]]; then
  pass "the refusal happens before any suite runs (0 suites recorded)"
else
  fail "refused only AFTER running $ARM_SUITES suites — the contention was already paid"
fi
# Naming the alternative is the difference between a block and a dead end. An agent that is
# refused without being told what to run instead will either re-run with the escape hatch or
# skip testing entirely, and both are worse than the thing being prevented.
if grep -qF 'SOLEUR_SUBAGENT' <<<"$ARM_OUT"; then
  pass "the refusal names the variable that caused it"
else
  fail "the refusal does not name SOLEUR_SUBAGENT, so its cause is unresolvable"
fi
if grep -qF 'targeting the files' <<<"$ARM_OUT"; then
  pass "the refusal names the targeted-suite alternative"
else
  fail "the refusal does not name the targeted-suite alternative"
fi
if grep -qF 'SOLEUR_ALLOW_FULL_GATE=1' <<<"$ARM_OUT"; then
  pass "the refusal names its escape hatch"
else
  fail "the refusal does not name an escape hatch"
fi

# --- Arm 2: negative control — without the variable, nothing changes -------------------------
# Without this arm the refusal could be unconditional and every assertion above would still
# pass. This is the arm that distinguishes a gate from a wall.
run_arm normal SOLEUR_SUBAGENT=
if [[ "$ARM_RC" -eq 0 ]]; then
  pass "an ordinary invocation is unaffected (rc=0)"
else
  fail "an ordinary invocation now fails (rc=$ARM_RC) — the refusal is unconditional"
fi
if [[ "$ARM_SUITES" -gt 0 ]]; then
  pass "an ordinary invocation still reaches its suites ($ARM_SUITES recorded)"
else
  fail "an ordinary invocation recorded no suites — the runner is broken, not gated"
fi
if grep -qF 'SOLEUR_ALLOW_FULL_GATE=1' <<<"$ARM_OUT"; then
  fail "the refusal text prints on a run that was never refused"
else
  pass "the refusal text is absent when the refusal did not fire"
fi

# --- Arm 3: the escape hatch actually escapes ------------------------------------------------
# A refusal with no documented override gets worked around by unsetting the variable, which
# removes the signal entirely. An explicit hatch keeps the override visible in the command line.
run_arm hatch SOLEUR_SUBAGENT=1 SOLEUR_ALLOW_FULL_GATE=1
if [[ "$ARM_RC" -eq 0 && "$ARM_SUITES" -gt 0 ]]; then
  pass "SOLEUR_ALLOW_FULL_GATE=1 overrides the refusal (rc=$ARM_RC, $ARM_SUITES suites)"
else
  fail "the escape hatch does not work (rc=$ARM_RC, $ARM_SUITES suites)"
fi

# --- Arm 4: the prose half, in both fan-out skills -------------------------------------------
# Anchored on a phrase that spans NO punctuation boundary, so a future reflow of the paragraph
# cannot silently break the assertion and leave it passing over a clause that no longer says
# what it said. A bare token like "SOLEUR_SUBAGENT" would match this suite's own name in a
# nearby sentence; the full clause cannot be produced by accident.
CLAUSE_ANCHOR='run only the suites targeting the files they were given'
for skill in "$WORK_SKILL" "$REVIEW_SKILL"; do
  rel="${skill#"$REPO_ROOT"/}"
  if [[ ! -f "$skill" ]]; then
    fail "$rel does not exist"
    continue
  fi
  if grep -qF "$CLAUSE_ANCHOR" "$skill"; then
    pass "$rel carries the fan-out scope clause"
  else
    fail "$rel is missing the fan-out scope clause"
  fi
  # This asserted `$rel tells the lead to export SOLEUR_SUBAGENT=1` while matching prose that
  # said the HARNESS sets it — describing an instruction the matched text did not contain, and
  # standing behind a claim it did not test (#7553). What is actually true, and all this grep can
  # establish, is that the file NAMES the variable. Assert that, and separately assert the file
  # does not re-assert the falsehood.
  if grep -qF 'SOLEUR_SUBAGENT' "$skill"; then
    pass "$rel names SOLEUR_SUBAGENT (the convention a lead may export)"
  else
    fail "$rel does not name SOLEUR_SUBAGENT at all"
  fi
  # The regression guard for the correction itself. Nothing in this repo sets SOLEUR_SUBAGENT on
  # a spawn path, so a file claiming the harness does is false — and it is a claim a future edit
  # can plausibly reintroduce, because it reads like a description of a mechanism that exists.
  if grep -qF 'are spawned with' "$skill"; then
    fail "$rel re-asserts that the harness SETS SOLEUR_SUBAGENT — measured false; no spawn path sets it"
  else
    pass "$rel does not claim the harness sets SOLEUR_SUBAGENT"
  fi
done

# --- Arms 4-7: the SIBLING refusal (#7553) --------------------------------------------------
#
# Arms 1-3 above cover the DECLARED antecedent (SOLEUR_SUBAGENT). Nothing in this repo sets that
# variable, so its refusal only fires when someone exports it deliberately. These arms cover the
# MEASURED antecedent: test-all.sh refuses when tc_preamble has already resolved that another
# worktree is running the full gate. That condition needs no spawn-path cooperation, which is why
# it is the one CI can actually exercise -- these arms need no spawned agent at all.
#
# The sibling is SYNTHESIZED via a fake procfs (cq-test-fixtures-synthesized-only), the same
# fixture shape scripts/test-contention.test.sh uses. TC_SELF_PID is left at its default so it
# names no entry in the fake tree, which disables self-exclusion -- exactly the synthetic-self
# path the library documents.

# --- Arm 4: a measured sibling refuses, before any work -------------------------------------
run_arm sibling-refuse TC_PROC_ROOT="$SIB_PROC_F"
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "a measured sibling full-gate run makes a full-gate invocation exit 4"
else
  fail "sibling present did not refuse with rc=4 — got rc=$ARM_RC"
fi
if [[ "$ARM_SUITES" -eq 0 ]]; then
  pass "the sibling refusal happens before any suite runs (0 suites recorded)"
else
  fail "refused only AFTER running $ARM_SUITES suites — the contention was already paid"
fi
# The refusal must fire BEFORE tc_acquire. Refusing after it would make a run that should never
# have started wait up to TC_LOCK_TIMEOUT (900 s) to be told so, and take the advisory lock a
# legitimate sibling is queued on.
#
# Asserted STRUCTURALLY, on source order in the real file — NOT by grepping the arm's output for a
# lock line. That was the first form and it was VACUOUS: build_sandbox neuters `tc_acquire` to `:`,
# so no lock line can ever appear in any arm's output and the assertion could not fail. Measured —
# relocating the refusal to AFTER tc_acquire left this suite at 24 passed, 0 failed. A guard that
# cannot be driven red is exactly what this PR exists to remove, so it is not shipped in one.
REFUSAL_LN=$(grep -n 'TC_SIBLING_RUN_COUNT:-0' "$TARGET" | head -1 | cut -d: -f1)
ACQUIRE_LN=$(grep -n '^tc_acquire "test-all"' "$TARGET" | head -1 | cut -d: -f1)
if [[ -z "$REFUSAL_LN" || -z "$ACQUIRE_LN" ]]; then
  fail "could not locate the sibling refusal and/or tc_acquire in $TARGET (refusal=${REFUSAL_LN:-none} acquire=${ACQUIRE_LN:-none})"
elif [[ "$REFUSAL_LN" -lt "$ACQUIRE_LN" ]]; then
  pass "the sibling refusal precedes tc_acquire in test-all.sh (line $REFUSAL_LN < $ACQUIRE_LN)"
else
  fail "the sibling refusal sits at line $REFUSAL_LN, AFTER tc_acquire at $ACQUIRE_LN — a refused run would queue up to TC_LOCK_TIMEOUT and take the lock a legitimate sibling is waiting on"
fi
if grep -qF 'sibling' <<<"$ARM_OUT"; then
  pass "the sibling refusal names its cause"
else
  fail "the sibling refusal does not say a sibling caused it, so a false positive is a mystery"
fi

# --- Arm 5: the sanctioned override is not collateral ---------------------------------------
# lefthook's pre-commit hook and the Grok pre-push gate both invoke the full gate deliberately and
# both carry this hatch. If it stopped working, a spawned agent could not commit a .ts file while
# any sibling ran -- the blast radius that disqualified the harness-identity design (#7553).
run_arm sibling-hatch TC_PROC_ROOT="$SIB_PROC_F" SOLEUR_ALLOW_FULL_GATE=1
if [[ "$ARM_RC" -ne 4 ]]; then
  pass "SOLEUR_ALLOW_FULL_GATE=1 overrides the sibling refusal (rc=$ARM_RC)"
else
  fail "the hatch did not override the sibling refusal — the sanctioned gate run is collateral"
fi
if [[ "$ARM_SUITES" -gt 0 ]]; then
  pass "the hatched run reaches suite registration ($ARM_SUITES suites)"
else
  fail "the hatched run recorded 0 suites — it was blocked by something"
fi

# --- Arm 6: the SOLO path is untouched (the highest-cost false positive) ---------------------
run_arm sibling-solo TC_PROC_ROOT="$SOLO_PROC_F"
if [[ "$ARM_RC" -ne 4 ]]; then
  pass "no sibling and no hatch does NOT refuse — the ordinary local run is unaffected"
else
  fail "refused with NO sibling present — this would break every solo run of the gate"
fi
if [[ "$ARM_SUITES" -gt 0 ]]; then
  pass "the solo run reaches suite registration ($ARM_SUITES suites)"
else
  fail "the solo run recorded 0 suites"
fi

# --- Arm 7: the two refusals are ADDITIVE, not a swap ----------------------------------------
# Arm 1 proves SOLEUR_SUBAGENT still refuses on its own. This proves the declared antecedent still
# refuses even with NO sibling measured, i.e. adding the measured arm did not replace it.
run_arm declared-still-refuses TC_PROC_ROOT="$SOLO_PROC_F" SOLEUR_SUBAGENT=1
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "SOLEUR_SUBAGENT=1 still refuses with no sibling present — the change is additive"
else
  fail "SOLEUR_SUBAGENT=1 stopped refusing once the sibling arm landed — got rc=$ARM_RC"
fi

# --- Anti-vacuity floor -----------------------------------------------------------------------
# Every assertion above is reachable only if the sandbox built and the arms ran. Strand the file
# — a renamed TARGET, a python failure, an early exit — and it would report "0 passed, 0 failed"
# and exit 0, which reads exactly like a clean run. A FLOOR, not equality: the count is
# developer-incremented and `-eq` turns every added assertion into a false red.
MIN_ASSERTIONS=13
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "fanout-suite-scope.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
