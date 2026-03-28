#!/usr/bin/env bash
# tmpfs-guard.sh — Monitors /tmp usage and removes oversized Claude Code
# task output files before they can fill tmpfs and crash all sessions.
#
# Designed to run as a user cron job every 5 minutes.
# No sudo required — only touches files owned by the current user.

set -euo pipefail

THRESHOLD_MB=200        # Delete .output files larger than this
USAGE_WARN_PCT=70       # Notify when /tmp usage exceeds this percentage
CLAUDE_TMP="/tmp/claude-$(id -u)"

# Exit early if no Claude temp directory exists
if [ ! -d "$CLAUDE_TMP" ]; then
  exit 0
fi

# Check /tmp usage percentage
USAGE_PCT=$(df /tmp --output=pcent | tail -1 | tr -d ' %')

# Find and remove oversized .output files
CLEANED=0
CLEANED_MB=0
while IFS= read -r file; do
  SIZE_BYTES=$(stat --format=%s "$file" 2>/dev/null) || continue
  SIZE_MB=$(( SIZE_BYTES / 1048576 ))
  # Skip files still being written by an active process
  if fuser "$file" >/dev/null 2>&1; then
    if [ "$USAGE_PCT" -lt 90 ]; then
      continue
    fi
    # At 90%+ usage, kill is justified — the system is about to lock up
  fi
  rm -f "$file"
  CLEANED=$(( CLEANED + 1 ))
  CLEANED_MB=$(( CLEANED_MB + SIZE_MB ))
done < <(find "$CLAUDE_TMP" -name "*.output" -size "+${THRESHOLD_MB}M" -type f 2>/dev/null)

# Notify if files were cleaned
if [ "$CLEANED" -gt 0 ]; then
  notify-send -u critical -i dialog-warning "tmpfs-guard" \
    "Removed $CLEANED runaway .output file(s) (${CLEANED_MB} MB). /tmp was at ${USAGE_PCT}%." 2>/dev/null || true
  logger -t tmpfs-guard "Removed $CLEANED .output files (${CLEANED_MB} MB). /tmp at ${USAGE_PCT}%."
fi

# Warn on high usage even if no files were cleaned (something else filling /tmp)
if [ "$USAGE_PCT" -ge "$USAGE_WARN_PCT" ] && [ "$CLEANED" -eq 0 ]; then
  notify-send -u normal -i dialog-information "tmpfs-guard" \
    "/tmp is at ${USAGE_PCT}% usage. Investigate with: du -sh /tmp/*" 2>/dev/null || true
  logger -t tmpfs-guard "/tmp at ${USAGE_PCT}% — no .output files found to clean."
fi
