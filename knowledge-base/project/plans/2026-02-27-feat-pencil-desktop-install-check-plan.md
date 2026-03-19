---
title: "feat: Add Pencil Desktop dependency check with install guidance to pencil-setup"
type: feat
date: 2026-02-27
---

# feat: Add Pencil Desktop Dependency Check with Install Guidance to pencil-setup

## Enhancement Summary

**Deepened on:** 2026-02-27
**Sections enhanced:** 6
**Research sources used:** PR #337 reference script, Pencil docs, 4 institutional learnings, cross-platform detection best practices, dpkg scripting patterns

### Key Improvements
1. Use `dpkg -s` instead of `dpkg -l` for Linux package detection -- cleaner exit codes, no grep needed
2. Add `mdfind` as a secondary macOS fallback -- catches apps installed outside `/Applications/`
3. Identified that the Pencil extension IS the hard dependency, not the Desktop app itself -- the MCP server binary lives in the extension, and the extension can function with just the IDE (Desktop app is needed separately for the `pencil` CLI and editor features, but MCP registration works without it)
4. Added `.pen` file association check as an alternative Desktop app detection signal
5. Clarified `--auto` exit behavior: in auto mode, exit 1 on any missing hard dependency (no prompts, no `[skip]`)

### New Considerations Discovered
- `dpkg -l pencil` is fragile: it lists packages even if only partially installed or removed but not purged; `dpkg -s pencil 2>/dev/null | grep -q '^Status:.*installed'` is the robust alternative
- The `pencil` CLI binary name may conflict with other tools named `pencil` (Pencil Project / evolus/pencil is a different product with the same name) -- platform-specific checks should take precedence over `command -v pencil`
- SKILL.md code blocks must NOT contain `$()` or `${VAR}` per constitution -- but the script file itself is safe (scripts execute as units)

## Overview

Add a `check_deps.sh` script to the `pencil-setup` skill that detects whether the Pencil Desktop app is installed, offers to install it if missing (cross-platform), and chains into the existing MCP registration flow. Follows the same `install_tool()`/`attempt_install()`/`verify_install()` pattern established in PR #337 (`feature-video/scripts/check_deps.sh`).

## Problem Statement / Motivation

The `pencil-setup` skill assumes Pencil Desktop and its IDE extension are already installed. When they are not, the skill fails partway through with a cryptic error (no MCP binary found). Users must manually discover the download page, figure out which package to get, install it, and then re-run the skill. This is the same UX gap that PR #337 solved for ffmpeg/rclone in feature-video.

Unlike ffmpeg and rclone, Pencil Desktop is **not available in any standard package manager** (no brew cask, no apt package). It is distributed as:
- **macOS**: `.dmg` download from pencil.dev/downloads
- **Linux (Debian/Ubuntu)**: `.deb` download from pencil.dev/downloads
- **Linux (other)**: `.AppImage` download from pencil.dev/downloads
- **Windows**: Installer download from pencil.dev/downloads

This means the `install_tool()` pattern from feature-video needs adaptation: instead of `apt-get install`/`brew install`, the script must print clear manual instructions with the download URL.

## Proposed Solution

### Architecture

```
plugins/soleur/skills/pencil-setup/
  SKILL.md          # Updated: add Phase 0 dependency check before Step 1
  scripts/
    check_deps.sh   # New: Pencil Desktop + IDE + extension preflight checker
```

### Detection Strategy

Pencil Desktop can be detected three ways, in order of reliability:

1. **macOS app bundle** -- `test -d "/Applications/Pencil.app"` (most common install location), then `mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null` (catches non-standard install paths via Spotlight index)
2. **Linux package** -- `dpkg -s pencil 2>/dev/null | grep -q '^Status:.*installed'` (Debian/Ubuntu .deb), or check for the binary in common paths (`/usr/bin/pencil`, `/opt/Pencil/pencil`)
3. **`pencil` CLI command** -- `command -v pencil` (cross-platform fallback, but requires the user to have explicitly installed CLI from Desktop app's "File > Install pencil command into PATH")

### Research Insights: Detection Best Practices

**Use `dpkg -s` over `dpkg -l` for scripting:**
- `dpkg -l` outputs lines even for packages that are removed-but-not-purged, half-installed, or config-remaining. Grepping for `^ii` works but is fragile because it depends on column formatting.
- `dpkg -s <package>` returns exit code 0 only for fully installed packages and includes a clean `Status:` line. The pattern `dpkg -s pencil 2>/dev/null | grep -q '^Status:.*installed'` is the robust alternative.
- Source: [Baeldung Linux package detection](https://www.baeldung.com/linux/check-how-package-installed), [Debian Forums](https://forums.debian.net/viewtopic.php?t=159341)

**Use `mdfind` as secondary macOS fallback:**
- `test -d "/Applications/Pencil.app"` only checks the standard location. Users may install in `~/Applications/` or other custom paths.
- `mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'"` searches the Spotlight index, catching apps in any location. However, it requires Spotlight indexing to be enabled (disabled on some developer machines).
- Check `/Applications/` first (fast, no index dependency), fall back to `mdfind` only if not found.
- Source: [Stack Overflow macOS app detection](https://stackoverflow.com/questions/54100496/check-if-an-app-is-installed-on-macos-using-the-terminal)

**Name collision risk with `command -v pencil`:**
- The Pencil Project (evolus/pencil) is a completely different open-source GUI prototyping tool that uses the same `pencil` command name. On systems where both are installed, `command -v pencil` may resolve to the wrong binary.
- Mitigation: Check platform-specific paths first, use `command -v pencil` only as a last-resort fallback, and verify identity with `pencil --version` if output format is known.

### Installation Approach

Since Pencil Desktop is not in any package manager, the script has two options per platform:

| Platform | Automated Install | Manual Fallback |
|----------|------------------|-----------------|
| **macOS** | `curl -L <dmg-url> -o /tmp/pencil.dmg && hdiutil attach /tmp/pencil.dmg && cp -R /Volumes/Pencil/Pencil.app /Applications/ && hdiutil detach /Volumes/Pencil` | Print download URL |
| **Debian/Ubuntu** | `curl -L <deb-url> -o /tmp/pencil.deb && sudo dpkg -i /tmp/pencil.deb` | Print download URL |
| **Linux (other)** | Download AppImage to `~/.local/bin/` | Print download URL |
| **Windows** | Not automated (no silent installer) | Print download URL |

**Decision point:** Automated download adds complexity (URL versioning, disk space, network errors) and requires hardcoding or scraping the download URL. The simpler approach -- which is more aligned with the learning from `2026-02-27-pencil-mcp-auto-registration-via-skill.md` ("skills that are ~5 sequential commands don't need script abstractions") -- is to:

1. **Detect** the app (hard check: exit 1 if missing)
2. **Print clear install instructions** with the download URL per platform
3. **Never auto-download** -- unlike `apt-get`/`brew` which are trusted, piped-curl installs of .dmg/.deb files require more user trust

**Recommendation: Manual-only install guidance (no auto-download).** The `--auto` flag suppresses interactive prompts for the IDE extension install step only (which CAN be automated via `cursor --install-extension`), not the Desktop app install.

### Script Structure (check_deps.sh)

```bash
#!/usr/bin/env bash
# pencil-setup dependency checker with optional auto-install for IDE extension
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each check uses explicit if/then.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Detect OS for platform-specific checks
OS="unknown"
[[ "$(uname -s)" == "Darwin" ]] && OS="macos"
[[ -f /etc/debian_version ]] && OS="debian"

# -- Detection Functions --

detect_pencil_desktop() {
  # Platform-specific checks first (avoid pencil CLI name collision)
  case "$OS" in
    macos)
      test -d "/Applications/Pencil.app" && return 0
      # Spotlight fallback for non-standard install locations
      mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
      ;;
    debian)
      dpkg -s pencil 2>/dev/null | grep -q '^Status:.*installed' && return 0
      ;;
  esac
  # Cross-platform fallback: pencil CLI (requires explicit install from Desktop menu)
  command -v pencil >/dev/null 2>&1 && return 0
  return 1
}

detect_ide() {
  # Prefer Cursor over VS Code (Pencil docs recommend Cursor)
  command -v cursor >/dev/null 2>&1 && echo "cursor" && return 0
  command -v code >/dev/null 2>&1 && echo "code" && return 0
  return 1
}

detect_extension() {
  local ide="$1"
  local extdir
  case "$ide" in
    cursor) extdir="$HOME/.cursor/extensions" ;;
    code)   extdir="$HOME/.vscode/extensions" ;;
    *)      return 1 ;;
  esac
  ls -d "${extdir}/highagency.pencildev-"*/out/mcp-server-* 2>/dev/null | sort -V | tail -1
}

# -- Checks --

echo "=== Pencil Setup Dependency Check ==="
echo

# 1. Hard dependency: Pencil Desktop app
if detect_pencil_desktop; then
  echo "  [ok] Pencil Desktop"
else
  echo "  [MISSING] Pencil Desktop (required)"
  case "$OS" in
    macos)  echo "    Download: https://www.pencil.dev/downloads (macOS .dmg)" ;;
    debian) echo "    Download: https://www.pencil.dev/downloads (Linux .deb)" ;;
    *)      echo "    Download: https://www.pencil.dev/downloads" ;;
  esac
  echo
  echo "Install Pencil Desktop, then run this check again."
  exit 1
fi

# 2. Hard dependency: IDE (Cursor or VS Code)
IDE=$(detect_ide)
if [[ -n "$IDE" ]]; then
  echo "  [ok] IDE: $IDE"
else
  echo "  [MISSING] No supported IDE (Cursor or VS Code)"
  echo "    Install Cursor: https://cursor.com"
  echo "    Install VS Code: https://code.visualstudio.com"
  exit 1
fi

# 3. Soft dependency: Pencil IDE extension (auto-installable)
BINARY=$(detect_extension "$IDE")
if [[ -n "$BINARY" ]]; then
  echo "  [ok] Pencil extension ($BINARY)"
else
  echo "  [MISSING] Pencil IDE extension"
  if [[ "$AUTO_INSTALL" == "true" ]]; then
    echo "  [installing] Pencil extension..."
    "$IDE" --install-extension highagency.pencildev 2>&1
  else
    echo "  Install extension? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "  [installing] Pencil extension..."
      "$IDE" --install-extension highagency.pencildev 2>&1
    else
      echo "  [skip] Pencil extension (declined)"
    fi
  fi
  # Re-check after install attempt
  BINARY=$(detect_extension "$IDE")
  if [[ -n "$BINARY" ]]; then
    echo "  [ok] Pencil extension installed ($BINARY)"
  else
    echo "  [FAILED] Extension install -- try manually from IDE marketplace"
    echo "    Search for 'Pencil' in $IDE Extensions, or visit:"
    echo "    https://docs.pencil.dev/getting-started/installation"
    exit 1
  fi
fi

# 4. Informational: pencil CLI (not required for MCP setup)
if command -v pencil >/dev/null 2>&1; then
  echo "  [ok] pencil CLI"
else
  echo "  [info] pencil CLI not in PATH (optional)"
  echo "    Install via: Pencil Desktop > File > Install pencil command into PATH"
fi

echo
echo "=== Check Complete ==="
```

### Research Insights: Script Design

**No `set -euo pipefail` -- intentional:**
- Per feature-video precedent and `2026-02-27-feature-video-graceful-degradation.md`: "Scripts should either have `set -e` at the top or include a comment explaining why it is absent."
- The comment in line 3 explains: soft dependency checks must not abort the script. If `mdfind` fails or `dpkg` is not installed, the script should fall through to the next check, not exit.

**`$()` in script is safe:**
- Per `2026-02-22-command-substitution-in-plugin-markdown.md` and `2026-02-24-extract-command-substitution-into-scripts.md`: `$()` is only a problem in SKILL.md code blocks (where Claude Code executes commands individually). Inside a bash script, `$()` is normal shell syntax and does not trigger permission prompts.
- The SKILL.md Phase 0 section invokes the script with a static `bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` command -- no `$()` in the markdown.

**Output convention matches feature-video:**
- `[ok]` -- dependency found and working
- `[MISSING]` -- dependency not found (may be hard or soft)
- `[installing]` -- actively installing
- `[FAILED]` -- install attempted but unsuccessful
- `[skip]` -- user declined to install
- `[info]` -- informational, not blocking

### SKILL.md Changes

Add Phase 0 before the existing Step 1. The Phase 0 section in SKILL.md must follow these rules from institutional learnings:
- No `$()` or `${VAR}` in bash code blocks (per constitution and `2026-02-22-shell-expansion-codebase-wide-fix.md`)
- Use markdown link to script file (per skill compliance checklist: `[check_deps.sh](./scripts/check_deps.sh)`)
- Use `./plugins/soleur/...` relative path (per `2026-02-22-shell-expansion-codebase-wide-fix.md`)

```markdown
## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked
from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts
and install the IDE extension automatically:

For interactive use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

For pipeline/automated use:

```bash
bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

If the script exits non-zero, a required dependency is missing. Stop and
inform the user with the printed instructions.

If all checks pass, proceed to Step 1 (Check if Already Registered).
```

## Technical Considerations

### Why Pencil Desktop is a Hard Dependency

Unlike ffmpeg/rclone in feature-video (soft dependencies that allow graceful degradation), Pencil Desktop is a **hard dependency** for the entire pencil-setup flow:
- The IDE extension (`highagency.pencildev`) embeds the MCP server binary
- The MCP server binary communicates with the Desktop app's editor runtime via WebSocket
- Without the Desktop app, MCP tool calls fail with "WebSocket not connected to app" (per `2026-02-27-pencil-editor-operational-requirements.md`)
- Without the Desktop app, the entire MCP registration is pointless

### Research Insights: Dependency Classification

The feature-video skill classifies dependencies as:
- **Hard:** agent-browser (exit 1, cannot proceed at all)
- **Soft:** ffmpeg, rclone (skip with `[skip]`, degraded capability)

For pencil-setup, the classification is:
- **Hard (exit 1):** Pencil Desktop, IDE (Cursor/VS Code), Pencil extension (without any of these, MCP registration cannot complete)
- **Informational (no exit):** `pencil` CLI (not needed for MCP, only for batch operations)

This differs from feature-video where ffmpeg/rclone allowed the skill to still produce value (screenshots). Here, the absence of any hard dependency means the entire skill has zero utility. Therefore all three primary checks are hard dependencies that exit 1.

### No Auto-Download for Desktop Apps

The feature-video pattern uses `apt-get install`/`brew install` because those tools:
- Come from trusted, curated repositories
- Handle dependencies automatically
- Are idempotent and safe to run with `sudo`

Pencil Desktop is distributed as raw binaries (.dmg, .deb, .AppImage). Auto-downloading and installing these would:
- Require hardcoding or scraping version-specific URLs (fragile -- URLs include version numbers)
- Pipe untrusted downloads to `dpkg -i` or `hdiutil mount` (security concern)
- Require `sudo` for `.deb` installation without the safety of a package manager

The `--auto` flag applies only to the IDE extension install step (`cursor --install-extension`), not the Desktop app.

### Research Insights: Security Considerations

**Never auto-download .dmg/.deb from hardcoded URLs:**
- Package managers (apt, brew) verify package signatures. Direct downloads have no built-in integrity verification.
- URLs with version numbers break when new versions are released. A script downloading `pencil-1.2.3.deb` becomes immediately outdated.
- The download page (pencil.dev/downloads) may change its URL structure at any time.
- A compromised URL (typosquatting, DNS hijack) would silently install malware. Package managers have multiple layers of signature verification that raw curl downloads lack.

**The `--install-extension` command IS safe to auto-run:**
- IDE extension marketplaces (VS Code, Cursor) have their own review and signing processes.
- `cursor --install-extension highagency.pencildev` fetches from the official marketplace with integrity checks.
- This is why `--auto` applies to extension install but NOT to Desktop app install.

### Pencil CLI is Informational Only

The `pencil` CLI is not required for MCP setup. It is an experimental feature for batch design operations. The script reports its absence as `[info]` (not `[MISSING]`) and provides the path to install it from the Desktop app menu.

### Research Insights: Future Consideration

Per Pencil's CLI docs: "Currently you need to have a desktop app installed to use pencil from CLI, but soon that's going to change." A headless npm package is planned. When available, the detection and install story simplifies dramatically (`npm install -g @pencil/cli` or equivalent). The script should be revisited when this ships.

## Acceptance Criteria

- [x] `scripts/check_deps.sh` created in `plugins/soleur/skills/pencil-setup/`
- [x] Script follows the output convention from `feature-video/scripts/check_deps.sh` (`[ok]`, `[MISSING]`, `[installing]`, `[FAILED]`, `[skip]`, `[info]`)
- [x] Pencil Desktop detected via platform-specific checks first, then `command -v pencil` fallback
- [x] macOS detection: `/Applications/Pencil.app` then `mdfind` fallback
- [x] Linux detection: `dpkg -s pencil` (not `dpkg -l`) with `Status:.*installed` grep
- [x] IDE (Cursor/VS Code) detected via `command -v`
- [x] Pencil extension detected via glob in IDE extension directory (same pattern as existing SKILL.md Step 3)
- [x] `--auto` flag installs extension without prompting but does NOT auto-download Desktop app
- [x] Missing Pencil Desktop prints platform-specific download URL and exits 1
- [x] Missing IDE prints install URLs and exits 1
- [x] Missing extension offers interactive install (or auto with `--auto`); exits 1 if install fails
- [x] Pencil CLI absence reported as informational (`[info]`), not blocking
- [x] SKILL.md updated with Phase 0 linking to `[check_deps.sh](./scripts/check_deps.sh)` (markdown link, not backtick)
- [x] SKILL.md Phase 0 code blocks contain no `$()` or `${VAR}` (per constitution)
- [x] Script has comment explaining absence of `set -euo pipefail`
- [x] Version bumped in plugin.json, CHANGELOG.md, README.md, marketplace.json

## Test Scenarios

- Given Pencil Desktop is installed and IDE has the extension, when running `check_deps.sh`, then all checks show `[ok]` and exit 0
- Given Pencil Desktop is NOT installed, when running `check_deps.sh`, then script prints download URL for the current OS and exits 1
- Given Pencil Desktop is installed but no IDE found, when running `check_deps.sh`, then script prints IDE install URLs and exits 1
- Given IDE is installed but extension is missing, when running `check_deps.sh` interactively, then prompted to install and responds N -- shows `[skip]` then exits 1 (extension is required for MCP binary)
- Given `--auto` flag and extension is missing, when running `check_deps.sh --auto`, then extension installs without prompting
- Given `--auto` flag and Desktop app is missing, when running `check_deps.sh --auto`, then prints download URL and exits 1 (no auto-download)
- Given all deps present but `pencil` CLI missing, when running `check_deps.sh`, then shows `[info]` for CLI and exits 0
- Given macOS with Pencil installed in `~/Applications/` (non-standard), when running `check_deps.sh`, then `mdfind` fallback detects it and shows `[ok]`
- Given Debian with Pencil .deb removed but config files remaining (`dpkg -l` shows `rc`), when running `check_deps.sh`, then `dpkg -s` correctly reports `[MISSING]`

### Edge Cases

- **Spotlight disabled (macOS):** If `mdutil` is off, `mdfind` returns empty. The script falls through to `command -v pencil`. If CLI is also not installed, reports `[MISSING]`. This is correct behavior -- the user needs to either enable Spotlight or install the CLI.
- **Multiple Pencil versions (extension):** The `sort -V | tail -1` pattern (from existing SKILL.md) picks the latest version. This is correct for the MCP binary path.
- **WSL (Windows Subsystem for Linux):** `uname -s` returns `Linux`, `/etc/debian_version` exists. The script will attempt Debian detection. If Pencil Desktop is installed on Windows but not in WSL, it won't be found. This is acceptable -- WSL users need to install the native Linux version or use the Windows host.
- **`pencil` CLI from wrong product:** If `command -v pencil` resolves to the Pencil Project (evolus/pencil), the platform-specific checks run first and fail, then the `command -v` fallback would incorrectly succeed. Mitigation: platform-specific checks return 0 first when the correct app IS installed. When it is NOT installed, the `command -v` fallback might produce a false positive. Consider adding `pencil --version 2>&1 | grep -qi "pencil.dev"` as a validator, but this risks brittleness if the version string changes.

## Dependencies & Risks

- **URL stability**: The pencil.dev/downloads URL must remain stable. If it changes, the script output is wrong but not broken (just stale URL).
- **Extension name stability**: `highagency.pencildev` is the current marketplace ID. A rename would break the glob and install command.
- **Desktop detection fragility**: The platform-specific app detection paths (`/Applications/Pencil.app`, `dpkg -s pencil`) may need adjustment as Pencil Desktop evolves its installation structure.
- **Bundle identifier unknown**: The `mdfind` query uses `dev.pencil.desktop` as the bundle identifier. This should be verified against the actual `.app` bundle's `Info.plist`. If wrong, `mdfind` will never match. Test on a machine with Pencil installed.
- **`dpkg -s` package name**: The .deb package name may not be exactly `pencil`. It could be `pencil-desktop` or `pencil-app`. Verify by downloading the .deb and checking `dpkg-deb --info pencil-*.deb`.

## References & Research

### Internal References
- PR #337: [feat(feature-video): add on-demand ffmpeg and rclone installation](https://github.com/jikig-ai/soleur/pull/337)
- Reference script: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- Existing skill: `plugins/soleur/skills/pencil-setup/SKILL.md`

### Institutional Learnings Applied
- `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md` -- remove-then-add pattern, skills that are ~5 commands don't need script abstractions
- `knowledge-base/learnings/2026-02-27-parameterized-shell-install-eliminates-duplication.md` -- parameterized functions over per-tool duplicates
- `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md` -- hard vs soft dependency classification, output convention
- `knowledge-base/learnings/2026-02-27-pencil-editor-operational-requirements.md` -- WebSocket requires visible editor, no programmatic save
- `knowledge-base/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md` -- Pencil MCP cannot be bundled, requires local install
- `knowledge-base/learnings/2026-02-22-command-substitution-in-plugin-markdown.md` -- no `$()` in SKILL.md code blocks
- `knowledge-base/learnings/2026-02-24-extract-command-substitution-into-scripts.md` -- extract shell logic into scripts
- `knowledge-base/learnings/2026-02-22-shell-expansion-codebase-wide-fix.md` -- no `${VAR}` in plugin markdown

### External References
- Pencil Desktop downloads: https://www.pencil.dev/downloads
- Pencil CLI docs: https://docs.pencil.dev/for-developers/pencil-cli
- Pencil installation docs: https://docs.pencil.dev/getting-started/installation
- macOS app detection patterns: https://stackoverflow.com/questions/54100496/check-if-an-app-is-installed-on-macos-using-the-terminal
- dpkg package detection: https://www.baeldung.com/linux/check-how-package-installed
- Cross-platform OS detection: https://safjan.com/bash-determine-if-linux-or-macos/
