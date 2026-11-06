# Learning: an orphaned one-shot arm is silent, not pending — session-state.md and the worktree are the rescue contract

## Problem

A `soleur:one-shot` arm running branch `feat-one-shot-10390-ci-hygiene-batch` died ~19:07 UTC mid-fix-round: no watch armed on draft PR #12064, zero file writes for 90+ minutes, the session process gone. Nothing in-repo distinguished "still running" from "dead" — the same silent-vs-pending shape as unwatched async work (`hr-dispatch-async-must-arm-watch`), except the session that would have armed the watch is the one that died. The orphan was discovered by a human noticing the stall, not by an alarm.

## Solution

A second Devin arm took over on the SAME branch/worktree rather than starting a new pipeline, and it worked because the handoff artifacts were already on disk:

- `session-state.md` at `knowledge-base/project/specs/feat-one-shot-10390-ci-hygiene-batch/` held per-phase status, reported suite greens, pending fix-round seats, and the operator-step ledger — written at each phase boundary, it was the recovery contract.
- The worktree lease (`SOLEUR_SKILL_NAME` + `SOLEUR_EXPECTED_DURATION_MIN`) kept `cleanup-merged` from reaping the orphaned tree while it looked idle.
- The prior arm's uncommitted fix-round-3 lint work was committed as `774412182c`; its partial D edits folded into the D workstream commit; D/E/F then landed as per-workstream commits `d90b37f8fb` / `88b7ab1260` / `8d74cda097`.
- Verification ran fresh rather than trusting the orphan's reported greens — an inherited verification claim is a statement about a tree that may no longer exist (token-discipline §4; #7397).
- The resume prompt emitted at end-of-work (`wg-end-of-work-emit-resume-prompt`) carried enough branch/worktree/PR/phase state to re-enter with zero re-reading.

## Key Insight

Write the recovery contract BEFORE the work it describes: session-state updates and tasks.md ticks only rescue a dead arm if they were committed before the long-running step spawned — a takeover inherits `git status`, not the dead session's memory. The remaining gap is detection: the lease prevents reaping but nothing alarms on silence, so a dead arm is indistinguishable from a patient one until somebody looks. Partial machinery exists (#11631 deadman-armed record, #11672 feeder follow-ups) — an armed deadman on the PR would have converted a 90-minute human-noticed stall into a page.

## Session Errors

1. **`git commit` denied twice by `guardrails.sh` ("Committing directly to main/master")** — the hook's `--cwd` resolved to the main checkout because the tool envelope omits `.cwd`. Recovery: `cd <worktree> &&` prefix (and `git -C` where applicable). Prevention: tracked upstream as #8254; until it lands, every worktree git-write command carries an explicit `cd`/`git -C`.
2. **Planning subagent had no Task/agent-spawn tool** — every prescribed fan-out (research, domain leaders, spec-flow, review panel) ran inline sequential-fallback. Recovery: completed inline with `Reviewed-Coverage` disclosure. Prevention: probe spawn capability before writing fan-out briefs.
3. **The prior pipeline arm orphaned with no liveness signal** — see Problem/Solution above. Recovery: same-branch takeover. Prevention: commit session-state at phase boundaries; arm an external deadman on the PR for long autonomous arms.
4. This (resuming) session: none.

## Tags
category: workflow-patterns
module: one-shot, session-state, worktree-manager
