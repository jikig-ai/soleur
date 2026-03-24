# Tasks: Pencil Headless CLI Integration

**Plan:** `knowledge-base/project/plans/2026-03-24-feat-pencil-headless-cli-integration-plan.md`
**Issue:** #1087

## Phase 1: MCP Adapter Core [Updated 2026-03-24]

- [x] 1.1 Create `plugins/soleur/skills/pencil-setup/scripts/package.json` — `@modelcontextprotocol/sdk@^1.27.1` + `zod@^4.0.0`, `"type": "module"`, `"private": true`
- [x] 1.2 Create `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
  - [x] 1.2.1 Imports: `McpServer` from `@modelcontextprotocol/sdk/server/mcp.js`, `StdioServerTransport` from `@modelcontextprotocol/sdk/server/stdio.js`, `z` from `zod`, `spawn` from `node:child_process`
  - [x] 1.2.2 Node version gate: `process.version` >= 22.9.0, exit(1) with message if too old
  - [x] 1.2.3 `buildPencilEnv()` — allowlist: HOME, PATH, NODE_ENV, LANG, TERM, USER, SHELL, TMPDIR, PENCIL_CLI_KEY
  - [x] 1.2.4 `stripAnsi(str)` — regex `/\x1b\[[0-9;]*[a-zA-Z]/g`
  - [x] 1.2.5 `PencilProcess` class: spawn/kill/restart/sendCommand/waitForPrompt
    - [x] 1.2.5a `spawn(outFile, inFile?)` — resolves binary, args=['interactive','--out',outFile], stdio=['pipe','pipe','pipe'], env=buildPencilEnv(), pipes child.stderr to process.stderr
    - [x] 1.2.5b `waitForPrompt(timeoutMs=30000)` — buffer stdout, strip ANSI, detect `\npencil >` prompt or `^pencil >` at start, timeout rejects
    - [x] 1.2.5c `sendCommand(cmd)` — write cmd+'\n' to child.stdin, waitForPrompt, return parsed response
    - [x] 1.2.5d Startup buffer: consume welcome banner + initial prompt in spawn()
    - [x] 1.2.5e Crash detection: child 'exit' event sets ready=false, logs to stderr
    - [x] 1.2.5f `nodeIdMap` — Map<string, string> for binding-to-ID tracking
  - [x] 1.2.6 `CommandQueue` class: enqueue(cmd) serializes concurrent calls, auto-restarts on crash
  - [x] 1.2.7 `formatReplCommand(toolName, params)` — converts to `tool_name({...})` format; batch_design.operations passed as-is string
  - [x] 1.2.8 `extractNodeIds(response)` — parse "Inserted node `<id>`" patterns from batch_design responses
  - [x] 1.2.9 `parseResponse(raw)` — strip ANSI, detect `[ERROR]`/`[31mError:` lines, return { text, isError }
  - [x] 1.2.10 Register 11 read-only tools with Zod schemas (batch_get, get_editor_state, get_guidelines, get_screenshot, get_style_guide, get_style_guide_tags, get_variables, find_empty_space_on_canvas, search_all_unique_properties, snapshot_layout, export_nodes)
  - [x] 1.2.11 get_screenshot handler: detect base64 image data in response, return as MCP `{type:"image"}` content; fallback to text
  - [x] 1.2.12 Register 3 mutating tools with auto-save (batch_design, replace_all_matching_properties, set_variables) — each sends `save()` after successful execution
  - [x] 1.2.13 batch_design handler: extract node IDs after execution, update nodeIdMap
  - [x] 1.2.14 Register `open_document` meta-tool: save current doc, restart pencil with new --in/--out file
  - [x] 1.2.15 Register `save` meta-tool: sends `save()` to REPL
  - [x] 1.2.16 Lazy spawn: pencil process NOT spawned at startup — spawned on first open_document or first tool call (with temp file)
  - [x] 1.2.17 Server startup: create McpServer({name:"pencil-mcp-adapter",version:"0.0.1"}), connect StdioServerTransport
- [x] 1.3 Add `node_modules/` to `.gitignore` for `plugins/soleur/skills/pencil-setup/scripts/` (already covered by root .gitignore)
- [x] 1.4 Install deps: `cd plugins/soleur/skills/pencil-setup/scripts && npm install`
- [x] 1.5 Smoke test: `node plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` starts without error (ctrl+c to exit)

## Phase 2: Detection + Registration

- [x] 2.1 Add `detect_headless_cli()` function to `check_deps.sh`
  - [x] 2.1.1 Check `~/.local/node_modules/.bin/pencil` exists (symlink target check, no execution)
  - [x] 2.1.2 Verify it's the headless CLI (check symlink target contains @pencil.dev/cli)
  - [x] 2.1.3 Node version gate: `find_node22()` probes system, nvm, fnm
- [x] 2.2 Add `try_headless_cli_tier()` function
  - [x] 2.2.1 Call `detect_headless_cli()`
  - [x] 2.2.2 Auth check: `PENCIL_CLI_KEY=... pencil status` exits 0 (using Node 22+)
  - [x] 2.2.3 Auto-install if `--auto` and not found: `attempt_headless_install()`
  - [x] 2.2.4 Set output vars: `PREFERRED_MODE=headless_cli`, `PREFERRED_BINARY=<adapter-path>`, `PREFERRED_APP=""`, `PREFERRED_NODE=<node-bin>`
- [x] 2.3 Update `detect_pencil_cli()` with negative guard: symlink target check prevents headless CLI matching Tier 1
- [x] 2.4 Update cascade: headless CLI tried first, then cli, desktop, ide
- [x] 2.5 Update `SKILL.md` Phase 0 to document `headless_cli` mode output
- [x] 2.6 Add `### Headless CLI mode` registration section to Step 2 with env var config
- [x] 2.7 Update Step 1 (check registered) and Step 3 (verify) for headless mode
- [x] 2.8 Add auth guidance section: `pencil login` or PENCIL_CLI_KEY setup
- [x] 2.9 Test: run `check_deps.sh` with headless CLI installed, verify Tier 0 selected

## Phase 3: Verify + Docs

- [x] 3.1 Update `constitution.md` Pencil MCP rule (~line 101) with headless mode addendum
- [x] 3.2 Update `ux-design-lead.md` prerequisites to mention headless option first
- [ ] 3.3 Register adapter with `claude mcp add -s user pencil -- node <adapter-path>`
- [ ] 3.4 Restart Claude Code, verify `mcp__pencil__*` tools appear
- [ ] 3.5 Test `get_editor_state` returns document state
- [ ] 3.6 Test `batch_design` creates nodes, node IDs tracked, auto-saves
- [ ] 3.7 Test `get_screenshot` with tracked node ID
- [ ] 3.8 Test `open_document` restarts pencil with different file
- [ ] 3.9 Unregister adapter, verify Desktop/IDE fallback still works
