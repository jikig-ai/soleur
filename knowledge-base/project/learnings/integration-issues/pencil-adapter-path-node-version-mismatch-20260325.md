---
module: pencil-setup
date: 2026-03-25
problem_type: integration_issue
component: tooling
symptoms:
  - "Pencil MCP tools time out with 'Timed out waiting for prompt after 30000ms'"
  - "pencil CLI crashes with ERR_REQUIRE_ESM when spawned by adapter"
  - "Adapter shows Connected in claude mcp list but all tool calls fail"
root_cause: config_error
resolution_type: code_fix
severity: high
tags: [pencil, mcp-adapter, node-version, path, env, child-process]
---

# Troubleshooting: Pencil MCP Adapter Spawns Pencil with Wrong Node Version

## Problem

The pencil MCP adapter was registered and showed "Connected" in `claude mcp list`, but every tool call (`get_editor_state`, `get_guidelines`, etc.) timed out after 30 seconds. The adapter's child process (pencil CLI) was crashing silently before producing the expected REPL prompt.

## Environment

- Module: pencil-setup (pencil-mcp-adapter.mjs)
- Node Version: Adapter runs on v22.14.0, pencil resolved to system v21.7.3
- Affected Component: `buildPencilEnv()` function in pencil-mcp-adapter.mjs
- Date: 2026-03-25

## Symptoms

- `mcp__pencil__get_editor_state` returns "[pencil-adapter] Timed out waiting for prompt after 30000ms"
- `mcp__pencil__get_guidelines` returns same timeout error
- `claude mcp list` shows pencil as "Connected" (misleading — adapter process is alive, child process is not)
- Running pencil directly with system Node produces `ERR_REQUIRE_ESM` crash

## What Didn't Work

**Attempted: Checking if Pencil Desktop was running**

- Pencil Desktop process not found, but irrelevant — headless CLI doesn't need it
- The real issue was invisible: the child process crash was caught by the adapter's timeout, not surfaced as an error

**Attempted: Checking authentication**

- Auth was fine (`~/.pencil/license-token.json` exists, `PENCIL_CLI_KEY` set in MCP env)
- Red herring that delayed root cause identification

## Session Errors

**MCP tool disconnection after killing adapter process**

- **Recovery:** Re-registered pencil MCP server via `claude mcp remove` + `claude mcp add`. Server reconnected but tools remained unavailable in the current conversation session.
- **Prevention:** Never kill an MCP adapter process mid-conversation. MCP tools from disconnected servers cannot be recovered via ToolSearch — a new conversation is required. If an adapter needs restarting, inform the user that a new session will be needed.

**Misread directory listing output**

- **Recovery:** Ran `ls -la` on the specific directory to verify contents
- **Prevention:** When `ls` output lists multiple paths from a glob, verify which path each file belongs to before assuming location

## Solution

The root cause was in `buildPencilEnv()`. The function creates a minimal environment for the pencil child process, passing through `PATH` from the adapter's own `process.env`. However, Claude Code launches the adapter with an explicit Node binary path (`/home/jean/.local/node22/bin/node`), bypassing PATH resolution. The adapter's inherited PATH doesn't include the node22 directory.

When the adapter spawns pencil via `nodeSpawn(binary, args, { env: buildPencilEnv() })`, the pencil CLI's `#!/usr/bin/env node` shebang resolves `node` from PATH — finding system Node v21.7.3 instead of v22.14.0. Node 21 can't load the `@anthropic-ai/claude-agent-sdk/sdk.mjs` ESM module via `require()`, causing an immediate crash.

**Code changes:**

```javascript
// Before (broken):
import { join } from "node:path";

function buildPencilEnv() {
  // ... allowlist loop ...
  return env;
}

// After (fixed):
import { dirname, join } from "node:path";

function buildPencilEnv() {
  // ... allowlist loop ...
  // Prepend the adapter's own Node directory to PATH so that pencil's
  // `#!/usr/bin/env node` shebang resolves to the same Node version (22+)
  // that runs the adapter, not an incompatible system Node.
  const nodeDir = dirname(process.execPath);
  if (env.PATH) {
    env.PATH = `${nodeDir}:${env.PATH}`;
  } else {
    env.PATH = nodeDir;
  }
  return env;
}
```

## Why This Works

The adapter process knows its own Node binary via `process.execPath`. By prepending that binary's directory to PATH before spawning the child process, any `#!/usr/bin/env node` shebang in child scripts resolves to the same Node version. This is robust regardless of the system's default Node version or how Claude Code launches the adapter.

The fix is in `buildPencilEnv()` rather than in the MCP registration command because:

1. The registration already uses an absolute path to the correct Node for the adapter itself
2. The problem only manifests in child processes spawned by the adapter
3. Fixing it in `buildPencilEnv()` makes the adapter self-healing across any PATH configuration

## Prevention

- When an MCP adapter spawns child processes, always ensure the child inherits the parent's Node version via PATH, not just the parent's env
- When a shebang uses `#!/usr/bin/env node`, the resolved binary depends on PATH — a process launched with an explicit Node path does NOT guarantee its children use the same version
- When MCP tools time out, check the child process's stderr for crash output before investigating auth or connectivity
- Adapter "Connected" status only means the adapter process is alive — it does not guarantee the underlying tool (pencil CLI) is functional

## Related Issues

- See also: [pencil-headless-cli-interactive-mode-not-mcp](../2026-03-24-pencil-headless-cli-interactive-mode-not-mcp.md) — documents the ERR_REQUIRE_ESM error in initial setup context (line 50-53), but the adapter PATH inheritance is a distinct issue
- See also: [pencil-desktop-standalone-mcp-three-tier-detection](../2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md) — original CLI detection cascade
