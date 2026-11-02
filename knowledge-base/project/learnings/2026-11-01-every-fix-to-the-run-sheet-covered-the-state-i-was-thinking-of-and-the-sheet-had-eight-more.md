---
synced_to: [review]
---

# Learning: every fix to the run sheet covered the state I was thinking of, and the sheet had eight more

## Problem

PR #11812 (Record PR, refs #8211 and #11704), 2026-11-01. The PR added a step-by-step owner run sheet (RF0 to RF9) for the first real git-data flip to `git-data-luks-cutover-5274.md`. It is prose, but it is a state machine: the owner follows it with the flag, the new-sessions pause, the exemption variable, the freeze sentinel, the cutover stamp and both hosts' `git_data_store=` lines all moving, and a wrong action loses a real user's only copy of a working tree.

1. **The first six-seat panel found 2 P1 and about 25 P2.** The P1s: the hold-limit exit sent the owner to the pre-flag abort path, which ends in pause OFF, after the store flag was already on; and the rollback gate after the pause was lifted counted live sessions only, which cannot see the trees of sessions that already ended without replicating.
2. **The first fix commit introduced 3 new P1 and about 12 P2.** The abort path was keyed on the flag alone (a half-unwound run, flag false with a host still `enabled`, sent the owner to pause OFF); the sheet called a re-pause "cheap and reversible" while the amendment I had just written forbade the `off` that reverses it; the counted-loss rule covered three trigger names instead of the state "a session ended in the window without replicating".
3. **The second fix round left one P1 and several P2.** A routine deliberate deploy had no counted-loss gate, and the read-state rule ignored the cutover stamp, the channel to read the sentinel while the flag is true, and the neighbouring Quiet-window sentences the new blockquotes did not supersede.
4. **A claim about code was written without reading the code.** "Running containers keep the baked mirror until a deploy" was false: `isNewAgentSessionsPaused()` returns the last known value OR the baked mirror on every Flagsmith miss, so a container baked with mirror 1 refuses a new session whenever Flagsmith does not answer.

## Solution

- **One read-state rule keyed on the failure table's own first step.** Read the flag, the freeze sentinel, the stamp and both hosts' `git_data_store=` lines; a failed read is `STATE UNKNOWN`. Three cases (flip not in effect; unknown, keep the pause on and never run `off`; flip in effect) replaced three per-row pointers that each named an action valid in only one state.
- **Walk the state space at every fix round, by reading.** List every variable (flag x pause x exemption x sentinel x stamp x per-host state x before/after the irreversible step) and name the action each sentence prescribes in each reachable state. Two sentences prescribing different actions in one state, or none, is a P1 whatever the wording.
- **Count loss as N, and let unknown dominate.** Every rollback or deploy after the pause is lifted needs `agent_sessions_live=0` AND the owner's typed words naming N counted from failure rows; the replication marker is presence-only, so N is unknown for the signal-group states, an unknown N dominates any counted rows, and it persists for the soak.
- **Send forks to the CTO in batches, never to the owner.** Two rounds, 18 rulings. Read the code behind each premise first: reading `isNewAgentSessionsPaused()` falsified a premise in a CTO ruling and changed RF6 from "repeat `off`" to "an intermittent refusal is a fail-safe availability effect, never a lost tree".
- **Treat a coverage consult's reply as a lead.** It named five absent classes; two verified (host reboot during the soak, row age) and the rest were already covered or refuted by the workflow (`cancel-in-progress: false`, no schedule).
- **Read the PASS-count delta on a doc-pin suite.** `git-data-cutover-access.test.sh` read 822 passed, 0 skipped on two runs and 795 passed, 27 skipped on two others: its docker runtime arm skipped on a transient `apt` failure inside the fixture container. Exit 0 either way; the line that names the skip is the evidence.

## Key Insight

A fix to prose that prescribes a procedure is written against the state its author is holding in mind, so it closes that state and leaves its neighbours. The review that finds the next defect is not a closer reading of the new sentence; it is the same walk over the whole state space that the first fix did not do. Do that walk before the first fix, key every abort and retry on the failure table's first step rather than on one variable, and expect the second round to find what the first walk skipped.

## Session Errors

1. **`until s=$(gh …); do … sleep; done` never waited.** `until` tests the exit status of the assignment, which is 0, so the Monitor ended at once while the PR was still queued. Recovery: `while true; do s=$(…); case "$s" in …) break;; esac; sleep 90; done`. **Prevention:** never put a command substitution assignment in an `until` or `while` condition; assign inside the body and test the value.
2. **Guessed helper path `plugins/soleur/scripts/session-state.sh`** (real path `plugins/soleur/scripts/lib/session-state.sh`). Recovery: `find`. **Prevention:** `ls` or `find` a helper before running it from memory.
3. **The queue's "merge strategy is set by the merge queue" message read as an error.** It was the queue accepting the request. Recovery: GraphQL `isInMergeQueue` and `mergeQueueEntry` showed position 2, QUEUED. **Prevention:** after a `gh pr merge` that prints text and no URL, read the queue state before concluding.
4. **The planning subagent returned without a `## Session Summary`.** Recovery: the partial-artifact check found the plan on disk with `## Acceptance Criteria` and `## Research Insights`. **Prevention:** none beyond the existing recovery; keep it.
5. **The first fix commit introduced new P1s** (see Problem 2). **Prevention:** the state-space walk before the first fix, and the one bullet routed to `review/references/risk-tier-and-fix-rounds.md`.
6. **A claim about code written without reading the code** (see Problem 4). **Prevention:** before writing a sentence that says what a function returns, read the function.
7. **Ruling gate failure:** a technical row whose ruling cell began "Applied as direct consequences…" instead of "Ruled by CTO agent, <date>:". Recovery: rewrote the cell. **Prevention:** write a ruling row by copying the shape, then re-run `technical-ruling-gate.sh --branch` before the commit.
8. **Tool timeouts under machine load (rc=124).** The cutover-access suite hit its own 280 s timeout at load average about 16, a chained run was moved to the background at 600 s, and `--print-selection` timed out once. Recovery: re-ran alone with a longer bound (216 to 255 s). **Prevention:** a timeout is unresolved, not a pass; read `/proc/loadavg`, give a suite its measured duration, and re-run alone.
9. **A session-record sentence claimed "doc-pin suites 822/0" before the summary line was read.** The next run read 795 passed, 27 skipped. Recovery: corrected the sentence in a follow-up commit. **Prevention:** read the suite's final summary line before writing any count into a record.
10. **Working-directory drift.** The environment reported the primary directory changing between worktree and repo root. Recovery: absolute paths and a `git branch --show-current` check before each write. **Prevention:** begin every Bash call with an absolute `cd` to the worktree.

## Tags

category: review-process
module: soleur:review, runbooks
