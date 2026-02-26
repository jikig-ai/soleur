#!/bin/bash
# PreToolUse guardrail hook for Bash commands.
# Blocks: commits on main, rm -rf on worktrees, --delete-branch with active worktrees.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Guard 1: Block git commit on main branch
# Match git commit at start of string OR after chain operators (&&, ||, ;)
# so chained commands like "git add && git commit" are caught.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  # Resolve the branch from the command's working directory, not the hook's CWD.
  # Three patterns: "cd /worktree && ...", "git -C /worktree commit", or bare
  # "git commit" when Claude Code's shell CWD is already the worktree.
  GIT_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    GIT_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    # Fallback: check the hook input for a cwd field (future-proofing),
    # then fall back to the hook's own CWD (repo root).
    HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      BRANCH=$(git -C "$HOOK_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    else
      BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo '{"decision":"block","reason":"BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."}'
    exit 0
  fi
fi

# Guard 2: Block rm -rf on worktree paths
# Match rm with recursive-force flags followed by a worktree path as an argument.
# Uses a single pattern to avoid false positives when .worktrees/ appears in
# unrelated text (e.g., inside a gh issue comment body or heredoc).
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
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
