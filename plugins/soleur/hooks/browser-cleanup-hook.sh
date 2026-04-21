#!/usr/bin/env bash

# Browser Cleanup Stop Hook
# Kills orphaned Playwright Chrome processes on session exit.
# Defense-in-depth: agents should call browser_close proactively,
# but this hook catches any that slip through.
#
# Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754)
# Rule: After completing a Playwright task, call `browser_close`
#   [id: cq-after-completing-a-playwright-task-call]
#   [hook-enforced: browser-cleanup-hook.sh].
# This hook is the defense-in-depth backstop. Agents MUST still call
# `browser_close` proactively at the end of each Playwright session —
# relying on the stop-hook alone leaves open browsers across tool calls,
# exhausts the Playwright `--isolated` singleton, and requires Chrome-kill
# recovery. See AGENTS.md pointer entry for the canonical one-liner.

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
