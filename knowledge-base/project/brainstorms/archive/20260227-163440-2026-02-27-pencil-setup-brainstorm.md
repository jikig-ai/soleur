# Pencil Setup Brainstorm

**Date:** 2026-02-27
**Issue:** #323 (scoped to auto-install + auto-register only; .pen file sync is a separate task)
**Status:** Complete

## What We're Building

A `pencil-setup` skill that auto-detects, installs, and registers the Pencil MCP server with Claude Code CLI. When a user invokes any Pencil-dependent workflow (e.g., ux-design-lead, brainstorm visual design handoff), and Pencil tools aren't available, this skill handles the full setup chain.

### The Problem

Pencil MCP is a stdio binary bundled inside the VS Code/Cursor IDE extension. It can't be bundled in `plugin.json` (HTTP-only). Currently, if Pencil isn't available, the ux-design-lead agent just prints "Install Pencil from docs.pencil.dev" and stops. Users must manually install the extension, hope it auto-registers, and restart Claude Code.

### The Solution

A skill that automates:
1. **Detect** — Is Pencil MCP already registered and working?
2. **Install** — If not, install the extension via IDE CLI
3. **Register** — Find the MCP binary and register with `claude mcp add`
4. **Verify** — Confirm tools are available
5. **Fix drift** — Re-register when extension updates cause stale paths

## Why This Approach

### Spike Results (2026-02-27)

Tested the Pencil MCP binary directly from this terminal:

| Finding | Detail |
|---------|--------|
| Binary location | `~/.cursor/extensions/highagency.pencildev-<version>-universal/out/mcp-server-<platform>` |
| Extension ID | `highagency.pencildev` (publisher: `highagency`) |
| Stdio mode | Works with `-app <ide>` flag |
| HTTP mode | Works: `http://localhost:<port>/mcp` (also needs `-app`) |
| Without IDE | Fails: `app connection is required` |
| Registration target | `~/.claude.json` via `claude mcp add pencil -- <binary> --app <ide>` |
| Version drift | Confirmed: registration pointed to v0.6.25 while v0.6.26 installed |
| Platform binaries | darwin-arm64, darwin-x64, linux-arm64, linux-x64, windows-arm64, windows-x64 |

### Architecture Constraints

- The MCP server binary is a Go executable (ELF, stripped)
- It ALWAYS needs a running IDE with the Pencil extension active (`-app` flag)
- No headless mode — all .pen file operations require the Pencil canvas
- The extension auto-registers on activation, but registration goes stale on updates

### CTO Assessment

- Risk for auto-install is LOW (well-understood extension install flow)
- Risk for auto-run is N/A (can't auto-start IDE, that's the user's responsibility)
- Consistent with existing patterns: rclone, agent-browser, xcode-test all use "check → instruct/install → verify"
- Do NOT create a centralized dependency framework — per-skill checks are the established pattern

## Key Decisions

1. **Extension-first approach** — Install via IDE CLI (`cursor --install-extension` / `code --install-extension`), not by downloading .vsix or desktop app
2. **Support both VS Code and Cursor** — Detect which is available, prefer the one with existing extensions
3. **Handle version drift** — Compare registered path version vs latest installed version, re-register if stale
4. **HTTP mode as secondary option** — Document HTTP mode (`-http -http-port <port>`) for advanced users who want a persistent server
5. **IDE must be running** — Make this a clear prerequisite, not a hidden failure. The skill should detect and communicate this.
6. **Separate tasks** — This skill is task 1. The .pen file sync (removing CaaS badge) is a separate follow-up task under the same issue.
7. **Update ux-design-lead** — Replace the natural-language Pencil check with a reference to `pencil-setup` skill

## Open Questions

1. Does `code --install-extension highagency.pencildev` work from snap-installed VS Code? (Snap may have sandbox restrictions)
2. Should the skill also handle Pencil account authentication (activation token from pencil.dev)?
3. Should agents that depend on Pencil automatically invoke `pencil-setup`, or should users run it manually first?

## Capability Gaps

- **No headless .pen file access** — The MCP server can't read/write .pen files without a running IDE. This limits CI/CD and pure-terminal workflows. Upstream feature request territory.
- **No npm/npx distribution** — Unlike XcodeBuildMCP, Pencil's MCP server has no standalone package. The only distribution channel is the IDE extension.
