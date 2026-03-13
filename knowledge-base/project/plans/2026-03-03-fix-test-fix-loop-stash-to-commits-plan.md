---
title: "fix: replace git stash with checkpoint commits in test-fix-loop"
type: fix
date: 2026-03-03
semver: patch
---

# fix: Replace git stash with checkpoint commits in test-fix-loop

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Test Scenarios, Acceptance Criteria)

### Key Improvements
1. Corrected the commit-based flow to match stash semantics precisely -- the original plan had a timing mismatch in when checkpoints occur vs when fixes are applied
2. Added explicit flow diagrams showing the state of HEAD and working tree at each step
3. Identified and resolved edge case: success path requires `git reset --soft` to unstage the checkpoint commit while preserving working tree fixes
4. Added missing test scenario for the SKILL.md prose placeholder convention (no `$()` in markdown code blocks)

### New Considerations Discovered
- The SKILL.md code block convention prohibits `$()` shell expansion -- the `initial_sha` capture must use prose placeholders, not literal `$(git rev-parse HEAD)`
- The max-iterations termination has two valid behaviors (keep partial progress vs revert to initial) that need an explicit decision
- The `git add -A` pattern is already used in other skills (`fix-issue`, `compound-capture`) so there is precedent

## Overview

The `test-fix-loop` skill uses `git stash` as a rollback mechanism (checkpoint before each fix iteration, pop to revert on regression). This directly violates the project's worktree rules documented in both AGENTS.md and constitution.md. Since test-fix-loop is always invoked within worktrees (via `soleur:work` and Tier 0 parallel lifecycle), this creates a hard conflict between the skill's implementation and the project's safety rules.

## Problem Statement

From `plugins/soleur/skills/test-fix-loop/SKILL.md`:
- Line 90: `git stash push -m "test-fix-loop: checkpoint iteration N"`
- Lines 97-99: `git stash drop` and `git stash pop` for rollback decisions
- Line 121: "Fail safe -- stash before every fix attempt, revert on regression"

From `AGENTS.md`:
- "Never `git stash` in worktrees. Commit WIP first, then merge."

From `knowledge-base/overview/constitution.md` (line 115):
- "Never use `git stash` in a worktree to hold significant uncommitted work during merge operations"

From `knowledge-base/learnings/2026-02-22-worktree-loss-stash-merge-pop.md`:
- A real incident where `git stash pop` conflict destroyed an entire worktree and branch, losing all uncommitted work. This is the documented catastrophic failure mode that the worktree stash prohibition was created to prevent.

The issue was surfaced by Tier 0 parallel lifecycle work (#396/#408) because Tier 0 always operates in worktrees and delegates to test-fix-loop after integration.

## Proposed Solution

Replace `git stash` with checkpoint commits that preserve identical rollback semantics.

### Current Flow (stash-based)

The stash-based flow saves the working tree BEFORE applying fixes, then either drops the stash (keep fixes) or pops it (revert fixes):

```
Iteration start:     working tree has state from prior iteration (or clean initial state)
Before fix attempt:  git stash push -m "test-fix-loop: checkpoint iteration N"
                     (working tree is now clean -- stash holds prior state)
Apply fixes to working tree
Run tests
  Success:           git stash drop    (discard stashed prior state, keep working tree fixes)
  Progress:          git stash drop    (same -- keep fixes in working tree, continue)
  Regression:        git stash pop     (restore stashed prior state, overwrite bad fixes)
```

### New Flow (commit-based) [Updated 2026-03-03]

The commit-based flow commits the current state as a checkpoint, applies fixes to the working tree, then either keeps the fixes or discards them via `git reset --hard`:

```
Phase 1 start:       record initial_sha = HEAD (before any checkpoints)
                     working tree is clean (Phase 0 guarantees this)

Iteration N:
  Step 1 (checkpoint): git add -A && git commit -m "test-fix-loop: checkpoint iteration N"
                       (commits current state -- on iteration 1, this is a no-op if tree is clean)
  Step 2 (fix):        apply fixes to implementation code
  Step 3 (test):       run full test suite
  Step 4 (evaluate):
    All pass:          fixes are in working tree (uncommitted), report success, STOP
    Progress:          continue to iteration N+1 (fixes stay in working tree, next checkpoint commits them)
    Regression:        git reset --hard HEAD  (discard uncommitted fixes, return to checkpoint), STOP
    Circular:          git reset --hard <initial_sha>  (revert ALL iterations), STOP
    Non-convergence:   git reset --hard <initial_sha>  (revert ALL iterations), STOP
    Max iterations:    git reset --hard <initial_sha>  (revert ALL iterations), STOP
```

### Research Insights

**Checkpoint timing matters.** The stash-based design saves state BEFORE fixing. The commit-based design must do the same: commit the current state as a checkpoint, then apply fixes on top as uncommitted changes. This is why the checkpoint commit on iteration 1 may be a no-op (clean tree) -- its purpose is to mark the rollback point, not to save uncommitted work.

**Progress path is the key difference.** On "failures decreased" (progress), the stash-based design drops the stash and the fixes remain in the working tree for the next iteration. In the commit-based design, the fixes remain in the working tree and the NEXT iteration's checkpoint commits them. This means progress accumulates naturally -- each checkpoint commit captures the cumulative fixes from all prior iterations.

**Regression vs single-iteration revert.** The plan correctly distinguishes two cases:
- Regression (failure count increased from last iteration): `git reset --hard HEAD` discards only the current iteration's uncommitted fixes
- Circular/non-convergence/max-iterations: `git reset --hard <initial_sha>` reverts ALL accumulated progress, returning to the state before the loop started

### Key Equivalence Table

| Old (stash) | New (commit) | Semantics |
|---|---|---|
| `git stash push -m "..."` | `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"` | Save current state as rollback point |
| `git stash drop` | No-op (checkpoint commit stays in history) | Discard rollback point, keep progress |
| `git stash pop` (revert one iteration) | `git reset --hard HEAD` | Discard uncommitted working tree changes |
| `git stash pop` (revert all) | `git reset --hard <initial-sha>` | Revert to pre-loop state |
| Clean stash at end | Squash at PR merge | Clean up intermediate commits |

### Termination Cleanup

On final termination (success or failure):

- **All tests pass:** Fixes are in the working tree as uncommitted changes. Stage them with `git add -A`. The checkpoint commits remain in branch history and will be squash-merged when the PR is merged (standard project workflow). Fixes are staged but NOT committed -- the user reviews and commits via `/ship`.
- **Regression:** `git reset --hard HEAD` discards the current iteration's bad fixes. Partial progress from prior iterations remains in committed checkpoints. Report what was attempted.
- **Circular / Non-convergence / Max iterations:** `git reset --hard <initial_sha>` reverts ALL progress, restoring the clean state before the loop started. This is the conservative choice -- partial fixes that don't converge are more dangerous than no fixes.

## Technical Considerations

### Why `git reset --hard` is safe here

1. The skill already requires a clean working tree (Phase 0). All changes within the loop are either committed (checkpoint) or applied by the skill itself.
2. `git reset --hard HEAD` only discards the skill's own uncommitted fix attempt -- it reverts to the immediately preceding checkpoint commit. No user work is at risk.
3. `git reset --hard <initial_sha>` reverts to the state before the loop started, which is a known-good committed state.
4. The AGENTS.md prohibition is on `git stash`, not `git reset --hard`. The constitution's "never delete or overwrite user data" is satisfied because checkpoint commits preserve all user state and the initial SHA is a committed state the user already had.

### Research Insights: git reset --hard safety precedent

The `merge-pr` skill already uses `git reset --hard <starting-sha>` as a rollback mechanism (SKILL.md lines 286, 316, 326). This establishes an existing project pattern for using `git reset --hard` with a captured SHA as a safe revert mechanism. The test-fix-loop change follows the same pattern.

### Why checkpoint commits do not pollute history

The project uses squash merging (`gh pr merge --squash`) for all PRs. Intermediate commits within a feature branch are collapsed into a single merge commit. The checkpoint commits will be squashed alongside all other feature commits -- they add zero noise to the main branch history.

### Edge case: initial state preservation

The skill must record the commit SHA at the start of Phase 1 (before any checkpoint commits). If the loop terminates on failure after multiple iterations, the revert target is this initial SHA, not just HEAD~1. This handles the case where multiple checkpoint commits were made before a regression is detected against a non-adjacent prior iteration.

**Important: SKILL.md prose placeholder convention.** The constitution prohibits `$()` shell variable expansion in skill markdown code blocks (constitution.md, "Never" section). The initial SHA capture must use angle-bracket prose placeholders:

```
Record the current commit SHA as <initial-sha> before entering the loop.
On failure termination: git reset --hard <initial-sha>
```

NOT:

```bash
initial_sha=$(git rev-parse HEAD)
```

### Edge case: iteration 1 checkpoint is a no-op

On iteration 1, the working tree is clean (Phase 0 guarantees this). Running `git add -A && git commit` would fail with "nothing to commit." The skill should handle this gracefully:
- Either skip the checkpoint on iteration 1 (the initial SHA already serves as the rollback point)
- Or use `git commit --allow-empty -m "test-fix-loop: checkpoint iteration 1"` to create an explicit marker

The simpler approach is to skip the checkpoint on iteration 1. The initial SHA is the rollback point. Starting from iteration 2, the checkpoint commits the prior iteration's fixes.

### Phase 0 clean tree check

The existing check (line 38: "Run `git status --porcelain`. If output is non-empty, STOP") remains valid. The rationale changes from "dirty working tree will cause stash interleaving" to "dirty working tree means uncommitted user work that checkpoint commits would capture and potentially discard on rollback."

## Non-Goals

- Changing the test-fix-loop's iteration logic, termination conditions, or diagnostic behavior
- Modifying how `soleur:work` or Tier 0 invokes test-fix-loop
- Adding new features to test-fix-loop
- Changing the work skill's `git stash list` warning (line 63 of work/SKILL.md) -- that check warns about pre-existing stashes and is not part of the stash-as-rollback pattern

## Acceptance Criteria

- [x] AC1: `plugins/soleur/skills/test-fix-loop/SKILL.md` contains zero occurrences of `git stash`
- [x] AC2: Checkpoint commits use `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"` pattern (with prose placeholders, no `$()`)
- [x] AC3: Rollback on regression uses `git reset --hard` to discard uncommitted working tree changes
- [x] AC4: Rollback on circular/non-convergence/max-iterations uses `git reset --hard <initial-sha>` to revert all progress
- [x] AC5: Success path stages fixes without committing (preserving existing behavior -- user reviews and commits via `/ship`)
- [x] AC6: Progress path leaves fixes in working tree; next iteration's checkpoint commits them
- [x] AC7: The skill description in SKILL.md frontmatter no longer mentions "git stash isolation"
- [x] AC8: The termination conditions table is updated to reference commit-based rollback instead of stash-based
- [x] AC9: The Key Principles section reflects commit-based isolation instead of stash-based
- [x] AC10: `plugins/soleur/README.md` skill table description updated (currently says "git stash isolation")
- [x] AC11: `plugins/soleur/CHANGELOG.md` is NOT edited (version bumping is automated at merge time)
- [x] AC12: No `$()` shell variable expansion in SKILL.md code blocks (use prose placeholders per constitution)

## Test Scenarios

- Given a clean worktree with failing tests, when test-fix-loop runs iteration 1, then it records the initial SHA and applies fixes without a checkpoint commit (clean tree has nothing to checkpoint)
- Given iteration 1 fixes reduce failures, when iteration 2 starts, then the checkpoint commits iteration 1's fixes before applying new fixes
- Given a regression (failure count increases), when test-fix-loop detects it, then it runs `git reset --hard HEAD` to discard uncommitted fixes and reports REGRESSION
- Given all tests pass after iteration 2, when test-fix-loop terminates, then fixes are staged but not committed, and checkpoint commits exist in the branch history
- Given a circular fix pattern, when test-fix-loop detects it, then it resets to the initial SHA (discarding all iteration progress) and reports CIRCULAR
- Given max iterations reached with partial progress, when test-fix-loop terminates, then it resets to the initial SHA (discarding partial progress) and reports MAX_ITERATIONS
- Given non-convergence (same failure count for 2 consecutive iterations), when test-fix-loop detects it, then it resets to the initial SHA and reports NON_CONVERGENCE
- Given the SKILL.md file after editing, when grepping for `git stash`, then zero matches are found
- Given the SKILL.md file after editing, when grepping for `$(`, then zero matches are found in code blocks

## Files to Modify

1. `plugins/soleur/skills/test-fix-loop/SKILL.md` -- Primary target. Replace all stash operations with commit-based equivalents across:
   - Description frontmatter (line 3): replace "git stash isolation" with "checkpoint commit isolation"
   - Phase 0 clean tree rationale (line 38): update reason from stash interleaving to checkpoint commit safety
   - Termination conditions table (lines 66-71): replace stash references with commit/reset equivalents
   - Critical sequence in "4. Stash and Fix" section (lines 87-100): rename to "4. Checkpoint and Fix", replace stash operations with commit-based flow
   - Key Principles section (line 121): replace "stash before every fix attempt" with "checkpoint commit before every fix attempt"

2. `plugins/soleur/README.md` -- Update skill table description (line 269): change "git stash isolation" to "checkpoint commit isolation"

## References

- Issue: #409
- Learning: `knowledge-base/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` -- the catastrophic incident that motivated the stash prohibition
- Learning: `knowledge-base/learnings/2026-03-03-tier-0-lifecycle-parallelism-design.md` -- Tier 0 invokes test-fix-loop in worktrees, making this fix a prerequisite
- Learning: `knowledge-base/learnings/2026-02-22-plan-review-collapses-agent-architecture.md` -- precedent for inline instructions over agents for deterministic operations
- Parallel lifecycle plan: `knowledge-base/plans/2026-03-03-feat-parallel-agent-lifecycle-plan.md` (line 158 documents the pre-existing conflict)
- Constitution: `knowledge-base/overview/constitution.md` (line 115 -- stash prohibition; "Never" section -- no `$()` in skill code blocks)
- AGENTS.md: hard rule "Never `git stash` in worktrees"
- Existing `git reset --hard` precedent: `plugins/soleur/skills/merge-pr/SKILL.md` (lines 286, 316, 326)
