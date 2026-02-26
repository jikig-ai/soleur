# Draft PR Workflow Brainstorm

**Date:** 2026-02-25
**Status:** Complete

## What We're Building

A "draft PR early, commit per phase" workflow pattern for the Soleur plugin. Currently, brainstorm and plan phases write markdown artifacts to local disk but never commit or push them. A hardware failure, session crash, or device switch loses all uncommitted work. The PR isn't created until `ship` Phase 7 — far too late for cross-device handoff.

The change introduces two behaviors:

1. **Draft PR at workflow start:** When a worktree or feature branch is created (brainstorm Phase 3, one-shot Step 0b), immediately create an empty commit, push, and open a draft PR. This establishes a remote coordination point from the first moment of work.

2. **Commit at phase boundaries:** Each skill phase that produces artifacts commits them at the end of the phase. Pushes happen at skill boundaries (end of brainstorm, end of plan, during work increments). This ensures local crash recovery at every phase and remote recovery at every skill boundary.

## Why This Approach

### Primary Drivers (equal weight)

- **Data loss protection:** Brainstorm and plan artifacts exist only on local disk today. A crash or power failure wipes them.
- **Cross-device handoff:** Starting work on one machine and continuing on another requires the branch + PR to exist on remote. Currently impossible until ship runs.

### Key Insight

The "commit is the gate" rule (Learning #10: review → compound → commit → push → CI → merge) applies to the **final shipping commit**, not to WIP commits during the lifecycle. The `work` skill already does incremental WIP commits in Phase 2 — so intermediate commits are an accepted pattern. We're extending this pattern to brainstorm and plan.

## Key Decisions

1. **Entry points for draft PR creation:** Brainstorm (Phase 3) and one-shot (Step 0b) only. The `work` skill inherits whatever PR state exists. `worktree-manager.sh` stays a pure git utility — no PR logic added to it.

2. **First commit timing:** Immediately at worktree/branch creation. An empty commit establishes the remote branch and draft PR before any artifacts are written. Maximizes the recovery window.

3. **Push frequency:** Push at skill boundaries, not after every commit.
   - Brainstorm: push after Phase 3 (initial), push after Phase 3.6 (spec + issue)
   - Plan: push after post-phase (tasks.md)
   - Work: push with incremental code commits (already happens)
   - Ship: final push + mark PR ready

4. **Ship PR handling:** Ship detects the existing draft PR (`gh pr list --head <branch>`), replaces the body entirely with the production-quality description (`gh pr edit`), then marks it ready (`gh pr ready`). The draft body is treated as a placeholder.

5. **Network failure:** Warn and continue. Print a warning if push or draft PR creation fails. The workflow continues — local commits still protect against crashes. The draft PR is a bonus, not a hard requirement.

6. **Implementation approach:** Shared `draft-pr.sh` script in `skills/git-worktree/scripts/` for the "empty commit → push → draft PR" sequence. Phase commit instructions added directly to each SKILL.md (brainstorm, plan). Ship adapted to detect and update existing draft PRs.

## Commit Points Map

| Skill | Phase | Commit contains | Push? |
|-------|-------|----------------|-------|
| brainstorm | 3 (worktree) | Empty commit | Yes + draft PR |
| brainstorm | 3.5 | Brainstorm doc | No |
| brainstorm | 3.6 | spec.md + issue link | Yes |
| plan | 5 | Plan markdown | No |
| plan | post | tasks.md | Yes |
| work | 2 | Code (incremental) | Yes (existing behavior) |
| ship | 7 | Version bump | Yes + mark PR ready |

## Files to Modify

| File | Change |
|------|--------|
| `skills/git-worktree/scripts/draft-pr.sh` | **New:** Reusable script for empty commit → push → draft PR |
| `skills/brainstorm/SKILL.md` | Add: call draft-pr after Phase 3, commit at 3.5 and 3.6, push at 3.6 |
| `skills/one-shot/SKILL.md` | Add: call draft-pr after Step 0b |
| `skills/plan/SKILL.md` | Add: commit at Phase 5 and post-phase, push at post-phase |
| `skills/ship/SKILL.md` | Modify: Phase 7 detects existing draft PR, uses `gh pr edit` + `gh pr ready` instead of `gh pr create` |

## Open Questions

- Should the draft PR title follow a convention? (e.g., "WIP: feat-<name>" or "Draft: <feature description>")
- Should the empty commit message be conventional? (e.g., "chore: initialize feat-<name>")
- Should the `work` skill also push at its skill boundary (end of Phase 3, before delegating to ship)?
