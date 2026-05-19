# Restart-fresh from existing WIP: /soleur:go needs a cleanup-scope ask before nuking

**Date:** 2026-05-12
**Category:** workflow / orchestration
**Status:** observation — feedback into `/soleur:go` Step 1

## Problem

When `/soleur:go <linear-id>` is invoked and the Linear issue already has an existing WIP attempt — open worktree (`.worktrees/feat-one-shot-<slug>/`), open draft PR, and a remote branch — the routing skill has no built-in detection for this. Its Step 1 only checks whether `pwd` is currently inside a worktree (offers "continue current feature?"). It does NOT inspect whether the Linear ID has a SIBLING worktree elsewhere on the same bare repo.

In SOL-39's case the operator was in the bare root. `/soleur:go SOL-39` would normally route straight to one-shot, which then creates a new worktree — colliding with the existing branch name and leaving the prior 5 commits / draft PR #3628 / remote branch orphaned.

## Solution

Before routing, scan `git worktree list` and `gh pr list --search "head:<expected-branch-name>"` for state matching the Linear ID's slug. If state exists, present an AskUserQuestion with **three** cleanup options (not just continue/restart):

1. **Continue in existing worktree** (Recommended when prior work is salvageable) — `cd` into the worktree, route to `soleur:work`.
2. **Review existing PR** — route to `soleur:review` against the existing PR head.
3. **Restart fresh** — destructive; nuke everything before re-running one-shot.
4. **Just brief me** — inspect-only path.

For the destructive path, follow up with a SECOND AskUserQuestion enumerating cleanup scope (full nuke / soft nuke / cancel) so the operator approves exactly what gets destroyed. Each destructive step (close PR, remove worktree, delete local branch, delete remote branch) is independently visible.

Implementing this flow in SOL-39's session:
- Detected `.worktrees/feat-one-shot-sol-39-sidebar-misalignment` + open PR #3628 (5 commits, 458/2 additions/deletions)
- Showed commit count + line counts so the operator could weigh the destruction
- User selected "Restart fresh" → second question with cleanup-scope options
- Full nuke executed: `gh pr close 3628`, `git worktree remove --force`, `git branch -D`, `git push origin --delete`

## Key Insight

`/soleur:go`'s worktree detection is currently CWD-relative ("am I IN a worktree?"). For Linear-ID-keyed entry points, it should ALSO be NAME-relative ("does a worktree NAMED after this Linear ID exist?"). The two checks compose: CWD-relative catches "user is already working on something"; NAME-relative catches "user is starting fresh but a prior attempt is parked".

The destructive cleanup path needs two-stage confirmation: the first picks the disposition (continue/review/restart/brief), the second picks the destruction scope (so a wrong-click on "restart" doesn't immediately nuke without a chance to back out).

## Session Errors

None detected. The session executed cleanly; this learning is a workflow observation, not a recovery note.

## Cross-references

- `/soleur:go` skill: `plugins/soleur/skills/go/SKILL.md` Step 1 (current CWD-relative worktree detection)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged` (post-merge case, complements this pre-start case)
- `2026-02-17-worktree-not-enforced-for-new-work.md` (related: ensuring new work always lands in a worktree)
- `2026-02-21-stale-worktrees-accumulate-across-sessions.md` (related: the post-merge-cleanup gap this learning is the pre-start mirror of)

## Tags

category: workflow
module: soleur-go
