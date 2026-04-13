# Learning: worktree-manager feature command can fail silently

## Problem

Running `worktree-manager.sh feature chat-message-ux` reported success (green output, "Feature setup complete!") but only created the `knowledge-base/project/specs/feat-chat-message-ux/` directory inside an empty `.worktrees/feat-chat-message-ux/` folder. No `.git` file was created, the branch was not registered in `git worktree list`, and all subsequent git commands failed with "fatal: this operation must be run in a work tree."

The script output showed the worktree being prepared and HEAD set, dependency installation, and a success message — but the actual git worktree was not functional. This led to 5 consecutive failed commit attempts before the root cause was identified.

## Solution

Recreated the worktree manually:

```bash
rm -rf .worktrees/feat-chat-message-ux
git worktree add -b feat-chat-message-ux .worktrees/feat-chat-message-ux main
```

Then verified with `git rev-parse --is-inside-work-tree` before proceeding.

## Key Insight

The worktree-manager script's `feature` subcommand does not validate that the git worktree was actually created before proceeding to create spec directories and install dependencies. The verification step (`git rev-parse --is-inside-work-tree`) should happen immediately after `git worktree add` and before any file operations.

**Prevention:** After any worktree creation (scripted or manual), always verify with `git rev-parse --is-inside-work-tree` before writing files. If it returns false, recreate with `git worktree add` directly.

## Session Errors

1. **worktree-manager silent failure** — Recovery: manual `git worktree add`. Prevention: add post-creation verification to worktree-manager.sh.
2. **5 failed git commits from broken worktree** — Recovery: identified missing `.git` file, recreated worktree. Prevention: verify worktree before first git operation.
3. **Research subagent hallucinated line numbers** — The Explore agent reported `agent-runner.ts` lines 1076-1089 and 1141-1157, but the file is only 504 lines. The CTO assessment caught this. Prevention: when receiving line-number claims from subagents, verify they exist before citing them.

## Tags

category: integration-issues
module: worktree-manager
