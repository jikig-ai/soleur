# Learning: gst-plugin-scanner infinite CPU loop on dev machines

## Problem
GNOME's `localsearch-3` (Tracker file indexer) spawns `gst-plugin-scanner` to scan media files. On developer machines with large repositories, gst-plugin-scanner gets stuck in an infinite CPU loop (99.9% CPU for 85+ minutes). Killing the process alone doesn't help — localsearch-3 immediately respawns it via systemd/D-Bus activation.

## Solution
Three-layer fix:

1. **Kill the scanner:** `kill <pid>` targets gst-plugin-scanner instances with >5 min CPU time
2. **Stop the parent:** `systemctl --user stop localsearch-3.service` prevents immediate respawn
3. **Mask the service:** `systemctl --user mask localsearch-3.service` prevents D-Bus reactivation

Added `cleanup_runaway_processes` to `worktree-manager.sh` that automates all three steps. It runs during `cleanup-merged` (session start + post-merge) and is available standalone as `cleanup-procs`.

The function uses CPU time (from `ps -o cputime=`) rather than wall clock time to distinguish stuck scanners (>5 min CPU) from legitimate short-lived scans.

## Key Insight
Killing child processes without addressing the parent service is futile when systemd manages the respawn. The fix must target the service unit, not just the process. `systemctl --user mask` is stronger than `stop` because it prevents D-Bus socket activation from restarting the service.

## Tags
category: runtime-errors
module: worktree-manager
