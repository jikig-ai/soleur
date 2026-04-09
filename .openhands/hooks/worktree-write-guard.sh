#!/usr/bin/env bash
# PreToolUse hook for file_editor tool.
# Blocks file writes to the main repo checkout when worktrees exist.
# OpenHands port of .claude/hooks/worktree-write-guard.sh.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Input: HookEvent JSON on stdin with tool_input.path and working_dir.
# OpenHands file_editor uses "path" (not "file_path" like Claude Code).
#
# Corresponding prose rules: see .claude/hooks/worktree-write-guard.sh

set -euo pipefail

INPUT=$(cat)
# OpenHands file_editor uses "path"; fall back to "file_path" for compatibility
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // .tool_input.file_path // ""')

[[ -z "$FILE_PATH" ]] && exit 0

# Get the main repo root (not the worktree root).
GIT_ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || exit 0)

# If file path is not under the repo root, allow it
[[ "$FILE_PATH" != "$GIT_ROOT"* ]] && exit 0

# If file path is inside a worktree, allow it
[[ "$FILE_PATH" == *"/.worktrees/"* ]] && exit 0

# Allow writes to .claude/ and .openhands/ directories
RELATIVE_PATH="${FILE_PATH#"$GIT_ROOT"/}"
[[ "$RELATIVE_PATH" == .claude/* ]] && exit 0
[[ "$RELATIVE_PATH" == .openhands/* ]] && exit 0

# Check if any worktrees exist
WORKTREE_DIR="$GIT_ROOT/.worktrees"
if [[ -d "$WORKTREE_DIR" ]] && [[ -n "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
  WORKTREE_NAMES=$(ls "$WORKTREE_DIR" 2>/dev/null | head -3 | tr '\n' ', ' | sed 's/,$//')
  jq -n --arg names "$WORKTREE_NAMES" --arg path "$GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH" \
    '{"decision":"deny","reason":("BLOCKED: Writing to main repo checkout while worktrees exist (" + $names + "). Write to the worktree path instead: " + $path)}'
  exit 2
fi

exit 0
