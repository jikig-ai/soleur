---
title: Concurrent cleanup-merged wipes an active worktree mid-session
date: 2026-04-21
category: workflow-patterns
tags: [worktree, cleanup-merged, concurrency, workflow, session-error]
related:
  - 2026-02-09-worktree-cleanup-gap-after-merge.md
  - 2026-02-22-cleanup-merged-path-mismatch.md
  - 2026-02-21-stale-worktrees-accumulate-across-sessions.md
---

# Learning: Concurrent cleanup-merged wipes an active worktree mid-session

## Problem

During a `/soleur:go` → `brainstorm` session for issue #1944, the
`worktree-manager.sh feature <name>` call reported success and the worktree
directory appeared, but by the time the brainstorm document was ready to
commit, the worktree was gone:

- `git worktree list` did not include the branch.
- The path existed but contained only the files the session had written
  (orphan `knowledge-base/project/brainstorms/*.md` and
  `knowledge-base/project/specs/feat-*/spec.md`).
- `git -C <worktree-path> status` returned `fatal: this operation must be run
  in a work tree`.
- `git branch -a` did not show the feature branch.

This repeated twice in the same session. Each time, `git worktree list`
additionally showed *other* newly-created or newly-removed worktrees from
parallel Claude Code sessions running concurrently against the same bare
repo. That is the root of the interaction.

## Root Cause

The repo root is bare (`git worktree list` marks it `(bare)`), and multiple
concurrent sessions share it. Every session's entry point runs
`worktree-manager.sh cleanup-merged` (per AGENTS.md rule
`wg-at-session-start-run-bash-plugins-soleur`) which prunes merged branches
and their worktrees.

When Session A creates `feat-X` but has not yet pushed or merged, Session B
starting `cleanup-merged` does not touch `feat-X` (it is unmerged). **But** if
Session B is on `main` and `cleanup-merged` also runs `git fetch --prune` and
a branch-delete sweep on any ref that looks stale, an in-flight worktree
whose branch was just created but not yet pushed can be caught by the
"no upstream + no local commits beyond main" check and pruned.

The evidence: in this session, two other worktrees in `git worktree list`
changed between my two `worktree list` calls (different SHAs, different names
— one appeared, one disappeared) — a signature of another session running
cleanup mid-turn.

Orphan files survive because `cleanup-merged` uses `git worktree remove`,
which refuses to delete dirs with untracked changes — it falls back to
`--force` OR leaves the dir behind. Either outcome yields a directory that
is no longer a registered worktree.

## Solution (what unblocked this session)

Backup-and-restore pattern when the worktree is wiped with orphan files:

```bash
# 1. Back up orphan writes to /tmp (not affected by worktree remove)
BAK=/tmp/feat-<name>-$$
mkdir -p "$BAK"
cp <worktree>/<survivor-path> "$BAK/"

# 2. Remove the orphan dir and stale branch (if any)
rm -rf <worktree>
git -C <bare-root> branch -D feat-<name> 2>/dev/null || true

# 3. Recreate cleanly
<bare-root>/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh \
  --yes feature <name>

# 4. Restore files into the fresh worktree
mkdir -p <worktree>/<survivor-parent-paths>
cp "$BAK"/* <worktree>/<appropriate-paths>/

# 5. Normal commit + push
cd <worktree> && git add ... && git commit && git push -u origin HEAD
```

In this session the backup lived in `/tmp/feat-content-service-automation-3355834`
and held the brainstorm markdown plus the spec markdown.

## Prevention

- **Short-term (this session, no code change):** push the branch immediately
  after the worktree is created. An unpushed-unmerged branch is the most
  fragile state — a pushed branch is safe from most cleanup heuristics.
- **Near-term (skill change):** `worktree-manager.sh feature <name>` should
  end with an automatic empty-commit + `git push -u origin <branch>` so the
  branch has a remote reference before any other session can touch it.
  `worktree-manager.sh draft-pr` already does this, but it is documented as a
  separate "next step" and most sessions skip it until the first real commit.
  Pulling the push into `feature <name>` closes the window.
- **Medium-term (cleanup heuristic):** `cleanup-merged` should refuse to
  prune any branch whose head commit is newer than the session's oldest
  active file lock / timestamp, or simpler: refuse to prune branches created
  in the last N minutes. A 10-minute grace window eliminates the concurrent-
  session wipe without affecting real merged cleanup.

## Session Errors

- **Worktree wiped after creation (twice).** Recovery: `/tmp` backup → remove
  orphan dir → recreate → restore. Prevention: auto-push on `feature <name>`.
- **`git status` returned `fatal: this operation must be run in a work tree`.**
  Caused by the wipe; git's worktree registration was gone even though the
  path existed with orphan files. Recovery: verify via `git worktree list`
  before using `-C <path>`. Prevention: rule
  `hr-before-running-git-commands-on-a` already mandates validating the path
  is a git repo — this learning extends it: when the path *was* a worktree
  but no longer is, treat as hostile environment and recover-from-backup
  before continuing.
- **`npx markdownlint-cli2 --fix` flagged MD013 on first run.** Caused by
  running from the bare repo root where `.markdownlint.json` does not ship
  (only the worktree checkout has it). Recovery: re-run from inside the
  worktree. Prevention: always run markdownlint from the worktree root, never
  the bare repo. Document in worktree skill.
- **Shell `cd` did not persist between Bash tool calls.** This is documented
  harness behavior (shell state does not persist) but the tool description
  also says "The working directory persists between commands" — contradictory.
  Recovery: use `cd <abs> && <cmd>` in every call, or `git -C <path>`. No
  prevention needed (known harness limitation).
- **Fresh worktree did not contain `knowledge-base/project/brainstorms/` or
  the feature's spec directory.** Recovery: `mkdir -p` before `Write`.
  Prevention: `worktree-manager.sh feature <name>` already creates the spec
  dir; it should also create the brainstorms dir (and the learnings dir) so
  the first `Write` call in Phase 3.5 of brainstorm does not fail.

## Key Insight

The bare-repo-plus-concurrent-sessions model makes `cleanup-merged` a
distributed-systems problem. Any rule that deletes based on "what looks
unused" will eventually race with "what is being used by a parallel session."
The only durable fix is to make the branch *visible to git* (pushed with an
upstream) before cleanup heuristics see it. Everything else is mitigation.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/git-worktree, plugins/soleur/skills/brainstorm
