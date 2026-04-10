#!/usr/bin/env bash
# SessionStart hook: first-time Soleur welcome message.
# OpenHands port of plugins/soleur/hooks/welcome-hook.sh.
#
# OpenHands protocol: exit 0 + JSON {"additionalContext":"..."} to inject context.
# Input: HookEvent JSON on stdin with working_dir.

set -euo pipefail

INPUT=$(cat)
PROJECT_DIR=$(echo "$INPUT" | jq -r '.working_dir // ""')
[[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="${OPENHANDS_PROJECT_DIR:-$(pwd)}"

# Only run in projects that have the Soleur plugin installed locally.
[[ -d "${PROJECT_DIR}/plugins/soleur" ]] || exit 0

SENTINEL_FILE="${PROJECT_DIR}/.claude/soleur-welcomed.local"
[[ -f "$SENTINEL_FILE" ]] && exit 0

mkdir -p "${PROJECT_DIR}/.claude" 2>/dev/null || true
touch "$SENTINEL_FILE" 2>/dev/null || true

jq -n '{"additionalContext":"Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."}'
exit 0
