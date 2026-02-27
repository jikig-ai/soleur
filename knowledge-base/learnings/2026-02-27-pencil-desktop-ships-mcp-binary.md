# Learning: Pencil Desktop ships its own MCP server binary

## Problem

The `check_deps.sh` script treated all MCP binaries as coming from the IDE extension only. When investigating whether Pencil Desktop should be preferred, we needed to know if Desktop ships its own MCP server binary and whether it's accessible.

## Solution

Extracted the Pencil Desktop AppImage (`--appimage-extract`) and found:
- Desktop ships `mcp-server-linux-x64` at `resources/app.asar.unpacked/out/`
- The binary is a different build from the extension's (different SHA256, same size)
- Desktop also bundles `@anthropic-ai/claude-agent-sdk` and `@openai/codex-sdk`
- The binary accepts the same `-app` flag as the extension's

### Platform accessibility

- **macOS**: Desktop binary is directly accessible at `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*`
- **Linux AppImage**: Binary is trapped inside the AppImage; only accessible if the user runs `--appimage-extract` to create `squashfs-root/`

### Extension binary platform filter bug

The `detect_extension()` function used `sort -V | tail -1` across all platform binaries (darwin, linux, windows). On Linux this returned `mcp-server-windows-x64.exe` (last alphabetically). Fixed by filtering with OS prefix and architecture suffix.

## Key Insight

When a tool ships binaries through multiple distribution channels (IDE extension, Desktop app), prefer the Desktop binary when directly accessible — it's likely more tightly coupled to the Desktop's version. But on Linux with AppImage distribution, the binary isn't accessible without extraction, so gracefully fall back to the extension binary. Always filter platform-specific binaries by the current OS and architecture, never rely on alphabetical sort order.

## Session Errors

1. Shell syntax error: `&;` is invalid bash (backgrounding doesn't use semicolon)
2. Pre-existing bug: `detect_extension()` returned Windows binary on Linux (fixed)
3. CWD drifted to `/tmp` after AppImage extraction (had to cd back to worktree)

## Tags
category: integration-issues
module: pencil-setup
