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
  # Platform-specific checks first (avoid pencil CLI name collision with evolus/pencil)
  case "$OS" in
    macos)
      test -d "/Applications/Pencil.app" && return 0
      # Spotlight fallback for non-standard install locations
      # TODO: verify bundle ID 'dev.pencil.desktop' against actual Pencil.app Info.plist
      mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
      ;;
    debian)
      # TODO: verify .deb package name -- may be 'pencil-desktop' or 'pencil-app', not 'pencil'
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

# 3. Hard dependency: Pencil IDE extension (auto-installable)
BINARY=$(detect_extension "$IDE")
if [[ -n "$BINARY" ]]; then
  echo "  [ok] Pencil extension"
else
  echo "  [MISSING] Pencil IDE extension"
  if [[ "$AUTO_INSTALL" != "true" ]]; then
    echo "  Install extension? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "  [MISSING] Pencil extension (declined -- required, cannot continue)"
      exit 1
    fi
  fi
  echo "  [installing] Pencil extension..."
  if ! "$IDE" --install-extension highagency.pencildev 2>&1; then
    echo "  [WARN] Extension install command returned non-zero"
  fi
  # Re-check after install attempt
  BINARY=$(detect_extension "$IDE")
  if [[ -n "$BINARY" ]]; then
    echo "  [ok] Pencil extension (installed)"
  else
    echo "  [FAILED] Extension install -- try manually from IDE marketplace"
    echo "    Search for 'Pencil' in the $IDE Extensions panel, or visit:"
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
