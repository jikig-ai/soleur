#!/usr/bin/env bash
set -euo pipefail

# orphan-reaper.sh -- Remove stale .orphaned-* workspace directories.
# Runs as a systemd timer every 6 hours. Always exits 0.
#
# workspace.ts removeWorkspaceDir() moves root-owned directories aside to
# .orphaned-<timestamp> paths under /mnt/data/workspaces/. This script
# cleans them up after MAX_AGE_HOURS to reclaim disk space.

readonly WORKSPACE_ROOT="${WORKSPACE_ROOT:-/mnt/data/workspaces}"
readonly MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

if [[ ! -d "$WORKSPACE_ROOT" ]]; then
  echo "Workspace root does not exist: $WORKSPACE_ROOT"
  exit 0
fi

# Find .orphaned-* directories older than MAX_AGE_HOURS
found=0
while IFS= read -r -d '' dir; do
  echo "Removing orphaned workspace: $dir"
  rm -rf "$dir"
  found=$((found + 1))
done < <(find "$WORKSPACE_ROOT" -maxdepth 1 -type d -name '*.orphaned-*' -mmin +$((MAX_AGE_HOURS * 60)) -print0)

if [[ "$found" -eq 0 ]]; then
  echo "No orphaned workspaces older than ${MAX_AGE_HOURS}h found"
else
  echo "Cleaned up $found orphaned workspace(s)"
fi

exit 0
