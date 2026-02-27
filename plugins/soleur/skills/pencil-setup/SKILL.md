---
name: pencil-setup
description: This skill should be used when Pencil MCP tools are unavailable and need to be installed and registered. It detects the IDE, installs the Pencil extension, and registers the MCP server binary with Claude Code CLI. Triggers on "setup pencil", "install pencil", "pencil not found", "pencil MCP missing".
---

# Pencil Setup

Auto-detect, install, and register the Pencil MCP server with Claude Code CLI.

**Prerequisite:** VS Code or Cursor must be installed. Pencil MCP requires a running IDE with the Pencil extension active. Pencil Desktop is optional.

## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked
from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts
and install the IDE extension automatically.

For interactive use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

For pipeline/automated use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

If the script exits non-zero, a required dependency is missing. Stop and
inform the user with the printed instructions.

If all checks pass, proceed to Step 1 (Check if Already Registered).

## Step 1: Check if Already Registered

```bash
claude mcp list -s user 2>&1 | grep -q "pencil" && echo "REGISTERED" || echo "NOT_REGISTERED"
```

If REGISTERED, check the registered binary path still exists on disk. Extract the path from `claude mcp list -s user` output, then `test -f <path>`. If the file exists, tell the user **"Pencil MCP is already configured. Make sure your IDE is running with Pencil active, then restart Claude Code."** and stop.

If the path does not exist or NOT_REGISTERED, continue to Step 2.

## Step 2: Detect IDE

```bash
command -v cursor >/dev/null 2>&1 && echo "IDE=cursor EXTDIR=$HOME/.cursor/extensions" || \
command -v code >/dev/null 2>&1 && echo "IDE=code EXTDIR=$HOME/.vscode/extensions" || \
echo "NO_IDE"
```

If NO_IDE, tell the user:

> **No supported IDE found.** Pencil requires VS Code or Cursor.
>
> - Install Cursor: https://cursor.com
> - Install VS Code: https://code.visualstudio.com
>
> After installing, run `/soleur:pencil-setup` again.

Then stop.

## Step 3: Find or Install Extension

Look for the Pencil extension binary:

```bash
ls -d ${EXTDIR}/highagency.pencildev-*/out/mcp-server-* 2>/dev/null | sort -V | tail -1
```

If no binary found, install the extension:

```bash
${IDE} --install-extension highagency.pencildev
```

Then re-run the `ls` command above. If still no binary found, tell the user:

> **Extension install failed.** Try installing Pencil manually from the IDE extension marketplace (search "Pencil") or visit https://docs.pencil.dev/getting-started/installation

Then stop.

## Step 4: Register MCP Server

Remove any existing registration, then add with user scope:

```bash
claude mcp remove pencil -s user 2>/dev/null
claude mcp add -s user pencil -- <BINARY_PATH> --app <IDE>
```

Replace `<BINARY_PATH>` with the path found in Step 3, and `<IDE>` with `cursor` or `code` from Step 2.

## Step 5: Verify

```bash
claude mcp list -s user 2>&1 | grep pencil
```

If the `pencil` entry appears, tell the user:

> **Pencil MCP registered.** Restart Claude Code for tools to become available. Make sure your IDE is open with Pencil active.

If it does not appear, tell the user the registration failed and suggest running the commands manually.

## Sharp Edges

- **WebSocket requires visible editor**: The MCP server process runs, but `batch_design`/`batch_get`/`open_document` calls fail with `WebSocket not connected to app` unless the .pen file tab is open and visible in the IDE. Opening via `cursor <path>` CLI is not sufficient -- the user must click the tab to activate the webview.
- **No programmatic save**: After `batch_design` operations, changes exist in editor memory only. The user must Ctrl+S the .pen tab to flush to disk. Verify with `git status` after requesting save.
- **Read before write**: Mockup property values (padding, colors, fonts) may diverge from live CSS. Always `batch_get` the current value before `batch_design` updates to avoid incorrect assumptions.
