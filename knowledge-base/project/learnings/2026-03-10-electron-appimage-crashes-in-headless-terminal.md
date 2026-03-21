# Learning: Electron/AppImage desktop apps crash in headless terminals

## Problem

During dogfood testing of the Pencil Desktop three-tier detection (#499), the `auto_launch_desktop()` function attempted to start Pencil Desktop (an Electron app distributed as an AppImage) with `--auto` in a headless SSH terminal. The process immediately died with `Trace/breakpoint trap` (SIGTRAP). This is expected behavior: Electron apps require a display server (X11/Wayland) for GPU compositing and window management. In headless environments, the app crashes before reaching any application logic.

This matters for the `pencil-setup` skill because Tier 2 (Desktop binary) may detect the binary but fail to launch it, leaving the MCP server unregistered.

## Solution

1. **Detect headless before launching**: Check for `$DISPLAY` (X11) or `$WAYLAND_DISPLAY` before attempting to launch any GUI app. If neither is set, skip the launch and fall through to the next tier.

```bash
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "[info] No display server detected -- skipping Desktop launch"
  return 1  # fall through to next tier
fi
```

2. **Separate detection from launch**: The three-tier cascade should detect the binary (confirming Tier 2 is available) without requiring it to be running. MCP registration can use the binary path directly. Only attempt launch if the user explicitly requests it or if a display server is available.

3. **Document the constraint**: Skills that depend on GUI apps should note in their SKILL.md that headless terminal environments will fall through to lower tiers.

## Key Insight

Binary detection and binary execution are separate concerns in dependency cascades. A tier can succeed at detection (the binary exists and is the right version) while failing at execution (no display server). Design cascades so that detection alone is sufficient for registration, and execution failures are handled gracefully rather than crashing the whole flow.

## Tags

category: runtime-errors
module: pencil-setup
symptoms: Trace/breakpoint trap, SIGTRAP, Electron crash in SSH, AppImage crash headless
