# Pencil Setup Skill — Spec

**Issue:** #323 (scoped to setup skill; .pen sync is separate)
**Branch:** feat-pencil-setup
**Brainstorm:** [2026-02-27-pencil-setup-brainstorm.md](../../brainstorms/2026-02-27-pencil-setup-brainstorm.md)

## Problem Statement

Pencil MCP tools are required for visual design workflows (ux-design-lead agent, brainstorm visual handoffs) but have no automated setup path. Users must manually install the IDE extension, hope auto-registration works, and troubleshoot stale paths when extensions update. This creates friction for new Soleur users and breaks silently after extension updates.

## Goals

- G1: One-command Pencil setup from any terminal where VS Code or Cursor is available
- G2: Detect and fix stale MCP registrations (version drift)
- G3: Clear error messages when prerequisites aren't met (no IDE, IDE not running)
- G4: Document HTTP mode as an advanced option

## Non-Goals

- Headless .pen file access (upstream Pencil limitation)
- Desktop app installation (extension-first approach only)
- Pencil account authentication (separate concern)
- Syncing the .pen design file (separate task under same issue)

## Functional Requirements

- **FR1:** Detect whether Pencil MCP tools are available in the current session
- **FR2:** Detect installed IDE CLIs (cursor, code) and their extension directories
- **FR3:** Install `highagency.pencildev` extension via IDE CLI if missing
- **FR4:** Locate the platform-correct MCP server binary in the extension directory
- **FR5:** Register the binary with Claude Code CLI (`claude mcp add pencil -- <binary> --app <ide>`)
- **FR6:** Detect version drift (registered path version != latest installed version) and re-register
- **FR7:** Verify registration by checking tool availability
- **FR8:** Print clear next-steps when IDE is not running

## Technical Requirements

- **TR1:** Platform detection for binary selection (darwin-arm64, darwin-x64, linux-arm64, linux-x64, windows-arm64, windows-x64)
- **TR2:** Extension directory patterns: `~/.cursor/extensions/highagency.pencildev-*-universal/out/` and `~/.vscode/extensions/highagency.pencildev-*-universal/out/`
- **TR3:** Skill follows existing patterns (flat under `skills/pencil-setup/`, SKILL.md with proper frontmatter)
- **TR4:** Update ux-design-lead agent to reference pencil-setup skill instead of manual instructions
- **TR5:** Version bump (MINOR) across plugin.json, CHANGELOG.md, README.md, marketplace.json

## Implementation Notes

### Binary path pattern
```
~/.cursor/extensions/highagency.pencildev-<version>-universal/out/mcp-server-<os>-<arch>
```

### Platform mapping
| `uname -s` + `uname -m` | Binary suffix |
|--------------------------|---------------|
| Linux x86_64 | linux-x64 |
| Linux aarch64 | linux-arm64 |
| Darwin arm64 | darwin-arm64 |
| Darwin x86_64 | darwin-x64 |

### Registration command
```bash
claude mcp add pencil -- /path/to/mcp-server-<platform> --app <ide>
```

### Version drift detection
```bash
# Get registered path from claude mcp list
# Extract version from path: highagency.pencildev-<VERSION>-universal
# Compare with latest version in extension directory (sort -V | tail -1)
```
