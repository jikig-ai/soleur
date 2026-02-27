#!/usr/bin/env bash
# pencil-setup dependency checker with optional auto-install for IDE extension
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each check uses explicit if/then.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Detect OS and architecture for platform-specific checks
OS="unknown"
[[ "$(uname -s)" == "Darwin" ]] && OS="macos"
[[ "$(uname -s)" == "Linux" ]] && OS="linux"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  MCP_SUFFIX="x64" ;;
  aarch64|arm64) MCP_SUFFIX="arm64" ;;
  *)       MCP_SUFFIX="x64" ;;
esac

# -- Detection Functions --

detect_pencil_desktop() {
  case "$OS" in
    macos)
      test -d "/Applications/Pencil.app" && return 0
      # Spotlight fallback for non-standard install locations
      # TODO: verify bundle ID 'dev.pencil.desktop' against actual Pencil.app Info.plist
      mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
      ;;
    linux)
      # Pencil Desktop is distributed as AppImage on Linux (no .deb/.rpm)
      # Check common AppImage locations
      for dir in "$HOME/Applications" "$HOME/.local/bin" "/opt"; do
        ls "$dir"/Pencil*.AppImage 2>/dev/null | grep -q . && return 0
      done
      ;;
  esac
  # Cross-platform fallback: pencil CLI (requires explicit install from Desktop menu)
  command -v pencil >/dev/null 2>&1 && return 0
  return 1
}

# Returns the MCP binary path from Pencil Desktop if directly accessible
detect_desktop_binary() {
  local binary=""
  case "$OS" in
    macos)
      # App bundle exposes the binary at a stable path
      binary=$(ls "/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-${MCP_SUFFIX}" 2>/dev/null)
      ;;
    linux)
      # AppImage binary is not directly accessible without extraction.
      # Check if user extracted the AppImage to a known location.
      for dir in "$HOME/Applications" "$HOME/.local/bin" "/opt"; do
        binary=$(ls "$dir"/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-"${MCP_SUFFIX}" 2>/dev/null | head -1)
        [[ -n "$binary" ]] && break
      done
      ;;
  esac
  [[ -n "$binary" && -x "$binary" ]] && echo "$binary"
}

detect_ide() {
  # Prefer Cursor over VS Code (Pencil docs recommend Cursor)
  command -v cursor >/dev/null 2>&1 && echo "cursor" && return 0
  command -v code >/dev/null 2>&1 && echo "code" && return 0
  return 1
}

detect_extension() {
  local ide="$1"
  local extdir os_prefix
  case "$ide" in
    cursor) extdir="$HOME/.cursor/extensions" ;;
    code)   extdir="$HOME/.vscode/extensions" ;;
    *)      return 1 ;;
  esac
  case "$OS" in
    macos) os_prefix="darwin" ;;
    linux) os_prefix="linux" ;;
    *)     os_prefix="linux" ;;
  esac
  ls -d "${extdir}/highagency.pencildev-"*/out/mcp-server-"${os_prefix}-${MCP_SUFFIX}" 2>/dev/null | sort -V | tail -1
}

echo "=== Pencil Setup Dependency Check ==="
echo

# 1. Hard dependency: IDE (Cursor or VS Code)
IDE=$(detect_ide)
if [[ -n "$IDE" ]]; then
  echo "  [ok] IDE: $IDE"
else
  echo "  [MISSING] No supported IDE (Cursor or VS Code)"
  echo "    Install Cursor: https://cursor.com"
  echo "    Install VS Code: https://code.visualstudio.com"
  exit 1
fi

# 2. Hard dependency: Pencil IDE extension (auto-installable)
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

# 3. Pencil Desktop: optional but preferred when available
DESKTOP_BINARY=$(detect_desktop_binary)
if detect_pencil_desktop; then
  if [[ -n "$DESKTOP_BINARY" ]]; then
    echo "  [ok] Pencil Desktop (MCP binary available)"
    echo "    Provides: standalone .pen editing, pencil CLI, bundled AI SDKs"
    echo "    MCP binary: $DESKTOP_BINARY"
    BINARY="$DESKTOP_BINARY"
  else
    echo "  [ok] Pencil Desktop"
    echo "    Provides: standalone .pen editing, pencil CLI"
    if [[ "$OS" == "linux" ]]; then
      echo "    Tip: extract AppImage with --appimage-extract for direct MCP binary access"
    fi
  fi
else
  echo "  [info] Pencil Desktop not found (recommended)"
  echo "    Unlocks: standalone .pen editing, pencil CLI, bundled AI SDKs"
  case "$OS" in
    macos) echo "    Download: https://www.pencil.dev/downloads (macOS .dmg)" ;;
    linux) echo "    Download: https://www.pencil.dev/downloads (Linux AppImage)" ;;
    *)     echo "    Download: https://www.pencil.dev/downloads" ;;
  esac
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

# Output preferred binary for SKILL.md consumption
echo
echo "PREFERRED_BINARY=$BINARY"
