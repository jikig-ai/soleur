---
name: pencil-setup
description: "Set up Pencil MCP tools when they are unavailable. Detects Pencil Desktop or an IDE with the Pencil extension and configures the MCP server in the OpenHands mcp_config."
triggers:
- pencil setup
- pencil mcp
- pencil install
---

# Pencil Setup

Auto-detect, install, and register the Pencil MCP server.

**Prerequisite:** One of: (1) the headless CLI (no GUI required, recommended for agents), (2) Pencil Desktop, or (3) an IDE (Cursor/VS Code) with the Pencil extension.

**Known limitation:** macOS detection uses unverified bundle ID `dev.pencil.desktop` -- falls back to PATH-based detection if incorrect.

## Phase 0: Dependency Check

Run the dependency check script before proceeding. When invoked from a pipeline, pass `--auto` to skip interactive prompts, auto-install the IDE extension, and auto-launch Pencil Desktop.

For interactive use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

For pipeline/automated use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

If the script exits non-zero, no Pencil MCP source is available. Stop and inform the user with the printed instructions (both Desktop and IDE options).

If all checks pass, capture these values from the script output:

- `PREFERRED_MODE` -- `headless_cli`, `cli`, `desktop_binary`, or `ide`
- `PREFERRED_BINARY` -- path to binary (adapter for headless, `pencil` for CLI mode)
- `PREFERRED_APP` -- `--app` flag value (empty for CLI and headless modes)
- `PREFERRED_NODE` -- (headless_cli only) path to Node >= 22.9.0 binary

Proceed to Step 1.

## Step 1: Check if Already Registered

Check the project's `.mcp.json` or `mcp_config` for an existing `pencil` server entry:

```bash
grep -q "pencil" .mcp.json 2>/dev/null && echo "REGISTERED" || echo "NOT_REGISTERED"
```

If REGISTERED, check the registered binary path still exists on disk. If it does, tell the user:

- **Headless CLI mode:** "Pencil MCP is already configured via headless CLI adapter. Restart the agent for tools to become available."
- **CLI/Desktop mode:** "Pencil MCP is already configured. Make sure Pencil Desktop is running, then restart the agent."
- **IDE mode:** "Pencil MCP is already configured. Make sure your IDE is running with Pencil active, then restart the agent."

Then stop.

If the path does not exist or NOT_REGISTERED, continue to Step 2.

## Step 2: Register MCP Server

Add the Pencil MCP server to the project's `.mcp.json` configuration. The format depends on `PREFERRED_MODE` from Phase 0.

### Headless CLI mode (`PREFERRED_MODE=headless_cli`)

The adapter requires `PENCIL_CLI_KEY` in the MCP environment. Add to `.mcp.json`:

```json
{
  "mcpServers": {
    "pencil": {
      "command": "<PREFERRED_NODE>",
      "args": ["<PREFERRED_BINARY>"],
      "env": {
        "PENCIL_CLI_KEY": "<key>"
      }
    }
  }
}
```

### CLI mode (`PREFERRED_MODE=cli`)

```json
{
  "mcpServers": {
    "pencil": {
      "command": "pencil",
      "args": ["mcp-server"]
    }
  }
}
```

### Desktop binary mode (`PREFERRED_MODE=desktop_binary`)

```json
{
  "mcpServers": {
    "pencil": {
      "command": "<PREFERRED_BINARY>",
      "args": ["--app", "<PREFERRED_APP>"]
    }
  }
}
```

### IDE mode (`PREFERRED_MODE=ide`)

```json
{
  "mcpServers": {
    "pencil": {
      "command": "<PREFERRED_BINARY>",
      "args": ["--app", "<PREFERRED_APP>"]
    }
  }
}
```

## Step 3: Verify

```bash
grep pencil .mcp.json
```

If the `pencil` entry appears, tell the user:

- **Headless CLI mode:** "Pencil MCP registered via headless adapter. Restart the agent for tools to become available. No GUI required."
- **CLI/Desktop mode:** "Pencil MCP registered. Restart the agent for tools to become available. Make sure Pencil Desktop is running."
- **IDE mode:** "Pencil MCP registered. Restart the agent for tools to become available. Make sure your IDE is open with Pencil active."

If it does not appear, tell the user the registration failed and suggest adding the configuration manually.

## Sharp Edges

- **IDE mode -- WebSocket requires visible editor**: In IDE mode, the MCP server connects via WebSocket to the IDE's editor webview. `batch_design`/`batch_get`/`open_document` calls fail with `WebSocket not connected to app` unless the .pen file tab is open and visible in the IDE.
- **Desktop mode -- app must be running**: In CLI or Desktop binary mode, Pencil Desktop must be running. The MCP server connects to the Desktop app directly. If Desktop is not running, tools fail silently.
- **No programmatic save (Desktop/IDE only)**: In Desktop or IDE mode, after `batch_design` operations, changes exist in editor memory only. The user must Ctrl+S (IDE) or Cmd+S/Ctrl+S (Desktop) to flush to disk. In headless CLI mode, the adapter auto-calls `save()` after mutating operations.
- **Read before write**: Mockup property values (padding, colors, fonts) may diverge from live CSS. Always `batch_get` the current value before `batch_design` updates.
- **pencil CLI collision**: The `pencil` binary name collides with evolus/pencil. The check_deps.sh script guards against this by verifying the version string.
- **Headless CLI has programmatic save**: Unlike Desktop/IDE modes, `pencil interactive --out` supports a `save()` command that writes to disk without manual Ctrl+S.
- **Text nodes do not support `padding`**: Passing `padding` to a `batch_design` operation on a text node produces "Invalid properties: /padding unexpected property". Wrap the text in a frame and apply padding to the frame instead.
