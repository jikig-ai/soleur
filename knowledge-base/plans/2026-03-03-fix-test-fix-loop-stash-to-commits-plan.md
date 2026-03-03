---
title: "fix: replace git stash with checkpoint commits in test-fix-loop"
type: fix
date: 2026-03-03
semver: patch
---

# fix: Replace git stash with checkpoint commits in test-fix-loop

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

Replace `git stash` with checkpoint commits that preserve identical rollback semantics:

### Current Flow (stash-based)

```
Before fix attempt:  git stash push -m "test-fix-loop: checkpoint iteration N"
Apply fixes, run tests
  Success:           git stash drop    (discard checkpoint, keep fixes)
  Progress:          git stash drop    (discard checkpoint, keep fixes, continue)
  Regression:        git stash pop     (revert to checkpoint)
```

### New Flow (commit-based)

```
Before fix attempt:  git add -A && git commit -m "test-fix-loop: checkpoint iteration N"
Apply fixes, run tests
  Success:           (checkpoint commit stays in history, stage fixes on top)
  Progress:          git add -A && git commit -m "test-fix-loop: iteration N progress"
  Regression:        git reset --hard HEAD~1  (revert to checkpoint commit)
```

### Termination Cleanup

On final termination (success or failure):

- **All tests pass:** Stage all current fixes. The checkpoint commits remain in history and will be squash-merged when the PR is merged (standard project workflow).
- **Max iterations / Regression / Circular / Non-convergence:** `git reset --hard` to the initial checkpoint commit (iteration 1), restoring the clean state before the loop started. This is equivalent to the old `git stash pop` behavior.

### Key Equivalence Table

| Old (stash) | New (commit) | Semantics |
|---|---|---|
| `git stash push -m "..."` | `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"` | Save current state as rollback point |
| `git stash drop` | No-op (checkpoint commit stays in history) | Discard rollback point, keep progress |
| `git stash pop` | `git reset --hard HEAD~1` | Revert to rollback point |
| Clean stash at end | Squash at PR merge | Clean up intermediate commits |

## Technical Considerations

### Why `git reset --hard` is safe here

1. The skill already requires a clean working tree (Phase 0). All changes within the loop are either committed (checkpoint) or applied by the skill itself.
2. `git reset --hard HEAD~1` only discards the skill's own fix attempt -- it reverts to the immediately preceding checkpoint commit. No user work is at risk.
3. The AGENTS.md prohibition is on `git stash`, not `git reset --hard`. The constitution's "never delete or overwrite user data" is satisfied because checkpoint commits preserve all user state.

### Why checkpoint commits do not pollute history

The project uses squash merging (`gh pr merge --squash`) for all PRs. Intermediate commits within a feature branch are collapsed into a single merge commit. The checkpoint commits will be squashed alongside all other feature commits -- they add zero noise to the main branch history.

### Edge case: initial state preservation

The skill must record the commit SHA at the start of Phase 1 (before any checkpoint commits). If the loop terminates on failure after multiple iterations, the revert target is this initial SHA, not just HEAD~1. This handles the case where multiple checkpoint commits were made before a regression is detected against a non-adjacent prior iteration.

```
initial_sha=$(git rev-parse HEAD)
# ... loop iterations with checkpoint commits ...
# On failure termination:
git reset --hard <initial_sha>
```

### Phase 0 clean tree check

The existing check (line 38: "Run `git status --porcelain`. If output is non-empty, STOP") remains valid. The rationale changes from "dirty working tree will cause stash interleaving" to "dirty working tree means uncommitted user work that checkpoint commits would capture and potentially discard on rollback."

## Non-Goals

- Changing the test-fix-loop's iteration logic, termination conditions, or diagnostic behavior
- Modifying how `soleur:work` or Tier 0 invokes test-fix-loop
- Adding new features to test-fix-loop
- Changing the work skill's `git stash list` warning (line 63 of work/SKILL.md) -- that check warns about pre-existing stashes and is not part of the stash-as-rollback pattern

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/skills/test-fix-loop/SKILL.md` contains zero occurrences of `git stash`
- [ ] AC2: Checkpoint commits use `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"` pattern
- [ ] AC3: Rollback on regression uses `git reset --hard` to the initial SHA captured before the loop
- [ ] AC4: Success path stages fixes without committing (preserving existing behavior -- user reviews and commits via `/ship`)
- [ ] AC5: Progress path (failures decreased) commits progress and continues to next iteration
- [ ] AC6: The skill description in SKILL.md frontmatter no longer mentions "git stash isolation"
- [ ] AC7: The termination conditions table is updated to reference commit-based rollback instead of stash-based
- [ ] AC8: The Key Principles section reflects commit-based isolation instead of stash-based
- [ ] AC9: `plugins/soleur/README.md` skill table description updated (currently says "git stash isolation")
- [ ] AC10: `plugins/soleur/CHANGELOG.md` is NOT edited (version bumping is automated at merge time)

## Test Scenarios

- Given a clean worktree with failing tests, when test-fix-loop runs, then it creates checkpoint commits (not stashes) before each fix iteration
- Given a regression (failure count increases), when test-fix-loop detects it, then it runs `git reset --hard` to the initial SHA and reports REGRESSION
- Given all tests pass after iteration 2, when test-fix-loop terminates, then fixes are staged but not committed, and checkpoint commits exist in the branch history
- Given a circular fix pattern, when test-fix-loop detects it, then it resets to the initial SHA (not stash pop)
- Given max iterations reached with partial progress, when test-fix-loop terminates, then it keeps the partial progress (checkpoint commits remain) and reports MAX_ITERATIONS
- Given non-convergence (same failure count for 2 iterations), when test-fix-loop detects it, then it resets to the initial SHA and reports NON_CONVERGENCE

## Files to Modify

1. `plugins/soleur/skills/test-fix-loop/SKILL.md` -- Primary target. Replace all stash operations with commit-based equivalents across:
   - Description frontmatter (line 3)
   - Phase 0 clean tree rationale (line 38)
   - Termination conditions table (lines 66-71)
   - Critical sequence in "4. Stash and Fix" section (lines 87-100) -- rename section to "4. Checkpoint and Fix"
   - Key Principles section (line 121)

2. `plugins/soleur/README.md` -- Update skill table description (line 269): change "git stash isolation" to "checkpoint commit isolation"

## References

- Issue: #409
- Learning: `knowledge-base/learnings/2026-02-22-worktree-loss-stash-merge-pop.md`
- Parallel lifecycle plan: `knowledge-base/plans/2026-03-03-feat-parallel-agent-lifecycle-plan.md` (line 158 documents the pre-existing conflict)
- Constitution: `knowledge-base/overview/constitution.md` (line 115)
- AGENTS.md: hard rule "Never `git stash` in worktrees"
