#!/bin/bash
# PreToolUse hook for Write and Edit tools.
# Blocks file writes to the main repo checkout when worktrees exist.
# Prevents the recurring problem of agents creating files on main instead of
# in the active worktree (screenshots, knowledge-base artifacts, etc.).

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Nothing to check if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Get the main repo root (not the worktree root).
# --show-toplevel returns the worktree when called from one, so we use
# --git-common-dir which always points to the main .git directory.
GIT_ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || exit 0)

# If file path is not under the repo root, allow it (e.g., memory files, external paths)
[[ "$FILE_PATH" != "$GIT_ROOT"* ]] && exit 0

# If file path is inside a worktree, allow it (correct behavior)
[[ "$FILE_PATH" == *"/.worktrees/"* ]] && exit 0

# Allow writes to .claude/ directory (settings, hooks, memory)
RELATIVE_PATH="${FILE_PATH#"$GIT_ROOT"/}"
[[ "$RELATIVE_PATH" == .claude/* ]] && exit 0

# Check if any worktrees exist
WORKTREE_DIR="$GIT_ROOT/.worktrees"
if [[ -d "$WORKTREE_DIR" ]] && [[ -n "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
  # Worktrees exist but write targets main checkout -- block it
  WORKTREE_NAMES=$(ls "$WORKTREE_DIR" 2>/dev/null | head -3 | tr '\n' ', ' | sed 's/,$//')
  echo "{\"decision\":\"block\",\"reason\":\"BLOCKED: Writing to main repo checkout while worktrees exist ($WORKTREE_NAMES). Write to the worktree path instead: $GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH\"}"
  exit 0
fi

# No worktrees exist, allow the write
exit 0
