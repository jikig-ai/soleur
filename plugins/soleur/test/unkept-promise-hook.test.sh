#!/usr/bin/env bash
# Guard suite for plugins/soleur/hooks/unkept-promise-hook.sh
#
# BOTH DIRECTIONS, DELIBERATELY. A suite whose fixtures all assert must-BLOCK
# cannot see a predicate becoming too aggressive, and over-firing is what gets a
# gate routed around. Every must-PASS row is load-bearing.
#
# The BLOCK fixtures carry a COURTESY CLOSER. An earlier revision's fixtures did
# not, and its ALLOW fixtures all did -- so the suite was green while measuring
# nothing but keyword presence: appending "Let me know if you want it different."
# to any real instance made the hook allow it. Separating the two sets by the
# defect rather than by politeness is the whole point of this file.
#
# Fixtures are real closings from the 2026-09-07 session, both directions.

set -uo pipefail
REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
HOOK="$REPO_ROOT/plugins/soleur/hooks/unkept-promise-hook.sh"

PASS=0; FAIL=0
FAILURES=()   # append-only: a conservation check on counters alone is silenced
              # by redirecting an increment; printed verdicts are not.
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL: $1"; }

# Counted through a FILE, not a variable. `verdict` is called from inside a
# $( ) in `expect`, so a shell variable increments in the subshell and is lost --
# the identical scoping bug that produced this file's earlier correlated-fixture
# defect, hit again by the counter added to catch a neutered harness.
INVOCATION_LOG="$(mktemp -t unkept-inv.XXXXXXXX)"
trap 'rm -f "$INVOCATION_LOG"' EXIT INT TERM
verdict() { # <message> [extra-json] -> BLOCK | ALLOW
  echo x >> "$INVOCATION_LOG"
  local msg="$1" extra="${2:-{\}}" out
  out=$(jq -n --arg m "$msg" --argjson e "$extra" '$e + {last_assistant_message:$m}' \
        | bash "$HOOK" 2>/dev/null)
  printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1 && echo BLOCK || echo ALLOW
}
EXPECT_ROWS=0
expect() { # <want> <label> <message>
  EXPECT_ROWS=$((EXPECT_ROWS + 1))
  local got; got=$(verdict "$3")
  [ "$got" = "$1" ] && pass "$2" || fail "$2 (want $1, got $got)"
}

echo "=== instrument self-test (both counters must move) ==="
_p0=$PASS; _f0=$FAIL
pass "self-check: pass() increments"
fail "self-check: fail() increments (EXPECTED, not a defect)"
[ "$PASS" -gt "$_p0" ] && [ "$FAIL" -gt "$_f0" ] \
  || { printf '[FATAL] assertion helpers do not both move their counters\n' >&2; exit 2; }
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'

echo "=== must BLOCK: the three real instances, BARE ==="
expect BLOCK "instance 1 bare" \
  "The ruling is comprehensive. Implementing the drafted wording verbatim now."
expect BLOCK "instance 2 bare" \
  "Remaining: emit the review trailer, then ship. I'll run those rather than describe them."
expect BLOCK "instance 3 bare" \
  "Both are empirical. I'll probe them rather than reason about them, then build."

echo "=== must BLOCK: the same three WITH a courtesy closer (the regression) ==="
# A guard that stops working when the turn is polite is inert in practice --
# every one of these was ALLOWed before per-sentence scoping.
expect BLOCK "instance 1 + 'Let me know if you want it different.'" \
  "Implementing the wording verbatim now. Let me know if you want it different."
expect BLOCK "instance 2 + 'Tell me if you'd rather I skip it.'" \
  "I'll run the full battery next. Tell me if you'd rather I skip it."
expect BLOCK "instance 3 + 'If you disagree, say so.'" \
  "I will implement the wording next. If you disagree, say so."
expect BLOCK "gerund + closer" \
  "All claims verified. Running the full battery now. Shout if that is wrong."

echo "=== NEWLINE-separated sentences (every other fixture uses \". \") ==="
# The suite was blind to this shape: a `sed` that could not match the record
# separator left the whole message as ONE sentence, so per-sentence scoping was
# inert for any multi-line text -- which is most real turns.
expect BLOCK "promise on its own line, sentinel only DISCUSSED earlier" \
  "The escape hatch is <stop>BLOCKED: reason</stop> as documented.

I will implement the fix next."
expect BLOCK "conditional on a SEPARATE line must not veto the promise" \
  "I will implement the wording next.

Let me know if you disagree."
expect ALLOW "sentinel as the final line is a real declaration" \
  "Implementing the register entry now.

<stop>OPERATOR-GATE: the credential must be entered by hand</stop>"
expect BLOCK "promise above a mandated fenced resume prompt" \
  "Remaining: emit the trailer, then ship. I'll run those rather than describe them.

\`\`\`
resume: feat-stop-hook-unkept-promise
next: review findings
owner: agent
\`\`\`"

echo "=== must PASS: correct handoffs ==="
expect ALLOW "conditional in the SAME sentence as the promise" \
  "My recommendation is to ship the corrected core. Say the word and I'll run it."
expect ALLOW "operator-gate sentinel (fixture CARRIES a promise, so it reaches the arm)" \
  "Implementing the register entry now. <stop>OPERATOR-GATE: the Sentry credential must be entered by hand</stop>"
expect ALLOW "blocked sentinel (fixture CARRIES a promise)" \
  "Let me now finish the determination. <stop>BLOCKED: the access investigation has not been run</stop>"
expect ALLOW "trailing question (fixture CARRIES a promise)" \
  "Let me now write the plan. Should I open the PR against main?"
expect ALLOW "past tense -- already done" \
  "Committed and pushed. lint-legal-registers: 7 assertions, 0 failed."
expect ALLOW "waiting on in-flight agents" \
  "Three agents are still running. I'll report what they find rather than assume."
expect ALLOW "waiting on CI" \
  "Auto-merge is queued. I'll open the follow-up once the tests pass."
expect ALLOW "operator's action, not mine" \
  "Your action is unchanged: rotate the token in prd_terraform."
expect ALLOW "future session, not this turn" \
  "The follow-up this earns is widening the rule to credential liveness, which is not in this PR."

echo "=== loop safety: stop_hook_active bounds the chain with NO persistence ==="
r=$(verdict "Let me now do it." '{"stop_hook_active":true}')
[ "$r" = "ALLOW" ] && pass "stop_hook_active=true -> never blocks twice in a chain" \
  || fail "stop_hook_active ignored (got $r) -- the hook can wedge a session"
r=$(verdict "Let me now do it." '{"stop_hook_active":false}')
[ "$r" = "BLOCK" ] && pass "stop_hook_active=false -> blocks normally" \
  || fail "stop_hook_active=false must still block (got $r)"
grep -q 'stop_hook_active' "$HOOK" && pass "loop bound reads the runtime field, not a counter" \
  || fail "no stop_hook_active guard"

echo "=== no on-disk state: every prior flake and the security surface came from it ==="
grep -qE 'mkdir|COUNTER_FILE|STATE_DIR|\.count' "$HOOK" \
  && fail "hook writes persistent state -- the source of all three flake classes" \
  || pass "hook is stateless (no mkdir / counter / state dir)"

echo "=== vocabulary: <promise> is owned by one-shot and ralph-loop ==="
# <promise>DONE</promise> is ONE_SHOT_DONE_MARKER and stop-hook.sh deletes ralph
# state on a match. Offering it as this hook's escape hatch would teach the model
# to forge the pipeline's completion marker on a turn that was just blocked.
# Behaviour, not source text: the header must be free to NAME the marker it
# deliberately avoids, and a source grep would forbid that while a comment
# containing the literal would defeat the grep anyway.
r=$(verdict "Let me now do it. <promise>OPERATOR-GATE: nope</promise>")
[ "$r" = "BLOCK" ] && pass "the one-shot marker does NOT satisfy this hook's escape hatch" \
  || fail "<promise> bought an exit (got $r) -- collides with ONE_SHOT_DONE_MARKER"
r=$(verdict "Let me now do it. <promise>DONE</promise>")
[ "$r" = "BLOCK" ] && pass "a forged <promise>DONE</promise> does NOT satisfy this hook" \
  || fail "<promise>DONE</promise> bought an exit (got $r)"

echo "=== fail-open: infrastructure problems must never wedge a turn ==="
for probe in '' 'not json at all'; do
  out=$(printf '%s' "$probe" | bash "$HOOK" 2>/dev/null); rc=$?
  [ "$rc" = "0" ] && [ -z "$out" ] && pass "stdin '${probe:0:12}' -> allow (rc=0)" \
    || fail "stdin '${probe:0:12}' must allow, got rc=$rc"
done
out=$(jq -n '{session_id:"x"}' | bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$out" ] && pass "missing last_assistant_message -> allow" \
  || fail "missing field must allow, got rc=$rc"

echo "=== the block payload is actionable ==="
body=$(jq -n --arg m "Let me now do it." '{last_assistant_message:$m}' | bash "$HOOK" 2>/dev/null)
printf '%s' "$body" | jq -e '.reason | test("OPERATOR-GATE")' >/dev/null 2>&1 \
  && pass "reason names the escape hatch" || fail "reason does not name the escape hatch"
printf '%s' "$body" | jq -e '.reason | test("in THIS turn")' >/dev/null 2>&1 \
  && pass "reason states the required action" || fail "reason does not state the action"

# Floor emitted DIRECTLY, never through the helpers it backstops.
# Every threshold below is MEASURED from a green run, never an expected
# value -- set from an expectation twice in this file and wrong both times.
# Each literal sits immediately above its own `if` so it binds inside the
# vacuity guard's mutant slice (see the note on the coverage floor below).
# A count of assertions cannot see a harness that stopped invoking the SUT:
# `expect() { pass "$2"; }` keeps every counter moving and runs the hook zero
# times. Assert the INVOCATIONS the rows must have produced.
#
# TWO CONSTRAINTS, BOTH LEARNED FROM `scripts/guard-vacuity-floor.test.sh`, which
# slices each floor into a mutant with every helper name neutered (via
# `command_not_found_handle`) and every COUNTER zeroed, then requires the floor
# to still exit non-zero.
#
#   1. NEITHER SIDE MAY BE A COUNTER. This compared INVOCATIONS against
#      EXPECT_ROWS -- both incremented by the harness -- so zeroing both made
#      `0 -lt 0` false: the floor exited 0 and certified a run that asserted
#      nothing. Each threshold is now a LITERAL.
#   2. THE THRESHOLD MUST BIND IN THE SLICE. The mutant widens BACKWARD only
#      over contiguous simple assignments, so a literal parked above a comment
#      or a command substitution is unbound under `set -u`; the mutant then dies
#      before reaching the floor and is scored "not constructible" rather than
#      firing -- which moves the guard's construction-failure ratchet instead of
#      its firing count. Hence each threshold sits IMMEDIATELY above its own
#      `if`, with nothing in between.
INVOCATIONS=$(wc -l < "$INVOCATION_LOG" 2>/dev/null | tr -d ' ')
INVOCATIONS=${INVOCATIONS:-0}
MIN_INVOCATIONS=24
if [ "$INVOCATIONS" -lt "$MIN_INVOCATIONS" ]; then
  printf '[FATAL] coverage: %s SUT invocations, floor is %s -- the harness is not running the hook\n' \
    "$INVOCATIONS" "$MIN_INVOCATIONS" >&2
  exit 1
fi
MIN_EXPECT_ROWS=20
if [ "$EXPECT_ROWS" -lt "$MIN_EXPECT_ROWS" ]; then
  printf '[FATAL] coverage: %s expect rows, floor is %s -- rows were removed\n' \
    "$EXPECT_ROWS" "$MIN_EXPECT_ROWS" >&2
  exit 1
fi
echo ""
echo "=== $PASS passed, $FAIL failed ($INVOCATIONS SUT invocations, $EXPECT_ROWS expect rows) ==="
[ "${#FAILURES[@]}" -gt 0 ] && printf 'FAILED: %s\n' "${FAILURES[@]}" >&2
MIN_ASSERTIONS=31
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: ran %s, expected >= %s\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$FAIL" ]; then
  printf '[FATAL] conservation: %s FAIL(s) counted but %s recorded\n' "$FAIL" "${#FAILURES[@]}" >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
