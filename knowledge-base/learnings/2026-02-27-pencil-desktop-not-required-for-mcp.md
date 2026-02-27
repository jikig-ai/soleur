# Learning: Pencil Desktop is not required for Pencil MCP

## Problem

The `check_deps.sh` script (PR #340) treated Pencil Desktop as a hard dependency, exiting with code 1 if not found. On Linux it also used `dpkg -s pencil` to detect it, but Pencil Desktop is distributed as an AppImage — no .deb package exists. This blocked the entire `pencil-setup` flow on machines where the MCP server works fine.

## Root Cause

Two incorrect assumptions baked into the original script:

1. **Pencil Desktop is required for MCP** — false. The MCP server binary ships inside the IDE extension (`highagency.pencildev-*/out/mcp-server-*`), not the Desktop app. The extension communicates directly with the Pencil editor webview in the IDE.
2. **Pencil Desktop on Linux is a .deb package** — false. The download page (pencil.dev/downloads) offers only AppImage and tarball for Linux. The `dpkg -s pencil` check was dead code that could never succeed.

## Solution

- Demoted Pencil Desktop from hard dependency (exit 1) to informational (`[info]`)
- Reordered checks: IDE first, extension second (the actual hard deps), Desktop last (optional)
- Fixed Linux detection: search for `Pencil*.AppImage` in `~/Applications`, `~/.local/bin`, `/opt`
- Changed OS detection from `debian` (distro-specific) to `linux` (generic `uname -s` check)
- Fixed download URL message: "Linux AppImage" instead of "Linux .deb"

## Key Insight

Always verify dependency claims by dogfooding on a real machine. The original script was written with reasonable-sounding assumptions about what's required, but running it revealed the actual dependency graph: IDE + extension is sufficient, Desktop is a nice-to-have. Check distribution methods before writing platform detection code — don't assume a package manager format exists.

## Session Errors

1. Bash tool display artifact: duplicated output on non-zero exit (investigated, not a real bug)
2. `claude mcp list -s project` — `-s` flag doesn't exist in current CLI version
3. Edit-before-Read tool rejection (forgot to read SKILL.md first)
4. Git merge blocked by uncommitted changes in worktree (committed WIP, then merged)
5. Version collision: bumped to 3.7.6 but main was already at 3.7.6 (re-bumped to 3.7.7)

## Cross-References

- Original pattern doc: `knowledge-base/learnings/2026-02-27-check-deps-pattern-for-gui-apps.md`
- Pencil MCP registration: `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Pencil editor requirements: `knowledge-base/learnings/2026-02-27-pencil-editor-operational-requirements.md`
- PR #340 (original script): merged to main as v3.7.5
- This fix: v3.7.7

## Tags
category: integration-issues
module: pencil-setup
