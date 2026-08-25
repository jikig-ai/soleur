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

# A direct invocation (the documented inner loop while editing this file) inherits the bare
# machine-global 4 GiB /tmp tmpfs; test-all.sh and run-registered-suites.sh both default to
# /var/tmp, so only the direct path was exposed. 58 suites in this repo carry this line,
# including scripts/guard-vacuity-floor.test.sh, shipped in this same PR.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Overridable so the suite can be pointed at an older or mutated copy and PROVED to red against
# it. A guard that has never been shown to fail is not evidence.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
WORK_SKILL="$REPO_ROOT/plugins/soleur/skills/work/SKILL.md"
REVIEW_SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# An INDEPENDENT count of assertion CALL SITES reached, incremented at the call sites and NEVER
# inside pass()/fail() — an increment in the helper is the tautology guard-vacuity-floor.test.sh's
# ARM 10d forbids, because it moves in lockstep with the verdict it is supposed to audit. Never
# incremented inside `$( … )` either: a subshell discards it and the code still reads as correct.
#
# This exists because the anti-vacuity floor at the bottom read PASS+FAIL, which is exactly the
# counter a neutered verdict helper keeps moving. Measured: with `fail()` rewritten to increment
# PASS, and the SUT simultaneously broken (`exit 4` -> `exit 0` in test-all.sh), this suite
# reported "31 passed, 0 failed" and exited 0. review/SKILL.md states the rule verbatim and
# scripts/guard-vacuity-floor.test.sh — shipped in this same PR — calls this half "the one that
# actually bites". It was missing from the PR's own primary suite.
CASES=0

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
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "SOLEUR_SUBAGENT=1 makes a full-gate invocation exit 4 (the refusal code)"
else
  fail "SOLEUR_SUBAGENT=1 did not refuse with rc=4 — got rc=$ARM_RC"
fi
CASES=$((CASES + 1))
if [[ "$ARM_SUITES" -eq 0 ]]; then
  pass "the refusal happens before any suite runs (0 suites recorded)"
else
  fail "refused only AFTER running $ARM_SUITES suites — the contention was already paid"
fi
# Naming the alternative is the difference between a block and a dead end. An agent that is
# refused without being told what to run instead will either re-run with the escape hatch or
# skip testing entirely, and both are worse than the thing being prevented.
CASES=$((CASES + 1))
if grep -qF 'SOLEUR_SUBAGENT' <<<"$ARM_OUT"; then
  pass "the refusal names the variable that caused it"
else
  fail "the refusal does not name SOLEUR_SUBAGENT, so its cause is unresolvable"
fi
CASES=$((CASES + 1))
if grep -qF 'targeting the files' <<<"$ARM_OUT"; then
  pass "the refusal names the targeted-suite alternative"
else
  fail "the refusal does not name the targeted-suite alternative"
fi
CASES=$((CASES + 1))
if grep -qF 'SOLEUR_ALLOW_FULL_GATE=1' <<<"$ARM_OUT"; then
  pass "the refusal names its escape hatch"
else
  fail "the refusal does not name an escape hatch"
fi

# --- Arm 2: negative control — without the variable, nothing changes -------------------------
# Without this arm the refusal could be unconditional and every assertion above would still
# pass. This is the arm that distinguishes a gate from a wall.
run_arm normal SOLEUR_SUBAGENT=
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 0 ]]; then
  pass "an ordinary invocation is unaffected (rc=0)"
else
  fail "an ordinary invocation now fails (rc=$ARM_RC) — the refusal is unconditional"
fi
# NORMAL_SUITES is the reference every later arm's registration assertion is measured against.
# `-gt 0` was satisfied by the CONSTANT 1 against a measured 335, and nothing anywhere read a
# recorded suite NAME — measured, a recorder that ignores $1 and writes one literal line forever
# left this suite at 31/31. DISTINCT == total is the real invariant (each suite registers once),
# and it is what a constant-recorder cannot satisfy.
NORMAL_SUITES="$ARM_SUITES"
NORMAL_DISTINCT=$(sort -u "$SANDBOX_RECORD" | grep -c '^RECORDED_SUITE:.' || true)
MIN_REGISTERED=300
CASES=$((CASES + 1))
if [[ "$ARM_SUITES" -ge "$MIN_REGISTERED" ]]; then
  pass "an ordinary invocation reaches suite registration ($ARM_SUITES recorded, floor $MIN_REGISTERED)"
else
  fail "an ordinary invocation recorded only $ARM_SUITES suite(s) (floor $MIN_REGISTERED) — the runner is broken, not gated"
fi
CASES=$((CASES + 1))
if [[ "$NORMAL_DISTINCT" -eq "$NORMAL_SUITES" && "$NORMAL_DISTINCT" -ge "$MIN_REGISTERED" ]]; then
  pass "every recorded line names a DISTINCT suite ($NORMAL_DISTINCT/$NORMAL_SUITES) — the recorder reads its argument"
else
  fail "recorded $NORMAL_SUITES line(s) but only $NORMAL_DISTINCT distinct suite name(s) — the recorder is not reading \$1, so every suite-count assertion in this file is satisfiable by a constant"
fi
CASES=$((CASES + 1))
if grep -qF 'SOLEUR_ALLOW_FULL_GATE=1' <<<"$ARM_OUT"; then
  fail "the refusal text prints on a run that was never refused"
else
  pass "the refusal text is absent when the refusal did not fire"
fi

# --- Arm 3: the escape hatch actually escapes ------------------------------------------------
# A refusal with no documented override gets worked around by unsetting the variable, which
# removes the signal entirely. An explicit hatch keeps the override visible in the command line.
run_arm hatch SOLEUR_SUBAGENT=1 SOLEUR_ALLOW_FULL_GATE=1
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 0 && "$ARM_SUITES" -ge $((NORMAL_SUITES - 5)) ]]; then
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
    CASES=$((CASES + 1))
    fail "$rel does not exist"
    continue
  fi
  CASES=$((CASES + 1))
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
  CASES=$((CASES + 1))
  if grep -qF 'SOLEUR_SUBAGENT' "$skill"; then
    pass "$rel names SOLEUR_SUBAGENT (the convention a lead may export)"
  else
    fail "$rel does not name SOLEUR_SUBAGENT at all"
  fi
  # The regression guard for the correction itself. Nothing in this repo sets SOLEUR_SUBAGENT on
  # a spawn path, so a file claiming the harness does is false — and it is a claim a future edit
  # can plausibly reintroduce, because it reads like a description of a mechanism that exists.
  CASES=$((CASES + 1))
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
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "a measured sibling full-gate run makes a full-gate invocation exit 4"
else
  fail "sibling present did not refuse with rc=4 — got rc=$ARM_RC"
fi
CASES=$((CASES + 1))
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
# Anchored on the STATEMENT, not the bare token. `grep -n 'TC_SIBLING_RUN_COUNT:-0' | head -1`
# reads comments too, and the explanatory block for this refusal sits ABOVE tc_acquire — so one
# added sentence quoting `${TC_SIBLING_RUN_COUNT:-0}` there would satisfy this ordering check
# with the refusal itself relocated below the lock (cq-assert-anchor-not-bare-token). A comment
# line cannot begin with `if [[`. Exactly-one, not head -1: two matches means the anchor has
# stopped identifying a unique statement and `head -1` would silently pick one.
REFUSAL_HITS=$(grep -cE '^if \[\[ "\$\{TC_SIBLING_RUN_COUNT:-0\}"' "$TARGET" || true)
REFUSAL_LN=$(grep -nE '^if \[\[ "\$\{TC_SIBLING_RUN_COUNT:-0\}"' "$TARGET" | cut -d: -f1)
ACQUIRE_LN=$(grep -n '^tc_acquire "test-all"' "$TARGET" | head -1 | cut -d: -f1)
CASES=$((CASES + 1))
if [[ "$REFUSAL_HITS" != "1" ]]; then
  fail "expected exactly one sibling-refusal statement in $TARGET, found $REFUSAL_HITS — the structural ordering check below no longer identifies a unique statement"
elif [[ -z "$REFUSAL_LN" || -z "$ACQUIRE_LN" ]]; then
  fail "could not locate the sibling refusal and/or tc_acquire in $TARGET (refusal=${REFUSAL_LN:-none} acquire=${ACQUIRE_LN:-none})"
elif [[ "$REFUSAL_LN" -lt "$ACQUIRE_LN" ]]; then
  pass "the sibling refusal precedes tc_acquire in test-all.sh (line $REFUSAL_LN < $ACQUIRE_LN)"
else
  fail "the sibling refusal sits at line $REFUSAL_LN, AFTER tc_acquire at $ACQUIRE_LN — a refused run would queue up to TC_LOCK_TIMEOUT and take the lock a legitimate sibling is waiting on"
fi
# The full clause AND the measured count. `grep -qF 'sibling'` was satisfied by tc_preamble's
# ADVISORY output, which prints "[contention] siblings: N other worktree(s) …" on EVERY run,
# refusing or not — measured on the solo arm (rc=0, no refusal). Deleting the word "sibling"
# from the refusal message itself left this suite green. Asserting the count reaches the text
# also closes the only path by which the measured number is ever read: the fixture has exactly
# one sibling, so a message that hardcodes a different number cannot pass.
CASES=$((CASES + 1))
if grep -qF '1 sibling full-gate run(s) already in flight' <<<"$ARM_OUT"; then
  pass "the sibling refusal names its cause AND carries the measured count (1)"
else
  fail "the refusal text does not carry '1 sibling full-gate run(s) already in flight' — either it no longer names a sibling as the cause, or the measured count never reaches the message, so a false positive is a mystery"
fi

# --- Arm 5: the sanctioned override is not collateral ---------------------------------------
# lefthook's pre-commit hook and the Grok pre-push gate both invoke the full gate deliberately and
# both carry this hatch. If it stopped working, a spawned agent could not commit a .ts file while
# any sibling ran -- the blast radius that disqualified the harness-identity design (#7553).
# `-eq 0`, not `-ne 4`: rc=1 is an ordinary suite failure and rc=3 is UNRESOLVED, and both
# satisfy "not 4" while meaning the hatched run did not actually complete. Same correction in
# the solo and inherited-count arms below.
run_arm sibling-hatch TC_PROC_ROOT="$SIB_PROC_F" SOLEUR_ALLOW_FULL_GATE=1
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 0 ]]; then
  pass "SOLEUR_ALLOW_FULL_GATE=1 overrides the sibling refusal (rc=$ARM_RC)"
else
  fail "the hatch did not override the sibling refusal (rc=$ARM_RC) — the sanctioned gate run is collateral"
fi
CASES=$((CASES + 1))
if [[ "$ARM_SUITES" -ge $((NORMAL_SUITES - 5)) ]]; then
  pass "the hatched run reaches suite registration ($ARM_SUITES of $NORMAL_SUITES)"
else
  fail "the hatched run recorded $ARM_SUITES suite(s) against a baseline of $NORMAL_SUITES — it was blocked partway"
fi

# --- Arm 6: the SOLO path is untouched (the highest-cost false positive) ---------------------
run_arm sibling-solo TC_PROC_ROOT="$SOLO_PROC_F"
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 0 ]]; then
  pass "no sibling and no hatch does NOT refuse — the ordinary local run is unaffected (rc=$ARM_RC)"
else
  fail "the solo run did not complete cleanly (rc=$ARM_RC) — rc=4 would break every solo run of the gate; any other non-zero means it broke for a different reason"
fi
CASES=$((CASES + 1))
if [[ "$ARM_SUITES" -ge $((NORMAL_SUITES - 5)) ]]; then
  pass "the solo run reaches suite registration ($ARM_SUITES of $NORMAL_SUITES)"
else
  fail "the solo run recorded $ARM_SUITES suite(s) against a baseline of $NORMAL_SUITES"
fi

# --- Arm 7: the two refusals are ADDITIVE, not a swap ----------------------------------------
# Arm 1 proves SOLEUR_SUBAGENT still refuses on its own. This proves the declared antecedent still
# refuses even with NO sibling measured, i.e. adding the measured arm did not replace it.
run_arm declared-still-refuses TC_PROC_ROOT="$SOLO_PROC_F" SOLEUR_SUBAGENT=1
CASES=$((CASES + 1))
if [[ "$ARM_RC" -eq 4 ]]; then
  pass "SOLEUR_SUBAGENT=1 still refuses with no sibling present — the change is additive"
else
  fail "SOLEUR_SUBAGENT=1 stopped refusing once the sibling arm landed — got rc=$ARM_RC"
fi

# --- Arm 8: an INHERITED sibling count must NOT refuse ---------------------------------------
#
# TC_SIBLING_RUN_COUNT is EXPORTED by tc_preamble, so a nested test-all.sh inherits it. A suite
# that drives this runner as its SUT neuters tc_preamble in its sandbox — so it measures nothing,
# inherits its parent's number, and (before the fix) refused on a machine state it never looked
# at. That is the DECLARED antecedent ADR-196 exists to move away from, reintroduced by an env
# var. Measured on the real suites: `TC_SIBLING_RUN_COUNT=4` alone took
# test-all-killed-classification from 77/0 to 40/37 and test-all-infra-coverage-notice from
# 118/0 to 38/81, with nothing wrong in either diff.
#
# The discriminating fixture must NEUTER tc_preamble — with it live, the inherited value is just
# overwritten by a real measurement and the arm passes either way. Dropping test-contention.sh
# from the sandbox's lib/ is exactly how test-all.sh reaches its no-op stubs in the wild.
NOLIB_SANDBOX="$TMP/nolib/test-all-sandbox.sh"
mkdir -p "$TMP/nolib"
if ! build_sandbox "$NOLIB_SANDBOX"; then
  CASES=$((CASES + 1))
  fail "no-lib sandbox build failed — the inherited-count arm cannot run"
else
  rm -f "$TMP/nolib/lib/test-contention.sh"
  export SANDBOX_RECORD="$TMP/record-inherited.txt"; : > "$SANDBOX_RECORD"
  INH_OUT=$(cd "$REPO_ROOT" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            TEST_TIMING_LOG="$TMP/arm-timing-inherited.tsv" \
            TC_PROC_ROOT="$SOLO_PROC_F" TC_SIBLING_RUN_COUNT=9 \
            timeout 120 bash "$NOLIB_SANDBOX" 2>&1)
  # NO `|| true`. `$?` after it reads TRUE's status, not the command's, so INH_RC was
  # pinned at 0 and the `-ne 4` assertion below became a tautology printing a fabricated
  # `rc=0` as evidence — a constant satisfying the assertion that pins this PR's own
  # thesis. This suite runs `set -uo pipefail` with NO errexit, which is exactly why
  # run_arm captures ARM_RC the same bare way.
  INH_RC=$?
  INH_SUITES=$(wc -l < "$SANDBOX_RECORD" | tr -d '[:space:]')
    CASES=$((CASES + 1))
  if [[ "$INH_RC" -eq 0 ]]; then
    pass "an inherited TC_SIBLING_RUN_COUNT does not refuse when this process measured nothing (rc=$INH_RC)"
  else
    fail "refused on an INHERITED sibling count — a nested runner that neutered tc_preamble is being refused on its parent's measurement, which reds every suite driving test-all.sh as its SUT"
  fi
    CASES=$((CASES + 1))
  if [[ "$INH_SUITES" -ge $((NORMAL_SUITES - 5)) ]]; then
    pass "the inherited-count run reached suite registration ($INH_SUITES of $NORMAL_SUITES)"
  else
    fail "the inherited-count run recorded $INH_SUITES suite(s) against a baseline of $NORMAL_SUITES"
  fi
    CASES=$((CASES + 1))
  if grep -qF 'sibling full-gate run(s) already in flight' <<<"$INH_OUT"; then
    fail "the refusal text printed on a run whose sibling count was inherited, not measured"
  else
    pass "no refusal text on an inherited count"
  fi

  # --- Arm 8b: a SET but FOREIGN stamp must not refuse either ------------------------------
  #
  # The arm above leaves TC_SIBLING_RUN_COUNT_PID UNSET, so it is satisfied by every predicate
  # that is false-on-unset — `-n`, `-v`, `!= ""`. Measured: replacing `== "$$"` with
  # `-n "${TC_SIBLING_RUN_COUNT_PID:-}"` in test-all.sh left this suite at 31 passed, 0 failed,
  # and `grep -rn TC_SIBLING_RUN_COUNT_PID` over every *.test.sh returned zero hits — no fixture
  # anywhere SET the variable. That is the whole claim of ADR-196 Decision 7 ("measured by THIS
  # process") degrading to "measured by someone", which is the DECLARED antecedent the ADR
  # exists to remove, and nothing could see it.
  #
  # It must run on $NOLIB_SANDBOX. With a live tc_preamble both variables are overwritten by a
  # real measurement before the refusal is reached, so a run_arm form passes under the mutation
  # and proves nothing.
  export SANDBOX_RECORD="$TMP/record-foreign.txt"; : > "$SANDBOX_RECORD"
  FGN_OUT=$(cd "$REPO_ROOT" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            TEST_TIMING_LOG="$TMP/arm-timing-foreign.tsv" \
            TC_PROC_ROOT="$SOLO_PROC_F" TC_SIBLING_RUN_COUNT=9 TC_SIBLING_RUN_COUNT_PID=1 \
            timeout 120 bash "$NOLIB_SANDBOX" 2>&1)
  FGN_RC=$?
  FGN_SUITES=$(wc -l < "$SANDBOX_RECORD" | tr -d '[:space:]')
    CASES=$((CASES + 1))
  if [[ "$FGN_RC" -eq 0 ]]; then
    pass "a SET but FOREIGN provenance stamp does not refuse (rc=$FGN_RC) — the predicate binds to THIS process, not to the stamp merely existing"
  else
    fail "refused (rc=$FGN_RC) on a stamp naming pid 1 — the provenance check has degraded from 'I measured this' to 'someone measured this'"
  fi
    CASES=$((CASES + 1))
  if [[ "$FGN_SUITES" -ge $((NORMAL_SUITES - 5)) ]]; then
    pass "the foreign-stamp run reached suite registration ($FGN_SUITES of $NORMAL_SUITES)"
  else
    fail "the foreign-stamp run recorded $FGN_SUITES suite(s) against a baseline of $NORMAL_SUITES"
  fi
    CASES=$((CASES + 1))
  if grep -qF 'sibling full-gate run(s) already in flight' <<<"$FGN_OUT"; then
    fail "the refusal text printed on a run whose stamp names a different process"
  else
    pass "no refusal text on a foreign stamp"
  fi
fi

# --- Arm 9: the sanctioned hooks actually CARRY the hatch ------------------------------------
#
# Arm 5 proves the hatch WORKS. Nothing proved the two invocations that depend on it still SET
# it, and ADR-196 Decision 6 ("the two GIT-HOOK invocations carry the hatch") asserted it in
# prose only. Blast radius if it drifts: no agent or developer can commit a `.ts` file, or push, while
# any sibling worktree runs the battery — the exact outcome that disqualified the
# harness-identity design.
#
# Asserted over EVERY uncommented full-gate invocation in each file, not just the line that
# carries it today: a second, unhatched invocation added later is the same outage. Comments are
# stripped FIRST because both files explain the hatch in prose directly above the invocation, so
# a bare token grep would match the explanation whether or not the code still carries it
# (cq-assert-anchor-not-bare-token).
for hookf in "$REPO_ROOT/lefthook.yml" "$REPO_ROOT/plugins/soleur/scripts/grok-pre-push-gate.sh"; do
  hookrel="${hookf#"$REPO_ROOT"/}"
  if [[ ! -f "$hookf" ]]; then
    CASES=$((CASES + 1))
    fail "$hookrel does not exist"
    continue
  fi
  # Three fail-open forms in the first version of this scan, each measured to survive at 31/31
  # with a live UNHATCHED invocation present in the file:
  #   1. `bash "$REPO_ROOT/scripts/test-all.sh"` — the pattern demanded the literal
  #      `bash scripts/test-all.sh`, so any variable or absolute prefix was invisible.
  #   2. `[[ -n "${X#no}" ]] && bash scripts/test-all.sh` — `sed 's/#.*$//'` strips from the `#`
  #      of a PARAMETER EXPANSION, deleting the whole line including the invocation.
  #   3. `… bash scripts/test-all.sh || bash scripts/test-all.sh` — `grep -v` is line-granular,
  #      so a hatched half vouched for an unhatched half on the same line.
  # And one false-RED: `SOLEUR_ALLOW_FULL_GATE=1 timeout 900 bash scripts/test-all.sh` was
  # reported unhatched, because the old hatch pattern required the assignment ADJACENT to `bash`.
  #
  # Fixed by (a) stripping comments only at a `#` that opens a word, (b) matching test-all.sh in
  # COMMAND POSITION — after an interpreter, after `./`, or as the segment's first word — which
  # admits any prefix or wrapper while not matching the path inside a diagnostic string (both
  # files print messages naming test-all.sh; a bare `grep -F` form of this scan false-RED'd on
  # them, measured), (c) splitting on `;`, `&&` and `||` so the hatch is checked PER INVOCATION,
  # and (d) requiring only that the hatch appear somewhere in the same segment.
  HOOK_SRC="$(sed 's/\(^\|[[:space:]]\)#.*$/\1/' "$hookf" | sed -E 's/(\&\&|\|\||;)/\n/g')"
  # NON-RUNNING MODES ARE NOT GATE RUNS. test-all.sh exits before registering any suite when
  # its first argument is `--capacity` (a ~3 s /proc probe, always exit 0) or
  # `--print-suite-globs`. Neither contends for anything, so neither needs the hatch — and
  # `grok-pre-push-gate.sh` legitimately calls the first one. Flagging it was a FALSE POSITIVE
  # of exactly the kind this arm exists to avoid producing: the property is "an unhatched GATE
  # RUN", and matching every invocation of the script is broader than that. Derived from the
  # runner rather than hardcoded, so a mode added later cannot silently start false-flagging.
  _modes="$(grep -oE '^if \[\[ "\$\{1:-\}" == "--[a-z-]+"' "$REPO_ROOT/scripts/test-all.sh" \
            | grep -oE -- '--[a-z-]+' || true)"
  HOOK_INV="$(grep -E '(^|[[:space:]])((bash|sh|zsh|exec|source)[[:space:]]+[^[:space:]|;&]*test-all\.sh|\.{0,2}/[^[:space:]|;&]*test-all\.sh)|^[[:space:]]*[^[:space:]|;&]*test-all\.sh([[:space:]]|$)' <<<"$HOOK_SRC" || true)"
  while IFS= read -r _m; do
    [[ -n "$_m" ]] || continue
    HOOK_INV="$(grep -vF -- "test-all.sh $_m" <<<"$HOOK_INV" || true)"
  done <<<"$_modes"
  CASES=$((CASES + 1))
  if [[ -z "$HOOK_INV" ]]; then
    fail "$hookrel no longer invokes scripts/test-all.sh — this guard is pinned to the wrong file"
    continue
  fi
  pass "$hookrel carries $(grep -c . <<<"$HOOK_INV") uncommented full-gate invocation segment(s)"
  HOOK_BARE="$(grep -vF 'SOLEUR_ALLOW_FULL_GATE=1' <<<"$HOOK_INV" || true)"
  CASES=$((CASES + 1))
  if [[ -z "$HOOK_BARE" ]]; then
    pass "$hookrel: every full-gate invocation carries SOLEUR_ALLOW_FULL_GATE=1 (ADR-196 section 6)"
  else
    fail "$hookrel has a full-gate invocation WITHOUT the hatch — it exits 4 whenever any sibling runs the battery: $HOOK_BARE"
  fi
done

# --- Arm 10: the provenance stamp is NOT exported --------------------------------------------
#
# `export -n TC_SIBLING_RUN_COUNT_PID` in tc_preamble is unfalsifiable through any rc assertion:
# `$$` differs in a forked child either way, so Arm 8 stays green both with the line DELETED and
# with an explicit `export` ADDED. The only level at which it is observable is the child's
# ENVIRONMENT — and it matters, because a stamp that propagates makes a descendant's inherited
# count look self-measured the moment the pids coincide.
#
# Measured on the real lib, not a sandbox copy: 0 on the current tree, 1 with `export -n`
# removed AND the name pre-set-and-exported in the environment.
STAMP_EXPORTED=$(env -u TC_SIBLING_RUN_COUNT_PID -u TC_SIBLING_RUN_COUNT \
  TC_PROC_ROOT="$SOLO_PROC_F" TC_LIB="$REPO_ROOT/scripts/lib/test-contention.sh" \
  bash -c '. "$TC_LIB" >/dev/null 2>&1; tc_preamble >/dev/null 2>&1
           env | grep -c "^TC_SIBLING_RUN_COUNT_PID=" || true' 2>/dev/null)
CASES=$((CASES + 1))
if [[ "$STAMP_EXPORTED" == "0" ]]; then
  pass "the provenance stamp is not exported — a child cannot inherit a claim of self-measurement"
else
  fail "TC_SIBLING_RUN_COUNT_PID reached the child environment ($STAMP_EXPORTED hit(s)); bash keeps the export attribute on reassignment, so the explicit 'export -n' is what removes it"
fi

# --- Verdict-machinery controls (ADR-193 #2/#3), BEFORE the floor -----------------------------
#
# Ordered before the floor deliberately: a neutered verdict helper deflates PASS/FAIL, so the
# floor would ALSO trip and would report "assertions were deleted" — the misleading diagnosis.
# Both report with echo + exit 1 DIRECTLY, never through pass()/fail(): a check that reports by
# calling the verdict helper is silenced by the very fault it exists to witness.
#
# The positive control runs first because the conservation identity below is satisfiable by
# helpers that move NEITHER counter. Its own output is suppressed and its counters are restored,
# so it is machinery, not a subject assertion, and it is deliberately NOT counted in CASES.
_p0=$PASS; _f0=$FAIL
{ pass "verdict-helper positive control"; fail "verdict-helper negative control"; } >/dev/null
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) ]]; then
  echo "" >&2
  echo "[FATAL] verdict helpers: pass() moved PASS by $((PASS - _p0)) and fail() moved FAIL by $((FAIL - _f0)); both must be exactly 1." >&2
  echo "  Every verdict printed above is unreliable — this is what a neutered pass()/fail() looks like." >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0
echo "  ok   verdict-helper controls: pass() and fail() each moved their own counter (counters restored)"

# printf, not echo, and the literal `[FATAL] accounting` is load-bearing:
# scripts/guard-vacuity-floor.test.sh ARM 10 builds its conserving population by grepping that
# exact string, and asserts the sentinel is emitted by a `printf` — i.e. NOT routed through the
# suite's own verdict helper, which is the fault this check exists to witness. It caught this
# block on its first run, when it used `echo`.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a discarded verdict looks like (a helper call inside a subshell, or a neutered helper).\n' >&2
  else
    printf '  A verdict was recorded at a call site with no CASES increment before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  printf '\nfanout-suite-scope.test.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
  exit 1
fi

# --- Anti-vacuity floor -----------------------------------------------------------------------
# Every assertion above is reachable only if the sandbox built and the arms ran. Strand the file
# — a renamed TARGET, a python failure, an early exit — and it would report "0 passed, 0 failed"
# and exit 0, which reads exactly like a clean run. A FLOOR, not equality: the count is
# developer-incremented and `-eq` turns every added assertion into a false red.
#
# Reads CASES, not PASS+FAIL. PASS+FAIL is the counter a neutered verdict helper keeps moving,
# so a floor over it shares a lifetime with what it guards; the conservation check above is what
# makes CASES trustworthy here.
#
# ZERO HEADROOM against the measured count, so any deletion is loud. It was 13 against a
# measured 31 — 18 fungible slots, enough that deleting every assertion #7553 and this PR added
# left the suite green (measured: 15 passed, 0 failed, rc=0). Ratchet this in the same commit as
# any added arm; a floor failure on an otherwise-green run means "you added assertions".
MIN_ASSERTIONS=36
if [[ "$CASES" -lt "$MIN_ASSERTIONS" ]]; then
  echo "" >&2
  echo "[FATAL] anti-vacuity floor: only $CASES assertion(s) ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "fanout-suite-scope.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
