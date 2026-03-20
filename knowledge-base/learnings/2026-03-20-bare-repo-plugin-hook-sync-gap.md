# Learning: Bare repo plugin hook sync gap

## Problem
The `cleanup-merged` function in `worktree-manager.sh` syncs critical on-disk files from `git HEAD` after merging worktrees back to main. However, the sync list only included `.claude/hooks/*` (user hooks) and a handful of explicitly listed files. Plugin hooks at `plugins/soleur/hooks/` were not in the sync list.

In a bare repo, the working tree files on disk are not automatically updated by git operations. This meant `plugins/soleur/hooks/stop-hook.sh` on disk was stuck at an old version (167 lines, 20-char stuck threshold) while HEAD had the fully hardened version (315 lines, PID-based, 150-char threshold, similarity detection). The stale stop hook caused an infinite "finish all slash commands" loop because its 20-char stuck detection couldn't catch substantive-looking responses.

## Solution
Added all plugin hook files to the `cleanup-merged` sync list:
- `plugins/soleur/hooks/hooks.json`
- `plugins/soleur/hooks/stop-hook.sh`
- `plugins/soleur/hooks/welcome-hook.sh`

Also added `chmod +x` for plugin hook scripts after sync, matching the existing pattern for `.claude/hooks/`.

## Key Insight
In a bare repo, any file that Claude Code reads at runtime (not from a worktree checkout) must be in the `cleanup-merged` sync list. The sync list was designed for config files (CLAUDE.md, settings.json) and the worktree manager itself, but plugin hooks execute from the bare repo root via `${CLAUDE_PLUGIN_ROOT}` and were overlooked. When adding new runtime-critical files to `plugins/soleur/`, always check if they need to be added to the sync list.

## Tags
category: integration-issues
module: git-worktree, ralph-loop
