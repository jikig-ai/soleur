#!/usr/bin/env bash
# feature-video dependency checker with optional auto-install
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each install uses explicit if/then checks.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Detect OS for install commands
OS="unknown"
[[ "$(uname -s)" == "Darwin" ]] && OS="macos"
[[ -f /etc/debian_version ]] && OS="debian"

install_tool() {
  local tool="$1"
  case "$OS" in
    debian)
      if sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y "$tool"
      else
        echo "  Run manually: sudo apt-get install -y $tool" >&2
        return 1
      fi ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install "$tool"
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi ;;
    *)
      echo "  Unsupported OS. Install $tool manually." >&2
      return 1 ;;
  esac
}

verify_install() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [ok] $tool (installed)"
  else
    echo "  [FAILED] $tool installed but not found in PATH"
    echo "    Try opening a new terminal or check your PATH"
  fi
}

attempt_install() {
  local tool="$1"

  if [[ "$AUTO_INSTALL" != "true" ]]; then
    echo "  $tool not installed. Install it? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "  [skip] $tool (declined)"
      return
    fi
  fi

  echo "  [installing] $tool..."
  if install_tool "$tool"; then
    verify_install "$tool"
  else
    echo "  [FAILED] $tool installation"
  fi
}

echo "=== feature-video Dependency Check ==="
echo

# Hard dependency -- cannot record without this
if command -v agent-browser >/dev/null 2>&1; then
  echo "  [ok] agent-browser"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install -g agent-browser && agent-browser install"
  echo
  echo "Cannot proceed without agent-browser."
  exit 1
fi

# Soft dependency: ffmpeg (video/GIF conversion)
if command -v ffmpeg >/dev/null 2>&1; then
  echo "  [ok] ffmpeg"
else
  attempt_install "ffmpeg"
fi

# Soft dependency: rclone (cloud upload)
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
  attempt_install "rclone"
fi

echo
echo "=== Check Complete ==="
