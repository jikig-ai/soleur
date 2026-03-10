#!/usr/bin/env bash
# pencil-setup dependency checker with three-tier MCP detection
# Priority: (1) pencil CLI, (2) Desktop binary, (3) IDE extension
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each check uses explicit if/then.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Detect OS and architecture for platform-specific checks
_UNAME=$(uname -s)
OS="unknown"
[[ "$_UNAME" == "Darwin" ]] && OS="macos"
[[ "$_UNAME" == "Linux" ]] && OS="linux"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  MCP_SUFFIX="x64" ;;
  aarch64|arm64) MCP_SUFFIX="arm64" ;;
  *)       MCP_SUFFIX="x64" ;;
esac

# Output variables (consumed by SKILL.md)
PREFERRED_BINARY=""
PREFERRED_APP=""
PREFERRED_MODE=""

# Common AppImage search directories (single source of truth)
APPIMAGE_DIRS=("$HOME/Applications" "$HOME/.local/bin" "/opt")

# -- Shared Helpers --

# Find the first Pencil AppImage in known directories
find_appimage() {
  local dir match
  for dir in "${APPIMAGE_DIRS[@]}"; do
    for match in "$dir"/Pencil*.AppImage; do
      [[ -e "$match" ]] && echo "$match" && return 0
    done
  done
  return 1
}

# Find extracted AppImage MCP binary in known directories
find_extracted_mcp_binary() {
  local dir binary
  for dir in "${APPIMAGE_DIRS[@]}"; do
    binary="$dir/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-${MCP_SUFFIX}"
    [[ -x "$binary" ]] && echo "$binary" && return 0
  done
  return 1
}

# -- Detection Functions --

# Check if the pencil CLI in PATH is pencil.dev (not evolus/pencil)
detect_pencil_cli() {
  command -v pencil >/dev/null 2>&1 || return 1
  # Guard against evolus/pencil name collision
  if pencil --version 2>&1 | grep -qi "pencil\.dev\|pencil v"; then
    return 0
  fi
  # If --version doesn't confirm pencil.dev, check if mcp-server subcommand exists
  pencil mcp-server --help >/dev/null 2>&1 && return 0
  return 1
}

detect_pencil_desktop() {
  case "$OS" in
    macos)
      [[ -d "/Applications/Pencil.app" ]] && return 0
      # Spotlight fallback for non-standard install locations
      mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
      ;;
    linux)
      # Check .deb installation
      dpkg -s pencil 2>/dev/null | grep -q "Status:.*installed" && return 0
      # Check AppImage
      find_appimage >/dev/null && return 0
      ;;
  esac
  return 1
}

# Returns the MCP binary path from Pencil Desktop if directly accessible
detect_desktop_binary() {
  local binary=""
  case "$OS" in
    macos)
      binary="/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-${MCP_SUFFIX}"
      [[ -x "$binary" ]] && echo "$binary" && return 0
      ;;
    linux)
      # .deb install: check system path
      binary="/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-${MCP_SUFFIX}"
      [[ -x "$binary" ]] && echo "$binary" && return 0
      # AppImage: binary is only accessible if user extracted it
      find_extracted_mcp_binary && return 0
      ;;
  esac
  return 1
}

detect_ide() {
  # Prefer Cursor over VS Code (Pencil docs recommend Cursor)
  command -v cursor >/dev/null 2>&1 && echo "cursor" && return 0
  command -v code >/dev/null 2>&1 && echo "code" && return 0
  return 1
}

# Map IDE command name to --app flag value
ide_to_app_value() {
  case "$1" in
    cursor) echo "cursor" ;;
    code)   echo "visual_studio_code" ;;
    *)      echo "ERROR: unknown IDE '$1'" >&2; return 1 ;;
  esac
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

# Check if Pencil Desktop is currently running (platform-specific to avoid false positives)
is_pencil_running() {
  case "$OS" in
    macos)
      pgrep -f "Pencil.app/Contents/MacOS" >/dev/null 2>&1
      ;;
    linux)
      # Match exact process name (from .deb) or AppImage pattern
      pgrep -x pencil >/dev/null 2>&1 || pgrep -f "Pencil.*AppImage" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# Attempt to install IDE extension (prompt or auto-install)
attempt_extension_install() {
  local ide="$1"
  local response=""
  if [[ "$AUTO_INSTALL" != "true" ]]; then
    if [[ -t 0 ]]; then
      echo "  Install extension? (y/N)"
      read -r response
    else
      echo "  [info] Non-interactive shell -- use --auto to install automatically"
      return 1
    fi
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "  [MISSING] Pencil extension (declined)"
      return 1
    fi
  fi
  echo "  [installing] Pencil extension..."
  if "$ide" --install-extension highagency.pencildev 2>&1; then
    local binary
    binary=$(detect_extension "$ide")
    if [[ -n "$binary" ]]; then
      echo "  [ok] Pencil extension (installed)"
      echo "$binary"
      return 0
    else
      echo "  [FAILED] Extension installed but binary not found -- restart $ide and re-run"
      return 1
    fi
  else
    echo "  [FAILED] Extension install command returned non-zero -- try manually from IDE marketplace"
    echo "    Search for 'Pencil' in the $ide Extensions panel, or visit:"
    echo "    https://docs.pencil.dev/getting-started/installation"
    return 1
  fi
}

# Launch Pencil Desktop if installed but not running (requires --auto)
auto_launch_desktop() {
  if is_pencil_running; then
    echo "  [ok] Pencil Desktop is running"
    return 0
  fi
  if [[ "$AUTO_INSTALL" != "true" ]]; then
    echo "  [info] Pencil Desktop is not running -- use --auto to launch automatically"
    return 1
  fi
  echo "  [info] Starting Pencil Desktop..."
  case "$OS" in
    macos)
      if [[ -d "/Applications/Pencil.app" ]]; then
        open "/Applications/Pencil.app"
      else
        echo "  [FAILED] Cannot locate Pencil.app to launch"
        return 1
      fi
      ;;
    linux)
      # Check if display server is available
      if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        echo "  [FAILED] No display server available (DISPLAY and WAYLAND_DISPLAY unset)"
        return 1
      fi
      # Only launch the validated pencil.dev binary or AppImage (not arbitrary 'pencil' in PATH)
      if detect_pencil_cli; then
        nohup pencil >/dev/null 2>&1 &
      else
        local appimage
        appimage=$(find_appimage)
        if [[ -n "$appimage" ]]; then
          echo "  [info] Launching $appimage"
          nohup "$appimage" >/dev/null 2>&1 &
        else
          echo "  [FAILED] Cannot locate Pencil binary to launch"
          return 1
        fi
      fi
      ;;
    *)
      echo "  [FAILED] Unsupported OS for auto-launch"
      return 1
      ;;
  esac
  # Wait for Desktop to initialize (poll up to 3 times at 2s intervals)
  local attempts=0
  while [[ $attempts -lt 3 ]]; do
    sleep 2
    if is_pencil_running; then
      echo "  [ok] Pencil Desktop started"
      return 0
    fi
    attempts=$((attempts + 1))
  done
  echo "  [FAILED] Pencil Desktop did not start within 6 seconds"
  return 1
}

# -- Tier Functions (early-exit pattern) --

try_cli_tier() {
  detect_pencil_cli || return 1
  echo "  [ok] pencil CLI (pencil.dev)"
  PREFERRED_MODE="cli"
  PREFERRED_BINARY="pencil"
  PREFERRED_APP=""
  # Auto-launch Desktop if installed (CLI needs Desktop running to connect)
  if detect_pencil_desktop; then
    auto_launch_desktop
  fi
  return 0
}

try_desktop_tier() {
  detect_pencil_desktop || return 1
  local binary
  binary=$(detect_desktop_binary)
  if [[ -n "$binary" ]]; then
    echo "  [ok] Pencil Desktop (MCP binary available)"
    echo "    MCP binary: $binary"
    PREFERRED_MODE="desktop_binary"
    PREFERRED_BINARY="$binary"
    PREFERRED_APP="pencil"
    auto_launch_desktop
    return 0
  fi
  # Desktop installed but binary not directly accessible
  echo "  [ok] Pencil Desktop (no direct MCP binary access)"
  if [[ "$OS" == "linux" ]]; then
    echo "    Tip: extract AppImage with --appimage-extract for direct MCP binary access"
    echo "    Or install pencil CLI: Pencil Desktop > File > Install pencil command into PATH"
  else
    echo "    Install pencil CLI: Pencil Desktop > File > Install pencil command into PATH"
  fi
  return 1
}

try_ide_tier() {
  local ide binary
  ide=$(detect_ide) || return 1
  echo "  [ok] IDE: $ide"
  binary=$(detect_extension "$ide")
  if [[ -n "$binary" ]]; then
    echo "  [ok] Pencil extension"
    PREFERRED_MODE="ide"
    PREFERRED_BINARY="$binary"
    PREFERRED_APP=$(ide_to_app_value "$ide")
    return 0
  fi
  echo "  [MISSING] Pencil IDE extension"
  binary=$(attempt_extension_install "$ide") || return 1
  PREFERRED_MODE="ide"
  PREFERRED_BINARY="$binary"
  PREFERRED_APP=$(ide_to_app_value "$ide")
  return 0
}

# -- Main Flow --

echo "=== Pencil Setup Dependency Check ==="
echo

# Warn about evolus/pencil collision
if ! detect_pencil_cli && command -v pencil >/dev/null 2>&1; then
  echo "  [info] pencil CLI found but is not pencil.dev (possible evolus/pencil)"
fi

# Try tiers in priority order -- first success wins
try_cli_tier || try_desktop_tier || try_ide_tier

# -- Result --
echo
if [[ -n "$PREFERRED_MODE" ]]; then
  echo "=== Check Complete ==="
  echo
  echo "PREFERRED_MODE=$PREFERRED_MODE"
  echo "PREFERRED_BINARY=$PREFERRED_BINARY"
  echo "PREFERRED_APP=$PREFERRED_APP"
else
  echo "=== Check Failed ==="
  echo
  echo "  No Pencil MCP source available. Install one of:"
  echo
  echo "  Option 1 (recommended): Pencil Desktop"
  case "$OS" in
    macos) echo "    Download: https://www.pencil.dev/downloads (macOS .dmg)" ;;
    linux) echo "    Download: https://www.pencil.dev/downloads (Linux .deb or AppImage)" ;;
    *)     echo "    Download: https://www.pencil.dev/downloads" ;;
  esac
  echo "    Then: File > Install pencil command into PATH"
  echo
  echo "  Option 2: IDE extension"
  echo "    Install Cursor (https://cursor.com) or VS Code (https://code.visualstudio.com)"
  echo "    Then install the Pencil extension from the marketplace"
  exit 1
fi
