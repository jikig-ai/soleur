#!/usr/bin/env bash
# SessionStart hook: preinstall the Soleur plugin from the local workspace
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/soleur"

if [ -d "$PLUGIN_DIR" ]; then
  claude plugin install "$PLUGIN_DIR" 2>/dev/null || true
fi
