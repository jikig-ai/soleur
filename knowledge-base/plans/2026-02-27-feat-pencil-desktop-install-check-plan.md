---
title: "feat: Add Pencil Desktop dependency check with install guidance to pencil-setup"
type: feat
date: 2026-02-27
---

# feat: Add Pencil Desktop Dependency Check with Install Guidance to pencil-setup

## Overview

Add a `check_deps.sh` script to the `pencil-setup` skill that detects whether the Pencil Desktop app is installed, offers to install it if missing (cross-platform), and chains into the existing MCP registration flow. Follows the same `install_tool()`/`attempt_install()`/`verify_install()` pattern established in PR #337 (`feature-video/scripts/check_deps.sh`).

## Problem Statement / Motivation

The `pencil-setup` skill assumes Pencil Desktop and its IDE extension are already installed. When they are not, the skill fails partway through with a cryptic error (no MCP binary found). Users must manually discover the download page, figure out which package to get, install it, and then re-run the skill. This is the same UX gap that PR #337 solved for ffmpeg/rclone in feature-video.

Unlike ffmpeg and rclone, Pencil Desktop is **not available in any standard package manager** (no brew cask, no apt package). It is distributed as:
- **macOS**: `.dmg` download from pencil.dev/downloads
- **Linux (Debian/Ubuntu)**: `.deb` download from pencil.dev/downloads
- **Linux (other)**: `.AppImage` download from pencil.dev/downloads
- **Windows**: Installer download from pencil.dev/downloads

This means the `install_tool()` pattern from feature-video needs adaptation: instead of `apt-get install`/`brew install`, the script must either download the package directly (with `curl`/`wget`) or print clear manual instructions with the download URL.

## Proposed Solution

### Architecture

```
plugins/soleur/skills/pencil-setup/
  SKILL.md          # Updated: add Phase 0 dependency check before Step 1
  scripts/
    check_deps.sh   # New: Pencil Desktop + IDE + CLI preflight checker
```

### Detection Strategy

Pencil Desktop can be detected three ways, in order of reliability:

1. **`pencil` CLI command** -- `command -v pencil` (installed via Desktop app's "File > Install pencil command into PATH")
2. **macOS app bundle** -- `test -d "/Applications/Pencil.app"` or `mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'"`
3. **Linux .desktop file** -- `test -f /usr/share/applications/pencil.desktop` or check for the binary in `/usr/bin/pencil` or `/opt/Pencil/`

The `pencil` CLI is the most portable check, but it requires the user to have explicitly installed it from the Desktop app menu. Falling back to platform-specific app detection catches users who installed the app but skipped the CLI step.

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

**Recommendation: Manual-only install guidance (no auto-download).** The `--auto` flag would only suppress interactive prompts for the IDE extension and MCP registration steps (which CAN be automated), not the Desktop app install.

### Script Structure (check_deps.sh)

```bash
#!/usr/bin/env bash
# pencil-setup dependency checker
# No set -euo pipefail: soft checks must not abort the script.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

OS="unknown"
[[ "$(uname -s)" == "Darwin" ]] && OS="macos"
[[ -f /etc/debian_version ]] && OS="debian"

# -- Functions (same pattern as feature-video) --

detect_pencil_desktop() {
  # Check CLI first (most portable)
  command -v pencil >/dev/null 2>&1 && return 0
  # Platform-specific fallbacks
  case "$OS" in
    macos) test -d "/Applications/Pencil.app" && return 0 ;;
    debian) dpkg -l pencil 2>/dev/null | grep -q '^ii' && return 0 ;;
  esac
  return 1
}

detect_ide() {
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

# 3. Soft dependency: Pencil IDE extension
BINARY=$(detect_extension "$IDE")
if [[ -n "$BINARY" ]]; then
  echo "  [ok] Pencil extension ($BINARY)"
else
  echo "  [MISSING] Pencil IDE extension"
  # attempt_install pattern: auto or prompt
  if [[ "$AUTO_INSTALL" == "true" ]]; then
    "${IDE}" --install-extension highagency.pencildev
  else
    echo "  Install extension? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      "${IDE}" --install-extension highagency.pencildev
    else
      echo "  [skip] Pencil extension (declined)"
    fi
  fi
  # Re-check
  BINARY=$(detect_extension "$IDE")
  if [[ -n "$BINARY" ]]; then
    echo "  [ok] Pencil extension installed"
  else
    echo "  [FAILED] Extension install -- try manually from IDE marketplace"
    exit 1
  fi
fi

# 4. Soft dependency: pencil CLI
if command -v pencil >/dev/null 2>&1; then
  echo "  [ok] pencil CLI"
else
  echo "  [info] pencil CLI not in PATH"
  echo "    Install via: Pencil Desktop > File > Install pencil command into PATH"
fi

echo
echo "=== Check Complete ==="
```

### SKILL.md Changes

Add Phase 0 before the existing Step 1:

```markdown
## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked
from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts
and install the IDE extension automatically:

For interactive use:
  bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh

For pipeline/automated use:
  bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto

If the script exits non-zero, a required dependency is missing. Stop and
inform the user with the printed instructions.

If all checks pass, proceed to Step 1 (Check if Already Registered).
```

## Technical Considerations

### Why Pencil Desktop is a Hard Dependency

Unlike ffmpeg/rclone in feature-video (soft dependencies that allow graceful degradation), Pencil Desktop is a **hard dependency** for the entire pencil-setup flow:
- The IDE extension (`highagency.pencildev`) embeds the MCP server binary
- The MCP server binary requires the Desktop app's runtime to function
- Without the Desktop app, the entire MCP registration is pointless

### No Auto-Download for Desktop Apps

The feature-video pattern uses `apt-get install`/`brew install` because those tools:
- Come from trusted, curated repositories
- Handle dependencies automatically
- Are idempotent and safe to run with `sudo`

Pencil Desktop is distributed as raw binaries (.dmg, .deb, .AppImage). Auto-downloading and installing these would:
- Require hardcoding or scraping version-specific URLs (fragile)
- Pipe untrusted downloads to `dpkg -i` or `hdiutil mount` (security concern)
- Require `sudo` for `.deb` installation without the safety of a package manager

The `--auto` flag applies only to the IDE extension install step (`cursor --install-extension`), not the Desktop app.

### Pencil CLI is Informational Only

The `pencil` CLI is not required for MCP setup. It is an experimental feature for batch design operations. The script reports its absence as `[info]` (not `[MISSING]`) and provides the path to install it from the Desktop app menu.

## Acceptance Criteria

- [ ] `scripts/check_deps.sh` created in `plugins/soleur/skills/pencil-setup/`
- [ ] Script uses the same `install_tool()`-family pattern as `feature-video/scripts/check_deps.sh`
- [ ] Pencil Desktop detected via `command -v pencil` with platform-specific fallbacks
- [ ] IDE (Cursor/VS Code) detected via `command -v`
- [ ] Pencil extension detected via glob in IDE extension directory
- [ ] `--auto` flag installs extension without prompting
- [ ] Missing Pencil Desktop prints platform-specific download URL and exits 1
- [ ] Missing IDE prints install URLs and exits 1
- [ ] Missing extension offers interactive install (or auto with `--auto`)
- [ ] Pencil CLI absence reported as informational, not blocking
- [ ] SKILL.md updated with Phase 0 linking to `check_deps.sh`
- [ ] Version bumped in plugin.json, CHANGELOG.md, README.md, marketplace.json

## Test Scenarios

- Given Pencil Desktop is installed and IDE has the extension, when running `check_deps.sh`, then all checks show `[ok]` and exit 0
- Given Pencil Desktop is NOT installed, when running `check_deps.sh`, then script prints download URL for the current OS and exits 1
- Given Pencil Desktop is installed but no IDE found, when running `check_deps.sh`, then script prints IDE install URLs and exits 1
- Given IDE is installed but extension is missing, when running `check_deps.sh` interactively, then prompted to install and responds N -- shows `[skip]` then exits 1 (extension is needed for MCP binary)
- Given `--auto` flag and extension is missing, when running `check_deps.sh --auto`, then extension installs without prompting
- Given all deps present but `pencil` CLI missing, when running `check_deps.sh`, then shows `[info]` for CLI and exits 0

## Dependencies & Risks

- **URL stability**: The pencil.dev/downloads URL must remain stable. If it changes, the script output is wrong but not broken (just stale URL).
- **Extension name stability**: `highagency.pencildev` is the current marketplace ID. A rename would break the glob and install command.
- **Desktop detection fragility**: The platform-specific app detection paths (`/Applications/Pencil.app`, `dpkg -l pencil`) may need adjustment as Pencil Desktop evolves its installation structure.

## References & Research

- PR #337: [feat(feature-video): add on-demand ffmpeg and rclone installation](https://github.com/jikig-ai/soleur/pull/337)
- Reference script: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- Pencil Desktop downloads: https://www.pencil.dev/downloads
- Pencil CLI docs: https://docs.pencil.dev/for-developers/pencil-cli
- Pencil installation docs: https://docs.pencil.dev/getting-started/installation
- Learning: `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Learning: `knowledge-base/learnings/2026-02-27-parameterized-shell-install-eliminates-duplication.md`
- Learning: `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Learning: `knowledge-base/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md`
