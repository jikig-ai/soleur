#!/usr/bin/env bash
# SessionStart hook: first-time Soleur welcome message.
# OpenHands port of plugins/soleur/hooks/welcome-hook.sh.
#
# OpenHands protocol: exit 0 + JSON {"additionalContext":"..."} to inject context.
# Input: HookEvent JSON on stdin with working_dir.

set -euo pipefail

INPUT=$(cat)
# Guarded: an unguarded jq under `set -euo pipefail` aborted this hook at rc 5
# on any document jq rejects — the same defect fixed in the three PreToolUse
# mirrors. A SessionStart hook has nothing to deny, so it fails open silently.
command -v jq >/dev/null 2>&1 || exit 0
PROJECT_DIR=$(printf '%s' "$INPUT" | jq -r '.working_dir // ""' 2>/dev/null) || PROJECT_DIR=""
[[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="${OPENHANDS_PROJECT_DIR:-$(pwd)}"

# Only run in projects that have the Soleur plugin installed locally.
[[ -d "${PROJECT_DIR}/plugins/soleur" ]] || exit 0

SENTINEL_FILE="${PROJECT_DIR}/.claude/soleur-welcomed.local"
[[ -f "$SENTINEL_FILE" ]] && exit 0

mkdir -p "${PROJECT_DIR}/.claude" 2>/dev/null || true
touch "$SENTINEL_FILE" 2>/dev/null || true

jq -n '{"additionalContext":"Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."}'
exit 0
