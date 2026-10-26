#!/usr/bin/env bash
# pencil-setup dependency checker with four-tier MCP detection
# Priority: (0) Headless CLI (@pen.dev/cli), (1) pencil CLI, (2) Desktop binary, (3) IDE extension
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each check uses explicit if/then.

case "$-" in
  *x*)
    if [ -n "${PEN_CLI_KEY:+x}" ] || [ -n "${PENCIL_CLI_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

AUTO_INSTALL=false
CHECK_ADAPTER_DRIFT=false
for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_INSTALL=true ;;
    --check-adapter-drift) CHECK_ADAPTER_DRIFT=true ;;
  esac
done

# Headless engine: @pen.dev/cli at an EXACT pin, installed from the committed lockfile pair in
# ./pen-cli/ into its own prefix. A separate prefix (not ~/.local) means the deprecated
# engine's old `pencil` bin link can never be reached through the new engine's bin names, and an
# old adapter copy can never find the new engine. The pin below, pen-cli/package.json and
# pen-cli/package-lock.json move together; bumping it requires a green engine-contract-probe.sh
# run first (see SKILL.md) and re-capturing the transcript fixture (a test pins its header to this).
PEN_CLI_VERSION="0.3.13"
PEN_CLI_PACKAGE="@pen.dev/cli"
PEN_CLI_PREFIX="$HOME/.local/share/pen-cli"
# Node floor, from the package's `engines.node` (>=22.19.0). One definition, compared numerically.
NODE_FLOOR_MAJOR=22
NODE_FLOOR_MINOR=19
NODE_FLOOR_PATCH=0
NODE_FLOOR="${NODE_FLOOR_MAJOR}.${NODE_FLOOR_MINOR}.${NODE_FLOOR_PATCH}"

# -- Adapter drift check (early short-circuit) --
#
# Compares the installed adapter at PENCIL_ADAPTER_INSTALL_DIR (default
# ~/.local/share/pencil-adapter) against the repo source. Returns:
#   exit 0 + OK            — hashes match
#   exit 3 + DRIFT         — hashes differ (unless --auto, which re-copies then exits 0)
#   exit 0 + NOT_INSTALLED — install dir absent
#
# Exists because the installed adapter had drifted 24 days behind repo source,
# masking error-classification fixes and producing the #2630 silent-drop.
# Rule: cq-pencil-mcp-silent-drop-diagnosis-checklist.

if [[ "$CHECK_ADAPTER_DRIFT" == "true" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  install_dir="${PENCIL_ADAPTER_INSTALL_DIR:-$HOME/.local/share/pencil-adapter}"
  installed_adapter="$install_dir/pencil-mcp-adapter.mjs"
  repo_adapter="$script_dir/pencil-mcp-adapter.mjs"

  if [[ ! -d "$install_dir" ]] || [[ ! -f "$installed_adapter" ]]; then
    echo "NOT_INSTALLED: $install_dir"
    exit 0
  fi

  if [[ ! -f "$repo_adapter" ]]; then
    echo "ERROR: repo adapter not found at $repo_adapter" >&2
    exit 2
  fi

  # `--` terminators prevent user-supplied paths beginning with `-` (e.g.,
  # PENCIL_ADAPTER_INSTALL_DIR=--help) from being interpreted as flags by
  # sha256sum / cp. Defense-in-depth; the path quoting already blocks shell
  # injection.
  installed_sha=$(sha256sum -- "$installed_adapter" | awk '{print $1}')
  repo_sha=$(sha256sum -- "$repo_adapter" | awk '{print $1}')

  # Compare EVERY runtime module copy_adapter.sh installs, not only the main
  # file: a stale sibling (the save sentinel, the REPL surface table) next to a
  # fresh adapter is exactly the state this check exists to catch. The list is
  # read from copy_adapter.sh so the two cannot disagree. (A while-read loop, not
  # mapfile: this script also runs on macOS bash 3.2.)
  drifted=""
  compared=0
  while IFS= read -r module; do
    [[ -n "$module" ]] || continue
    compared=$((compared + 1))
    if [[ ! -f "$install_dir/$module" ]] || ! cmp -s -- "$script_dir/$module" "$install_dir/$module"; then
      drifted="$drifted $module"
    fi
  done < <(sed -n '/^ADAPTER_FILES=(/,/^)/p' "$script_dir/copy_adapter.sh" | grep -o '"[^"]*\.mjs"' | tr -d '"')
  if [[ "$compared" -eq 0 ]]; then
    # An unreadable module list must not read as "no drift": it would compare nothing.
    echo "ERROR: no adapter modules parsed from $script_dir/copy_adapter.sh ADAPTER_FILES" >&2
    exit 2
  fi

  if [[ -z "$drifted" ]]; then
    echo "OK: installed adapter matches repo (sha ${repo_sha:0:12})"
    exit 0
  fi

  if [[ "$AUTO_INSTALL" == "true" ]]; then
    # Delegate the full sync to copy_adapter.sh — it copies the adapter
    # AND its sibling pure modules (pencil-response-classify.mjs,
    # pencil-save-gate.mjs, etc.) AND runs npm ci when the install dir
    # has a package.json but no node_modules. A bare `cp` here would
    # leave the adapter ahead of its dependencies.
    if PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$script_dir/copy_adapter.sh"; then
      new_sha=$(sha256sum -- "$installed_adapter" | awk '{print $1}')
      echo "OK: re-copied adapter (was ${installed_sha:0:12} → now ${new_sha:0:12})"
      exit 0
    else
      echo "ERROR: copy_adapter.sh failed during drift auto-repair" >&2
      exit 2
    fi
  fi

  echo "DRIFT: installed ${installed_sha:0:12} != repo ${repo_sha:0:12}; differing or missing:${drifted}"
  echo "       Run: bash $(basename "${BASH_SOURCE[0]}") --check-adapter-drift --auto"
  echo "       Or re-run /soleur:pencil-setup to refresh the installed adapter."
  exit 3
fi

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
PREFERRED_NODE=""

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

# Numeric dotted-version compare against the Node floor (never lexical: 22.100.0 is above the
# floor, an older minor is below it). Accepts an optional leading "v" and ignores a prerelease/build suffix.
# Anything that is not major.minor.patch fails closed.
node_version_ok() {
  local v="${1#v}" major minor patch rest
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
  major=${v%%.*}
  rest=${v#*.}
  minor=${rest%%.*}
  patch=${rest#*.}
  patch=${patch%%[!0-9]*}
  major=$((10#$major)); minor=$((10#$minor)); patch=$((10#$patch))
  if (( major != NODE_FLOOR_MAJOR )); then
    (( major > NODE_FLOOR_MAJOR )); return
  fi
  if (( minor != NODE_FLOOR_MINOR )); then
    (( minor > NODE_FLOOR_MINOR )); return
  fi
  (( patch >= NODE_FLOOR_PATCH ))
}

# Print the version of a node binary, or nothing.
_node_version() {
  "$1" --version 2>/dev/null | sed 's/^v//'
}

# Find a Node binary >= the floor (checks system, nvm, fnm)
find_node22() {
  local node_bin version
  # Check system node first
  node_bin=$(command -v node 2>/dev/null)
  if [[ -n "$node_bin" ]]; then
    version=$(_node_version "$node_bin")
    if node_version_ok "$version"; then
      echo "$node_bin"
      return 0
    fi
  fi
  # Check nvm
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [[ -d "$nvm_dir/versions/node" ]]; then
    local nvm_node
    for nvm_node in "$nvm_dir"/versions/node/v2[2-9]*/bin/node "$nvm_dir"/versions/node/v[3-9]*/bin/node; do
      [[ -x "$nvm_node" ]] || continue
      version=$(_node_version "$nvm_node")
      if node_version_ok "$version"; then
        echo "$nvm_node"
        return 0
      fi
    done
  fi
  # Check fnm
  local fnm_dir="${FNM_DIR:-$HOME/.local/share/fnm}"
  if [[ -d "$fnm_dir/node-versions" ]]; then
    local fnm_node
    for fnm_node in "$fnm_dir"/node-versions/v2[2-9]*/installation/bin/node "$fnm_dir"/node-versions/v[3-9]*/installation/bin/node; do
      [[ -x "$fnm_node" ]] || continue
      version=$(_node_version "$fnm_node")
      if node_version_ok "$version"; then
        echo "$fnm_node"
        return 0
      fi
    done
  fi
  return 1
}

# Absolute, symlink-resolved path. The GNU-only link-resolving readlink flag is not portable to
# macOS, so: realpath when present (GNU, macOS 13+), else Node's fs.realpathSync. Prints nothing and
# fails when the path does not exist.
_realpath() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$1" 2>/dev/null
    return
  fi
  local n
  n=$(command -v node 2>/dev/null) || return 1
  "$n" -e 'try{process.stdout.write(require("fs").realpathSync(process.argv[1]))}catch{process.exit(1)}' "$1" 2>/dev/null
}

# The credential, resolved once as PEN_CLI_KEY, else the deprecated PENCIL_CLI_KEY. An empty or
# whitespace-only value counts as unset. Prints the value; callers must never echo it.
resolve_pen_key() {
  local k="${PEN_CLI_KEY:-}"
  k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
  if [[ -z "$k" ]]; then
    k="${PENCIL_CLI_KEY:-}"
    k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
  fi
  printf '%s' "$k"
}

# Print "<package name>\n<bin.pen>\n<version>" from a package.json. Any JSON-capable node will do
# (parsing needs no 22.19 features); the path is argv, never interpolated into code.
_pen_pkg_facts() {
  local n
  n=$(command -v node 2>/dev/null) || return 1
  "$n" -e '
    try {
      const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const b = p.bin && typeof p.bin === "object" ? p.bin.pen : "";
      console.log(String(p.name || "")); console.log(typeof b === "string" ? b : ""); console.log(String(p.version || ""));
    } catch { process.exit(1); }
  ' "$1" 2>/dev/null
}

# Identity rule for the headless engine (Guard 2). The credential is only ever handed to a binary
# that is the installed @pen.dev/cli package's OWN declared bin.pen:
#   - <prefix>/node_modules/.bin/pen exists, and the package.json beside it names @pen.dev/cli;
#   - realpath(.bin/pen) is EQUAL to realpath(<package dir>/<declared bin.pen>), and that target
#     sits inside the package directory on a separator boundary (no sibling-prefix match, no escape);
#   - only `pen` is read: the `pencil` alias is never a candidate and there is no PATH fallback.
# Prints the resolved binary path on success. Does NOT run the binary. The adapter's findPenBinary()
# applies the same rule (shared table: test/fixtures/pen-identity-cases.tsv).
detect_headless_cli() {
  local bin="$PEN_CLI_PREFIX/node_modules/.bin/pen"
  local pkgjson="$PEN_CLI_PREFIX/node_modules/$PEN_CLI_PACKAGE/package.json"
  [[ -e "$bin" && -f "$pkgjson" ]] || return 1
  local facts name declared real_bin real_pkg expected
  facts=$(_pen_pkg_facts "$pkgjson") || return 1
  name=$(printf '%s\n' "$facts" | sed -n 1p)
  declared=$(printf '%s\n' "$facts" | sed -n 2p)
  [[ "$name" == "$PEN_CLI_PACKAGE" && -n "$declared" ]] || return 1
  real_bin=$(_realpath "$bin") || return 1
  real_pkg=$(_realpath "$PEN_CLI_PREFIX/node_modules/$PEN_CLI_PACKAGE") || return 1
  expected=$(_realpath "$real_pkg/$declared") || return 1
  [[ -n "$real_bin" && -n "$real_pkg" && -f "$expected" ]] || return 1
  [[ "$expected" == "$real_pkg"/* ]] || return 1
  [[ "$real_bin" == "$expected" ]] || return 1
  printf '%s\n' "$real_bin"
  return 0
}

# One-line advisories about the install state. Never fatal, never uses the deprecated package.
warn_pen_cli_state() {
  local legacy_pkg="$HOME/.local/node_modules/@pencil.dev/cli"
  if [[ -d "$legacy_pkg" ]]; then
    echo "  [warn] Deprecated @pencil.dev/cli found under ~/.local/node_modules: it is not used. The headless tier runs $PEN_CLI_PACKAGE from $PEN_CLI_PREFIX. Remove with: npm uninstall --prefix ~/.local @pencil.dev/cli"
  fi
  local pkgjson="$PEN_CLI_PREFIX/node_modules/$PEN_CLI_PACKAGE/package.json" facts installed
  if [[ -f "$pkgjson" ]]; then
    facts=$(_pen_pkg_facts "$pkgjson") && installed=$(printf '%s\n' "$facts" | sed -n 3p)
    if [[ -n "${installed:-}" && "$installed" != "$PEN_CLI_VERSION" ]]; then
      echo "  [warn] $PEN_CLI_PACKAGE $installed is installed but the pin is $PEN_CLI_VERSION; re-run with --auto to reinstall from the lockfile"
    fi
  fi
  return 0
}

# Check if the pencil CLI in PATH is pencil.dev (not evolus/pencil)
detect_pencil_cli() {
  command -v pencil >/dev/null 2>&1 || return 1
  # Negative guard: if the PATH pencil resolves to either headless CLI package (the deprecated
  # @pencil.dev/cli or the maintained @pen.dev/cli, whose second bin is also named `pencil`),
  # skip it for Tier 1 (handled by Tier 0)
  local resolved
  resolved=$(_realpath "$(command -v pencil)")
  if [[ "$resolved" == *"@pencil.dev/cli"* || "$resolved" == *"@pen.dev/cli"* || "$resolved" == *"pencil-cli"* ]]; then
    return 1
  fi
  # Guard against evolus/pencil name collision
  if grep -qi "pencil\.dev\|pencil v" < <(pencil --version 2>&1); then
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
      grep -q . < <(mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null) && return 0
      ;;
    linux)
      # Check .deb installation
      grep -q "Status:.*installed" < <(dpkg -s pencil 2>/dev/null) && return 0
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

try_headless_cli_tier() {
  local pen_bin
  pen_bin=$(detect_headless_cli) || return 1
  # Node version gate
  local node_bin
  node_bin=$(find_node22)
  if [[ -z "$node_bin" ]]; then
    echo "  [skip] Headless CLI found but Node >= $NODE_FLOOR not available"
    echo "    Install Node 22+ via nvm: nvm install 22   (the engine requires >= $NODE_FLOOR)"
    return 1
  fi
  # Auth check: PEN_CLI_KEY (or the deprecated PENCIL_CLI_KEY fallback; empty counts as unset) is
  # handed to `pen status` as PEN_CLI_KEY only. A fail-open engine still runs with a bad key, so
  # exit 0 is not enough: the reply must report Active. Output carries account details and is
  # never printed.
  local key status_out
  key=$(resolve_pen_key)
  if [[ -z "$key" ]]; then
    echo "  [skip] Headless CLI found but auth failed: PEN_CLI_KEY is not set"
    echo "    Set the PEN_CLI_KEY environment variable (the adapter needs it; a pen login is not enough)"
    return 1
  fi
  if status_out=$(env -u PENCIL_CLI_KEY PEN_CLI_KEY="$key" "$node_bin" "$pen_bin" status 2>&1) \
     && printf '%s' "$status_out" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -q 'Active'; then
    :
  else
    echo "  [skip] Headless CLI found but auth failed"
    echo "    Set a valid PEN_CLI_KEY environment variable (PENCIL_CLI_KEY is still read as a deprecated fallback)"
    return 1
  fi
  echo "  [ok] Headless CLI (Tier 0)"
  # Adapter path is relative to check_deps.sh location
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PREFERRED_MODE="headless_cli"
  PREFERRED_BINARY="$script_dir/pencil-mcp-adapter.mjs"
  PREFERRED_APP=""
  PREFERRED_NODE="$node_bin"
  return 0
}

# Auto-install headless CLI if --auto and not found
attempt_headless_install() {
  if [[ "$AUTO_INSTALL" != "true" ]]; then
    return 1
  fi
  local node_bin
  node_bin=$(find_node22)
  if [[ -z "$node_bin" ]]; then
    echo "  [skip] Cannot auto-install headless CLI: Node >= $NODE_FLOOR not available"
    return 1
  fi
  local npm_bin
  npm_bin="$(dirname "$node_bin")/npm"
  [[ -x "$npm_bin" ]] || npm_bin=$(command -v npm 2>/dev/null)
  if [[ -z "$npm_bin" || ! -x "$npm_bin" ]]; then
    echo "  [skip] Cannot auto-install headless CLI: npm not found"
    return 1
  fi
  local src_dir
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pen-cli"
  [[ "$src_dir" == /* && "$PEN_CLI_PREFIX" == /* ]] || { echo "  [FAILED] install paths are not absolute"; return 1; }
  if [[ ! -f "$src_dir/package.json" || ! -f "$src_dir/package-lock.json" ]]; then
    echo "  [FAILED] Missing committed lockfile pair in $src_dir (package.json, package-lock.json)"
    return 1
  fi
  echo "  [installing] Headless CLI $PEN_CLI_PACKAGE@$PEN_CLI_VERSION to $PEN_CLI_PREFIX (lockfile, scripts ignored)..."
  mkdir -p "$PEN_CLI_PREFIX" || { echo "  [FAILED] cannot create $PEN_CLI_PREFIX"; return 1; }
  local f
  for f in package.json package-lock.json; do
    # unlink first so a pre-planted symlink at the destination is replaced, not followed
    rm -f -- "$PEN_CLI_PREFIX/$f"
    install -m 0644 -- "$src_dir/$f" "$PEN_CLI_PREFIX/$f" || { echo "  [FAILED] cannot copy $f"; return 1; }
  done
  # `npm ci` from the pinned lockfile: every transitive version and integrity hash is fixed, and
  # the credential is removed from the environment so install-time code never sees it. Lifecycle
  # scripts are ignored (verified: the engine opens, exports and screenshots without them, see
  # engine-contract-probe.sh). The old ~/.local/node_modules tree is deliberately left alone.
  # Node's directory goes first on PATH so npm's `#!/usr/bin/env node` uses the vetted binary.
  if (cd "$PEN_CLI_PREFIX" && env -u PEN_CLI_KEY -u PENCIL_CLI_KEY PATH="$(dirname "$node_bin"):$PATH" "$npm_bin" ci --ignore-scripts 2>&1); then
    detect_headless_cli >/dev/null && return 0
    echo "  [FAILED] Install succeeded but the $PEN_CLI_PACKAGE binary was not found or failed the identity check"
  else
    echo "  [FAILED] npm ci returned non-zero"
  fi
  return 1
}

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

# Sourced (by tests): expose the functions without running any tier.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

# -- Main Flow --

echo "=== Pencil Setup Dependency Check ==="
echo

# Leftover deprecated engine / version drift against the pin (advisory only)
warn_pen_cli_state

# Warn about evolus/pencil collision
if ! detect_pencil_cli && ! detect_headless_cli >/dev/null && command -v pencil >/dev/null 2>&1; then
  echo "  [info] pencil CLI found but is not pencil.dev (possible evolus/pencil)"
fi

# Try tiers in priority order -- first success wins
# Tier 0: Headless CLI, @pen.dev/cli (no GUI required)
# Tier 1: Desktop CLI (needs Desktop running)
# Tier 2: Desktop binary (needs Desktop running)
# Tier 3: IDE extension
if ! try_headless_cli_tier; then
  # Auto-install headless CLI if --auto
  if [[ "$AUTO_INSTALL" == "true" ]] && ! detect_headless_cli >/dev/null; then
    attempt_headless_install && try_headless_cli_tier
  fi
fi
[[ -n "$PREFERRED_MODE" ]] || try_cli_tier || try_desktop_tier || try_ide_tier

# -- Result --
echo
if [[ -n "$PREFERRED_MODE" ]]; then
  echo "=== Check Complete ==="
  echo
  echo "PREFERRED_MODE=$PREFERRED_MODE"
  echo "PREFERRED_BINARY=$PREFERRED_BINARY"
  echo "PREFERRED_APP=$PREFERRED_APP"
  [[ -n "$PREFERRED_NODE" ]] && echo "PREFERRED_NODE=$PREFERRED_NODE"
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
