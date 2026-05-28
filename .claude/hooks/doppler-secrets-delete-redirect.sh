#!/usr/bin/env bash
# PreToolUse hook: block Doppler secret-mutating commands without stdout redirect
# Source rule: constitution.md "Never run doppler secrets delete/set/upload without redirecting stdout"
# Why: Doppler CLI prints the ENTIRE remaining config on write operations — all secrets exposed.
set -euo pipefail

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$CMD" ]] || exit 0

# Intercept any Doppler secrets write command (delete, set, upload)
# Read-only commands (get, download) are safe — they show only requested keys.
if printf '%s' "$CMD" | grep -qE 'doppler\s+secrets\s+(delete|set|upload)'; then
  if ! printf '%s' "$CMD" | grep -qE '>\s*/dev/null|>\s*&-|1>\s*/dev/null'; then
    SUBCMD=$(printf '%s' "$CMD" | grep -oE 'doppler\s+secrets\s+(delete|set|upload)' | awk '{print $3}')
    jq -n --arg subcmd "$SUBCMD" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: ("BLOCKED: `doppler secrets " + $subcmd + "` without `> /dev/null` — the CLI prints ALL remaining secrets to stdout. Add `> /dev/null` and verify with a separate `doppler secrets get` call.")
      }
    }'
    exit 0
  fi
fi
