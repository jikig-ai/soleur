#!/usr/bin/env bash
# PreToolUse hook: block Doppler secret-mutating commands without stdout redirect
# Source rule: constitution.md "Never run doppler secrets delete/set/upload without redirecting stdout"
# Why: Doppler CLI prints the ENTIRE remaining config on write operations — all secrets exposed.
set -euo pipefail

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[doppler-secrets-delete-redirect] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
__HI_RAW="$INPUT"
# ADR-155: hook stdin is model-controlled. A non-string field is surfaced,
# never coerced — this hook never ran eval, but `jq -r` renders an array
# across lines, which matches none of its guards, so the payload would have
# slipped every gate below (#7164). ADR-156: it asks instead.
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "doppler-secrets-delete-redirect"
  hook_input_should_ask && { hook_input_emit_ask "doppler-secrets-delete-redirect"; exit 0; }
  exit 0
fi

TOOL="$HOOK_TOOL_NAME"
[[ "$TOOL" == "Bash" ]] || exit 0

CMD="$HOOK_CMD"
[[ -n "$CMD" ]] || exit 0

# Intercept any Doppler secrets write command (delete, set, upload)
# Read-only commands (get, download) are safe — they show only requested keys.
if grep -qE 'doppler\s+secrets\s+(delete|set|upload)' <<<"$CMD"; then
  if ! grep -qE '>\s*/dev/null|>\s*&-|1>\s*/dev/null' <<<"$CMD"; then
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
