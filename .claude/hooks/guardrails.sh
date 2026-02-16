#!/bin/bash
# PreToolUse guardrail hook for Bash commands.
# Blocks: commits on main, rm -rf on worktrees, --delete-branch with active worktrees.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Guard 1: Block git commit on main branch
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo '{"decision":"block","reason":"BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."}'
    exit 0
  fi
fi

# Guard 2: Block rm -rf on worktree paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-rf)\s' && echo "$COMMAND" | grep -qE '\.worktrees/'; then
  echo '{"decision":"block","reason":"BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."}'
  exit 0
fi

# Guard 3: Block gh pr merge --delete-branch when worktrees exist
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    echo '{"decision":"block","reason":"BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."}'
    exit 0
  fi
fi

# All checks passed
exit 0
