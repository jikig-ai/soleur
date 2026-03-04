#!/usr/bin/env bash
set -euo pipefail

# --- Sentinel Check ---
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
SENTINEL_FILE="${PROJECT_ROOT}/.claude/soleur-welcomed.local"

[[ -f "$SENTINEL_FILE" ]] && exit 0

# --- First-Time Welcome ---
mkdir -p "${PROJECT_ROOT}/.claude" 2>/dev/null || true
touch "$SENTINEL_FILE" 2>/dev/null || true

cat <<'WELCOME_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."
  }
}
WELCOME_JSON
