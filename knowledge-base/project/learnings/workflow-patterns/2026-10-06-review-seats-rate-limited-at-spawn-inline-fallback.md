# Learning: review seats can rate-limit at SPAWN, not only mid-work

**Date:** 2026-10-06
**Session:** `feat-one-shot-9614-9618-canary-capture-fixture` (PR #9636, issues #9614/#9618)

## What happened

A `soleur:one-shot` run dispatched all 8 review-panel seats as parallel
`run_subagent` calls on Devin CLI. All 8 returned the same spawn-level error —
`Reached free model rate limit ... reset in 34 minutes` — before producing any
output. Zero seats ran.

`review/SKILL.md` Gate 2a covers "agents CANNOT be spawned" (harness/tool
absence) and Gate 2b covers "agents spawned but died/returned empty." A
rate-limited *spawn refusal* sits between the two: the dispatch happened, the
agent never began, so there is no transcript to resume (`SendMessage`/`resume`
has nothing to continue) — the retry is a fresh re-spawn, and only after the
blocking condition clears.

## What worked

- The all-failed path is covered end-to-end anyway: Gate 2b's "ALL agents
  returned empty output or rate-limit errors" clause fires on this shape, the
  inline review runs, and `emit-review-trailer.sh --mode inline-fallback
  --agents-ran 0 --agents-expected 8` records honest degraded coverage that
  `soleur:ship`'s evidence gate can distinguish from a full panel.
- No invented coverage: the trailer emitted `Reviewed-Coverage: inline-fallback
  0/8` and session-state.md records the optional resume point (re-run the panel
  after the reset window).

## Session Errors

1. `worktree-manager.sh draft-pr` push rejected (`remote rejected ... (failed)`)
   — transient; immediate manual `git push -u` succeeded. **Prevention:** none
   needed — the script's warn-and-continue contract already covers it; retry the
   push directly before treating it as a hard failure.
2. All 8 review seats rate-limited at spawn (free-model tier, ~34 min reset).
   **Prevention:** when `run_subagent` returns a rate-limit completion instead
   of a seat report, treat it as Gate-2a spawn-unavailable for that window —
   run the inline review, emit the degraded trailer, and record the re-run as
   an optional resume point rather than blocking the pipeline on the reset.
3. `git show main:<path>` returned nothing on a stale local `main` (detached
   HEAD checkout); the merged files lived on `origin/main`. **Prevention:**
   already covered by `rf-after-merging-read-files-from-the-merged` — read
   post-merge state from `origin/main`, never the local `main` ref.

## Tags
review-panel, rate-limit, devin-cli, sequential-fallback, trailer-coverage
