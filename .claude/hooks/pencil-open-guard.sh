#!/usr/bin/env bash
# PreToolUse hook: block opening untracked .pen files with Pencil MCP.
# Source rule: AGENTS.md "Before calling mcp__pencil__open_document, ensure the target .pen file is committed in git."
# Why: open_document silently overwrites untracked .pen files with an empty document.
#      Untracked files have no git recovery path, causing irreversible data loss.
set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.filePath // ""')

# Skip if no filePath provided
[[ -z "$FILE_PATH" ]] && exit 0

# Resolve to absolute path for git checks
if [[ ! "$FILE_PATH" = /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Find the git repo root for this file
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || echo "")
[[ -z "$REPO_ROOT" ]] && exit 0

# Get path relative to repo root for git ls-files
REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null || echo "")
[[ -z "$REL_PATH" ]] && exit 0

# Check if file is tracked in git
if ! git -C "$REPO_ROOT" ls-files --error-unmatch "$REL_PATH" &>/dev/null 2>&1; then
  emit_incident "cq-before-calling-mcp-pencil-open-document" "deny" "Pencil MCP open_document can clear untracked files" "$FILE_PATH"
  jq -n '{hookSpecificOutput:{permissionDecision:"deny",permissionDecisionReason:"BLOCKED: .pen file is untracked in git. Pencil MCP open_document can silently clear file contents. Commit the file first (git add <file> && git commit) to enable recovery."}}'
  exit 0
fi

exit 0
