---
title: "feat: Integrate Pencil headless CLI as Tier 0 MCP source"
type: feat
date: 2026-03-24
---

# feat: Integrate Pencil headless CLI as Tier 0 MCP source

## Overview

Add the Pencil headless CLI as the highest-priority MCP source (Tier 0) in the pencil-setup detection cascade. This involves writing an MCP adapter that bridges `pencil interactive` mode's custom REPL to the MCP protocol, updating detection scripts, and updating the setup skill registration flow.

**Issue:** #1087
**Brainstorm:** `knowledge-base/project/brainstorms/2026-03-24-pencil-headless-cli-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-pencil-headless-cli/spec.md`

## Problem Statement / Motivation

The current Pencil integration requires either Pencil Desktop running or an IDE with the Pencil extension. Phase 1 of the roadmap requires designing many new screens, and the Desktop/IDE dependency creates friction for agent-driven design sessions. The pencil.dev founder released a headless CLI that bundles its own Skia renderer and exposes the same design tools — but through a custom REPL format, not MCP protocol.

## Proposed Solution

### Architecture

```text
Claude Code ←(MCP stdio)→ pencil-mcp-adapter.js ←(stdin/stdout REPL)→ pencil interactive --out file.pen
```

The adapter is a thin Node.js MCP server that:

1. Receives MCP tool calls from Claude Code via stdio
2. Translates them to `pencil interactive` REPL commands (`tool_name({ args })`)
3. Sends commands to the pencil child process stdin
4. Parses responses from stdout
5. Returns results as MCP tool responses

### Detection Priority (4-tier cascade)

| Tier | Source | Detection | Needs GUI? |
|------|--------|-----------|-----------|
| 0 | Headless CLI (npm) | `npm list` or `~/.local/node_modules/.bin/pencil` | No |
| 1 | Desktop CLI (PATH) | `pencil --version` + `mcp-server` subcommand | Yes (Desktop) |
| 2 | Desktop binary | Platform-specific MCP binary path | Yes (Desktop) |
| 3 | IDE extension | Cursor/VS Code extension binary | Yes (IDE) |

## Technical Considerations

### MCP Adapter Implementation

**File:** `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`

The adapter uses `@modelcontextprotocol/sdk` with `StdioServerTransport`:

```javascript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { spawn } from "node:child_process";
```

**Key design decisions:**

- **ESM module** (`.mjs`) — the MCP SDK is ESM-only
- **Zero external deps beyond MCP SDK + zod** — keeps the adapter minimal
- **Child process lifecycle** — spawn on first tool call, restart on crash, graceful shutdown on exit
- **Response parsing** — parse the REPL output to extract node IDs, errors, and results
- **save() injection** — the adapter calls `save()` after mutating operations to ensure disk persistence (resolves constitution Ctrl+S constraint for headless mode)

**Tool registration:** Register all 14 tools from the `pencil interactive --help` output:

1. `batch_design` — mutating, call `save()` after
2. `batch_get` — read-only
3. `export_nodes` — read-only, returns file paths
4. `find_empty_space_on_canvas` — read-only
5. `get_editor_state` — read-only, call on startup
6. `get_guidelines` — read-only (API call)
7. `get_screenshot` — read-only, returns image data
8. `get_style_guide` — read-only (API call)
9. `get_style_guide_tags` — read-only (API call)
10. `get_variables` — read-only
11. `replace_all_matching_properties` — mutating, call `save()` after
12. `search_all_unique_properties` — read-only
13. `set_variables` — mutating, call `save()` after
14. `snapshot_layout` — read-only

**Additionally handle:**

- `open_document` — restart `pencil interactive` with new `--in`/`--out` file paths
- `save` — explicit save (maps to `save()` REPL command)

### Child Process Stdio Configuration (CRITICAL)

The adapter's own stdio is consumed by MCP transport (StdioServerTransport reads from `process.stdin`, writes to `process.stdout`). The `pencil interactive` child process MUST use separate pipes:

```javascript
spawn(pencilBinary, ['interactive', '--out', filePath], {
  stdio: ['pipe', 'pipe', 'pipe'],  // CRITICAL: never inherit
  env: buildPencilEnv(),  // explicit allowlist, never { ...process.env }
});
```

If child stdout inherits from the adapter's stdout, REPL output corrupts the MCP JSON-RPC stream. Child stderr should be logged to the adapter's stderr (which is safe — MCP only uses stdin/stdout).

### REPL Protocol Parsing

The interactive shell has a specific response format:

```text
pencil > [command response here - may be multiline]
pencil >
```

The adapter needs to:

1. **Startup buffering** — consume the welcome banner and initial `pencil >` prompt before sending any commands
2. **Command sender** — write a command line to child stdin, terminated by `\n`
3. **Response buffering** — buffer child stdout until the next `\npencil >` prompt appears (anchored with newline prefix + trailing space to avoid false matches inside response content)
4. **ANSI stripping** — strip escape sequences BEFORE prompt detection (order matters)
5. **Error detection** — lines prefixed with `[ERROR]` or `[31mError:` indicate tool failures
6. **Command queue** — MCP clients may send concurrent tool calls, but the REPL is serial. The adapter must queue commands and process them sequentially.
7. **Per-command timeout** — if no prompt appears within 30 seconds, return an MCP error and optionally restart the pencil process
8. **Node ID extraction** — parse `batch_design` responses to extract generated node IDs (e.g., "Inserted node 4jQbj") and maintain an in-memory binding-to-ID map for cross-call reference. CRITICAL: binding names are ephemeral within a single `batch_design` call.

### Node Version Management

The CLI requires Node >= 22.9.0. The adapter script should:

1. Check `process.version` on startup
2. If too old, print an error and exit with code 1
3. The `check_deps.sh` script handles finding the right Node binary (nvm/fnm aware)

### Auth Flow

- `PENCIL_CLI_KEY` env var is passed through to the child process
- `check_deps.sh` runs `pencil status` to verify auth before selecting Tier 0
- If auth fails, Tier 0 is skipped and cascade continues to Tier 1

### Confidentiality Constraint

The npm package name must not appear in public-facing code, issues, or docs until the founder announces. Use:

- Variable/env-based references in check_deps.sh
- Generic "headless CLI" or "npm CLI" in SKILL.md and agent docs
- The package name only appears in the actual npm install command within scripts

## Acceptance Criteria

- [ ] `check_deps.sh` detects and prioritizes headless CLI as Tier 0
- [ ] `check_deps.sh` auto-installs the headless CLI when missing and `--auto` is set
- [ ] `check_deps.sh` verifies Node >= 22.9.0 and probes nvm/fnm if system Node is too old
- [ ] `check_deps.sh` verifies auth via `pencil status` before selecting Tier 0
- [ ] MCP adapter translates batch_design, batch_get, get_screenshot, and save correctly
- [ ] MCP adapter auto-calls save() after mutating operations
- [ ] MCP adapter handles pencil process crash and restarts gracefully
- [ ] `pencil-setup` SKILL.md registers the adapter correctly for headless tier
- [ ] Existing Desktop/IDE tiers work unchanged when headless CLI unavailable
- [ ] Auth failure produces clear user guidance
- [ ] No npm package name in public-facing artifacts (issues, PR body, docs)

## Test Scenarios

- Given headless CLI installed and auth valid, when `check_deps.sh` runs, then Tier 0 is selected with `PREFERRED_MODE=headless_cli`
- Given headless CLI installed but auth invalid, when `check_deps.sh` runs, then Tier 0 is skipped and cascade continues to Tier 1
- Given headless CLI not installed and `--auto` flag, when `check_deps.sh` runs, then the package is installed to `~/.local/node_modules`
- Given Node < 22.9.0 and no nvm/fnm, when `check_deps.sh` runs, then Tier 0 is skipped with informative message
- Given MCP adapter running, when `batch_design` tool is called, then operations execute and `save()` is called automatically
- Given MCP adapter running, when pencil process crashes, then adapter restarts it on next tool call
- Given MCP adapter running, when `open_document` is called with new file, then pencil process restarts with new file

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| REPL protocol changes across versions | Version-pin to CLI 0.2.x, test in CI |
| Node version requirement (>=22.9.0) | nvm/fnm detection, clear skip message |
| Auth token expiration | `pencil status` check at detection time |
| 58MB package size slows install | One-time install to `~/.local`, not per-invocation |
| REPL response parsing fragility | Strip ANSI codes, use prompt detection as delimiter |
| Concurrent sessions | Test in isolation; document as open question |

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO)

**Status:** reviewed
**Assessment:** MCP adapter pattern is architecturally sound. Key risks: REPL protocol not formally specified (parsing could be fragile), Node version gate adds dependency. Recommend version-pinning and integration tests.

### Product (CPO)

**Status:** reviewed
**Assessment:** Unblocks Phase 1 screen design. Tiered fallback ensures no disruption. Auth setup is a friction point — setup skill should guide clearly.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** CONFIDENTIAL — npm package URL must not be shared publicly. No public marketing content until founder announces. Opportunity: co-marketing when public.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — this is infrastructure/tooling, no user-facing UI changes.

## Implementation Phases

### Phase 1: MCP Adapter Core (`pencil-mcp-adapter.mjs`) [Updated 2026-03-24]

**Files to create:**

- `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` — the MCP server
- `plugins/soleur/skills/pencil-setup/scripts/package.json` — minimal deps (MCP SDK + zod)

#### 1a. package.json

```json
{
  "name": "pencil-mcp-adapter",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.27.1",
    "zod": "^4.0.0"
  }
}
```

**Note:** The SDK is `@modelcontextprotocol/sdk` v1 (v2 `@modelcontextprotocol/server` is not yet published on npm as of 2026-03-24). Import paths use the v1 deep-import pattern:

```javascript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
```

Zod 4 is used (`zod` ^4.0.0, SDK supports `^3.25 || ^4.0`). Import as:

```javascript
import { z } from "zod";
```

#### 1b. Adapter Module Structure

The adapter file (`pencil-mcp-adapter.mjs`) should be organized into these sections in order:

1. **Imports & constants** — MCP SDK, zod, node:child_process, node:path, node:fs
2. **Node version gate** — check `process.version` >= 22.9.0, exit(1) if too old
3. **Env allowlist builder** — `buildPencilEnv()` returns `{ HOME, PATH, NODE_ENV, LANG, TERM, USER, SHELL, TMPDIR, PENCIL_CLI_KEY }` from `process.env`
4. **ANSI strip utility** — regex to remove escape sequences: `/\x1b\[[0-9;]*[a-zA-Z]/g`
5. **REPL response parser** — `parseResponse(rawOutput)` strips ANSI, detects errors, extracts content
6. **Node ID extractor** — `extractNodeIds(batchDesignResponse)` parses "Inserted node `<id>`" patterns
7. **Child process manager class** — `PencilProcess` with spawn/kill/restart/sendCommand/waitForPrompt
8. **Command queue** — serializes concurrent MCP tool calls through the single-threaded REPL
9. **Tool registration** — all 14 tools + open_document + save
10. **Server startup** — create McpServer, connect StdioServerTransport

#### 1c. PencilProcess Class

```javascript
class PencilProcess {
  constructor() {
    this.child = null;
    this.ready = false;        // true after initial prompt consumed
    this.buffer = "";          // accumulates child stdout
    this.outputFile = null;    // current --out path
    this.inputFile = null;     // current --in path
    this.nodeIdMap = new Map(); // binding -> actual node ID
  }

  async spawn(outFile, inFile = null) { /* ... */ }
  async kill() { /* ... */ }
  async restart(outFile, inFile = null) { /* ... */ }
  async sendCommand(cmd) { /* returns parsed response string */ }
  async waitForPrompt(timeoutMs = 30000) { /* ... */ }
}
```

**spawn() contract:**

- Resolves the pencil binary via `process.env.PENCIL_BINARY || findPencilBinary()` where `findPencilBinary()` checks: (1) `~/.local/node_modules/.bin/pencil`, (2) `which pencil`
- Args: `['interactive', '--out', outFile]` plus `['--in', inFile]` if provided
- stdio: `['pipe', 'pipe', 'pipe']` — CRITICAL: never inherit
- env: `buildPencilEnv()` — explicit allowlist, never spread process.env
- Pipes child.stderr to process.stderr (safe — MCP only uses stdin/stdout)
- After spawn, calls `waitForPrompt()` to consume welcome banner + initial `pencil >` prompt
- Sets `this.ready = true` after initial prompt consumed

**sendCommand() contract:**

- Writes `cmd + '\n'` to child.stdin
- Calls `waitForPrompt(30000)` to collect response
- Returns the stripped/parsed response text between the command echo and the next prompt
- On timeout: throws error (caller decides whether to restart)

**waitForPrompt() contract:**

- Listens to child.stdout `data` events, appending to `this.buffer`
- After each chunk: strip ANSI from buffer, check for `\npencil >` prompt (or `^pencil >` at buffer start)
- When prompt found: extract everything before the prompt as response, clear buffer, resolve
- On timeout: reject with descriptive error

#### 1d. Command Queue

```javascript
class CommandQueue {
  constructor(pencilProcess) {
    this.process = pencilProcess;
    this.queue = [];
    this.running = false;
  }

  async enqueue(command) {
    return new Promise((resolve, reject) => {
      this.queue.push({ command, resolve, reject });
      if (!this.running) this._drain();
    });
  }

  async _drain() {
    this.running = true;
    while (this.queue.length > 0) {
      const { command, resolve, reject } = this.queue.shift();
      try {
        const result = await this.process.sendCommand(command);
        resolve(result);
      } catch (err) {
        reject(err);
      }
    }
    this.running = false;
  }
}
```

#### 1e. Tool Registration (All 14 + 2 Meta Tools)

Each tool is registered via `server.tool(name, zodSchema, handler)`. The Zod schemas are derived from the `pencil interactive --help` output:

**Read-only tools:**

| Tool | Zod Schema | Notes |
|------|-----------|-------|
| `batch_get` | `{ patterns?: z.array(z.record(z.unknown())).optional(), nodeIds?: z.array(z.string()).optional(), readDepth?: z.number().optional() }` | Returns node data |
| `get_editor_state` | `{ include_schema: z.boolean() }` | Call on startup to get document state |
| `get_guidelines` | `{ topic: z.enum(["code","table","tailwind","landing-page","design-system","slides","mobile-app","web-app"]) }` | API call |
| `get_screenshot` | `{ nodeId: z.string() }` | Returns image — see 1f |
| `get_style_guide` | `{ name?: z.string().optional(), tags?: z.array(z.string()).optional() }` | API call |
| `get_style_guide_tags` | `{}` (no params) | API call |
| `get_variables` | `{}` (no params) | Returns theme/variable data |
| `find_empty_space_on_canvas` | `{ direction: z.enum(["top","right","bottom","left"]), height: z.number(), width: z.number(), padding: z.number(), nodeId?: z.string().optional() }` | |
| `search_all_unique_properties` | `{ parents: z.array(z.string()), properties: z.array(z.string()) }` | |
| `snapshot_layout` | `{ parentId?: z.string().optional(), maxDepth?: z.number().optional(), problemsOnly?: z.boolean().optional() }` | |
| `export_nodes` | `{ nodeIds: z.array(z.string()), outputDir: z.string(), format?: z.enum(["png","jpeg","webp","pdf"]).optional(), scale?: z.number().optional(), quality?: z.number().optional() }` | Returns file paths |

**Mutating tools (auto-save after):**

| Tool | Zod Schema | Notes |
|------|-----------|-------|
| `batch_design` | `{ operations: z.string() }` | The `operations` string is the REPL operation list format. After response, call `save()`. Parse node IDs from response. |
| `replace_all_matching_properties` | `{ parents: z.array(z.string()), properties: z.record(z.unknown()) }` | After response, call `save()` |
| `set_variables` | `{ variables: z.record(z.unknown()), replace?: z.boolean().optional() }` | After response, call `save()` |

**Meta tools (adapter-level):**

| Tool | Zod Schema | Notes |
|------|-----------|-------|
| `open_document` | `{ filePath: z.string(), inputPath?: z.string().optional() }` | Calls `pencilProcess.restart(filePath, inputPath)` |
| `save` | `{}` (no params) | Sends `save()` to REPL |

**Handler pattern for read-only tools:**

```javascript
server.tool("batch_get", { /* zod schema */ }, async (params) => {
  const cmd = `batch_get(${JSON.stringify(params)})`;
  const response = await commandQueue.enqueue(cmd);
  return { content: [{ type: "text", text: response }] };
});
```

**Handler pattern for mutating tools:**

```javascript
server.tool("batch_design", { operations: z.string() }, async ({ operations }) => {
  const cmd = `batch_design({ operations: ${JSON.stringify(operations)} })`;
  const response = await commandQueue.enqueue(cmd);
  // Extract node IDs from response
  const nodeIds = extractNodeIds(response);
  for (const [binding, id] of nodeIds) {
    pencilProcess.nodeIdMap.set(binding, id);
  }
  // Auto-save
  await commandQueue.enqueue("save()");
  return { content: [{ type: "text", text: response }] };
});
```

**Handler pattern for open_document:**

```javascript
server.tool("open_document", { filePath: z.string(), inputPath: z.string().optional() },
  async ({ filePath, inputPath }) => {
    // Save current document first if process is running
    if (pencilProcess.ready) {
      await commandQueue.enqueue("save()");
    }
    await pencilProcess.restart(filePath, inputPath);
    return { content: [{ type: "text", text: `Opened ${filePath}` }] };
  }
);
```

#### 1f. get_screenshot Image Handling

The `get_screenshot` response from `pencil interactive` returns base64-encoded image data. The adapter must detect this and return it as MCP image content:

```javascript
server.tool("get_screenshot", { nodeId: z.string() }, async ({ nodeId }) => {
  const cmd = `get_screenshot({ nodeId: ${JSON.stringify(nodeId)} })`;
  const response = await commandQueue.enqueue(cmd);
  // The REPL response includes base64 image data
  // Parse and return as image content type
  const base64Match = response.match(/data:image\/(png|jpeg);base64,([A-Za-z0-9+/=]+)/);
  if (base64Match) {
    return {
      content: [{
        type: "image",
        data: base64Match[2],
        mimeType: `image/${base64Match[1]}`
      }]
    };
  }
  // Fallback: return as text if format is unexpected
  return { content: [{ type: "text", text: response }] };
});
```

**IMPORTANT:** The exact response format for `get_screenshot` needs verification during implementation. The REPL may return the image data differently (JSON object with base64 field, raw base64, etc.). Test with a real `get_screenshot` call and adjust parsing accordingly.

#### 1g. Error Handling & Process Recovery

```javascript
// In PencilProcess class
child.on('exit', (code, signal) => {
  this.ready = false;
  this.child = null;
  // Log to stderr (safe for MCP)
  process.stderr.write(`[pencil-adapter] pencil process exited: code=${code} signal=${signal}\n`);
});

// In command queue — wrap sendCommand with crash detection
async enqueue(command) {
  if (!this.process.ready && !this.process.child) {
    // Process died — restart on the same file
    if (this.process.outputFile) {
      await this.process.spawn(this.process.outputFile, this.process.inputFile);
    } else {
      throw new Error("Pencil process not running and no file to restart with");
    }
  }
  // ... normal queue logic
}
```

#### 1h. Lazy Spawn Strategy

The pencil process is NOT spawned at adapter startup. Instead:

- Adapter starts, creates McpServer, connects StdioServerTransport
- On first `open_document` call: spawn pencil with the given file
- On first tool call that isn't `open_document`: spawn with a temp file (`/tmp/pencil-adapter-<pid>.pen`)
- Rationale: the adapter must be registered before Claude Code starts. The pencil process should only run when actually needed.

#### 1i. REPL Command Formatting

The REPL expects commands in the format `tool_name({ key: value })` with JavaScript object syntax. The adapter must convert JSON-style params to this format:

```javascript
function formatReplCommand(toolName, params) {
  if (!params || Object.keys(params).length === 0) {
    return `${toolName}()`;
  }
  // For batch_design, operations is a string that goes directly into the call
  if (toolName === "batch_design") {
    return `batch_design({ operations: ${JSON.stringify(params.operations)} })`;
  }
  // For all other tools, serialize params as JS object literal
  // JSON.stringify produces valid JS object literal for simple values
  const paramStr = JSON.stringify(params);
  // Convert outer braces — JSON objects are valid JS object literals
  return `${toolName}(${paramStr})`;
}
```

**Note:** JSON object syntax `{"key": "value"}` is valid JavaScript, so `JSON.stringify` output works as REPL input. The one exception is `batch_design.operations` which is already a string of REPL operation syntax and must be passed through as-is.

### Phase 2: Detection Script Updates (`check_deps.sh`)

**File to modify:** `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`

**Changes:**

1. Add `try_headless_cli_tier()` function above `try_cli_tier()`
2. Detection: check `~/.local/node_modules/.bin/pencil` or `npm list -g` for the package
3. Node version check: parse `node --version` for >= 22.9.0, probe nvm/fnm if too old
4. Auth check: run `pencil status` with `PENCIL_CLI_KEY` from env
5. Auto-install: `npm install --prefix ~/.local` when `--auto` and not found
6. Set `PREFERRED_MODE=headless_cli`, `PREFERRED_BINARY=<path to adapter>`, `PREFERRED_APP=""`
7. Update cascade: `try_headless_cli_tier || try_cli_tier || try_desktop_tier || try_ide_tier`

### Phase 3: Registration, Docs & Verification

**Setup Skill Updates** (`plugins/soleur/skills/pencil-setup/SKILL.md`):

1. Add headless CLI mode to Phase 0 output variables documentation
2. Add `### Headless CLI mode (PREFERRED_MODE=headless_cli)` registration section:
   `claude mcp add -s user pencil -- node <path-to-adapter>/pencil-mcp-adapter.mjs`
3. Update Step 3 verify message for headless mode
4. Update Sharp Edges (already partially done in brainstorm session)
5. Add auth guidance: if `pencil status` shows unauthenticated, guide through `pencil login` or `PENCIL_CLI_KEY`

**Constitution & Agent Updates** (same commit):

1. `knowledge-base/project/constitution.md` line ~101 — add headless mode addendum:
   - No visible editor tab requirement
   - `save()` works programmatically — no Ctrl+S needed (reword "no programmatic save exists" to scope it to IDE/Desktop modes)
   - Read-before-write still applies
   - Auth required (PENCIL_CLI_KEY or pencil login)
2. `plugins/soleur/agents/product/design/ux-design-lead.md` line ~11 — update prerequisites to mention headless option first

**Integration Verification** (before PR):

1. Register the adapter: `claude mcp add -s user pencil -- node pencil-mcp-adapter.mjs`
2. Restart Claude Code, verify `mcp__pencil__*` tools appear
3. Test `get_editor_state` returns document state
4. Test `batch_design` creates nodes, node IDs tracked, auto-saves
5. Test `get_screenshot` with tracked node ID
6. Test fallback: unregister adapter, verify Desktop/IDE tiers still work

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-24-pencil-headless-cli-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pencil-headless-cli/spec.md`
- Learning: `knowledge-base/project/learnings/2026-03-24-pencil-headless-cli-interactive-mode-not-mcp.md`
- Three-tier cascade learning: `knowledge-base/project/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- MCP Tool Design: `plugins/soleur/skills/agent-native-architecture/references/mcp-tool-design.md`
- MCP SDK: `@modelcontextprotocol/sdk@1.27.1` (v1) with `McpServer` + `StdioServerTransport` (v1 deep-import paths)
- Zod: `zod@4.x` (SDK peer dep supports `^3.25 || ^4.0`)
- Pencil CLI: v0.2.3, Node >= 22.9.0 (verified on Node 22.22.0), `pencil interactive --help` for full tool API
- Context7 MCP SDK docs: tool registration via `server.tool(name, zodSchema, handler)` pattern confirmed for v1
