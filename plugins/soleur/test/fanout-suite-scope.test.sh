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
  python3 - "$out" <<'PY' || exit 2
import re, sys
path = sys.argv[1]
s = open(path).read()

m = re.search(r'^run_suite\(\) \{.*?^\}', s, re.S | re.M)
assert m, "could not locate run_suite() definition"
s = s[:m.start()] + 'run_suite() { echo "RECORDED_SUITE:$1" >> "$SANDBOX_RECORD"; }' + s[m.end():]

# Neuter the contention hooks at their CALL sites (the lib itself still sources cleanly).
for call in ('tc_preamble\n', 'tc_acquire "test-all"\n'):
    assert s.count(call) == 1, f"expected exactly one {call!r}, found {s.count(call)}"
    s = s.replace(call, ':\n')

open(path, 'w').write(s)
PY
}

SANDBOX="$TMP/test-all-sandbox.sh"
build_sandbox "$SANDBOX" || { echo "FATAL: sandbox build failed" >&2; exit 2; }

# Run the sandbox under a given environment. $1 = arm label; remaining args are VAR=VALUE pairs.
# Sets ARM_OUT / ARM_RC / ARM_SUITES.
run_arm() {
  local label="$1"; shift
  export SANDBOX_RECORD="$TMP/record-$label.txt"
  : > "$SANDBOX_RECORD"
  ARM_OUT=$(cd "$REPO_ROOT" && env "$@" timeout 120 bash "$SANDBOX" 2>&1)
  ARM_RC=$?
  ARM_SUITES=$(wc -l < "$SANDBOX_RECORD" | tr -d '[:space:]')
}

echo "=== fan-out suite-scope suite ==="

# --- Arm 1: the refusal fires, and fires BEFORE any work ------------------------------------
run_arm refuse SOLEUR_SUBAGENT=1
if [[ "$ARM_RC" -ne 0 ]]; then
  pass "SOLEUR_SUBAGENT=1 makes a full-gate invocation exit non-zero (rc=$ARM_RC)"
else
  fail "SOLEUR_SUBAGENT=1 did not refuse — exited 0"
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
  if grep -qF 'SOLEUR_SUBAGENT=1' "$skill"; then
    pass "$rel tells the lead to export SOLEUR_SUBAGENT=1"
  else
    fail "$rel does not name the variable the mechanical guard reads"
  fi
done

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
