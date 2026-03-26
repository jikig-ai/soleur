#!/usr/bin/env bash
# feature-video dependency checker with optional auto-install
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each install uses explicit if/then checks.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

# Ensure ~/.local/bin is in PATH for user-local installs
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# Detect OS for install commands
_UNAME=$(uname -s)
OS="unknown"
[[ "$_UNAME" == "Darwin" ]] && OS="macos"
[[ "$_UNAME" == "Linux" ]] && OS="linux"

# Detect architecture for static binary downloads
ARCH=$(uname -m)
ARCH_SUFFIX=""
case "$ARCH" in
  x86_64)        ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
esac

# BtbN uses different arch names than rclone
FFMPEG_ARCH=""
case "$ARCH" in
  x86_64)        FFMPEG_ARCH="linux64" ;;
  aarch64|arm64) FFMPEG_ARCH="linuxarm64" ;;
esac

# --- Pinned Versions ---
# To update: change version/build constants, fetch new checksums, update SHA256 constants.
#
# rclone:
#   1. Pick version from https://downloads.rclone.org/
#   2. Fetch checksums: curl -sL https://downloads.rclone.org/v<NEW_VERSION>/SHA256SUMS
#   3. Extract hashes for linux-amd64.zip and linux-arm64.zip
#
# ffmpeg (BtbN autobuilds):
#   1. Find latest autobuild tag:
#      curl -s "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases" | jq '.[1].tag_name'
#      (index 1 because index 0 is the floating "latest" tag)
#   2. Fetch checksums and extract build ID:
#      curl -sL "https://github.com/BtbN/FFmpeg-Builds/releases/download/<tag>/checksums.sha256" \
#        | grep linux64-gpl.tar.xz | grep -v shared
#      Output: <hash>  ffmpeg-N-XXXXX-g<hash>-linux64-gpl.tar.xz
#      The BUILD_ID is the "N-XXXXX-g<hash>" portion of the filename
#   3. Update FFMPEG_AUTOBUILD (date from tag), FFMPEG_BUILD_ID, and both SHA256 constants

RCLONE_VERSION="1.73.2"
FFMPEG_AUTOBUILD="2026-03-20-13-06"
FFMPEG_BUILD_ID="N-123570-gf72f692afa"

# rclone checksums (from https://downloads.rclone.org/v1.73.2/SHA256SUMS)
RCLONE_SHA256_AMD64="00a1d8cb85552b7b07bb0416559b2e78fcf9c6926662a52682d81b5f20c90535"
RCLONE_SHA256_ARM64="2f7d8b807e6ea638855129052c834ca23aa538d3ad7786e30b8ad1e97c5db47b"

# ffmpeg checksums (from BtbN autobuild-2026-03-20-13-06 checksums.sha256)
FFMPEG_SHA256_LINUX64="f550cd5fad7bc9045f9e6b4370204ddd245b8120f6bc193e0c09c58569e3cb32"
FFMPEG_SHA256_LINUXARM64="89b959bed4b6d63bad2d85870468a9a52cf84efd216a12fbf577a011ef391644"

verify_checksum() {
  local file="$1"
  local expected="$2"
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ "$actual" != "$expected" ]]; then
    echo "  CHECKSUM MISMATCH for $file" >&2
    echo "  Expected: $expected" >&2
    echo "  Got:      $actual" >&2
    return 1
  fi
  echo "  [ok] checksum verified"
}

install_ffmpeg_linux() {
  local ffmpeg_arch="$1"
  if [[ -z "$ffmpeg_arch" ]]; then
    echo "  Unsupported architecture: $ARCH. Install ffmpeg manually." >&2
    return 1
  fi
  if ! tar --help >/dev/null 2>&1 || ! xz --help >/dev/null 2>&1; then
    echo "  tar and xz are required to install ffmpeg. Install them first." >&2
    return 1
  fi
  local filename="ffmpeg-${FFMPEG_BUILD_ID}-${ffmpeg_arch}-gpl.tar.xz"
  local url="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-${FFMPEG_AUTOBUILD}/${filename}"
  local expected
  case "$ffmpeg_arch" in
    linux64)    expected="$FFMPEG_SHA256_LINUX64" ;;
    linuxarm64) expected="$FFMPEG_SHA256_LINUXARM64" ;;
    *) echo "  No checksum available for architecture: $ffmpeg_arch" >&2; return 1 ;;
  esac
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN
  echo "  Downloading ffmpeg (autobuild ${FFMPEG_AUTOBUILD})..."
  mkdir -p "$HOME/.local/bin"
  if ! curl -sfL "$url" -o "$tmpdir/ffmpeg.tar.xz"; then
    echo "  Download failed. Install ffmpeg manually: https://github.com/BtbN/FFmpeg-Builds/releases" >&2
    return 1
  fi
  if ! verify_checksum "$tmpdir/ffmpeg.tar.xz" "$expected"; then
    return 1
  fi
  tar -xJf "$tmpdir/ffmpeg.tar.xz" -C "$tmpdir"
  cp "$tmpdir"/ffmpeg-*/bin/ffmpeg "$HOME/.local/bin/ffmpeg"
  chmod +x "$HOME/.local/bin/ffmpeg"
}

install_rclone_linux() {
  local arch_suffix="$1"
  if [[ -z "$arch_suffix" ]]; then
    echo "  Unsupported architecture: $ARCH. Install rclone manually." >&2
    return 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "  unzip is required to install rclone. Install unzip first." >&2
    return 1
  fi
  local url="https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${arch_suffix}.zip"
  local expected
  case "$arch_suffix" in
    amd64) expected="$RCLONE_SHA256_AMD64" ;;
    arm64) expected="$RCLONE_SHA256_ARM64" ;;
    *) echo "  No checksum available for architecture: $arch_suffix" >&2; return 1 ;;
  esac
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN
  echo "  Downloading rclone v${RCLONE_VERSION}..."
  mkdir -p "$HOME/.local/bin"
  if ! curl -sfL "$url" -o "$tmpdir/rclone.zip"; then
    echo "  Download failed. Install rclone manually: https://rclone.org/install/" >&2
    return 1
  fi
  if ! verify_checksum "$tmpdir/rclone.zip" "$expected"; then
    return 1
  fi
  unzip -q "$tmpdir/rclone.zip" -d "$tmpdir"
  cp "$tmpdir"/rclone-*/rclone "$HOME/.local/bin/rclone"
  chmod +x "$HOME/.local/bin/rclone"
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
        ffmpeg) install_ffmpeg_linux "$FFMPEG_ARCH" ;;
        rclone) install_rclone_linux "$ARCH_SUFFIX" ;;
        *)
          echo "  No installer for $tool. Install manually." >&2
          return 1
          ;;
      esac
      ;;
    macos)
      # Homebrew handles its own integrity verification (bottle SHA256)
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
  # Version guard: must be 0.21.x+ (Chrome for Testing, no Playwright dep)
  AB_VERSION=$(agent-browser --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ -n "$AB_VERSION" ]]; then
    AB_MAJOR=$(echo "$AB_VERSION" | cut -d. -f1)
    AB_MINOR=$(echo "$AB_VERSION" | cut -d. -f2)
    if [[ "$AB_MAJOR" -eq 0 && "$AB_MINOR" -lt 21 ]]; then
      echo "  [ERROR] agent-browser $AB_VERSION is too old (pre-0.21 uses Playwright, causes version mismatch)"
      echo "    Required: >= 0.21.1 (uses Chrome for Testing, no shared Playwright cache)"
      echo "    Fix: sudo npm uninstall -g agent-browser && npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
      exit 1
    fi
  fi
  echo "  [ok] agent-browser${AB_VERSION:+ ($AB_VERSION)}"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
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
