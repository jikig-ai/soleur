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

# The plugin's own SessionStart registration implies the plugin is installed for
# the user — but plugin hooks are GLOBAL, firing in every project the user opens,
# so registration is not a per-project scope predicate (the old
# `plugins/soleur`-dir guard was the #1383 fix AND the #5119 root cause: it
# silenced real installs while failing to scope). The dedupe lives OUTSIDE the
# project tree — a plugin-owned state dir keyed by the repo-hash trick
# emit-decision.sh uses — so no artifact lands in the user's repo at all and
# welcome still fires once per project on real (marketplace) installs.

if command -v sha256sum >/dev/null 2>&1; then
  repo_key="$(printf '%s' "$PROJECT_ROOT" | sha256sum | cut -c1-16)"
elif command -v shasum >/dev/null 2>&1; then
  repo_key="$(printf '%s' "$PROJECT_ROOT" | shasum -a 256 | cut -c1-16)"
else
  # No sha tool: fall back to a path-derived key (slashes flattened, bounded).
  repo_key="$(printf '%s' "$PROJECT_ROOT" | tr -c '[:alnum:]' '_' | cut -c1-120)"
fi

SENTINEL_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/soleur/welcomed"
SENTINEL_FILE="$SENTINEL_DIR/$repo_key"

[[ -f "$SENTINEL_FILE" ]] && exit 0

# --- First-Time Welcome ---
# Only emit when the dedupe marker lands — a welcome that cannot be remembered
# fires every session, which is worse than none.
mkdir -p "$SENTINEL_DIR" 2>/dev/null || exit 0
touch "$SENTINEL_FILE" 2>/dev/null || exit 0

cat <<'WELCOME_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."
  }
}
WELCOME_JSON
