# Learning: Pencil Editor Operational Requirements for MCP Editing

## Problem

When using Pencil MCP tools (`batch_design`, `batch_get`, `open_document`) to edit `.pen` files, three operational requirements were discovered that are not documented elsewhere:

1. The Pencil editor webview must be **actively visible** in Cursor — the MCP server binary runs as a process but fails with `WebSocket not connected to app: cursor` unless the editor webview has an active connection.
2. Pencil does **not auto-save** after `batch_design` operations. Changes persist in memory but are not flushed to disk until the user presses Ctrl+S.
3. `.pen` mockup values may **diverge from live CSS** — always read the current property value before updating to avoid incorrect assumptions.

## Solution

### Ensuring Pencil Connection
1. Open the `.pen` file in Cursor (via `cursor <path>` CLI or manually)
2. **Click on the .pen tab** so the Pencil editor webview is active and visible
3. Only then call `mcp__pencil__open_document` — it will succeed once WebSocket connects
4. If connection fails, ask the user to focus the .pen tab in Cursor

### Saving Changes to Disk
After `batch_design` operations complete:
1. Verify changes via `batch_get` (confirms in-memory state)
2. Ask the user to press Ctrl+S on the .pen tab
3. Verify with `stat --format='%y' <path>` and `git status --short` that the file was written

No programmatic save trigger exists — `xdotool` and `ydotool` are not reliably available, and there is no Pencil MCP "save" operation.

### Read Before Write
Always call `batch_get` on the target node before `batch_design` updates. In this session, the plan assumed hero padding was 128px (from CSS `--space-12` history), but the actual .pen value was `[100, 80, 80, 80]`. The correction was straightforward only because we read the value first.

## Key Insight

Pencil MCP is a bridge between an in-editor webview and the CLI. Both sides must be active: the MCP server process (auto-started by Claude Code) AND the editor webview (requires user to have the .pen file tab open). Edits via MCP are in-memory until explicitly saved by the user. Always verify disk persistence after edits.

## Tags
category: integration-issues
module: pencil-mcp
symptoms: WebSocket not connected, .pen file not modified in git after batch_design
