# Learning: Bare repo sync must use full-tree extraction, not a hardcoded whitelist

## Problem

The `sync_bare_files` function in `worktree-manager.sh` used a hardcoded whitelist of ~11 files to sync from git HEAD to the bare repo root. This was the third occurrence of the same class of bug:

1. **2026-03-13:** Initial sync function created with whitelist of config files (CLAUDE.md, settings.json, worktree-manager.sh)
2. **2026-03-20:** Plugin hooks added to whitelist after stop-hook.sh staleness caused infinite loop
3. **2026-03-27:** Commands (`go.md`), skills, agents, and docs still missing — 49 stale files + 13 missing files. The updated `/soleur:go` routing (brainstorm-first, no confirmation) was committed to main but never reached the bare root, causing the old 4-intent routing with confirmation to run instead.

Each fix added more files to the whitelist, but the whitelist always fell behind as new files were added to the plugin.

## Solution

[Updated 2026-03-27] Replaced the hardcoded whitelist with `git archive HEAD -- plugins/ CLAUDE.md AGENTS.md README.md .claude-plugin .claude/settings.json | tar -xC "$GIT_ROOT"`. This extracts the entire plugin tree in one shot — no whitelist to maintain, no files to miss.

## Key Insight

A hardcoded sync whitelist is a maintenance trap. Every new file requires remembering to update the list, and forgetting is silent — the stale file works fine until someone changes it. The fix is to sync entire directory trees (`git archive | tar -x`), not individual files. This is the same principle as "don't enumerate cases when you can match a pattern."

## Session Errors

- `/soleur:go` loaded stale instructions (old 4-intent routing with confirmation) because `go.md` was not in the sync whitelist. User had to manually select "Explore" to override the wrong default.

## Tags

category: integration-issues
module: git-worktree
