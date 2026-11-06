---
title: A probe that could finally pass would have closed its own tracker on pre-restart evidence
date: 2026-10-28
category: workflow-patterns
tags: [follow-through, observation-window, sweeper, restart-floor, mutation-battery, review]
module: scripts/followthroughs
---

# Learning: making a probe's PASS reachable makes everything its PASS triggers reachable

## Problem

The S4 observation-window probe (tracker #10865) could never pass: it took each run's PR from the run's own
`pull_requests`, which GitHub empties when the PR merges, so 135 of the 151 green runs named no PR and the
distinct-PR count was 0 by construction. The fix (attribute such a run through `commits/<sha>/pulls`) made PASS
reachable, and a single live read-only run then returned exit 0 with 18 distinct PRs.

The plan, the plan-review panel, the CTO rulings and a green 1250-assertion suite all treated "the verdict can now be
PASS" as the goal. Nobody had read what a PASS **does**: `scripts/sweep-followthroughs.sh` closes the tracker on exit 0
(posting its own PASS comment, and never reopening a closure it justified itself). The plan's observability section said the
sweeper "comments". Only the architecture and history seats of the review panel read the sweeper, and found that:

1. The probe counted from the PR3a merge while the runbook's drain-claim paragraph and issue #10949 record that the window
   counts only runs created after the latest merged `s4-drain` PR (PR5, 2026-10-26T21:59:35Z). #10949's own
   re-evaluation criterion ("if the probe is touched for another reason") was met by this very PR.
2. So most of the 156 units behind the PASS predated the recorded restart, and the first sweep that runs the probe
   (2026-10-31) would have closed the tracker on them, irreversibly.

## Solution

Read the `s4-drain` label list once (fail-closed: non-list, malformed timestamp, `date -d` failure and a full page of 100
are all exit 3) and count from the later of the PR3a merge and the latest drain merge; `age_days` and the 30-day
triggers stay on PR3a; the status line says `floor=pr3a|s4-drain`.

## Key Insight

When a change makes a verdict **reachable** that was unreachable before, list what the verdict triggers (here: a
tracker close) and re-verify every criterion that was previously masked by the verdict being unreachable. Two
recorded rules (the runbook's drain restart, the 30-day ceiling re-rule) had been inert for exactly that reason.

## Session Errors

1. **Technical-ruling gate rejected the ruling rows** (`bad-ruling-shape`): rows prefixed `[Amended by ...]` or reading
   `Ruled by CTO agent, <date> (re-ruling), ...`. Recovery: reshape to `Ruled by CTO agent, <date>: ...`.
   **Prevention:** the gate already caught it; plan subagents should run `technical-ruling-gate.sh --branch` before returning.
2. **Mutant `old` strings went stale each time I edited the probe line they anchor** (retry-twice,
   retry-ignores-rate-flag, drain-floor-ignored, drain-timestamp-unvalidated): each cost a 10-35 minute full-suite run
   to discover, because `ow_mutate` verifies landing only when the suite reaches it. **Prevention:** after editing any
   probe line, grep every `^ow_mutate` old string against the probe (or run the OW-only driver with every mutant
   enabled) before the full run; a cheap landing check beats a full battery.
3. **A mutant that removes its own termination hangs the battery** (`[ "$tries" -eq 0 ]` -> `-le 1` with `tries=1`
   never incremented looped forever; the 9m40s timeout hid it). **Prevention:** write a "second retry" mutant as the
   whole line including the counter increment, and run mutant batteries under `timeout`.
4. **My own cleanup glob (`ERR*_*commits_*`) deleted another section's fixtures**, flipping an unrelated mutant
   (`cleared-read-error-as-cleared`) to SURVIVED; found only by running the PRE-change suite file against the tree.
   **Prevention:** anchor fixture cleanup globs on a prefix only this section's fixtures carry (here an 8-zero sha).
5. **`fixture-relative-assert` read `[[ "$a" > "$b" ]]` as a redirect** (a string comparison inside `[[ ]]`).
   **Prevention:** compare timestamps as epochs with `(( ))`, which also validates them; do not use `>` in `[[ ]]`.
6. **A test row passed for a different reason than it stated** (`${x% *}` stripped the branch, not a mode field; found by two
   seats). **Prevention:** print what a table-driven fixture parses into once, before trusting the row.
7. **Plan read the sweeper's exit-code contract wrongly (comment vs close) and never read the runbook paragraph for the
   tracker it was editing.** **Prevention:** see the plan-sharp-edges bullet added with this learning.
8. **Closing messages naming a future action tripped the unkept-promise stop hook** while waiting on background seats.
   **Prevention:** end waiting turns with one `Paused:` sentence (already hook-enforced).
9. **A Monitor armed for a suite expired at 30 minutes under load** (box load 13 from other worktrees; the run needed
   ~45). **Prevention:** check the run is still alive before concluding it hung; re-arm.
