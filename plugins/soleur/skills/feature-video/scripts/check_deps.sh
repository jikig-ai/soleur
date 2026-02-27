#!/usr/bin/env bash
# feature-video dependency checker with optional auto-install
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each install uses explicit if/then checks.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

echo "=== feature-video Dependency Check ==="
echo

# --- OS detection ---
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -f /etc/debian_version ]]; then echo "debian"
      else echo "unknown"
      fi ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)

# --- Install helpers ---
install_ffmpeg() {
  case "$OS" in
    debian)
      if sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y ffmpeg
      else
        echo "  Run manually: sudo apt-get install -y ffmpeg" >&2
        return 1
      fi ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi ;;
    *)
      echo "  Manual install: https://ffmpeg.org/download.html" >&2
      return 1 ;;
  esac
}

install_rclone() {
  case "$OS" in
    debian)
      if sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y rclone
      else
        echo "  Run manually: sudo apt-get install -y rclone" >&2
        return 1
      fi ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install rclone
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi ;;
    *)
      echo "  Manual install: https://rclone.org/install/" >&2
      return 1 ;;
  esac
}

# --- Attempt install of a soft dependency ---
# Usage: attempt_install <tool-name> <install-function>
attempt_install() {
  local tool_name="$1"
  local install_fn="$2"

  if [[ "$AUTO_INSTALL" == "true" ]]; then
    echo "  [installing] $tool_name..."
    if $install_fn; then
      if command -v "$tool_name" >/dev/null 2>&1; then
        echo "  [ok] $tool_name ($($tool_name --version 2>/dev/null | head -1 || echo 'installed'))"
      else
        echo "  [FAILED] $tool_name installed but not found in PATH"
        echo "    Try opening a new terminal or check your PATH"
      fi
    else
      echo "  [FAILED] $tool_name installation"
    fi
  else
    echo "  $tool_name not installed. Install it? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "  [installing] $tool_name..."
      if $install_fn; then
        if command -v "$tool_name" >/dev/null 2>&1; then
          echo "  [ok] $tool_name ($($tool_name --version 2>/dev/null | head -1 || echo 'installed'))"
        else
          echo "  [FAILED] $tool_name installed but not found in PATH"
          echo "    Try opening a new terminal or check your PATH"
        fi
      else
        echo "  [FAILED] $tool_name installation"
      fi
    else
      echo "  [skip] $tool_name (declined)"
    fi
  fi
}

# --- Hard dependency: agent-browser ---
if command -v agent-browser >/dev/null 2>&1; then
  echo "  [ok] agent-browser"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install -g agent-browser && agent-browser install"
  echo
  echo "Cannot proceed without agent-browser."
  exit 1
fi

# --- Soft dependency: ffmpeg (video/GIF conversion) ---
if command -v ffmpeg >/dev/null 2>&1; then
  echo "  [ok] ffmpeg"
else
  attempt_install "ffmpeg" "install_ffmpeg"
fi

# --- Soft dependency: rclone (cloud upload) ---
if command -v rclone >/dev/null 2>&1; then
  echo "  [ok] rclone"
  REMOTES=$(rclone listremotes 2>/dev/null || true)
  if [ -z "$REMOTES" ]; then
    echo "  [skip] rclone: no remotes configured (see rclone skill)"
  else
    REMOTE_COUNT=$(echo "$REMOTES" | wc -l | tr -d ' ')
    echo "  [ok] rclone: $REMOTE_COUNT remote(s) configured"
  fi
else
  attempt_install "rclone" "install_rclone"
fi

echo
echo "=== Check Complete ==="
