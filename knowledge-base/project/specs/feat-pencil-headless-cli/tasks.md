# Tasks: Pencil Headless CLI Integration

**Plan:** `knowledge-base/project/plans/2026-03-24-feat-pencil-headless-cli-integration-plan.md`
**Issue:** #1087

## Phase 1: MCP Adapter Core

- [ ] 1.1 Create `plugins/soleur/skills/pencil-setup/package.json` with `@modelcontextprotocol/sdk` and `zod` deps
- [ ] 1.2 Create `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` scaffold
  - [ ] 1.2.1 McpServer + StdioServerTransport setup
  - [ ] 1.2.2 Node version check on startup (exit if < 22.9.0)
  - [ ] 1.2.3 Child process manager: spawn `pencil interactive --out <file>` with `{ stdio: ['pipe', 'pipe', 'pipe'] }` — CRITICAL: never inherit stdio
  - [ ] 1.2.4 Explicit env allowlist for child process (HOME, PATH, NODE_ENV, LANG, TERM, USER, SHELL, TMPDIR, PENCIL_CLI_KEY) — never spread `process.env`
  - [ ] 1.2.5 Startup buffer: consume welcome banner and initial `pencil >` prompt before accepting commands
  - [ ] 1.2.6 REPL command sender: write to child stdin terminated by `\n`
  - [ ] 1.2.7 Response buffer: accumulate child stdout until `\npencil >` prompt (ANSI-strip first, then match)
  - [ ] 1.2.8 Command queue: serialize concurrent MCP tool calls — REPL is single-threaded
  - [ ] 1.2.9 Per-command timeout: 30s default, return MCP error if prompt never arrives
  - [ ] 1.2.10 Node ID extraction: parse `batch_design` responses for `Inserted node \`<id>\`` patterns, maintain in-memory binding-to-ID map
  - [ ] 1.2.11 Error detection: `[ERROR]` prefixed lines and `[31mError:` ANSI patterns
  - [ ] 1.2.12 Register read-only tools: batch_get, get_editor_state, get_guidelines, get_screenshot, get_style_guide, get_style_guide_tags, get_variables, find_empty_space_on_canvas, search_all_unique_properties, snapshot_layout, export_nodes
  - [ ] 1.2.13 Register mutating tools with auto-save: batch_design, replace_all_matching_properties, set_variables
  - [ ] 1.2.14 Implement open_document handler (save current, restart pencil with new `--in`/`--out` file)
  - [ ] 1.2.15 Implement explicit save tool
  - [ ] 1.2.16 Error handling: pencil process crash detection and restart on next tool call
- [ ] 1.3 Add `node_modules/` to `.gitignore` for the skill directory
- [ ] 1.4 Install adapter deps: `cd plugins/soleur/skills/pencil-setup && npm install`
- [ ] 1.5 Manual smoke test: register adapter with `claude mcp add`, verify tools appear

## Phase 2: Detection + Registration

- [ ] 2.1 Add `detect_headless_cli()` function to `check_deps.sh`
  - [ ] 2.1.1 Check `~/.local/node_modules/.bin/pencil` exists and is executable
  - [ ] 2.1.2 Verify it's the headless CLI (check for `interactive` subcommand, no `mcp-server`)
  - [ ] 2.1.3 Node version gate: parse `node --version`, probe nvm/fnm if < 22.9.0
- [ ] 2.2 Add `try_headless_cli_tier()` function
  - [ ] 2.2.1 Call `detect_headless_cli()`
  - [ ] 2.2.2 Auth check: `PENCIL_CLI_KEY=... pencil status` exits 0
  - [ ] 2.2.3 Auto-install if `--auto` and not found: `npm install --prefix ~/.local <package>`
  - [ ] 2.2.4 Set output vars: `PREFERRED_MODE=headless_cli`, `PREFERRED_BINARY=<adapter-path>`, `PREFERRED_APP=""`
- [ ] 2.3 Update `detect_pencil_cli()` with negative guard: skip if `interactive` subcommand works but `mcp-server` doesn't (prevents headless CLI matching Tier 1)
- [ ] 2.4 Update cascade: `try_headless_cli_tier || try_cli_tier || try_desktop_tier || try_ide_tier`
- [ ] 2.5 Update `SKILL.md` Phase 0 to document `headless_cli` mode output
- [ ] 2.6 Add `### Headless CLI mode` registration section to Step 2 with env var config
- [ ] 2.7 Update Step 1 (check registered) and Step 3 (verify) for headless mode
- [ ] 2.8 Add auth guidance section: `pencil login` or PENCIL_CLI_KEY setup
- [ ] 2.9 Test: run `check_deps.sh` with headless CLI installed, verify Tier 0 selected

## Phase 3: Verify + Docs

- [ ] 3.1 Update `constitution.md` Pencil MCP rule (~line 101) with headless mode addendum
- [ ] 3.2 Update `ux-design-lead.md` prerequisites to mention headless option first
- [ ] 3.3 Register adapter with `claude mcp add -s user pencil -- node <adapter-path>`
- [ ] 3.4 Restart Claude Code, verify `mcp__pencil__*` tools appear
- [ ] 3.5 Test `get_editor_state` returns document state
- [ ] 3.6 Test `batch_design` creates nodes, node IDs tracked, auto-saves
- [ ] 3.7 Test `get_screenshot` with tracked node ID
- [ ] 3.8 Test `open_document` restarts pencil with different file
- [ ] 3.9 Unregister adapter, verify Desktop/IDE fallback still works
