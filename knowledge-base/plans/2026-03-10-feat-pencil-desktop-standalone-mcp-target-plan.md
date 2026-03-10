---
title: "feat: use Pencil Desktop as standalone MCP target, remove IDE hard dependency"
type: feat
date: 2026-03-10
---

# feat: Use Pencil Desktop as Standalone MCP Target

## Overview

The `pencil-setup` skill currently requires Cursor or VS Code as a hard dependency. If no IDE is detected, `check_deps.sh` exits with error and setup fails entirely. This blocks Pencil MCP from working in Claude Code standalone terminal sessions, CI/CD pipelines, and environments where the user prefers a different editor.

Pencil Desktop ships its own MCP server binary (confirmed in `knowledge-base/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md`). When Desktop is installed, the IDE should be optional -- the Desktop binary can serve as the MCP target with `--app pencil` (or whatever value Desktop accepts).

## Problem Statement / Motivation

During the X banner design session (#483), Pencil MCP failed with `"WebSocket not connected to app: cursor"` because no `.pen` tab was visible in Cursor. The entire Pencil step was skipped and the workflow pivoted to Pillow-only generation. If Pencil Desktop had been auto-detected as the MCP target, the design workflow would have succeeded without IDE dependency.

The current dependency hierarchy is:

```
1. IDE required (hard exit if missing)
2. IDE extension required (can auto-install)
3. Desktop optional (informational only)
```

The proposed hierarchy is:

```
1. Pencil Desktop running     -> use Desktop binary + --app pencil (no IDE needed)
2. IDE with Pencil extension   -> use extension binary + --app cursor/code (current behavior)
3. Neither available           -> error with install instructions for both options
```

## Proposed Solution

### Phase 1: Investigation (must complete before coding)

Three unknowns must be resolved before implementation:

1. **What `--app` values does the Desktop MCP binary accept?** Test `--app pencil`, `--app desktop`, or whether the binary auto-detects when no `--app` flag is passed. The extension binary requires `--app cursor` or `--app code` -- the Desktop binary may differ.

2. **Can Pencil Desktop be launched programmatically?**
   - macOS: `open /Applications/Pencil.app`
   - Linux: run the AppImage directly or from extracted `squashfs-root/`

3. **Does the Desktop app expose a WebSocket endpoint that the MCP binary can connect to?** The IDE extension's MCP binary connects to the IDE's webview. Does the Desktop binary connect to the Desktop app's own editor window? Or does it still require an IDE webview?

### Phase 2: `check_deps.sh` modifications

File: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`

- Add a `PREFERRED_APP` output variable alongside existing `PREFERRED_BINARY`
- Restructure the main flow: try Desktop binary first, fall back to IDE+extension
- Demote IDE from hard dependency to optional when Desktop binary is available
- Add Desktop auto-launch logic (launch if installed but not running)
- New dependency check exit states:
  - `PREFERRED_APP=pencil PREFERRED_BINARY=<desktop_path>` -- Desktop mode
  - `PREFERRED_APP=cursor PREFERRED_BINARY=<ext_path>` -- IDE mode (current behavior)
  - `exit 1` -- neither Desktop nor IDE available

### Phase 3: `SKILL.md` modifications

File: `plugins/soleur/skills/pencil-setup/SKILL.md`

- Update prerequisite text: remove "VS Code or Cursor must be installed" hard requirement
- Step 2: try Desktop detection first, fall back to IDE detection
- Step 4: register with `--app <PREFERRED_APP>` instead of always `--app <IDE>`
- Add auto-launch step: if Desktop is available but not running, launch it before registration
- Update Sharp Edges section to document Desktop-specific constraints

### Phase 4: Constitution and agent updates

- Update `knowledge-base/overview/constitution.md` line 90 (Pencil MCP three-conditions rule) to account for Desktop mode where IDE webview is not required
- Update `plugins/soleur/agents/product/design/ux-design-lead.md` to suggest Desktop as an alternative when IDE setup fails

## Technical Considerations

### Binary accessibility by platform

| Platform | Desktop Binary Path | Accessible? |
|----------|-------------------|-------------|
| macOS | `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*` | Yes, directly |
| Linux (extracted) | `<dir>/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-*` | Yes, if extracted |
| Linux (AppImage) | Inside AppImage | No, requires `--appimage-extract` |

### Registration idempotency

The existing remove-then-add pattern (`claude mcp remove pencil -s user; claude mcp add -s user pencil -- <binary> --app <app>`) remains valid. The only change is the `--app` value and binary path.

### WebSocket connection model

The critical unknown: does Desktop mode eliminate the "tab must be visible" constraint? If Desktop runs its own editor window, the WebSocket connection may be automatic when Desktop is running -- no need to focus a specific tab. This would be a significant UX improvement over IDE mode.

### Auto-launch considerations

- macOS: `open /Applications/Pencil.app` is reliable and non-blocking
- Linux AppImage: running the AppImage directly should work but needs testing
- Both: need a brief delay after launch for the app to initialize before MCP registration
- Detection that Desktop is already running: `pgrep -f Pencil` or similar

## Non-goals

- Bundling Pencil MCP in `plugin.json` (stdio binary, not bundleable -- see `2026-02-14-pencil-mcp-local-binary-constraint.md`)
- Supporting Pencil web editor as an MCP target
- Auto-extracting Linux AppImages (too invasive; provide instructions instead)
- Adding Pencil Desktop installation automation (link to downloads page)

## Acceptance Criteria

- [ ] `check_deps.sh` succeeds when Pencil Desktop is installed but no IDE exists
- [ ] `check_deps.sh` outputs both `PREFERRED_BINARY` and `PREFERRED_APP` values
- [ ] MCP registration works with Desktop as the target app (`--app pencil` or equivalent)
- [ ] Pencil MCP tools (`batch_design`, `batch_get`, `open_document`) work when connected to Desktop
- [ ] Auto-launch Desktop if installed but not running (macOS and Linux)
- [ ] Falls back to IDE path when Desktop is not available (no regression)
- [ ] Works on both macOS and Linux
- [ ] `SKILL.md` no longer lists IDE as a hard prerequisite
- [ ] Constitution.md Pencil rule updated for Desktop mode

## Test Scenarios

- Given Pencil Desktop is installed and running but no IDE exists, when `check_deps.sh` runs, then it exits 0 with `PREFERRED_APP=pencil` and `PREFERRED_BINARY=<desktop_binary_path>`
- Given both Desktop and IDE are available, when `check_deps.sh` runs, then Desktop is preferred (`PREFERRED_APP=pencil`)
- Given only IDE with extension is available (no Desktop), when `check_deps.sh` runs, then current behavior is preserved (`PREFERRED_APP=cursor`)
- Given neither Desktop nor IDE is available, when `check_deps.sh` runs, then it exits 1 with install instructions for both options
- Given Desktop is installed but not running, when `check_deps.sh --auto` runs, then Desktop is launched automatically before returning
- Given Linux AppImage without extraction, when `check_deps.sh` runs, then it falls back to IDE extension binary (no crash or hang)
- Given registration with `--app pencil`, when `claude mcp list` runs, then `pencil` entry appears with correct binary path
- Given Desktop mode registration, when `mcp__pencil__get_editor_state` is called with Desktop running, then it returns editor state (no WebSocket error)

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `--app pencil` may not be a valid flag value | Blocks entire feature | Phase 1 investigation tests this first; abort if unsupported |
| Desktop WebSocket may still require IDE | Reduces value proposition to "different binary, same constraint" | Phase 1 investigation confirms; document if true |
| Desktop not running at registration time | MCP registration succeeds but tools fail at invocation | Auto-launch before registration; `get_editor_state` health check |
| Linux AppImage launch behavior varies | May not work on all distributions | Document as "extract first" with fallback to IDE path |

## Semver Intent

`semver:patch` -- This modifies an existing skill's dependency detection logic. No new skill, agent, or command is added.

## References and Research

### Internal References

- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` -- current dependency checker (171 lines)
- `plugins/soleur/skills/pencil-setup/SKILL.md` -- current setup flow (116 lines)
- `plugins/soleur/agents/product/design/ux-design-lead.md:11` -- agent prerequisite check
- `knowledge-base/overview/constitution.md:90` -- Pencil MCP three-conditions rule

### Institutional Learnings

- `knowledge-base/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md` -- Desktop binary confirmed at `resources/app.asar.unpacked/out/`, accepts `-app` flag, different build from extension
- `knowledge-base/learnings/2026-02-27-pencil-editor-operational-requirements.md` -- WebSocket requires visible editor, no programmatic save, read before write
- `knowledge-base/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md` -- stdio binary cannot be bundled in plugin.json
- `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md` -- remove-then-add pattern, `--app` always required, `-s user` scope

### Related Issues

- #483 -- X banner design session where Pencil MCP failed (motivation for this issue)
- #493 -- This issue
