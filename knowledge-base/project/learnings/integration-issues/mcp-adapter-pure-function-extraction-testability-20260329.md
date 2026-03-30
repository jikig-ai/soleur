---
module: Pencil MCP Adapter
date: 2026-03-29
problem_type: integration_issue
component: tooling
symptoms:
  - "Cannot find module '@modelcontextprotocol/sdk/server/mcp.js' when importing adapter in tests"
  - "MCP adapter functions untestable due to transitive SDK dependency chain"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: medium
tags: [mcp-adapter, testability, pure-function-extraction, pencil]
synced_to: []
---

# Troubleshooting: MCP Adapter Pure Functions Untestable via Direct Import

## Problem

When writing unit tests for `enrichErrorMessage()` in `pencil-mcp-adapter.mjs`, importing the adapter file directly failed because Bun could not resolve `@modelcontextprotocol/sdk/server/mcp.js` -- the MCP SDK is installed in the adapter's own `node_modules` (under `skills/pencil-setup/scripts/`), not at the plugin test level.

## Environment

- Module: Pencil MCP Adapter
- Affected Component: `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
- Date: 2026-03-29

## Symptoms

- `bun test` fails with: `Cannot find module '@modelcontextprotocol/sdk/server/mcp.js'`
- The function under test (`enrichErrorMessage`) has zero dependencies but is trapped inside a module with heavy imports

## What Didn't Work

**Attempted Solution 1:** Direct import of `pencil-mcp-adapter.mjs` from test file

- **Why it failed:** The adapter's top-level imports (`McpServer`, `StdioServerTransport`, `z`) execute immediately on import, and the MCP SDK is not available in the test runner's resolution scope

## Session Errors

**Wrong script path for setup-ralph-loop.sh**

- **Recovery:** Corrected from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** Verify script paths exist before executing; the one-shot skill base directory is not the scripts directory

## Solution

Extract pure functions from MCP adapter modules into standalone files with zero dependencies.

**Code changes:**

```javascript
// Before: enrichErrorMessage() was a local function inside pencil-mcp-adapter.mjs
// pencil-mcp-adapter.mjs (590+ lines, heavy imports)
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
// ... many other imports ...
function enrichErrorMessage(text) { /* ... */ }

// After: extracted to pencil-error-enrichment.mjs (zero imports)
// pencil-error-enrichment.mjs
export function enrichErrorMessage(text) { /* ... */ }

// pencil-mcp-adapter.mjs now imports it
import { enrichErrorMessage } from "./pencil-error-enrichment.mjs";
```

## Why This Works

1. **Root cause:** MCP adapter files have top-level imports that execute on module load. Test runners resolve modules from their own `node_modules` scope, not the adapter's scope.
2. **Solution:** Pure functions (string in, string out) have no dependency on the MCP SDK. Extracting them into standalone modules breaks the transitive dependency chain.
3. **The pattern generalizes:** Any MCP adapter function that is pure (no references to `server`, `commandQueue`, `process`, etc.) can be extracted for testability.

## Prevention

- When adding testable logic to MCP adapters, place pure functions in separate modules from the start
- MCP adapter files should only contain wiring code (tool registration, process management); business logic belongs in importable modules
- Test files should never need to resolve MCP SDK dependencies

## Related Issues

- See also: [pencil-adapter-path-node-version-mismatch-20260325.md](./pencil-adapter-path-node-version-mismatch-20260325.md)
- See also: [pencil-mcp-adapter-zod4-stderr-detection-20260324.md](./pencil-mcp-adapter-zod4-stderr-detection-20260324.md)
- GitHub issue: #1117
