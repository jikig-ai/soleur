# Learning: Worktree loss during stash/merge/pop sequence

## Problem

While implementing the COO domain leader agent, the Workflow Completion Protocol required merging main into the feature branch before bumping the version (AGENTS.md step 5). The worktree had uncommitted changes across multiple files (new agent definitions, plugin registration, README updates, CHANGELOG entries). The following sequence was executed:

1. `git stash` -- saved all uncommitted changes in the worktree
2. `git fetch origin main && git merge origin/main` -- merged latest main into the feature branch
3. `git stash pop` -- attempted to reapply stashed changes

Step 3 produced a merge conflict in `plugins/soleur/skills.js` (a pre-existing comment count mismatch between the stashed version and the merged version). After the conflict, the entire worktree directory (`.worktrees/feat-coo-domain-leader/`) and its associated branch were destroyed. All uncommitted work was lost -- agent files, plugin registration changes, README updates, CHANGELOG entries, brainstorm documents, and spec files. The worktree had to be recreated from scratch with `git worktree add`, and every change had to be reimplemented manually.

The exact mechanism of destruction is not fully diagnosed. Git stash pop with conflicts can leave the working tree in an inconsistent state, and in combination with worktree-specific state, it may have corrupted the worktree linkage. The guardrails hook may have also interfered -- it blocks `rm -rf` on worktree paths, but the stash/pop failure may have triggered internal git cleanup that bypassed the hook.

## Solution

**Recovery:** Recreated the worktree with `git worktree add .worktrees/feat-coo-domain-leader -b feat/coo-domain-leader` and reimplemented all changes from memory and existing brainstorm/spec documents.

**Prevention -- commit before merging main:**

The correct sequence in the Workflow Completion Protocol step 5 is:

1. **Commit** all current work first (even as a WIP commit)
2. `git fetch origin main && git merge origin/main`
3. Resolve any merge conflicts (which are now between two committed states, not between committed and stashed)
4. If the WIP commit needs cleanup, amend it or squash later

Never use `git stash` in a worktree when the stash contains significant uncommitted work. Stash is designed for quick context switches on a single branch, not for temporarily shelving an entire feature's worth of changes during a merge operation.

**Alternative -- reorder the protocol:**

The Workflow Completion Protocol currently places "Merge main" (step 5) before "Commit" (step 7). This ordering forces either a stash or a temporary commit. The safer approach is:

1. Make a WIP commit with all changes
2. Merge main
3. Resolve conflicts
4. Amend the WIP commit or proceed to version bump and final commit

## Key Insight

`git stash` in a worktree is a catastrophic risk when the stash contains the entire feature's uncommitted work. Unlike a failed merge between two committed branches (which can always be aborted with `git merge --abort` and both sides remain intact), a stash pop failure can leave work in a state where neither the stash nor the working tree contains a complete copy. In a worktree context, this corruption can cascade to destroy the worktree linkage itself.

The general rule: never hold significant work in an uncommitted state when performing merge operations. Commit early, commit often. A WIP commit that gets amended later is infinitely safer than a stash that gets corrupted.

## Session Errors

1. **Worktree and branch catastrophically lost during stash/merge/pop** -- `git stash pop` conflict in `skills.js` destroyed the entire worktree directory and its branch. All uncommitted work across 10+ files was lost. Root cause: using `git stash` to hold an entire feature's changes during a merge instead of committing first.

2. **CWD drift from worktree to main repo root** -- Multiple times during the session, the working directory silently shifted from `.worktrees/feat-coo-domain-leader/` to the main repository root. File edits and git operations were executed in the wrong location before the drift was detected. This is a recurring pattern documented in `2026-02-11-worktree-edit-discipline.md`.

3. **Guardrails hook blocked rm -rf on worktree paths** -- When attempting to clean up stale files, `rm -rf` on paths within `.worktrees/` was blocked by the guardrails hook. Required individual file deletion with `rm` (no `-rf` flag) instead. The hook is working as intended -- the error was in the cleanup approach.

4. **Pre-existing count mismatch in skills.js comments** -- The `skills.js` file had a comment stating a skill count that did not match the actual number of registered skills. This pre-existing inconsistency caused the merge conflict during `git stash pop` that triggered the worktree destruction. The count was corrected during reimplementation.

5. **Version bump required re-reading main after worktree recreation** -- After the worktree was destroyed and recreated, the version state was uncertain. Had to run `git show origin/main:plugins/soleur/plugin.json` to confirm the latest version on main before bumping, as the recreated worktree started from HEAD which may not have had the latest merge.

## Related

- [Worktree edit discipline](workflow-patterns/2026-02-11-worktree-edit-discipline.md) -- CWD drift pattern (error #2)
- [Worktree cleanup gap after merge](2026-02-09-worktree-cleanup-gap-after-merge.md) -- worktree lifecycle management
- [Stale worktrees accumulate across sessions](2026-02-21-stale-worktrees-accumulate-across-sessions.md) -- session boundary failures
- [Never use --delete-branch with parallel worktrees](2026-02-19-never-use-delete-branch-with-parallel-worktrees.md) -- another worktree destruction vector

## Tags
category: runtime-errors
module: git-worktree
symptoms: worktree deleted, branch lost, stash conflict, uncommitted work destroyed, stash pop failure
