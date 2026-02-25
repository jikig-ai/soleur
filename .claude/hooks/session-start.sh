#!/usr/bin/env bash
# SessionStart hook: register the local Soleur marketplace and install the plugin
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARKETPLACE_DIR="$REPO_ROOT"

# Only proceed if the marketplace manifest exists
if [ ! -f "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" ]; then
  exit 0
fi

# Add the local marketplace (idempotent — no-ops if already added)
claude plugin marketplace add "$MARKETPLACE_DIR" 2>/dev/null || true

# Install the soleur plugin from the local marketplace into local scope
# --scope local keeps it gitignored and per-user
claude plugin install "soleur@soleur" --scope local 2>/dev/null || true
