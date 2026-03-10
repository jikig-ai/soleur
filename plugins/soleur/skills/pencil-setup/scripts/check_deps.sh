#!/usr/bin/env bash
# pencil-setup dependency checker with three-tier MCP detection
# Priority: (1) pencil CLI, (2) Desktop binary, (3) IDE extension
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

# Output variables (consumed by SKILL.md)
PREFERRED_BINARY=""
PREFERRED_APP=""
PREFERRED_MODE=""

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
      test -d "/Applications/Pencil.app" && return 0
      # Spotlight fallback for non-standard install locations
      mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
      ;;
    linux)
      # Check .deb installation
      dpkg -s pencil 2>/dev/null | grep -q "Status:.*installed" && return 0
      # Check common AppImage locations
      for dir in "$HOME/Applications" "$HOME/.local/bin" "/opt"; do
        ls "$dir"/Pencil*.AppImage 2>/dev/null | grep -q . && return 0
      done
      ;;
  esac
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
      # .deb install: check system path
      binary=$(ls "/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-${MCP_SUFFIX}" 2>/dev/null)
      if [[ -z "$binary" ]]; then
        # AppImage: binary is only accessible if user extracted it
        for dir in "$HOME/Applications" "$HOME/.local/bin" "/opt"; do
          binary=$(ls "$dir"/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-"${MCP_SUFFIX}" 2>/dev/null | head -1)
          [[ -n "$binary" ]] && break
        done
      fi
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

# Map IDE command name to --app flag value
ide_to_app_value() {
  case "$1" in
    cursor) echo "cursor" ;;
    code)   echo "visual_studio_code" ;;
    *)      echo "$1" ;;
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

# Check if Pencil Desktop is currently running
is_pencil_running() {
  pgrep -f "[Pp]encil" >/dev/null 2>&1
}

# Launch Pencil Desktop if installed but not running
auto_launch_desktop() {
  if is_pencil_running; then
    echo "  [ok] Pencil Desktop is running"
    return 0
  fi
  echo "  [info] Pencil Desktop is not running"
  if [[ "$AUTO_INSTALL" != "true" ]]; then
    return 1
  fi
  echo "  [launching] Starting Pencil Desktop..."
  case "$OS" in
    macos)
      if test -d "/Applications/Pencil.app"; then
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
      # Try .deb install first, then AppImage
      if command -v pencil >/dev/null 2>&1; then
        nohup pencil >/dev/null 2>&1 &
      else
        local appimage=""
        for dir in "$HOME/Applications" "$HOME/.local/bin" "/opt"; do
          appimage=$(ls "$dir"/Pencil*.AppImage 2>/dev/null | head -1)
          [[ -n "$appimage" ]] && break
        done
        if [[ -n "$appimage" ]]; then
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

echo "=== Pencil Setup Dependency Check ==="
echo

# -- Tier 1: pencil CLI in PATH --
if detect_pencil_cli; then
  echo "  [ok] pencil CLI (pencil.dev)"
  PREFERRED_MODE="cli"
  PREFERRED_BINARY="pencil"
  PREFERRED_APP=""
  # Attempt auto-launch if Desktop is installed but not running
  if detect_pencil_desktop; then
    auto_launch_desktop
  fi
else
  if command -v pencil >/dev/null 2>&1; then
    echo "  [info] pencil CLI found but is not pencil.dev (possible evolus/pencil)"
  fi

  # -- Tier 2: Desktop binary directly accessible --
  DESKTOP_BINARY=$(detect_desktop_binary)
  if detect_pencil_desktop; then
    if [[ -n "$DESKTOP_BINARY" ]]; then
      echo "  [ok] Pencil Desktop (MCP binary available)"
      echo "    MCP binary: $DESKTOP_BINARY"
      PREFERRED_MODE="desktop_binary"
      PREFERRED_BINARY="$DESKTOP_BINARY"
      PREFERRED_APP="pencil"
      auto_launch_desktop
    else
      echo "  [ok] Pencil Desktop (no direct MCP binary access)"
      if [[ "$OS" == "linux" ]]; then
        echo "    Tip: extract AppImage with --appimage-extract for direct MCP binary access"
        echo "    Or install pencil CLI: Pencil Desktop > File > Install pencil command into PATH"
      else
        echo "    Install pencil CLI: Pencil Desktop > File > Install pencil command into PATH"
      fi
      # Desktop found but binary not accessible -- fall through to IDE tier
    fi
  fi

  # -- Tier 3: IDE with Pencil extension --
  if [[ -z "$PREFERRED_MODE" ]]; then
    IDE=$(detect_ide)
    if [[ -n "$IDE" ]]; then
      echo "  [ok] IDE: $IDE"
      BINARY=$(detect_extension "$IDE")
      if [[ -n "$BINARY" ]]; then
        echo "  [ok] Pencil extension"
        PREFERRED_MODE="ide"
        PREFERRED_BINARY="$BINARY"
        PREFERRED_APP=$(ide_to_app_value "$IDE")
      else
        echo "  [MISSING] Pencil IDE extension"
        if [[ "$AUTO_INSTALL" != "true" ]]; then
          echo "  Install extension? (y/N)"
          read -r response
          if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "  [MISSING] Pencil extension (declined)"
          fi
        fi
        if [[ "$AUTO_INSTALL" == "true" ]] || [[ "${response:-}" =~ ^[Yy]$ ]]; then
          echo "  [installing] Pencil extension..."
          if "$IDE" --install-extension highagency.pencildev 2>&1; then
            BINARY=$(detect_extension "$IDE")
            if [[ -n "$BINARY" ]]; then
              echo "  [ok] Pencil extension (installed)"
              PREFERRED_MODE="ide"
              PREFERRED_BINARY="$BINARY"
              PREFERRED_APP=$(ide_to_app_value "$IDE")
            else
              echo "  [FAILED] Extension installed but binary not found -- restart $IDE and re-run"
            fi
          else
            echo "  [FAILED] Extension install command returned non-zero -- try manually from IDE marketplace"
            echo "    Search for 'Pencil' in the $IDE Extensions panel, or visit:"
            echo "    https://docs.pencil.dev/getting-started/installation"
          fi
        fi
      fi
    else
      echo "  [info] No supported IDE (Cursor or VS Code)"
    fi
  fi
fi

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
