#!/usr/bin/env bash
# PreToolUse guardrail hook for terminal commands (OpenHands port).
# Blocks: commits on main, rm -rf on worktrees, --delete-branch with active worktrees,
# commits with conflict markers in staged content, gh issue create without --milestone,
# git stash in worktrees.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Input: HookEvent JSON on stdin with tool_input.command and working_dir.
#
# Corresponding prose rules: see .claude/hooks/guardrails.sh

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
HOOK_CWD=$(echo "$INPUT" | jq -r '.working_dir // ""')

deny() {
  jq -n --arg reason "$1" '{"decision":"deny","reason":$reason}'
  exit 2
}

# guardrails:block-commit-on-main — Block git commit on main branch
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  GIT_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    GIT_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  elif [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    BRANCH=$(git -C "$HOOK_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    deny "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
  deny "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    deny "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)'; then
  CONFLICT_MARKERS_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$CONFLICT_MARKERS_DIR" ] || [ ! -d "$CONFLICT_MARKERS_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      CONFLICT_MARKERS_DIR="$HOOK_CWD"
    fi
  fi
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    STAGED_DIFF=$(git -C "$CONFLICT_MARKERS_DIR" diff --cached 2>/dev/null || true)
  else
    STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
  fi
  if echo "$STAGED_DIFF" | grep -qE '^\+(<{7}|={7}|>{7})'; then
    deny "BLOCKED: Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'; then
  if ! echo "$COMMAND" | grep -qF -- '--milestone'; then
    deny "BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash in worktrees
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+stash'; then
  STASH_GUARD_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$STASH_GUARD_DIR" ] || [ ! -d "$STASH_GUARD_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      STASH_GUARD_DIR="$HOOK_CWD"
    fi
  fi
  RESOLVE_DIR="${STASH_GUARD_DIR:-.}"
  if echo "$(cd "$RESOLVE_DIR" 2>/dev/null && pwd)" | grep -qF '.worktrees'; then
    deny "BLOCKED: git stash in worktrees is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
  fi
fi

# All checks passed
exit 0
