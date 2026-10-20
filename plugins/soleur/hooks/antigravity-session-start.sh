#!/usr/bin/env bash
set -euo pipefail

[[ -n "${ANTIGRAVITY_CLI:-}" || -n "${AGY_VERSION:-}" || -n "${GEMINI_CLI:-}" || -n "${PLUGIN_ROOT:-}" ]] || exit 0
SOLEUR_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run session start worktree cleanup if available
if [[ -f "$SOLEUR_PLUGIN_ROOT/skills/git-worktree/scripts/worktree-manager.sh" ]]; then
  bash "$SOLEUR_PLUGIN_ROOT/skills/git-worktree/scripts/worktree-manager.sh" cleanup-merged 2>/dev/null || true
fi

jq -n --arg root "$SOLEUR_PLUGIN_ROOT" \
  --rawfile instructions "$SOLEUR_PLUGIN_ROOT/antigravity/INSTRUCTIONS.md" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    ("Soleur plugin root: " + $root + "\n" + $instructions)}}'
