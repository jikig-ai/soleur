# Tasks: Pencil Desktop Standalone MCP Target

## Phase 1: Investigation

- [ ] 1.1 Test `--app` flag values on Desktop MCP binary (`--app pencil`, `--app desktop`, no `--app`)
- [ ] 1.2 Verify Desktop can be launched programmatically (macOS `open`, Linux AppImage)
- [ ] 1.3 Confirm Desktop exposes WebSocket endpoint for MCP binary connection
- [ ] 1.4 Document findings -- update or create learning if behavior differs from expectations

## Phase 2: Core Implementation (`check_deps.sh`)

- [ ] 2.1 Restructure main flow to try Desktop binary first, fall back to IDE
  - [ ] 2.1.1 Move IDE detection (lines 91-99) after Desktop check
  - [ ] 2.1.2 Add `PREFERRED_APP` output variable alongside `PREFERRED_BINARY`
  - [ ] 2.1.3 Only require IDE when Desktop binary is unavailable
- [ ] 2.2 Add Desktop auto-launch function
  - [ ] 2.2.1 `launch_desktop()` for macOS (`open /Applications/Pencil.app`)
  - [ ] 2.2.2 `launch_desktop()` for Linux (run AppImage or extracted binary)
  - [ ] 2.2.3 Add brief delay after launch for app initialization
  - [ ] 2.2.4 Add `is_desktop_running()` check (`pgrep -f Pencil` or equivalent)
- [ ] 2.3 Update exit states
  - [ ] 2.3.1 Desktop mode: `PREFERRED_APP=pencil PREFERRED_BINARY=<path>`
  - [ ] 2.3.2 IDE mode: `PREFERRED_APP=cursor PREFERRED_BINARY=<path>` (preserve current)
  - [ ] 2.3.3 Neither: `exit 1` with install instructions for both options

## Phase 3: SKILL.md Updates

- [ ] 3.1 Update prerequisite text -- remove IDE hard requirement
- [ ] 3.2 Update Phase 0 to capture both `PREFERRED_BINARY` and `PREFERRED_APP`
- [ ] 3.3 Update Step 2 -- try Desktop detection first, fall back to IDE
- [ ] 3.4 Update Step 4 -- register with `--app <PREFERRED_APP>`
- [ ] 3.5 Add auto-launch step between detection and registration
- [ ] 3.6 Update Sharp Edges section for Desktop-specific constraints

## Phase 4: Downstream Updates

- [ ] 4.1 Update `knowledge-base/overview/constitution.md` line 90 -- Pencil three-conditions rule for Desktop mode
- [ ] 4.2 Update `plugins/soleur/agents/product/design/ux-design-lead.md` -- suggest Desktop alternative

## Phase 5: Testing

- [ ] 5.1 Test: Desktop installed, no IDE -- `check_deps.sh` exits 0
- [ ] 5.2 Test: Both Desktop and IDE available -- Desktop preferred
- [ ] 5.3 Test: Only IDE available -- current behavior preserved (regression)
- [ ] 5.4 Test: Neither available -- exits 1 with instructions
- [ ] 5.5 Test: Desktop installed but not running, `--auto` flag -- auto-launch works
- [ ] 5.6 Test: MCP registration with Desktop app value
- [ ] 5.7 Test: `mcp__pencil__get_editor_state` works in Desktop mode
