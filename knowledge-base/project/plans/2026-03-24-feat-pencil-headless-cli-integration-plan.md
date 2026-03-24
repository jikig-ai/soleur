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

### REPL Protocol Parsing

The interactive shell has a specific response format:

```text
pencil > [command response here - may be multiline]
pencil >
```

The adapter needs to:

1. Send a command line to stdin
2. Buffer stdout until the next `pencil >` prompt appears
3. Strip ANSI codes from output
4. Parse JSON-like responses or structured text
5. Handle `[ERROR]` prefixed lines as tool errors

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

### Phase 1: MCP Adapter Core (`pencil-mcp-adapter.mjs`)

**Files to create:**

- `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` — the MCP server
- `plugins/soleur/skills/pencil-setup/scripts/package.json` — minimal deps (MCP SDK + zod)

**Implementation:**

1. Set up McpServer with StdioServerTransport
2. Implement child process manager (spawn/restart/shutdown `pencil interactive`)
3. Implement REPL command sender (write to child stdin, buffer until prompt)
4. Implement response parser (strip ANSI, detect errors, extract content)
5. Register all 14 tools with Zod schemas matching pencil interactive's API
6. Add auto-save after mutating operations (batch_design, replace_all_matching_properties, set_variables)
7. Add `open_document` handler that restarts pencil with new file
8. Add Node version check on startup

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

### Phase 3: Setup Skill Updates (`SKILL.md`)

**File to modify:** `plugins/soleur/skills/pencil-setup/SKILL.md`

**Changes:**

1. Add headless CLI mode to Phase 0 output variables documentation
2. Add `### Headless CLI mode (PREFERRED_MODE=headless_cli)` registration section:
   `claude mcp add -s user pencil -- node <path-to-adapter>/pencil-mcp-adapter.mjs`
3. Update Step 3 verify message for headless mode
4. Update Sharp Edges (already partially done in brainstorm session)
5. Add auth guidance: if `pencil status` shows unauthenticated, guide through `pencil login` or `PENCIL_CLI_KEY`

### Phase 4: Constitution & Agent Updates

**Files to modify:**

1. `knowledge-base/project/constitution.md` line ~101 — add headless mode addendum:
   - No visible editor tab requirement
   - `save()` works programmatically (no Ctrl+S needed)
   - Read-before-write still applies
   - Auth required (PENCIL_CLI_KEY or pencil login)

2. `plugins/soleur/agents/product/design/ux-design-lead.md` line ~11 — update prerequisites to mention headless option:
   - If Pencil MCP tools unavailable, suggest headless CLI as first option

### Phase 5: Integration Verification

1. Register the adapter: `claude mcp add -s user pencil -- node pencil-mcp-adapter.mjs`
2. Restart Claude Code
3. Test `get_editor_state` via ux-design-lead
4. Test `batch_design` + `get_screenshot` end-to-end
5. Test `save()` auto-call after mutation
6. Test fallback: unregister adapter, verify Desktop/IDE tiers still work

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-24-pencil-headless-cli-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pencil-headless-cli/spec.md`
- Learning: `knowledge-base/project/learnings/2026-03-24-pencil-headless-cli-interactive-mode-not-mcp.md`
- Three-tier cascade learning: `knowledge-base/project/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- MCP SDK: `@modelcontextprotocol/sdk` with `McpServer` + `StdioServerTransport`
- Pencil CLI: v0.2.3, Node >= 22.9.0, `pencil interactive --help` for full tool API
