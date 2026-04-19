---
name: pencil-setup
description: "This skill should be used when Pencil MCP tools are unavailable and need installation. It detects Pencil Desktop or an IDE with the Pencil extension and registers the MCP server with Claude Code CLI."
---

# Pencil Setup

Auto-detect, install, and register the Pencil MCP server with Claude Code CLI.

**Prerequisite:** One of: (1) the headless CLI (no GUI required, recommended for agents), (2) Pencil Desktop, or (3) an IDE (Cursor/VS Code) with the Pencil extension.

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

If all checks pass, capture these values from the script output:

- `PREFERRED_MODE` -- `headless_cli`, `cli`, `desktop_binary`, or `ide`
- `PREFERRED_BINARY` -- path to binary (adapter for headless, `pencil` for CLI mode)
- `PREFERRED_APP` -- `--app` flag value (empty for CLI and headless modes)
- `PREFERRED_NODE` -- (headless_cli only) path to Node >= 22.9.0 binary

Proceed to Step 1.

## Step 1: Check if Already Registered

<!-- verified: 2026-04-19 source: claude mcp list --help (the `-s` flag was dropped from `list`; plain `claude mcp list` now includes user-scoped entries) -->

```bash
claude mcp list 2>&1 | grep -q "pencil" && echo "REGISTERED" || echo "NOT_REGISTERED"
```

If REGISTERED, check the registered binary path still exists on disk. Extract the path from `claude mcp list` output, then `test -f <path>`. If the file exists (or `PREFERRED_MODE=cli`), tell the user:

- **Headless CLI mode:** "Pencil MCP is already configured via headless CLI adapter. Restart Claude Code for tools to become available."
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

### Headless CLI mode (`PREFERRED_MODE=headless_cli`)

**First**, sync the repo adapter into the user's install location so stale installed copies don't mask repo-level fixes (see #2630):

```bash
bash plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh
```

The adapter requires `PENCIL_CLI_KEY` in the MCP environment. Retrieve the key, then register with `-e` **before** the `--` separator:

```bash
# Retrieve the key (Doppler, or use pencil login token)
PENCIL_KEY=$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain 2>/dev/null)
# If Doppler is not available, check for a stored login token:
# PENCIL_KEY=$(cat ~/.config/pencil/auth.json 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

claude mcp add pencil -s user -e PENCIL_CLI_KEY="$PENCIL_KEY" -- <PREFERRED_NODE> <PREFERRED_BINARY>
```

Replace `<PREFERRED_NODE>` with the Node 22+ binary path and `<PREFERRED_BINARY>` with the adapter path from Phase 0.

**Critical:** The `-e` flag must appear before `--`. Placing it after `--` passes it as a CLI arg to the adapter instead of setting an environment variable, causing silent auth failures.

**Drift check.** If the adapter ever appears to "silently drop" operations, verify the installed copy is in sync with the repo:

```bash
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift
# On DRIFT, re-sync: add --auto, or re-run copy_adapter.sh
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
claude mcp list 2>&1 | grep pencil
```

If the `pencil` entry appears, tell the user:

- **Headless CLI mode:** "Pencil MCP registered via headless adapter. Restart Claude Code for tools to become available. No GUI required."
- **CLI/Desktop mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure Pencil Desktop is running."
- **IDE mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure your IDE is open with Pencil active."

If it does not appear, tell the user the registration failed and suggest running the commands manually.

## Sharp Edges

- **IDE mode -- WebSocket requires visible editor**: In IDE mode (`PREFERRED_MODE=ide`), the MCP server connects via WebSocket to the IDE's editor webview. `batch_design`/`batch_get`/`open_document` calls fail with `WebSocket not connected to app` unless the .pen file tab is open and visible in the IDE. Opening via `cursor <path>` CLI is not sufficient -- the user must click the tab to activate the webview.
- **Desktop mode -- app must be running**: In CLI or Desktop binary mode, Pencil Desktop must be running. The MCP server connects to the Desktop app directly. If Desktop is not running, tools fail silently. Use `--auto` to auto-launch Desktop before registration.
- **No programmatic save (Desktop/IDE only)**: In Desktop or IDE mode, after `batch_design` operations, changes exist in editor memory only. The user must Ctrl+S (IDE) or Cmd+S/Ctrl+S (Desktop) to flush to disk. In headless CLI mode, the adapter auto-calls `save()` after mutating operations — no manual save needed.
- **Read before write**: Mockup property values (padding, colors, fonts) may diverge from live CSS. Always `batch_get` the current value before `batch_design` updates to avoid incorrect assumptions.
- **pencil CLI collision**: The `pencil` binary name collides with evolus/pencil. The check_deps.sh script guards against this by verifying the version string contains "pencil.dev" or checking for the `mcp-server` subcommand.
- **Headless CLI interactive mode is not MCP**: The Pencil npm headless CLI's `pencil interactive` command speaks a custom REPL format (`tool_name({ key: value })`), not MCP protocol. An adapter wrapper is needed to bridge it to Claude Code's MCP framework. The headless CLI also lacks the `mcp-server` subcommand that the Desktop-installed CLI exposes, and its version string (`pencil 0.2.3`) doesn't match existing detection patterns.
- **Headless CLI has programmatic save**: Unlike Desktop/IDE modes, `pencil interactive --out` supports a `save()` command that writes to disk without manual Ctrl+S.
- **Adapter child process Node version**: The pencil CLI uses `#!/usr/bin/env node`, so the resolved Node depends on PATH, not on the binary that launched the adapter. The adapter's `buildPencilEnv()` must prepend `dirname(process.execPath)` to PATH to ensure child processes inherit the correct Node version (22+).
- **Text nodes do not support `padding`**: Passing `padding` to a `batch_design` operation on a text node produces "Invalid properties: /padding unexpected property". The adapter enriches this error with a hint, but the fix is to wrap the text in a frame and apply padding to the frame instead (see #1107 workaround).
