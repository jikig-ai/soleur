#!/usr/bin/env bash
set -euo pipefail

[[ -n "${DEVIN:-}" || -n "${DEVIN_HOME:-}" || -n "${DEVIN_PROJECT_DIR:-}" || -n "${DEVIN_PLUGIN_ROOT:-}" ]] || exit 0
SOLEUR_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jq -n --arg root "$SOLEUR_PLUGIN_ROOT" \
  --rawfile instructions "$SOLEUR_PLUGIN_ROOT/devin/INSTRUCTIONS.md" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    ("Soleur plugin root: " + $root + "\n" + $instructions)}}'
