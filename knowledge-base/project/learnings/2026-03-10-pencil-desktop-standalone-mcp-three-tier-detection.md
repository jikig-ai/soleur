---
title: Pencil Desktop standalone MCP support with three-tier detection cascade
date: 2026-03-10
category: integration-issues
tags: [pencil-setup, mcp-integration, dependency-detection, process-management, desktop-support, three-tier detection removes IDE hard dependency]
---

# Learning: Pencil Desktop standalone MCP support with three-tier detection cascade

## Problem

The `pencil-setup` skill's `check_deps.sh` treated IDE (Cursor/VS Code) as a hard dependency for Pencil MCP setup. When no IDE was detected, setup failed entirely (`exit 1`), making Pencil MCP unusable from Claude Code in standalone terminal environments, CI/CD pipelines, and any setup without an IDE. During the X banner design session (#483), Pencil MCP failed with `"WebSocket not connected to app: cursor"` because no .pen tab was visible, blocking the entire design workflow.

## Solution

Restructured `check_deps.sh` with a three-tier detection cascade where each tier is independent and falls through cleanly:

1. **CLI tier** (highest priority): Detect `pencil` CLI in PATH (with evolus/pencil collision guard via version string check), register as `pencil mcp-server`. No `--app` flag needed -- the CLI handles connection internally.

2. **Desktop binary tier**: Detect Pencil Desktop via platform-specific checks (macOS app bundle, Linux .deb/AppImage), locate the MCP binary directly, register with `--app pencil`.

3. **IDE tier** (fallback): Detect IDE extension and register with `--app cursor` or `--app visual_studio_code` (corrected from the previous `--app code` value).

Key implementation details:

- Output contract: `PREFERRED_MODE`, `PREFERRED_BINARY`, `PREFERRED_APP` consumed by SKILL.md
- Main flow flattened to `try_cli_tier || try_desktop_tier || try_ide_tier`
- `is_pencil_running()` uses platform-specific process matching (macOS: `Pencil.app/Contents/MacOS`, Linux: `pgrep -x pencil` or AppImage pattern) to avoid false positives from broad `pgrep -f "[Pp]encil"`
- `find_appimage()` helper eliminates triplicated directory scan loops
- `auto_launch_desktop()` validates pencil.dev binary before launching (prevents launching evolus/pencil)
- `attempt_extension_install()` extracted to flatten Tier 3 nesting from 5 levels to 2

## Key Insight

When a tool distributes through multiple channels (IDE extension, Desktop app, CLI), structure dependency detection as a priority cascade where each tier is independent and falls through cleanly. The CLI abstraction layer is the best tier because it eliminates platform-specific binary path resolution entirely. Each tier should set the same output contract variables and the main flow should be a simple `try_A || try_B || try_C` chain -- this makes the code linear and each tier testable in isolation.

## Session Errors

None.

## Tags

category: integration-issues
module: pencil-setup
symptoms: IDE hard dependency blocks standalone terminal use, WebSocket not connected to app
