---
title: "feat: use Pencil Desktop as standalone MCP target, remove IDE hard dependency"
type: feat
date: 2026-03-10
---

# feat: Use Pencil Desktop as Standalone MCP Target

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 7
**Research sources:** Pencil docs, community articles, institutional learnings, codebase analysis

### Key Improvements

1. Discovered two distinct Desktop MCP registration paths: `pencil` CLI command (`pencil mcp-server`) and direct binary path -- the CLI path eliminates binary-hunting entirely
2. Found that `--app` flag uses `visual_studio_code` (not `code`) for VS Code -- existing `check_deps.sh` likely uses wrong value
3. Pencil Desktop auto-detects compatible AI CLIs and may auto-register MCP -- Phase 1 must test whether manual registration is even needed
4. Linux now has `.deb` package option (not just AppImage) -- `detect_pencil_desktop()` needs `dpkg` check added back

### New Considerations Discovered

- The `pencil` CLI (`File > Install pencil command into PATH`) may be the simplest Desktop MCP path -- register as `pencil mcp-server` instead of binary path
- Pencil docs state "MCP server runs automatically when you use Pencil" -- if Desktop auto-registers, the skill just needs to verify it is running
- The existing learning `2026-02-27-pencil-desktop-not-required-for-mcp.md` documents the exact inverse assumption; this feature inverts that relationship
- Shell script uses no `set -euo pipefail` by design (soft dependency checks) -- maintain this convention per `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`

## Overview

The `pencil-setup` skill currently requires Cursor or VS Code as a hard dependency. If no IDE is detected, `check_deps.sh` exits with error and setup fails entirely. This blocks Pencil MCP from working in Claude Code standalone terminal sessions, CI/CD pipelines, and environments where the user prefers a different editor.

Pencil Desktop ships its own MCP server binary (confirmed in `knowledge-base/project/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md`). When Desktop is installed, the IDE should be optional -- the Desktop binary can serve as the MCP target with `--app pencil` (or whatever value Desktop accepts).

### Research Insights

**Pencil CLI MCP path (simpler alternative):**
A [community workflow guide](https://atalupadhyay.wordpress.com/2026/02/25/pencil-dev-claude-code-workflow-from-design-to-production-code-in-minutes/) documents a configuration using the `pencil` CLI directly:

```json
{
  "mcpServers": {
    "pencil": {
      "command": "pencil",
      "args": ["mcp-server"],
      "env": {}
    }
  }
}
```

This eliminates binary path hunting entirely. When the `pencil` CLI is in PATH (installed via Desktop > File > Install pencil command into PATH), the MCP server can be registered with `claude mcp add -s user pencil -- pencil mcp-server` -- no `--app` flag, no binary path resolution.

**Auto-detection capability:**
[BetterStack's Pencil guide](https://betterstack.com/community/guides/ai/pencil-ai/) states: "Pencil is smart enough to auto-detect if you have these tools installed and will automatically set up the connection." The [official docs](https://docs.pencil.dev/getting-started/ai-integration) confirm: "The Pencil MCP server runs automatically when you use Pencil." Phase 1 must test whether Pencil Desktop auto-registers with Claude Code without any manual `claude mcp add`.

**`--app` flag values:**
A [DevelopersIO article](https://dev.classmethod.jp/en/articles/claude-code-pencil-mcp-web-design/) shows the extension binary using `--app visual_studio_code` (not `--app code` as the current SKILL.md assumes). The existing `check_deps.sh` may already be using incorrect values -- investigate during Phase 1.

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
1. Pencil CLI in PATH           -> register as `pencil mcp-server` (simplest)
2. Pencil Desktop running       -> use Desktop binary + correct --app value (no IDE needed)
3. IDE with Pencil extension    -> use extension binary + --app cursor/visual_studio_code
4. Neither available            -> error with install instructions for both options
```

### Research Insights

**Three-tier hierarchy rationale:**
The `pencil` CLI path is preferred over the direct binary path because:

- No platform-specific binary resolution (macOS/Linux paths differ)
- No AppImage extraction requirement on Linux
- `pencil mcp-server` is version-agnostic (the CLI resolves internally)
- Matches the pattern documented in Pencil's own guides

The direct binary path remains as fallback for cases where the CLI is not installed but the Desktop app is present.

## Proposed Solution

### Phase 1: Investigation (must complete before coding)

Four unknowns must be resolved before implementation:

1. **Does `pencil mcp-server` work as a Claude Code MCP command?**
   - Test: `claude mcp add -s user pencil -- pencil mcp-server`
   - Verify: `claude mcp list -s user | grep pencil`
   - Test tool availability: call `mcp__pencil__get_editor_state` with Desktop running

2. **Does Pencil Desktop auto-register with Claude Code?**
   - Start Pencil Desktop, then run `claude mcp list` without manual registration
   - Check `~/.claude.json` and `.mcp.json` for auto-added entries
   - If auto-registration works, the skill only needs to verify Desktop is running

3. **What `--app` values does the Desktop MCP binary accept?**
   - Test the direct binary with: `--app pencil`, `--app desktop`, `--app pencil_desktop`, no `--app` flag
   - Verify the extension binary: is it `--app cursor` or `--app cursor_editor`? Is it `--app code` or `--app visual_studio_code`?
   - Record the error message for invalid `--app` values (useful for user-facing diagnostics)

4. **Does Desktop mode eliminate the "tab must be visible" constraint?**
   - With Desktop running and a `.pen` file open, call `mcp__pencil__get_editor_state`
   - Compare behavior: IDE mode requires the `.pen` tab to be focused; does Desktop require the same?

### Research Insights

**Investigation priority order:**
Test the `pencil` CLI path first (investigation item 1). If it works, items 3 becomes less critical since the CLI abstracts away the binary and `--app` flag. Item 2 (auto-registration) should be tested second -- if Desktop auto-registers, the entire skill simplifies to "verify Desktop is running."

**Edge case: `pencil` CLI name collision:**
Per `knowledge-base/project/learnings/2026-02-27-check-deps-pattern-for-gui-apps.md`, the `pencil` CLI binary name collides with evolus/pencil (a different tool). After `command -v pencil` succeeds, verify it is the correct pencil: `pencil --version 2>&1 | grep -qi "pencil.dev"` or similar.

### Phase 2: `check_deps.sh` modifications

File: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`

- Add `PREFERRED_APP` and `PREFERRED_MODE` output variables alongside existing `PREFERRED_BINARY`
- Restructure the main flow with three-tier detection:
  1. Check `pencil` CLI in PATH (with collision guard) -> set `PREFERRED_MODE=cli`
  2. Check Desktop binary directly accessible -> set `PREFERRED_MODE=desktop_binary`
  3. Check IDE + extension -> set `PREFERRED_MODE=ide` (current behavior)
- Demote IDE from hard dependency to optional when Desktop/CLI is available
- Add Desktop auto-launch logic (launch if installed but not running)
- New output format:
  - CLI mode: `PREFERRED_MODE=cli PREFERRED_BINARY=pencil PREFERRED_APP=`
  - Desktop binary mode: `PREFERRED_MODE=desktop_binary PREFERRED_BINARY=<path> PREFERRED_APP=<value>`
  - IDE mode: `PREFERRED_MODE=ide PREFERRED_BINARY=<ext_path> PREFERRED_APP=<ide_value>`
  - `exit 1` -- no Pencil MCP source available

### Research Insights

**Shell script conventions to preserve:**

- The script deliberately omits `set -euo pipefail` because soft dependency checks must not abort on missing dependencies. Per `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`, do not upgrade this script's strict mode.
- Continue using `[ok]`, `[MISSING]`, `[installing]`, `[FAILED]`, `[info]` status tag convention per `2026-02-27-check-deps-pattern-for-gui-apps.md`.
- `--auto` flag scope remains narrow: auto-install IDE extension, auto-launch Desktop. Never auto-download Desktop itself.

**Linux `.deb` package detection:**
The [Pencil installation docs](https://docs.pencil.dev/getting-started/installation) now list `.deb` as an install option: `sudo dpkg -i pencil-*.deb`. The previous learning (`2026-02-27-pencil-desktop-not-required-for-mcp.md`) removed `dpkg -s pencil` because no .deb existed at the time. Re-add `dpkg -s pencil 2>/dev/null` as a Linux detection path alongside the AppImage glob.

**Process detection for auto-launch:**
Use `pgrep -f "[Pp]encil"` (case-insensitive bracket trick) rather than `pgrep -fi Pencil` -- the `-i` flag is not POSIX and not available on all Linux distributions. Verify the process name against multiple possible formats:

- macOS: process name may be `Pencil` or `Pencil.app`
- Linux AppImage: process name may include the AppImage filename
- Linux .deb: process name may be `pencil` (lowercase)

### Phase 3: `SKILL.md` modifications

File: `plugins/soleur/skills/pencil-setup/SKILL.md`

- Update prerequisite text: "Pencil Desktop or an IDE (Cursor/VS Code) with the Pencil extension must be available"
- Restructure Step 2: detect in priority order (CLI -> Desktop -> IDE)
- Update Step 4: registration varies by mode:
  - CLI mode: `claude mcp add -s user pencil -- pencil mcp-server`
  - Desktop binary mode: `claude mcp add -s user pencil -- <BINARY_PATH> --app <APP_VALUE>`
  - IDE mode: `claude mcp add -s user pencil -- <BINARY_PATH> --app <IDE_VALUE>` (current)
- Add auto-launch step between detection and registration
- Update Sharp Edges section for Desktop-specific constraints

### Research Insights

**Skill SKILL.md code fence permissions:**
Per `2026-02-22-skill-code-fence-permission-flow.md`, bash commands in `!` code fences fail silently on permission denial. The `check_deps.sh` script path should be in the allow list. Verify `.claude/settings.json` includes the script path before shipping.

### Phase 4: Constitution and agent updates

- Update `knowledge-base/overview/constitution.md` line 90: the three-conditions rule (visible tab, Ctrl+S save, read-before-write) applies to IDE mode. Desktop mode may have different constraints (Phase 1 investigation determines this). Update to: "In IDE mode, three conditions apply: [...]. In Desktop mode, [...]."
- Update `plugins/soleur/agents/product/design/ux-design-lead.md`: when Pencil MCP tools are unavailable, suggest both `pencil-setup` and "install Pencil Desktop" as alternatives, not just IDE setup.

## Technical Considerations

### Binary accessibility by platform

| Platform | CLI Path | Desktop Binary Path | Accessible? |
|----------|----------|-------------------|-------------|
| macOS | `pencil` (if installed to PATH) | `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*` | Yes, directly |
| Linux (.deb) | `pencil` (if installed to PATH) | Investigate -- likely `/usr/lib/pencil/` or similar | Likely yes |
| Linux (extracted AppImage) | `pencil` (if in PATH) | `<dir>/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-*` | Yes, if extracted |
| Linux (AppImage, not extracted) | `pencil` (if in PATH) | Inside AppImage | No, requires `--appimage-extract` |

### Research Insights

**New: Linux `.deb` binary location:**
When installed via `.deb`, the binary is likely at a system path (e.g., `/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-*`). Phase 1 should test this on a `.deb` installation. However, if the `pencil` CLI path works, the binary location is irrelevant.

### Registration idempotency

The existing remove-then-add pattern (`claude mcp remove pencil -s user; claude mcp add -s user pencil -- <binary> --app <app>`) remains valid. The only change is the `--app` value and binary path.

### Research Insights

**Potential simplification -- auto-registration:**
If Phase 1 confirms Pencil Desktop auto-registers with Claude Code, the remove-then-add pattern may conflict with auto-registration. The skill should detect existing auto-registered entries and not overwrite them. Check `claude mcp list -s user` output format to distinguish auto-registered from manually registered entries.

### WebSocket connection model

The critical unknown: does Desktop mode eliminate the "tab must be visible" constraint? If Desktop runs its own editor window, the WebSocket connection may be automatic when Desktop is running -- no need to focus a specific tab. This would be a significant UX improvement over IDE mode.

### Research Insights

**Evidence suggests Desktop eliminates the constraint:**
The [Pencil AI integration docs](https://docs.pencil.dev/getting-started/ai-integration) list "Claude Code (CLI)" as a supported integration without mentioning any IDE tab requirement. The prerequisite is simply "Have Pencil running." This strongly suggests Desktop mode does not require a visible tab -- the Desktop app IS the editor, not a webview inside an IDE.

If confirmed, this is the primary UX benefit of Desktop mode: no more "WebSocket not connected" errors caused by unfocused IDE tabs.

### Auto-launch considerations

- macOS: `open /Applications/Pencil.app` is reliable and non-blocking
- Linux .deb: `pencil &` or `nohup pencil &` if the binary is in PATH
- Linux AppImage: `./Pencil*.AppImage &` from the install directory
- Both: need a brief delay after launch for the app to initialize before MCP registration
- Detection that Desktop is already running: `pgrep -f "[Pp]encil"` (POSIX-compatible)

### Research Insights

**Launch timing:**
The Pencil docs state the MCP server starts automatically with the app. After `open /Applications/Pencil.app`, wait for the MCP server to be ready. A reasonable approach: launch, then poll `mcp__pencil__get_editor_state` with a timeout (e.g., 3 retries at 2-second intervals). This is more reliable than a fixed `sleep` since app startup time varies by machine.

**Headless launch consideration:**
For CI/CD or terminal-only environments, Pencil Desktop requires a display server (X11 or Wayland on Linux, WindowServer on macOS). If no display is available, auto-launch will fail. The skill should detect `$DISPLAY` (Linux) or assume display availability (macOS) and provide a clear error message when auto-launch fails.

## Non-goals

- Bundling Pencil MCP in `plugin.json` (stdio binary, not bundleable -- see `2026-02-14-pencil-mcp-local-binary-constraint.md`)
- Supporting Pencil web editor as an MCP target
- Auto-extracting Linux AppImages (too invasive; provide instructions instead)
- Adding Pencil Desktop installation automation (link to downloads page)
- Headless/display-less operation (Pencil requires a GUI)

## Acceptance Criteria

- [x] `check_deps.sh` succeeds when Pencil Desktop is installed but no IDE exists
- [x] `check_deps.sh` outputs `PREFERRED_BINARY`, `PREFERRED_APP`, and `PREFERRED_MODE` values
- [ ] MCP registration works with Desktop as the target (via CLI or binary path)
- [ ] Pencil MCP tools (`batch_design`, `batch_get`, `open_document`) work when connected to Desktop
- [x] Auto-launch Desktop if installed but not running (macOS and Linux)
- [x] Falls back to IDE path when Desktop is not available (no regression)
- [x] Works on both macOS and Linux
- [x] `SKILL.md` no longer lists IDE as a hard prerequisite
- [x] Constitution.md Pencil rule updated for Desktop mode
- [x] `pencil` CLI name collision with evolus/pencil is guarded against

## Test Scenarios

- Given Pencil Desktop is installed with `pencil` CLI in PATH, when `check_deps.sh` runs, then it exits 0 with `PREFERRED_MODE=cli`
- Given Pencil Desktop is installed (no CLI in PATH) and running but no IDE exists, when `check_deps.sh` runs, then it exits 0 with `PREFERRED_MODE=desktop_binary`
- Given both Desktop and IDE are available, when `check_deps.sh` runs, then Desktop/CLI is preferred over IDE
- Given only IDE with extension is available (no Desktop), when `check_deps.sh` runs, then current behavior is preserved (`PREFERRED_MODE=ide`)
- Given neither Desktop nor IDE is available, when `check_deps.sh` runs, then it exits 1 with install instructions for both options
- Given Desktop is installed but not running, when `check_deps.sh --auto` runs, then Desktop is launched automatically before returning
- Given Linux AppImage without extraction and no CLI, when `check_deps.sh` runs, then it falls back to IDE extension binary (no crash or hang)
- Given the `pencil` command in PATH is evolus/pencil (not pencil.dev), when `check_deps.sh` runs, then it is not misdetected as Pencil Desktop CLI
- Given registration via `pencil mcp-server`, when `claude mcp list` runs, then `pencil` entry appears
- Given Desktop mode registration, when `mcp__pencil__get_editor_state` is called with Desktop running, then it returns editor state (no WebSocket error)
- Given no display server available (`$DISPLAY` unset on Linux), when `check_deps.sh --auto` attempts auto-launch, then it reports a clear error and falls back to IDE path

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `pencil mcp-server` may not work as Claude Code MCP command | Must fall back to binary path approach | Phase 1 tests this first; binary path is the fallback |
| `--app` values may differ from assumptions (`cursor` vs `cursor_editor`) | Wrong registration causes WebSocket errors | Phase 1 enumerates valid values; script stores discovered values |
| Desktop WebSocket may still require visible editor tab | Reduces value proposition (same constraint, different binary) | Phase 1 investigation confirms; document if true |
| Desktop not running at registration time | MCP registration succeeds but tools fail at invocation | Auto-launch before registration; `get_editor_state` health check |
| Linux AppImage launch behavior varies | May not work on all distributions | Document as "extract first" with fallback to IDE path |
| `pencil` CLI name collision with evolus/pencil | False positive in detection | Version string check: `pencil --version 2>&1 \| grep -qi "pencil.dev"` |
| Pencil auto-registers and our manual registration conflicts | Duplicate or conflicting MCP entries | Check for existing registration before remove-then-add |
| No display server in headless environments | Auto-launch fails | Detect `$DISPLAY` before attempting launch; clear error message |

## Semver Intent

`semver:patch` -- This modifies an existing skill's dependency detection logic. No new skill, agent, or command is added.

## References and Research

### Internal References

- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` -- current dependency checker (171 lines)
- `plugins/soleur/skills/pencil-setup/SKILL.md` -- current setup flow (116 lines)
- `plugins/soleur/agents/product/design/ux-design-lead.md:11` -- agent prerequisite check
- `knowledge-base/overview/constitution.md:90` -- Pencil MCP three-conditions rule

### Institutional Learnings

- `knowledge-base/project/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md` -- Desktop binary confirmed at `resources/app.asar.unpacked/out/`, accepts `-app` flag, different build from extension
- `knowledge-base/project/learnings/2026-02-27-pencil-editor-operational-requirements.md` -- WebSocket requires visible editor, no programmatic save, read before write
- `knowledge-base/project/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md` -- stdio binary cannot be bundled in plugin.json
- `knowledge-base/project/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md` -- remove-then-add pattern, `--app` always required, `-s user` scope
- `knowledge-base/project/learnings/2026-02-27-check-deps-pattern-for-gui-apps.md` -- GUI app detection pattern, `pencil` CLI name collision with evolus/pencil
- `knowledge-base/project/learnings/2026-02-27-pencil-desktop-not-required-for-mcp.md` -- documents inverse assumption (Desktop optional); this feature inverts that hierarchy
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- do not upgrade check_deps.sh to strict mode
- `knowledge-base/project/learnings/2026-02-22-skill-code-fence-permission-flow.md` -- ensure script paths are in allow list

### External References

- [Pencil AI Integration docs](https://docs.pencil.dev/getting-started/ai-integration) -- lists Claude Code as supported, states "Have Pencil running" as prerequisite
- [Pencil Installation docs](https://docs.pencil.dev/getting-started/installation) -- Linux .deb now available alongside AppImage
- [Pencil + Claude Code workflow guide](https://atalupadhyay.wordpress.com/2026/02/25/pencil-dev-claude-code-workflow-from-design-to-production-code-in-minutes/) -- shows `pencil mcp-server` CLI registration
- [DevelopersIO Pencil article](https://dev.classmethod.jp/en/articles/claude-code-pencil-mcp-web-design/) -- shows `--app visual_studio_code` (not `--app code`)
- [BetterStack Pencil guide](https://betterstack.com/community/guides/ai/pencil-ai/) -- confirms auto-detection of compatible AI CLIs

### Related Issues

- #483 -- X banner design session where Pencil MCP failed (motivation for this issue)
- #493 -- This issue
