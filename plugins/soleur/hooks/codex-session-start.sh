#!/usr/bin/env bash
set -euo pipefail

[[ -n "${CODEX_THREAD_ID:-}" || -n "${PLUGIN_ROOT:-}" ]] || exit 0
SOLEUR_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jq -n --arg root "$SOLEUR_PLUGIN_ROOT" \
  --rawfile instructions "$SOLEUR_PLUGIN_ROOT/codex/INSTRUCTIONS.md" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    ("Soleur plugin root: " + $root + "\n" + $instructions)}}'
