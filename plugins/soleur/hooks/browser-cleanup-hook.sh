#!/usr/bin/env bash

# Browser Cleanup Stop Hook
# Kills orphaned Playwright Chrome processes on session exit.
# Defense-in-depth: agents should call browser_close proactively,
# but this hook catches any that slip through.

set -euo pipefail

# Consume stdin (stop hook API sends last_assistant_message)
cat > /dev/null

# Find Chrome processes launched by Playwright MCP (--remote-debugging-pipe flag
# is unique to Playwright-managed Chrome instances, avoiding false positives
# against user-launched browsers).
PLAYWRIGHT_PIDS=$(pgrep -f 'chrome.*--remote-debugging-pipe' 2>/dev/null || true)

if [[ -n "$PLAYWRIGHT_PIDS" ]]; then
  KILLED=0
  for pid in $PLAYWRIGHT_PIDS; do
    if kill "$pid" 2>/dev/null; then
      KILLED=$((KILLED + 1))
    fi
  done
  if [[ $KILLED -gt 0 ]]; then
    echo "Browser cleanup: killed $KILLED orphaned Playwright Chrome process(es)." >&2
  fi
fi

# Allow exit (do not block)
exit 0
