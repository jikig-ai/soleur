# Learning: `--print-affected-set` prints classes, not the diff's selection, and "make the gate affected + parallel" was already half shipped

## Problem

A parallel session reported the pre-ship gate "over-selected 229 mostly unrelated suites" and "ran serially". The request read as greenfield ("improve our workflow and skills to avoid unrelated suites and run in parallel"). It was not: ADR-242 already made the local gate affected-by-default, and local parallelism had been rejected on purpose (#3672 sharp edges) and reframed to CI (#8322 spec).

## Solution

Re-derived the premise before scoping:

- **Correction (same session):** `bash scripts/test-all.sh --print-affected-set` prints each registration's CLASS, not what the diff selects (`_affected_emit_receipt`, `scripts/test-all.sh:2477-2481`, never reads the diff). I first read its 306 lines as "306 selected" — wrong. Selection for a KB-only diff is the 145-entry always-on floor plus ~5 edge suites, all via one false-positive edge (bare `test` token from `bun test <file>`, substring-matched at `:2015`).
- The plugin ships no test gate at all: `work` / `ship` / `review` call the repo-local `scripts/test-all.sh`, so Soleur users' repos get neither selection nor parallelism. That is the real user-facing gap.
- Scoped the work into three tracked PRs (repo over-selection fix, plugin-generic gate, #8231 parallel scheduler) under #9307.

## Key Insight

Two claims hide inside "make the gate affected-only": whether the *mechanism* exists (it does, in the Soleur repo) and whether the *user* has it (they do not). Measuring selection on a trivially small diff is a cheap probe of "affected" quality — but only if the tool's output actually describes the selection. A per-registration classification receipt looks like a selection and is not; read the code that produces an output before quoting it as a measurement.

## Session Errors

1. **Session-start preamble call rejected by the operator** — I ran a condensed combined script (classifier + `cleanup-merged` + `.mcp.json` restore + decision emit) instead of the verbatim fences. Recovery: skipped the mutating preamble, ran only the decision emit. Prevention: run the fences verbatim, one per call, or say up front which steps are being skipped.
2. **A research agent reported `ALWAYS_ON_SUITES` = 547 entries** — real count is 145 (`awk` over the array and `source` + `${#ALWAYS_ON_SUITES[@]}` agree). Recovery: re-derived two ways before use. Prevention: already covered by brainstorm's "a subagent's COUNT is a claim to re-derive"; no new rule.
3. **`--print-affected-set` output truncated by `head -400`, and two commands exceeded the 120 s tool timeout** (the full enumerate and `worktree-manager.sh feature`). Recovery: re-ran to a file / waited for the background notification. Prevention: write long enumerations to a file first and count from the file; treat `--print-affected-set` as a >2 min command.
4. **`sleep 45 && cat ...` blocked by the tool guard** — Recovery: waited for the background completion notification instead. Prevention: use the completion notification or Monitor, never chained sleeps.
5. **Stop hook fired on a closing line that promised a next action** — Recovery: acted in the same turn (asked the scoping question). Prevention: do not end a turn with a first-person commitment while a question or tool call is the actual next step.

## Tags

category: workflow-issues
module: test-all, plugin skills (work, ship, review), brainstorm
