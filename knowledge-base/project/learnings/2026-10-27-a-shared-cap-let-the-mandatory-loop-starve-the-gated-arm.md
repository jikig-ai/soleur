# Learning: a shared cap let the mandatory loop starve the gated arm, and the tests pinned the refusal as correct

## Problem

WikiSkill Phase 2 shipped the create arm of `cron-compound-promote`, dark-launched and manual-only, sharing the
week cap (`WEEK_CAP_DEFAULT = 2` open `self-healing/auto` PRs) with the edit loop, which ran first. The first
live-fire (2026-10-27, run `01M5YB28JD20JKKH4HG04CX2Z4`, zero open PRs beforehand) ended `create-refused`, class
`week-cap`, detail `no-slot`: the edit loop opened two draft PRs and took both slots before the arm ran. With two
qualifying edit clusters the arm was unreachable on a clean state.

## Solution

Hold one slot back for the arm: `editCap = allowCreate ? Math.max(remaining - 1, 0) : remaining`, used in the
clustering prompt, the post-parse slice, and an early return in the `anthropic-cluster` step (step id unchanged).
Scheduled, corpus and non-`true` runs are byte-identical. Runbook, ADR-092 and ADR-300 amended.

## Key Insight

Three things made this invisible before the live-fire. (1) The design (G2, "edit loop first, arm shares the cap")
was ruled on semantics, never driven with the loop at its maximum yield. (2) The tests for the cap asserted the
refusal (`one slot left and the edit loop spending it -> week-cap`) as EXPECTED, so the unreachable case was
encoded as correct and the suite stayed green. (3) The arm's main scenario was only ever run with the loop
returning zero or one cluster. Rule of thumb: for a gated optional arm that shares a budget with a mandatory
stage, the test matrix must include "mandatory stage at its maximum yield" and assert the optional arm still runs;
a test whose title says the arm is refused in its own headline scenario is a reachability bug written down.

## Session Errors

1. **Plan subagent wrote `decision-challenges.md` rows that failed `technical-ruling-gate.sh`** (technical rows
   without `Ruled by CTO agent, <date>: ...` shape; class `mechanical`). Recovery: reclassified planner calls as
   `taste`, kept the CTO row in ruling shape. **Prevention:** brief the planner with the exact row shape and the
   three allowed classes (`technical`, `taste`, `operator (<category>)`); run the gate before `work`.
2. **A foreground `sleep 90 && ...` was blocked by the hook.** Recovery: Monitor with an until-loop.
   **Prevention:** poll with Monitor/`run_in_background`, never a foreground sleep.
3. **Monitor emitted only the first line of a pretty-printed JSON row.** Recovery: re-queried the full row.
   **Prevention:** have a monitor emit `jq -c` single-line summaries, not multi-line objects.
4. **The affected-test gate queued 30+ minutes behind another worktree's stalled full run** (`position=3`).
   Recovery: proceeded on the targeted suites, tsc and markdownlint; left the other session's process alone.
   **Prevention:** run `scripts/test-all.sh --capacity` before launching and read the holder's worktree.
5. **A closing message named an action not yet taken and the stop hook blocked it.** Recovery: ended with a
   `Paused:` sentence stating the real wait. **Prevention:** end a waiting turn with `Paused:`/`Blocked:`.
6. **Cited the arm's merge date as 2026-10-26** (the git-history seat measured 2026-10-27 UTC). **Prevention:**
   take dates from `gh pr view --json mergedAt`, not from a branch or ADR date.

## Tags

category: logic-errors
module: compound-promote
