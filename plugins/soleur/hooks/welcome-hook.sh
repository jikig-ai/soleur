#!/usr/bin/env bash
set -euo pipefail

# --- Sentinel Check ---
# Sentinel file tracks whether the welcome message has been shown.
# Uses .local suffix to stay gitignored; per-project (relative path).
SENTINEL_FILE=".claude/soleur-welcomed.local"

if [[ -f "$SENTINEL_FILE" ]]; then
  # Already welcomed -- allow session start without output
  exit 0
fi

# --- First-Time Welcome ---
# Create sentinel file. If this fails (read-only filesystem, permissions),
# the welcome message will repeat next session -- acceptable degradation.
mkdir -p .claude 2>/dev/null || true
touch "$SENTINEL_FILE" 2>/dev/null || true

# Output JSON with additional context for Claude.
# SessionStart uses additionalContext (not systemMessage) to inject context
# that Claude can see and act on.
cat <<'WELCOME_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."
  }
}
WELCOME_JSON

exit 0
