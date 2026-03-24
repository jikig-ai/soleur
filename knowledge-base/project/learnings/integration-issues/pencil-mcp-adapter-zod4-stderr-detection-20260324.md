---
module: Pencil MCP Adapter
date: 2026-03-24
problem_type: integration_issue
component: tooling
symptoms:
  - "MCP listTools() crashes with Cannot read properties of undefined (reading '_zod') when using z.record(z.unknown())"
  - "batch_design errors return empty response text — pencil writes errors to stderr not stdout"
  - "detect_headless_cli() fails because binary requires Node 22+ but system has Node 21"
  - ".mcp.json created by claude mcp add -s project contains plaintext API key"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [mcp-adapter, zod-4, stderr, pencil, node-version, detection]
synced_to: []
---

# Learning: Pencil MCP Adapter — Zod 4 Compat, Stderr Capture, and Detection Gotchas

## Problem

Building an MCP adapter to bridge the pencil interactive REPL to Claude Code's MCP protocol exposed three independent integration issues:

1. **Zod 4 + MCP SDK compat**: `z.record(z.unknown())` causes `listTools()` to throw `Cannot read properties of undefined (reading '_zod')`. The SDK's `toJsonSchemaCompat()` tries to detect the Zod version by accessing `schema._zod`, but the one-arg `z.record()` in Zod 4 produces an object the SDK can't introspect.

2. **stderr vs stdout for errors**: The pencil interactive REPL writes `[ERROR]` and error stack traces to stderr, not stdout. The adapter's `waitForPrompt()` only buffers stdout, so error responses came back as empty strings.

3. **Binary detection without execution**: `detect_headless_cli()` tried to run `pencil interactive --help` to verify the binary, but the pencil CLI requires Node >= 22.9.0 and the system Node was 21.x. The binary can't even be executed to check its capabilities.

## Solution

1. **Zod 4 fix**: Use the two-arg form `z.record(z.string(), z.unknown())` instead of `z.record(z.unknown())`. The SDK handles the explicit key-type form correctly.

2. **Stderr capture**: Added per-command `stderrBuffer` to `PencilProcess`. In `sendCommand()`, if stdout response is empty but stderr has content, return the stderr content. This preserves error messages for MCP error responses.

3. **Symlink detection**: Instead of executing the binary, `detect_headless_cli()` checks `readlink -f` of `~/.local/node_modules/.bin/pencil` and verifies the symlink target contains `@pencil.dev/cli`. No execution needed. The actual Node version check happens later in `try_headless_cli_tier()` via `find_node22()` which probes system node, nvm, and fnm.

## Key Insight

When bridging two systems via child process stdio:

- **Never assume error output goes to stdout** — check both streams. The adapter pattern of "buffer stdout for response, pipe stderr to parent stderr" loses error content that the REPL puts on stderr.
- **Never detect capabilities by executing a binary** when version requirements may prevent execution — use filesystem inspection (symlink targets, file existence) for detection, and defer execution tests to after version validation.
- **Always test Zod schemas individually** when using Zod 4 with the MCP SDK — the compatibility layer has edge cases with certain Zod 4 type constructors.

## Session Errors

1. **Security hook false positive on spawn**: The `security_reminder_hook.py` flagged `import { spawn } from "node:child_process"` in a standalone MCP adapter file, recommending `execFileNoThrow` from the main codebase. This is a false positive — the adapter is an independent Node.js server, not part of the TypeScript codebase. **Prevention:** The hook could check if the file is inside `plugins/soleur/skills/*/scripts/` and skip it for standalone script files.

2. **Smoke test path doubling**: After `cd` + `npm install` in the scripts dir, running `node plugins/.../pencil-mcp-adapter.mjs` doubled the path because CWD had changed. **Prevention:** Always use absolute paths for node scripts in tests.

3. **PENCIL_CLI_KEY not exported**: Used `PENCIL_CLI_KEY=$(doppler ...) && node test.mjs` — shell variable assignment without `export` doesn't propagate to child processes. **Prevention:** Always use `export VAR=$(...)` when the value must be available to child processes.

4. **Old project-scoped pencil entry**: `.claude.json` had a stale project-scoped `pencil` MCP entry that overrode the new adapter registration. Had to manually edit JSON. **Prevention:** Always check `claude mcp list` output after registration and verify the correct entry is active.

5. **.mcp.json with plaintext API key**: `claude mcp add -s project -e KEY=val` creates `.mcp.json` in the repo with the key in plaintext. **Prevention:** Added `.mcp.json` to `.gitignore`. Never use `-e` with secrets for project-scoped MCP registrations — use shell profile exports instead.

## Cross-References

- [Pencil headless CLI interactive mode is not MCP](../2026-03-24-pencil-headless-cli-interactive-mode-not-mcp.md)
- [Pencil Desktop standalone MCP three-tier detection](../2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md)
- [Pencil batch design text node gotchas](../2026-03-10-pencil-batch-design-text-node-gotchas.md)
- [process.env spread leaks secrets to subprocess (CWE-526)](../2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md)

## Tags

category: integration-issues
module: pencil-mcp-adapter
