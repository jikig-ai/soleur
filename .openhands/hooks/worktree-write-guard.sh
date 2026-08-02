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

# --- ADR-155 (mirror): the HookEvent envelope is MODEL-CONTROLLED ------------
# This port never called eval, so it never had the #7164 code execution. It DID
# have the evasion half, and this file is a WIRED BLOCKING guard
# (.openhands/hooks.json, file_editor matcher). Measured on this branch before
# the guard below existed: a string `.tool_input.path` into the main checkout
# denied with exit 2, while the SAME target as a one-element ARRAY exited 0 —
# `jq -r` renders it across lines, the `$GIT_ROOT*` prefix test below fails to
# match, and the write sails through.
#
# Its .claude twin was migrated in this PR; this file was missed because the
# scope was written as "the two mirrors" when hooks.json wires THREE blocking
# ones. Caught by code-simplicity-reviewer, reproduced before fixing.
#
# Scoped NARROW, matching the sibling mirrors: fires only when the document
# PARSES and a contracted field is the wrong TYPE, so a transport failure keeps
# the pre-existing behaviour. No `ask` exists in this protocol, so an anomalous
# shape denies — no legitimate caller sends a non-string, and a deny is
# recoverable where a silent bypass is not.
WWG_ENVELOPE_SHAPE=$(printf '%s' "$INPUT" | jq -r '
  # NB the // operator is deliberately absent: in jq it is a FALSY-alternative,
  # so a JSON false would be rewritten to "" and pass the type check below
  # (measured on the .claude side before this was fixed). Only null defaults.
  if (type == "object")
     and ((.tool_input? | type) as $t | $t == null or $t == "object")
     and ((if (.tool_input | has("path")) and (.tool_input.path != null) then .tool_input.path else .tool_input.file_path end | if . == null then "" else . end) | type == "string")
     and ((.working_dir? | if . == null then "" else . end) | type == "string")
  then "ok" else "nonstring" end' 2>/dev/null) || WWG_ENVELOPE_SHAPE="unparseable"
if [[ "$WWG_ENVELOPE_SHAPE" == "nonstring" ]]; then
  jq -n '{"decision":"deny","reason":"BLOCKED: the tool-call envelope carries a non-string field (e.g. an ARRAY tool_input.path). Hook stdin is model-controlled and untrusted (ADR-155); a non-string is never coerced, because the coerced value matches no path test and would bypass this guard. Re-send the path as a string."}'
  exit 2
fi

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
