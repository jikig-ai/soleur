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
# WRITTEN BY THE SUT, not by this harness. INVOCATION_LOG is appended by verdict()
# BEFORE the hook is spawned, so it certifies what the harness intended to do.
# SOLEUR_HOOK_TRACE is appended by the hook itself on entry, so a harness that
# never runs it cannot satisfy the floor below. Measured: an expect() that
# incremented both harness counters and skipped the spawn reported 50/43/39 --
# every green-run value -- with the subject never executed.
export SOLEUR_HOOK_TRACE
SOLEUR_HOOK_TRACE="$(mktemp -t unkept-sut.XXXXXXXX)"
trap 'rm -f "$INVOCATION_LOG" "$SOLEUR_HOOK_TRACE"' EXIT INT TERM
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
echo "=== the parked-deliverable arm (2026-09-17) ==="
# A stop tag is legitimate for something the model CANNOT clear. It is not
# legitimate for handing FINISHED WORK back for a merge/review/ship, which
# rf-never-skip-qa-review-before-merging requires be carried in-session.
#
# ROW 1 IS THE MOTIVATING TURN, VERBATIM. Two earlier shapes of this arm passed
# every other row and let it through, for two different structural reasons -- a
# `tail -n 1` scope that missed a tag spanning two sentences, and nesting inside
# promise detection when a parked turn makes no promise. A suite without the real
# case cannot tell a working arm from those.
expect BLOCK "the real 2026-09-17 turn: green PR parked on the operator" \
  "Done. <stop>OPERATOR-GATE: PR #8244 is green and awaiting your merge. Nothing else is outstanding.</stop>"
expect BLOCK "awaiting review as an end state" \
  "Pushed. <stop>OPERATOR-GATE: awaiting review before merge.</stop>"
expect BLOCK "needs a human, bare -- no trailing verb" \
  "That is as far as I can take it. <stop>OPERATOR-GATE: this needs a human.</stop>"
expect BLOCK "the obvious rephrase: ready for your merge" \
  "Green. <stop>OPERATOR-GATE: PR #8244 is ready for your merge.</stop>"
expect BLOCK "the obvious rephrase: over to you to merge" \
  "Green. <stop>OPERATOR-GATE: over to you to merge.</stop>"

# ── THE OVER-BLOCK DIRECTION ────────────────────────────────────────────────────
# Every row below is a stop this repo's own rules MANDATE. An earlier revision
# blocked 13 of 15 such closings -- because its object set included
# `decision|approv|go-?ahead|sign-off` -- and answered each with "Do it now, in
# THIS turn", i.e. it instructed an unauthorized outward-facing action while
# citing a rule. hr-technical-fork-is-not-an-operator-question is explicit that
# authorization, COST and SCOPE are the operator's to answer. This direction is
# the one a self-written battery omits, and it is the one that does real harm.
expect ALLOW "a genuine requirements fork" \
  "Two designs are viable. <stop>OPERATOR-GATE: waiting for your decision on which to build.</stop>"
expect ALLOW "pre-agent confirmation (wg-zero-agents-until-user-confirms)" \
  "I summarised the landscape. <stop>OPERATOR-GATE: pending your go-ahead before I spawn the research agents.</stop>"
expect ALLOW "API budget disclosure (hr-autonomous-loop-skill-api-budget-disclosure)" \
  "The loop will cost roughly 40 dollars in API spend. <stop>OPERATOR-GATE: awaiting your approval of the budget.</stop>"
expect ALLOW "outward-facing effect: an invoice reaching a customer" \
  "The invoice preview is rendered. <stop>OPERATOR-GATE: awaiting your approval before it is sent to the customer.</stop>"
expect ALLOW "outward-facing effect: a post leaving the repo" \
  "Draft post is ready. <stop>OPERATOR-GATE: needs your sign-off before it goes out on X.</stop>"
expect ALLOW "word boundary: a human-READABLE message is not 'needs a human'" \
  "The error copy is placeholder. <stop>OPERATOR-GATE: needs a human-readable message before launch.</stop>"

# ── SCOPE: all three terms must describe the SAME stop ──────────────────────────
# Tested independently over the window, the terms can be satisfied by three
# DIFFERENT sentences -- co-occurrence, not the waiting-on relationship the arm
# claims to key on. Measured on the first revision: the row below BLOCKED a
# legitimate in-flight CI gate because a neighbouring sentence mentioned somebody
# else's review.
expect ALLOW "an unrelated sibling review does not veto a CI gate" \
  "The sibling PR is still awaiting review by the other team. <stop>OPERATOR-GATE: waiting on CI run 123 for this one.</stop>"
# The mirror: an unrelated sentence must not DISARM the arm either. The escape is
# scoped to the tag's sentence, which is this file's own documented lesson --
# "a courtesy closer anywhere in the window vetoed a promise anywhere else in it".
expect BLOCK "an unrelated 'revoked' sentence does not disarm the arm" \
  "I revoked the old token as part of cleanup. <stop>OPERATOR-GATE: PR #8244 is green and awaiting your merge.</stop>"

# ── LEGITIMATE STOPS, verbatim from the session that motivated this arm ─────────
expect ALLOW "waiting on an in-flight CI run" \
  "Pushed. <stop>OPERATOR-GATE: waiting on CI for PR #8244 -- in-flight checks, not a decision of yours.</stop>"
expect ALLOW "waiting on in-flight review agents" \
  "Spawned. <stop>OPERATOR-GATE: waiting on 7 of 8 review seats -- in-flight agents, not a decision of yours.</stop>"
expect ALLOW "names a merge it will perform ITSELF on green" \
  "Green so far. <stop>OPERATOR-GATE: waiting on the aggregate test gate. On green I merge without asking.</stop>"
expect ALLOW "mid-flight production apply, nothing actionable" \
  "Applying. <stop>OPERATOR-GATE: apply run 35215052952 is mid-replace; the host is being replaced now.</stop>"
# LOAD-BEARING escape row. The obvious "awaiting your authorization" fixture allows
# because PARKED_RE never matches it ("authorization" is not in the object set), so
# it passes for a different reason than the one it names -- measured: deleting
# PARKED_AUTH_RE entirely left the suite GREEN until this row existed.
expect ALLOW "PARKED_RE fires, and the irreversible-prod escape is what rescues it" \
  "Plan is ready. <stop>OPERATOR-GATE: awaiting your review of the irreversible production wipe before I run it per-command.</stop>"
# Residual #5 says forcing a real question through is the worse failure. This arm
# runs above the message-level question escape, so it carries its own.
expect ALLOW "a turn ending in a genuine question is not parked work" \
  "<stop>OPERATOR-GATE: PR is awaiting your review.</stop> Which approach do you want?"

# ── each escape alternative pinned ALONE ───────────────────────────────────────
# The single escape row tripped `irreversible`, `wipe` AND `per-command` at once,
# so each rescued the other two: deleting any ONE of the eleven alternatives left
# the suite green. Cardinality 1 on a redundant fixture is not coverage. These
# three trip exactly one apiece; `hr-menu-option-ack-not-prod-write-auth` is the
# rule the escape honours, so its own vocabulary is what needs pinning.
expect ALLOW "escape: irreversible, alone" \
  "Plan is ready. <stop>OPERATOR-GATE: awaiting your review of the irreversible migration.</stop>"
expect ALLOW "escape: per-command ack, alone" \
  "Staged. <stop>OPERATOR-GATE: awaiting your review, per-command, before I proceed.</stop>"
# `destroy` covers `ack-destroy` by substring, so a dedicated alternative for the
# latter is unpinnable by construction — measured: breaking it left the suite
# green because `destroy` rescued the fixture. Removed from the pattern rather
# than documented as equivalent; this row pins what remains.
expect ALLOW "escape: destroy, alone (covers the ack-destroy literal too)" \
  "Plan graded. <stop>OPERATOR-GATE: awaiting your review of the ack-destroy line.</stop>"

# ── the tag alternation, and WHICH tag is selected ─────────────────────────────
# A `BLOCKED:` parked fixture existed at HEAD and I rewrote it to OPERATOR-GATE
# while adding rows, so every parked BLOCK row used one alternative and the other
# went dark: narrowing the tag pattern to (OPERATOR-GATE) then survived.
expect BLOCK "the BLOCKED: tag alternative parks work too" \
  "Finished. <stop>BLOCKED: this is awaiting your merge.</stop>"
# `tail -n 1` selects the LAST tag. With `head -n 1` a turn that DOCUMENTS the
# sentinel first and parks second escapes — the self-disarm-by-documenting class
# this hook's history is built around. The promise arm has a fixture for it; the
# parked arm had none, because no parked fixture carried two tags.
expect BLOCK "a documented sentinel first, real parking last" \
  "The escape hatch is <stop>BLOCKED: what is blocking</stop> as documented. And now: <stop>OPERATOR-GATE: PR #8244 is green and awaiting your merge.</stop>"

# ── `ship` is in the arm's stated object set and had no fixture ────────────────
expect BLOCK "ship is an object verb, not just merge and review" \
  "Release notes written. <stop>OPERATOR-GATE: awaiting your ship of the 0.265.0 tag.</stop>"
# The word boundary on `awaiting (review|merge)`. The IDENTICAL guard on
# `needs a human` is pinned; this site was not, so one row on the boundary axis
# read as covering the axis while covering one of its two sites.
expect ALLOW "boundary: 'awaiting reviewers' is not 'awaiting review'" \
  "Staffing note. <stop>OPERATOR-GATE: awaiting reviewers to be assigned by the other team.</stop>"

# ── the arm's OUTPUT is the whole mechanism, so it is asserted ──────────────────
# A Stop block changes behaviour only through what the model READS. With only
# `.decision == "block"` asserted, PARKED_REASON could be replaced with "x" (1093
# chars deleted) and the suite stayed green -- as could emitting the PROMISE arm's
# reason verbatim, which would tell a parked turn to go execute a commitment it
# never made. The promise path already has two `.reason` assertions; this arm had
# none.
PARKED_BODY=$(jq -n --arg m "Done. <stop>OPERATOR-GATE: PR #8244 is green and awaiting your merge.</stop>" \
  '{last_assistant_message:$m}' | bash "$HOOK" 2>/dev/null)
PARKED_RC=$?
EXPECT_ROWS=$((EXPECT_ROWS + 1)); echo x >> "$INVOCATION_LOG"
printf '%s' "$PARKED_BODY" | jq -e '.reason | test("rf-never-skip-qa-review-before-merging")' >/dev/null 2>&1 \
  && pass "parked reason cites the rule it enforces" || fail "parked reason cites the rule it enforces"
EXPECT_ROWS=$((EXPECT_ROWS + 1))
printf '%s' "$PARKED_BODY" | jq -e '.reason | test("in THIS turn")' >/dev/null 2>&1 \
  && pass "parked reason states the required action" || fail "parked reason states the required action"
# The carve-outs are the half that prevents harm: an earlier revision blocked 13 of
# 15 rule-mandated gates and told the model to act anyway. If the exemptions are
# deleted from the message, the model loses the only signal that those stops remain
# legitimate.
EXPECT_ROWS=$((EXPECT_ROWS + 1))
printf '%s' "$PARKED_BODY" | jq -e '.reason | test("hr-menu-option-ack-not-prod-write-auth") and test("COST or SCOPE") and test("in-flight")' >/dev/null 2>&1 \
  && pass "parked reason names the stops it does NOT block" || fail "parked reason names the stops it does NOT block"
# The two block arms must be distinguishable downstream; emitting the promise arm's
# systemMessage for a parked turn survived every row.
EXPECT_ROWS=$((EXPECT_ROWS + 1))
printf '%s' "$PARKED_BODY" | jq -e '.systemMessage | test("parked on the operator")' >/dev/null 2>&1 \
  && pass "parked systemMessage is distinct from the promise arm's" || fail "parked systemMessage is distinct from the promise arm's"
# Protocol: this hook blocks by JSON on stdout at rc 0. Appending `exit 2` to the
# block path (a DIFFERENT Claude Code protocol -- stderr as the reason) survived.
EXPECT_ROWS=$((EXPECT_ROWS + 1))
[ "$PARKED_RC" -eq 0 ] \
  && pass "a parked block exits 0 and speaks via stdout JSON, not rc 2" || fail "a parked block exits 0 (got rc=$PARKED_RC)"

SUT_RUNS=$(wc -l < "$SOLEUR_HOOK_TRACE" 2>/dev/null | tr -d ' ')
SUT_RUNS=${SUT_RUNS:-0}
INVOCATIONS=$(wc -l < "$INVOCATION_LOG" 2>/dev/null | tr -d ' ')
INVOCATIONS=${INVOCATIONS:-0}
MIN_INVOCATIONS=51
# THE SUT-WRITTEN FLOOR, checked FIRST. This is the one a neutered harness cannot
# satisfy, because only the hook appends to it.
MIN_SUT_RUNS=55
if [ "$SUT_RUNS" -lt "$MIN_SUT_RUNS" ]; then
  printf '[FATAL] coverage: the hook itself ran %s time(s), floor is %s -- the harness is certifying rows it never spawned the SUT for\n' \
    "$SUT_RUNS" "$MIN_SUT_RUNS" >&2
  exit 1
fi
# The harness-side counter stays as a CONSERVATION check against the SUT-written
# one: they must agree, so a harness that inflates its own count without spawning
# (or a hook that runs without the harness knowing) is caught by the mismatch.
# Direction matters. SUT_RUNS >= INVOCATIONS is the invariant: verdict() spawns the
# hook once per call, and several rows spawn it DIRECTLY without going through
# verdict() (the fail-open and payload-shape rows), so the SUT legitimately runs
# more often than the harness counts. The reverse -- the harness claiming more
# invocations than the hook actually served -- is exactly the neutered-harness
# defect this pair exists to catch. Measured on the real suite: 43 vs 47.
if [ "$INVOCATIONS" -gt "$SUT_RUNS" ]; then
  printf '[FATAL] coverage: harness counted %s invocation(s) but the hook ran only %s time(s) -- the instrument is not attached to the subject\n' \
    "$INVOCATIONS" "$SUT_RUNS" >&2
  exit 1
fi
if [ "$INVOCATIONS" -lt "$MIN_INVOCATIONS" ]; then
  printf '[FATAL] coverage: %s SUT invocations, floor is %s -- the harness is not running the hook\n' \
    "$INVOCATIONS" "$MIN_INVOCATIONS" >&2
  exit 1
fi
MIN_EXPECT_ROWS=51
if [ "$EXPECT_ROWS" -lt "$MIN_EXPECT_ROWS" ]; then
  printf '[FATAL] coverage: %s expect rows, floor is %s -- rows were removed\n' \
    "$EXPECT_ROWS" "$MIN_EXPECT_ROWS" >&2
  exit 1
fi
echo ""
echo "=== $PASS passed, $FAIL failed ($INVOCATIONS SUT invocations, $EXPECT_ROWS expect rows) ==="
[ "${#FAILURES[@]}" -gt 0 ] && printf 'FAILED: %s\n' "${FAILURES[@]}" >&2
MIN_ASSERTIONS=62
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
