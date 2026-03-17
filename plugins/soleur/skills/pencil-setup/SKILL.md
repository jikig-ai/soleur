---
name: pencil-setup
description: "This skill should be used when Pencil MCP tools are unavailable and need installation. It detects Pencil Desktop or an IDE with the Pencil extension and registers the MCP server with Claude Code CLI."
---

# Pencil Setup

Auto-detect, install, and register the Pencil MCP server with Claude Code CLI.

**Prerequisite:** Pencil Desktop or an IDE (Cursor/VS Code) with the Pencil extension must be available. Pencil Desktop is preferred -- it works without an IDE.

**Known limitation:** macOS detection uses unverified bundle ID `dev.pencil.desktop` -- falls back to PATH-based detection if incorrect.

## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked
from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts,
auto-install the IDE extension, and auto-launch Pencil Desktop.

For interactive use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

For pipeline/automated use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

If the script exits non-zero, no Pencil MCP source is available. Stop and
inform the user with the printed instructions (both Desktop and IDE options).

If all checks pass, capture three values from the script output:
- `PREFERRED_MODE` -- `cli`, `desktop_binary`, or `ide`
- `PREFERRED_BINARY` -- path to binary (or `pencil` for CLI mode)
- `PREFERRED_APP` -- `--app` flag value (empty for CLI mode)

Proceed to Step 1.

## Step 1: Check if Already Registered

```bash
claude mcp list -s user 2>&1 | grep -q "pencil" && echo "REGISTERED" || echo "NOT_REGISTERED"
```

If REGISTERED, check the registered binary path still exists on disk. Extract the path from `claude mcp list -s user` output, then `test -f <path>`. If the file exists (or `PREFERRED_MODE=cli`), tell the user:

- **CLI/Desktop mode:** "Pencil MCP is already configured. Make sure Pencil Desktop is running, then restart Claude Code."
- **IDE mode:** "Pencil MCP is already configured. Make sure your IDE is running with Pencil active, then restart Claude Code."

Then stop.

If the path does not exist or NOT_REGISTERED, continue to Step 2.

## Step 2: Register MCP Server

Registration varies by `PREFERRED_MODE` from Phase 0:

Remove any existing registration first:

```bash
claude mcp remove pencil -s user 2>/dev/null
```

### CLI mode (`PREFERRED_MODE=cli`)

```bash
claude mcp add -s user pencil -- pencil mcp-server
```

No `--app` flag needed -- the CLI handles connection internally.

### Desktop binary mode (`PREFERRED_MODE=desktop_binary`)

```bash
claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>
```

Replace `<PREFERRED_BINARY>` and `<PREFERRED_APP>` with values from Phase 0.

### IDE mode (`PREFERRED_MODE=ide`)

```bash
claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>
```

Replace `<PREFERRED_BINARY>` with the extension binary path and `<PREFERRED_APP>` with `cursor` or `visual_studio_code`.

## Step 3: Verify

```bash
claude mcp list -s user 2>&1 | grep pencil
```

If the `pencil` entry appears, tell the user:

- **CLI/Desktop mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure Pencil Desktop is running."
- **IDE mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure your IDE is open with Pencil active."

If it does not appear, tell the user the registration failed and suggest running the commands manually.

## Sharp Edges

- **IDE mode -- WebSocket requires visible editor**: In IDE mode (`PREFERRED_MODE=ide`), the MCP server connects via WebSocket to the IDE's editor webview. `batch_design`/`batch_get`/`open_document` calls fail with `WebSocket not connected to app` unless the .pen file tab is open and visible in the IDE. Opening via `cursor <path>` CLI is not sufficient -- the user must click the tab to activate the webview.
- **Desktop mode -- app must be running**: In CLI or Desktop binary mode, Pencil Desktop must be running. The MCP server connects to the Desktop app directly. If Desktop is not running, tools fail silently. Use `--auto` to auto-launch Desktop before registration.
- **No programmatic save**: After `batch_design` operations, changes exist in editor memory only. The user must Ctrl+S (IDE) or Cmd+S/Ctrl+S (Desktop) to flush to disk. Verify with `git status` after requesting save.
- **Read before write**: Mockup property values (padding, colors, fonts) may diverge from live CSS. Always `batch_get` the current value before `batch_design` updates to avoid incorrect assumptions.
- **pencil CLI collision**: The `pencil` binary name collides with evolus/pencil. The check_deps.sh script guards against this by verifying the version string contains "pencil.dev" or checking for the `mcp-server` subcommand.
