#!/usr/bin/env bash
set -euo pipefail

[[ -n "${CODEX_THREAD_ID:-}" || -n "${PLUGIN_ROOT:-}" ]] && exit 0

# --- Sentinel Check ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/resolve-git-root.sh" || {
  # Not in a git repo -- skip welcome silently
  exit 0
}
PROJECT_ROOT="$GIT_ROOT"

# The plugin's own SessionStart registration implies the plugin is active in
# this project — no further "installed" probe is needed (and the old
# `plugins/soleur`-directory guard silently never fired on marketplace
# installs, where the plugin lives outside the project tree). The per-project
# sentinel below is the dedupe.

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
