# Tasks: Pencil Desktop Dependency Check

## Phase 1: Setup

- 1.1 Create `plugins/soleur/skills/pencil-setup/scripts/` directory
- 1.2 Read `plugins/soleur/skills/feature-video/scripts/check_deps.sh` as reference pattern
- 1.3 Verify Pencil Desktop bundle identifier for macOS `mdfind` (check Info.plist if available)
- 1.4 Verify .deb package name (may be `pencil`, `pencil-desktop`, or `pencil-app`)

## Phase 2: Core Implementation

- 2.1 Create `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
  - 2.1.1 Add shebang (`#!/usr/bin/env bash`), header comment, and explanation for absent `set -euo pipefail`
  - 2.1.2 Add `AUTO_INSTALL` flag parsing (`--auto`)
  - 2.1.3 Add OS detection (`Darwin` -> macos, `/etc/debian_version` -> debian)
  - 2.1.4 Implement `detect_pencil_desktop()` -- platform-specific checks FIRST (avoid pencil CLI name collision with evolus/pencil):
    - macOS: `test -d "/Applications/Pencil.app"` then `mdfind` fallback
    - Debian: `dpkg -s pencil 2>/dev/null | grep -q '^Status:.*installed'` (NOT `dpkg -l`)
    - Cross-platform fallback: `command -v pencil`
  - 2.1.5 Implement `detect_ide()` -- `command -v cursor` then `command -v code`
  - 2.1.6 Implement `detect_extension()` -- glob `${EXTDIR}/highagency.pencildev-*/out/mcp-server-*` with `sort -V | tail -1`
  - 2.1.7 Add hard dependency check: Pencil Desktop (exit 1 with platform-specific download URL if missing)
  - 2.1.8 Add hard dependency check: IDE (exit 1 with install URLs if missing)
  - 2.1.9 Add soft dependency check: Pencil extension (prompt to install, or auto-install with `--auto`; exit 1 if install fails)
  - 2.1.10 Add informational check: `pencil` CLI (report `[info]` if missing, do not block)
  - 2.1.11 Make script executable (`chmod +x`)
- 2.2 Update `plugins/soleur/skills/pencil-setup/SKILL.md`
  - 2.2.1 Add Phase 0 section with dependency check instructions before existing Step 1
  - 2.2.2 Add `--auto` flag documentation for pipeline use
  - 2.2.3 Use markdown link to `[check_deps.sh](./scripts/check_deps.sh)` (not backtick)
  - 2.2.4 Verify no `$()` or `${VAR}` in SKILL.md code blocks (per constitution)

## Phase 3: Version Bump & Docs

- 3.1 Fetch and check main for current version (`git fetch origin main`)
- 3.2 Bump version in `plugin.json` (PATCH increment)
- 3.3 Update `CHANGELOG.md` with new entry
- 3.4 Update `README.md` component counts if changed
- 3.5 Update `.claude-plugin/marketplace.json` plugin version
- 3.6 Update root `README.md` version badge
- 3.7 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder

## Phase 4: Testing

- 4.1 Run `bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` on current machine -- verify correct detection and output
- 4.2 Test `--auto` flag behavior (extension auto-install)
- 4.3 Verify SKILL.md code blocks have no `$()` or `${VAR}`: `grep -n '\$(' plugins/soleur/skills/pencil-setup/SKILL.md` should return nothing
- 4.4 Run `bun test` to verify no regressions
