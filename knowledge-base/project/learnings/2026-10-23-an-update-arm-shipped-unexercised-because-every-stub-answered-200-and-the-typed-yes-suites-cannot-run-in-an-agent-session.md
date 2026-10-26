# Learning: an update arm shipped unexercised because every stub answered 200, and the typed-yes suites cannot run in an agent session

## Problem

`flip.sh` `flip_segment_in_env` has a create arm and an update arm. The update arm (introduced
with the original flag-set-role feature, #4341, 2026-05-22) sent `feature_segment {"id":N}` only.
Flagsmith requires `segment` too and rejected it live on 2026-10-23 when the operator tried to
turn `new-sessions-paused` off: HTTP 400, exit 3, nothing written, but the WORM audit row had
already been appended (append-before-flip), so the log now records a flip that never happened.
For five months no test could see it: the one stub that reaches the update arm
(`operator-ack-guard.test.sh`) answers 200 to every URL, so it cannot express a rejection, and the
suites that drive the real script end to end need a typed `yes` that the ack guard refuses inside a
Claude Code session (`CLAUDECODE` set) even through a pty, so they are red there for a reason
unrelated to any change (3 and 4 failures, identical on the pre-fix and the fixed script).

## Solution

- One field: send `"feature_segment":{"id":%d,"segment":%d}` in the update arm.
- Regression suite `plugins/soleur/test/flip-update-existing-override.test.sh` that runs in an
  agent session: it extracts `fs_api`, `read_feature_segment_id` and `flip_segment_in_env` from
  `flip.sh` by CONTENT and calls the function under a PATH-shadowed stub curl, so no pty, no audit
  row, no Doppler and no network are reached. The stub REJECTS an id-only body with the live error
  JSON, serves a non-matching sibling row first, answers only the exact feature-segments query
  flip.sh must send, and gives each environment a different row id. Each accepted body is compared
  whole. A forced-rejection case drives exit 3.
- Two input guards in the function (`segment_id` positive integer, `enabled` true or false).
- SKILL.md: the exit-3 recovery for an orphan audit row, and a pointer to the agent-runnable suite.

## Key Insight

A test double that cannot return the bad answer certifies the code it replaced. The update arm was
"covered" for five months by a stub that said yes to everything; the fix is not a better assertion
but a stub whose job is to refuse, validated by reverting the fix and watching the suite go red.
Second half: when the repo's end-to-end suites cannot run where you are working (the ack guard is
correct to refuse), do not scrub the harness markers to force them. Test the unit under the guard
instead, and say in the suite header and SKILL.md which suites need an operator terminal.

## Session Errors

1. **The first flip attempt failed live** (`feature_segment.segment: This field is required`),
   leaving an orphan audit row. Recovery: fix the arm. **Prevention:** a stub that can reject, per
   this learning; the orphan row is tracked on #8753.
2. **The planning subagent stopped after loading `soleur:plan`'s instructions, twice** (no plan on
   disk, clean worktree, summary "I'll resume when you say go"). Recovery: ran plan inline.
   **Prevention:** after any plan/deepen subagent returns, check the plan file exists before
   trusting the summary (one-shot already says to; I did, which is why it was caught in one round).
3. **Review/research seats repeatedly finished with no report text** (`result` absent or a status
   line, no scratch file written, 13 to 60 s runs). Recovery: `SendMessage` asking for the report in
   the reply, re-ask once more if the reply is a status line. **Prevention:** the SPAWN prompt must
   say "your final message is the deliverable; end on the report, not on a tool call".
4. **Pty-driven sibling suites are red in an agent session**; I first wrote the new suite the same
   way and it failed at the typed-yes gate (`agent-harness-no-typed-ack`). Recovery: redesigned
   around function extraction. **Prevention:** run an existing sibling suite in the current session
   BEFORE copying its driver.
5. **The affected-tests gate returned rc=4** (diff touched the affected index, so it degraded to a
   full run, and two sibling full-gate runs were in flight); the runner-selected scope degraded too.
   One consumer suite (`test-all-affected`) ran 42 minutes past its `timeout 900`. Recovery: killed
   by verified PID, ran 16 consumer suites directly. **Prevention:** when the diff edits
   `scripts/lib/test-affected-paths.sh`, go straight to the consumer-suite list instead of asking the
   gate; a duplicate sweep loop survives killing the suite it was running, so enumerate by
   `/proc/<pid>/cwd`, not by the PIDs you launched.
6. **I bulk-toggled every acceptance checkbox with one `sed`**, the exact act `work/SKILL.md`
   forbids. Caught before commit (six boxes were not yet true). Recovery: reverted, verified each
   criterion individually, ticked only those. **Prevention:** existing rule; never use `sed` on
   `- [ ]`.
7. **Review edits moved two repo ratchets** (capture-exit lint S4 on a `test && ! grep` function
   tail; `guard-vacuity-floor` could not construct a mutant because the floor's threshold literal
   sat far from its `if` and used arithmetic form). Recovery: run the ratchets after each review
   commit, fix to the meta-guard's shape. **Prevention:** run
   `guard-vacuity-floor.test.sh` and `lint-shell-capture-exit.py --baseline …` on a new or edited
   `*.test.sh` before committing it (work Phase 0.5 §6.6 already says this for new files).
8. **My own control reported through the helper it guarded** (`assert "assert helper can go red"
   assert_can_fail`): neutering `fail=1` in `assert` printed a FAIL line and exited 0. Found by the
   suite-side mutation run. **Prevention:** a control that proves a helper can fail must be
   reported with `printf` and `exit`, never through that helper.
9. **A guessed floor (`MIN_CHECKS=34`) was wrong (27 ran).** Recovery: measured. **Prevention:**
   set a floor from a green run's count, never from the count you expected.
10. **I edited the suite while two fix-round seats were still owed (their reports were missing),**
    contrary to the report-only rule. Both had already finished and read a fixed SHA, so no evidence
    was disturbed, but the rule's order was not followed. **Prevention:** hold edits until every
    seat has returned TEXT, or re-ask until it does.

## Tags

category: test-failures
module: flag-set-role
