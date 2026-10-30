# Learning: reversing a fixture's order closes the first-element survivor only — put the extreme in the middle

## Problem

Fixing `ci-head-verdict.sh` so its stall clock starts at the head's first appearance in CI (PR #10873, umbrella #9757 item 3) added a rule that takes the earliest check suite. The tests listed the suites oldest first, so the earliest was also the first element and the last element equalled the maximum's opposite. Mutating `(min | tostring)` to `(.[0] | tostring)` survived. The review's test-design seat flagged it; the fix flipped the fixtures to newest first, as the real API lists them. That closed the `.[0]` mutant. A second seat then showed that `.[-1]` instead of `min`, and the last page instead of all pages, still survived, because with a strictly descending list the earliest is now the last element and on the last page. Two rounds were spent on one defect class.

Separate observation: the plan prescribed a mutant ("drop T from `max(T, A)`") that is equivalent by construction, because the outer gate (`NOW - T > N`) already holds whenever `A <= T`. The plan's claim that the `max` line was load-bearing was wrong, and it was caught only when writing the mutant and seeing both sides give the same verdict.

## Solution

Place the extreme value in the MIDDLE of the ordered fixture (suites at 7900, 7500, 7700 with the earliest in position 2 of 3; the same three as one-suite pages). Then first, last, `min`, `max`, first page and last page all give different answers, and one row kills every positional mutant. Add a mutant per positional shortcut (`.[0]`, `.[-1]`, first page, last page). Drop mutants that are equivalent by construction and pin the behaviour with a row instead, saying so in a comment.

## Key Insight

A fixture whose order is monotonic cannot tell "the extreme" from "an end". When closing a survivor of the form `extreme -> first element`, reversing the order only moves the coincidence to the other end. Test the extreme at a position that is neither end, and enumerate positional shortcuts in both directions (`first`, `last`) before declaring the survivor closed. Companion: before adding a mutant, check it is not equivalent given the guard upstream of it; an equivalent mutant is a documentation burden, not coverage.

## Session Errors

1. **Plan-subagent could not find the CTO follow-up list in the issue** (forwarded from session-state.md). Recovery: recovered from the held-merge session transcript. **Prevention:** a handoff naming "P2/P3/P4" must carry the definitions in a durable artifact (issue comment or plan), not a transcript.
2. **A new helper write under `$d` raised the fixture-relative ratchet from 3 to 4.** Recovery: copied the canonical `assert_fixture_dir` guard and called it. **Prevention:** already covered by work/SKILL.md Phase 0.5 check 6.6; run `fixture-relative-assert.test.sh` before the first commit of any new `*.test.sh` write helper.
3. **A mutant's old-string matched twice** (`and .head_sha == $h` also exists in `read_test_row`). Recovery: widened the string. **Prevention:** the harness's "lands exactly once" check caught it; keep that check.
4. **The plan's M39 mutant was equivalent by construction.** Recovery: dropped it and pinned the behaviour with row V25d. **Prevention:** at plan time, ask of each prescribed mutant whether an upstream gate already forces the same verdict.
5. **Fixture order closed only the first-element survivor** (above). Recovery: middle-extreme fixtures plus mutants M48 and M49. **Prevention:** when fixing a "first element equals the extreme" survivor, place the extreme in the middle.
6. **Plan ACs went stale after review fixes** (`see ci-head-verdict.sh for the stall clock` became `... --help ...`). Recovery: QA ran the AC commands literally and amended the two ACs. **Prevention:** re-run the plan's AC commands after the last fix round, not only after implementation.
7. **A shell command contained `git stash list`** and was blocked by the PreToolUse hook. Recovery: re-ran without it. **Prevention:** already hook-enforced.
8. **The Stop hook rejected closing text that named a future action.** Recovery: ended with an explicit `Paused:` sentence. **Prevention:** already hook-enforced; when waiting on background seats, close with `Paused: <what>`.
9. **A long affected-test gate returned rc=6 (budget deferred).** Recovery: recorded CI as the authoritative gate per the contract and ran the suites covering the diff directly. **Prevention:** none needed; the contract held.

## Tags
category: test-failures
module: plugins/soleur/scripts/ci-head-verdict.sh
