#!/usr/bin/env bash
# PreToolUse hook: block `doppler secrets delete` without stdout redirect
# Source rule: constitution.md "Never run doppler secrets delete without redirecting stdout"
# Why: Doppler CLI prints the ENTIRE remaining config on delete — all secrets exposed.
set -euo pipefail

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$CMD" ]] || exit 0

# Only intercept `doppler secrets delete` commands
if printf '%s' "$CMD" | grep -qE 'doppler\s+secrets\s+delete'; then
  # Check if stdout is already redirected
  if ! printf '%s' "$CMD" | grep -qE '>\s*/dev/null|>\s*&-|1>\s*/dev/null'; then
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: `doppler secrets delete` without `> /dev/null` — the CLI prints ALL remaining secrets to stdout. Add `> /dev/null` and verify deletion with a separate `doppler secrets get` call."
      }
    }'
    exit 0
  fi
fi
