# Tasks: Pencil Headless CLI Integration

**Plan:** `knowledge-base/project/plans/2026-03-24-feat-pencil-headless-cli-integration-plan.md`
**Issue:** #1087

## Phase 1: MCP Adapter Core

- [ ] 1.1 Create `plugins/soleur/skills/pencil-setup/scripts/package.json` with `@modelcontextprotocol/sdk` and `zod` deps
- [ ] 1.2 Create `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` scaffold
  - [ ] 1.2.1 McpServer + StdioServerTransport setup
  - [ ] 1.2.2 Node version check on startup (exit if < 22.9.0)
  - [ ] 1.2.3 Child process manager: spawn `pencil interactive --out <file>`
  - [ ] 1.2.4 REPL command sender: write to child stdin, buffer until `pencil >` prompt
  - [ ] 1.2.5 Response parser: strip ANSI codes, detect `[ERROR]` lines, extract content
  - [ ] 1.2.6 Register read-only tools: batch_get, get_editor_state, get_guidelines, get_screenshot, get_style_guide, get_style_guide_tags, get_variables, find_empty_space_on_canvas, search_all_unique_properties, snapshot_layout, export_nodes
  - [ ] 1.2.7 Register mutating tools with auto-save: batch_design, replace_all_matching_properties, set_variables
  - [ ] 1.2.8 Implement open_document handler (restart pencil with new file)
  - [ ] 1.2.9 Implement explicit save tool
  - [ ] 1.2.10 Error handling: pencil process crash detection and restart on next tool call
- [ ] 1.3 Install adapter deps: `cd plugins/soleur/skills/pencil-setup/scripts && npm install`
- [ ] 1.4 Manual smoke test: register adapter with `claude mcp add`, verify tools appear

## Phase 2: Detection Script Updates

- [ ] 2.1 Add `detect_headless_cli()` function to `check_deps.sh`
  - [ ] 2.1.1 Check `~/.local/node_modules/.bin/pencil` exists and is executable
  - [ ] 2.1.2 Verify it's the headless CLI (check for `interactive` subcommand, no `mcp-server`)
  - [ ] 2.1.3 Node version gate: parse `node --version`, probe nvm/fnm if < 22.9.0
- [ ] 2.2 Add `try_headless_cli_tier()` function
  - [ ] 2.2.1 Call `detect_headless_cli()`
  - [ ] 2.2.2 Auth check: `PENCIL_CLI_KEY=... pencil status` exits 0
  - [ ] 2.2.3 Auto-install if `--auto` and not found: `npm install --prefix ~/.local <package>`
  - [ ] 2.2.4 Set output vars: `PREFERRED_MODE=headless_cli`, `PREFERRED_BINARY=<adapter-path>`, `PREFERRED_APP=""`
- [ ] 2.3 Update cascade: `try_headless_cli_tier || try_cli_tier || try_desktop_tier || try_ide_tier`
- [ ] 2.4 Test: run `check_deps.sh` with headless CLI installed, verify Tier 0 selected

## Phase 3: Setup Skill Updates

- [ ] 3.1 Update `SKILL.md` Phase 0 to document `headless_cli` mode output
- [ ] 3.2 Add `### Headless CLI mode` registration section to Step 2
- [ ] 3.3 Update Step 1 (check registered) to handle headless_cli mode
- [ ] 3.4 Update Step 3 verify message for headless mode
- [ ] 3.5 Add auth guidance section: `pencil login` or PENCIL_CLI_KEY setup

## Phase 4: Constitution & Agent Updates

- [ ] 4.1 Update `constitution.md` Pencil MCP rule (~line 101) with headless mode addendum
- [ ] 4.2 Update `ux-design-lead.md` prerequisites to mention headless option first

## Phase 5: Integration Verification

- [ ] 5.1 Register adapter with `claude mcp add -s user pencil -- node <adapter-path>`
- [ ] 5.2 Restart Claude Code, verify `mcp__pencil__*` tools appear
- [ ] 5.3 Test `get_editor_state` returns document state
- [ ] 5.4 Test `batch_design` creates nodes and auto-saves
- [ ] 5.5 Test `get_screenshot` returns image for created node
- [ ] 5.6 Test `open_document` restarts pencil with different file
- [ ] 5.7 Unregister adapter, verify Desktop/IDE fallback still works
