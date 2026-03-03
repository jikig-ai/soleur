# Agent Instructions

This repository contains the Soleur Claude Code plugin. Detailed conventions live in `knowledge-base/overview/constitution.md` -- read it when needed. This file contains only rules the agent will violate without being told on every turn.

## Hard Rules

- Never commit directly to main. Create a worktree: `git worktree add .worktrees/feat-<name> -b feat/<name>`. If one exists for the task, use it.
- Never `--delete-branch` with `gh pr merge`. Use `gh pr merge <number> --squash --auto`, then poll with `gh pr view <number> --json state --jq .state` until MERGED, then run `cleanup-merged`.
- Never edit files in the main repo when a worktree is active. Run `pwd` before every file write or git command to verify you're in `.worktrees/<name>/`.
- Never `git stash` in worktrees. Commit WIP first, then merge.
- Never `rm -rf` on the current directory, a worktree path, or the repo root.
- MCP tools (Playwright, etc.) resolve paths from the repo root, not the shell CWD. Always pass absolute paths to MCP tools when in a worktree.
- When a command exits non-zero or prints a warning, investigate before proceeding. Never treat a failed step as success.
- Before merging any PR, rebase on origin/main (`git fetch origin main && git rebase origin/main`). Never use interactive rebase (`-i`).
- Always read a file before editing it. The Edit tool rejects unread files, but context compaction erases prior reads -- re-read after any compaction event.
- PreToolUse hooks block: commits on main, rm -rf on worktrees, --delete-branch with active worktrees, writes to main repo when worktrees exist. Work with these guards, not around them.
- The host terminal is Warp. Do not attempt automated terminal manipulation via escape sequences (cursor position queries, TUI rendering, and similar sequences are intercepted by Warp's tmux control mode and silently fail).
- The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead.

## Workflow Gates

- Zero agents until user confirms direction. Present a concise summary first, ask if they want to go deeper, only then launch research.
- Before every commit, run compound (`skill: soleur:compound`). Do not ask whether to run it -- just run it.
- Never bump version files in feature branches. Version is derived from git tags — CI creates GitHub Releases with `vX.Y.Z` tags at merge time via semver labels. Set labels with `/ship`. Do NOT edit `plugin.json` version (frozen sentinel) or `marketplace.json` version.
- Use `/ship` to automate the full commit/push/PR workflow. It enforces review and compound gates.
- After marking a PR ready, run `gh pr merge <number> --squash --auto` to queue auto-merge, then poll `gh pr view <number> --json state --jq .state` until MERGED, then `cleanup-merged`. Never stop at "waiting for CI" -- actively poll and merge in the same session.
- At session start, from the repo root: run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`.
- When an audit identifies pre-existing issues, create GitHub issues to track them before fixing. Don't just note them in conversation -- file them.

## Communication

- Challenge reasoning instead of validating. No flattery. If something looks wrong, say so.
- Delegate verbose exploration (3+ file reads, research, analysis) to subagents. Keep main context for edits and user-facing iteration.
