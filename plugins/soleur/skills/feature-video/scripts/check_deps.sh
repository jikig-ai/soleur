#!/usr/bin/env bash
# feature-video dependency checker with optional auto-install
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each install uses explicit if/then checks.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Ensure ~/.local/bin is in PATH for user-local installs
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# Detect OS for install commands
OS="unknown"
[[ "$(uname -s)" == "Darwin" ]] && OS="macos"
[[ "$(uname -s)" == "Linux" ]] && OS="linux"

# Detect architecture for static binary downloads
ARCH_SUFFIX=""
case "$(uname -m)" in
  x86_64)        ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
esac

install_ffmpeg_linux() {
  local arch_suffix="$1"
  if [[ -z "$arch_suffix" ]]; then
    echo "  Unsupported architecture: $(uname -m). Install ffmpeg manually." >&2
    return 1
  fi
  local url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${arch_suffix}-static.tar.xz"
  echo "  Downloading ffmpeg static build (~80MB)..."
  mkdir -p "$HOME/.local/bin"
  if curl -sL "$url" | tar -xJf - --strip-components=1 -C "$HOME/.local/bin" --wildcards '*/ffmpeg'; then
    chmod +x "$HOME/.local/bin/ffmpeg"
    return 0
  else
    echo "  Download failed. Install ffmpeg manually: https://johnvansickle.com/ffmpeg/" >&2
    return 1
  fi
}

install_rclone_linux() {
  local arch_suffix="$1"
  if [[ -z "$arch_suffix" ]]; then
    echo "  Unsupported architecture: $(uname -m). Install rclone manually." >&2
    return 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "  unzip is required to install rclone. Install unzip first." >&2
    return 1
  fi
  local url="https://downloads.rclone.org/rclone-current-linux-${arch_suffix}.zip"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  echo "  Downloading rclone (~25MB)..."
  mkdir -p "$HOME/.local/bin"
  if curl -sL "$url" -o "$tmpdir/rclone.zip" && \
     unzip -q "$tmpdir/rclone.zip" -d "$tmpdir" && \
     cp "$tmpdir"/rclone-*/rclone "$HOME/.local/bin/rclone" && \
     chmod +x "$HOME/.local/bin/rclone"; then
    rm -rf "$tmpdir"
    trap - EXIT
    return 0
  else
    echo "  Download failed. Install rclone manually: https://rclone.org/install/" >&2
    rm -rf "$tmpdir"
    trap - EXIT
    return 1
  fi
}

install_tool() {
  local tool="$1"
  if ! command -v curl >/dev/null 2>&1; then
    echo "  curl is required for auto-install. Install curl first." >&2
    return 1
  fi
  case "$OS" in
    linux)
      case "$tool" in
        ffmpeg) install_ffmpeg_linux "$ARCH_SUFFIX" ;;
        rclone) install_rclone_linux "$ARCH_SUFFIX" ;;
        *)
          echo "  No installer for $tool. Install manually." >&2
          return 1
          ;;
      esac
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install "$tool"
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi
      ;;
    *)
      echo "  Unsupported OS. Install $tool manually." >&2
      return 1
      ;;
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
  echo "    Install: npm install -g agent-browser@0.21.4 && agent-browser install"
  echo "    On Linux: agent-browser install --with-deps (if system deps missing)"
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
