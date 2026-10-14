# Tasks: Pencil Desktop Standalone MCP Target

## Phase 1: Investigation (blocks all other phases)

- [ ] 1.1 Test `pencil mcp-server` as Claude Code MCP command
  - [ ] 1.1.1 Verify `pencil` CLI is pencil.dev (not evolus/pencil): `pencil --version 2>&1 | grep -qi "pencil.dev"`
  - [ ] 1.1.2 Register: `claude mcp add -s user pencil -- pencil mcp-server`
  - [ ] 1.1.3 Verify: `claude mcp list -s user | grep pencil`
  - [ ] 1.1.4 Test tool availability: `mcp__pencil__get_editor_state` with Desktop running
- [ ] 1.2 Test Pencil Desktop auto-registration
  - [ ] 1.2.1 Start Pencil Desktop without prior `claude mcp add`
  - [ ] 1.2.2 Check `claude mcp list` for auto-registered entries
  - [ ] 1.2.3 Check `~/.claude.json` and `.mcp.json` for auto-added config
- [ ] 1.3 Test `--app` flag values on Desktop MCP binary
  - [ ] 1.3.1 Try `--app pencil`, `--app desktop`, `--app pencil_desktop`, no `--app` flag
  - [ ] 1.3.2 Verify IDE extension values: `--app cursor` vs `--app cursor_editor`, `--app code` vs `--app visual_studio_code`
  - [ ] 1.3.3 Record error messages for invalid `--app` values
- [ ] 1.4 Confirm Desktop mode eliminates "visible tab" constraint
  - [ ] 1.4.1 Open `.pen` file in Desktop, call `mcp__pencil__get_editor_state`
  - [ ] 1.4.2 Compare with IDE mode behavior (tab must be focused)
- [ ] 1.5 Document findings in a learning file

## Phase 2: Core Implementation (`check_deps.sh`)

- [ ] 2.1 Add three-tier detection: CLI -> Desktop binary -> IDE
  - [ ] 2.1.1 Add `detect_pencil_cli()` function with evolus/pencil collision guard
  - [ ] 2.1.2 Re-add `dpkg -s pencil` check for Linux .deb installations in `detect_pencil_desktop()`
  - [ ] 2.1.3 Restructure main flow: try CLI first, then Desktop binary, then IDE
  - [ ] 2.1.4 Add `PREFERRED_MODE`, `PREFERRED_APP`, `PREFERRED_BINARY` output variables
- [ ] 2.2 Add Desktop auto-launch function
  - [ ] 2.2.1 Add `is_desktop_running()` using `pgrep -f "[Pp]encil"` (POSIX-compatible)
  - [ ] 2.2.2 `launch_desktop()` for macOS (`open /Applications/Pencil.app`)
  - [ ] 2.2.3 `launch_desktop()` for Linux (.deb: `pencil &`, AppImage: `./Pencil*.AppImage &`)
  - [ ] 2.2.4 Check `$DISPLAY` on Linux before attempting launch
  - [ ] 2.2.5 Poll `mcp__pencil__get_editor_state` after launch (3 retries, 2s interval) instead of fixed sleep
- [ ] 2.3 Update exit states and output format
  - [ ] 2.3.1 CLI mode: `PREFERRED_MODE=cli PREFERRED_BINARY=pencil`
  - [ ] 2.3.2 Desktop binary mode: `PREFERRED_MODE=desktop_binary PREFERRED_BINARY=<path> PREFERRED_APP=<value>`
  - [ ] 2.3.3 IDE mode: `PREFERRED_MODE=ide PREFERRED_BINARY=<path> PREFERRED_APP=<ide_value>` (preserve current)
  - [ ] 2.3.4 Neither: `exit 1` with install instructions for both Desktop and IDE options
- [ ] 2.4 Preserve shell conventions
  - [ ] 2.4.1 No `set -euo pipefail` upgrade (soft dependency checks by design)
  - [ ] 2.4.2 Maintain `[ok]`/`[MISSING]`/`[info]` status tag convention

## Phase 3: SKILL.md Updates

- [ ] 3.1 Update prerequisite text: "Pencil Desktop or IDE with Pencil extension"
- [ ] 3.2 Update Phase 0 to capture `PREFERRED_MODE`, `PREFERRED_BINARY`, and `PREFERRED_APP`
- [ ] 3.3 Restructure Step 2: detect in priority order (CLI -> Desktop -> IDE)
- [ ] 3.4 Update Step 4: registration varies by mode
  - [ ] 3.4.1 CLI mode: `claude mcp add -s user pencil -- pencil mcp-server`
  - [ ] 3.4.2 Desktop binary mode: `claude mcp add -s user pencil -- <BINARY> --app <APP>`
  - [ ] 3.4.3 IDE mode: existing behavior
- [ ] 3.5 Add auto-launch step between detection and registration
- [ ] 3.6 Update Sharp Edges section for Desktop-specific constraints
- [ ] 3.7 Verify script path is in `.claude/settings.json` allow list

## Phase 4: Downstream Updates

- [ ] 4.1 Update `knowledge-base/overview/constitution.md` line 90 -- bifurcate Pencil rules for IDE vs Desktop mode
- [ ] 4.2 Update `plugins/soleur/agents/product/design/ux-design-lead.md` -- suggest Desktop as alternative to IDE

## Phase 5: Testing

- [ ] 5.1 Test: `pencil` CLI in PATH -- `check_deps.sh` exits 0 with `PREFERRED_MODE=cli`
- [ ] 5.2 Test: Desktop installed (no CLI), no IDE -- exits 0 with `PREFERRED_MODE=desktop_binary`
- [ ] 5.3 Test: Both Desktop and IDE available -- Desktop/CLI preferred
- [ ] 5.4 Test: Only IDE available -- current behavior preserved (regression)
- [ ] 5.5 Test: Neither available -- exits 1 with instructions for both options
- [ ] 5.6 Test: Desktop not running, `--auto` flag -- auto-launch works
- [ ] 5.7 Test: Linux AppImage without extraction, no CLI -- falls back to IDE
- [ ] 5.8 Test: evolus/pencil in PATH (collision) -- not misdetected
- [ ] 5.9 Test: MCP registration via `pencil mcp-server` -- tools available
- [ ] 5.10 Test: `mcp__pencil__get_editor_state` works in Desktop mode
- [ ] 5.11 Test: No display server (`$DISPLAY` unset) -- clear error on auto-launch
