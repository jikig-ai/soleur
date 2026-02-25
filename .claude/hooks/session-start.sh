#!/usr/bin/env bash
# SessionStart hook: register the local Soleur marketplace and install the plugin
#
# Timing: This hook runs AFTER Claude Code loads its plugin registry.
# - First session on a fresh container: plugin is installed to cache but skills
#   are NOT available until the next session (container state is cached).
# - Subsequent sessions: plugin is loaded from cache at startup; this hook
#   is a fast no-op that ensures the cache stays fresh.
set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Only proceed if the marketplace manifest exists
if [ ! -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]; then
  exit 0
fi

# Register the local marketplace (idempotent -- no-ops if already added)
claude plugin marketplace add "$REPO_ROOT" 2>/dev/null || true

# Install the plugin from the local marketplace into local scope
# --scope local keeps it gitignored and per-user
# Idempotent: updates the cache if the version in marketplace.json changed
claude plugin install "soleur@soleur" --scope local 2>/dev/null || true
