#!/usr/bin/env bash
# PreToolUse hook for Write and Edit tools.
# Blocks file writes to the main repo checkout when worktrees exist.
# NOTE: When adding or modifying guards, update the corresponding prose rule comments below.
#
# Corresponding prose rules:
#   constitution.md "Never edit files in the main repo root when a worktree is active for the current feature"
# Prevents the recurring problem of agents creating files on main instead of
# in the active worktree (screenshots, knowledge-base artifacts, etc.).

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

INPUT=$(cat)
__HI_RAW="$INPUT"
# ADR-155: hook stdin is model-controlled. A non-string field is surfaced,
# never coerced — this hook never ran eval, but `jq -r` renders an array
# across lines, which matches none of its guards, so the payload would have
# slipped every gate below (#7164). ADR-156: it asks instead.
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "worktree-write-guard"
  hook_input_should_ask && { hook_input_emit_ask "worktree-write-guard"; exit 0; }
  exit 0
fi

FILE_PATH="$HOOK_FILE_PATH"

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

# Allow writes to .claude/ and .openhands/ directories (settings, hooks, memory)
RELATIVE_PATH="${FILE_PATH#"$GIT_ROOT"/}"
[[ "$RELATIVE_PATH" == .claude/* ]] && exit 0
[[ "$RELATIVE_PATH" == .openhands/* ]] && exit 0

# Check if any worktrees exist
WORKTREE_DIR="$GIT_ROOT/.worktrees"
if [[ -d "$WORKTREE_DIR" ]] && [[ -n "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
  # Worktrees exist but write targets main checkout -- block it
  WORKTREE_NAMES=$(ls "$WORKTREE_DIR" 2>/dev/null | head -3 | tr '\n' ', ' | sed 's/,$//')
  emit_incident "guardrails-worktree-write-guard" "deny" "Never edit main when a worktree is active" "$FILE_PATH"
  jq -n --arg names "$WORKTREE_NAMES" --arg path "$GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Writing to main repo checkout while worktrees exist (" + $names + "). Write to the worktree path instead: " + $path)
    }
  }'
  exit 0
fi

# No worktrees exist, allow the write
exit 0
