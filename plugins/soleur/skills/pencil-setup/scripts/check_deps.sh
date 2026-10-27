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
CHECK_DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Portable sha256 of a file (GNU sha256sum, else macOS/perl shasum). Prints the hex digest only;
# prints nothing and fails when neither tool exists or the file is unreadable.
sha256_of() { # <file>
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

# Both installs record the sha256 of the package-lock.json they were built from in a stamp file
# inside node_modules; a node_modules whose stamp differs from (or lacks) the lockfile that sits next
# to it was not built from that lockfile. copy_adapter.sh writes the adapter's stamp, this script
# writes the engine's.
LOCK_STAMP_NAME=".soleur-package-lock.sha256"

# Compare EVERY runtime file copy_adapter.sh installs against an install dir, not only the main
# adapter: a stale sibling (the save sentinel, the REPL surface table) or a stale dependency
# manifest (package.json / package-lock.json) next to a fresh adapter is exactly the state the
# drift check exists to catch. The list is read from copy_adapter.sh so the two cannot disagree.
# Sets ADAPTER_COMPARED (count) and ADAPTER_DRIFTED (space-prefixed names of differing or missing
# files). Returns 2 when no file name could be parsed: an unreadable list must never read as "no
# drift". (A while-read loop, not mapfile: this script also runs on macOS bash 3.2.)
adapter_drifted_modules() { # <install_dir>
  local install_dir="$1" module
  ADAPTER_COMPARED=0
  ADAPTER_DRIFTED=""
  while IFS= read -r module; do
    [[ -n "$module" ]] || continue
    ADAPTER_COMPARED=$((ADAPTER_COMPARED + 1))
    if [[ ! -f "$install_dir/$module" ]] || ! cmp -s -- "$CHECK_DEPS_DIR/$module" "$install_dir/$module"; then
      ADAPTER_DRIFTED="$ADAPTER_DRIFTED $module"
    fi
  done < <(sed -n '/^ADAPTER_FILES=(/,/^)/p' "$CHECK_DEPS_DIR/copy_adapter.sh" 2>/dev/null | grep -oE '"[^"]*\.(mjs|json)"' | tr -d '"')
  [[ "$ADAPTER_COMPARED" -gt 0 ]] || return 2
  # `npm ci` deletes node_modules before it installs, so an interrupted or offline copy leaves the
  # new files with NO node_modules, and the adapter then dies at its first dependency import. A
  # dependency manifest with no node_modules beside it is therefore drift, never "nothing to compare".
  if [[ -f "$install_dir/package.json" && ! -d "$install_dir/node_modules" ]]; then
    ADAPTER_DRIFTED="$ADAPTER_DRIFTED node_modules(missing: the dependency install did not complete)"
  fi
  # The files can all match while node_modules was built from an older lockfile (a bumped
  # dependency that never got installed): compare the stamp with the lockfile in place.
  if [[ -d "$install_dir/node_modules" && -f "$install_dir/package-lock.json" ]]; then
    local want have=""
    want=$(sha256_of "$install_dir/package-lock.json")
    [[ -f "$install_dir/node_modules/$LOCK_STAMP_NAME" ]] && have=$(cat "$install_dir/node_modules/$LOCK_STAMP_NAME" 2>/dev/null)
    if [[ -n "$want" && "$want" != "$have" ]]; then
      ADAPTER_DRIFTED="$ADAPTER_DRIFTED node_modules(built from a different package-lock.json)"
    fi
  fi
  return 0
}


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

# The home directory the passwd database assigns this user (not $HOME, which a project settings
# env block can redirect). Prints nothing when it cannot be determined.
_passwd_home() {
  local n
  n=$(command -v node 2>/dev/null) || return 0
  "$n" -e 'try{process.stdout.write(require("os").userInfo().homedir)}catch{}' 2>/dev/null
}

# "<uid> <octal mode>" of a path (Node's statSync: `stat` flags differ between GNU and BSD).
_pen_stat() {
  local n
  n=$(command -v node 2>/dev/null) || return 1
  "$n" -e 'try{const s=require("fs").statSync(process.argv[1]);console.log(s.uid+" "+(s.mode&0o7777).toString(8))}catch{process.exit(1)}' "$1" 2>/dev/null
}

# True when <path> is <root> or lies under it, on a separator boundary.
_pen_path_inside() { # <root> <path>
  [[ "$1" != "/" && ( "$2" == "$1" || "$2" == "$1"/* ) ]]
}

# Trust rule for where the engine lives, mirroring the adapter's findPenBinary(): the package
# directory must be outside the working directory and CLAUDE_PROJECT_DIR (a project cannot supply
# the binary), owned by this user, and not group- or world-writable. A project root that CONTAINS
# the home directory is the user's own tree and is exempt ONLY for the passwd home; for a $HOME the
# environment supplied that exemption is never granted (a project env block can set HOME inside the
# project). Prints the refusal cause and fails when untrusted.
_pen_trust_why() { # <real package dir> <home exempt from the ancestor rule, or empty> <engine prefix, for the remedy>
  local real_pkg="$1" exempt_home="${2:-}" prefix="${3:-$PEN_CLI_PREFIX}" root realhome="" roots=() r st uid mode
  if [[ -n "$exempt_home" ]]; then realhome=$(_realpath "$exempt_home"); fi
  for r in "$(pwd -P 2>/dev/null)" "${CLAUDE_PROJECT_DIR:-}"; do
    [[ -n "$r" ]] || continue
    root=$(_realpath "$r") || continue
    [[ -n "$root" && "$root" != "/" ]] || continue
    if [[ -n "$realhome" ]] && _pen_path_inside "$root" "$realhome"; then continue; fi
    roots+=("$root")
  done
  for root in ${roots[@]+"${roots[@]}"}; do
    if _pen_path_inside "$root" "$real_pkg"; then
      echo "the package directory is inside the working directory or the project directory"
      return 1
    fi
  done
  st=$(_pen_stat "$real_pkg") || { echo "the package directory cannot be inspected"; return 1; }
  uid=${st%% *}
  mode=${st##* }
  if [[ "$uid" != "$(id -u)" ]]; then
    echo "the package directory is not owned by the current user"
    return 1
  fi
  if (( (8#$mode & 8#022) != 0 )); then
    echo "the package directory is group- or world-writable (a umask of 002 does this); fix with: chmod -R go-w $prefix/node_modules"
    return 1
  fi
  return 0
}

# Identity rule for the headless engine (Guard 2). The credential is only ever handed to a binary
# that is the installed @pen.dev/cli package's OWN declared bin.pen, in a package directory that
# passes the trust rule above:
#   - <prefix>/node_modules/.bin/pen exists, and the package.json beside it names @pen.dev/cli;
#   - realpath(.bin/pen) is EQUAL to realpath(<package dir>/<declared bin.pen>), and that target
#     is a regular file inside the package directory on a separator boundary (no sibling-prefix
#     match, no escape);
#   - only `pen` is read: the `pencil` alias is never a candidate and there is no PATH fallback.
# Prints one line: "OK<TAB><resolved binary>", "NOTINSTALLED<TAB><cause>" or "WHY<TAB><cause>"; always
# returns 0. Does NOT run the binary. The adapter's findPenBinary() applies the same rule (shared
# table: test/fixtures/pen-identity-cases.tsv).
_pen_inspect_prefix() { # <prefix> <home exempt from the ancestor rule, or empty>
  local prefix="$1" exempt_home="${2:-}"
  local bin="$prefix/node_modules/.bin/pen"
  local pkgdir="$prefix/node_modules/$PEN_CLI_PACKAGE"
  local pkgjson="$pkgdir/package.json"
  local facts name declared real_bin real_pkg expected why
  if ! real_pkg=$(_realpath "$pkgdir") || [[ -z "$real_pkg" ]]; then
    printf 'NOTINSTALLED\t%s is not installed under %s\n' "$PEN_CLI_PACKAGE" "$prefix"; return 0
  fi
  if ! why=$(_pen_trust_why "$real_pkg" "$exempt_home" "$prefix"); then printf 'WHY\t%s\n' "$why"; return 0; fi
  [[ -f "$pkgjson" ]] || { printf 'WHY\tits package.json is unreadable\n'; return 0; }
  if ! facts=$(_pen_pkg_facts "$pkgjson"); then printf 'WHY\tits package.json is unreadable\n'; return 0; fi
  name=$(printf '%s\n' "$facts" | sed -n 1p)
  declared=$(printf '%s\n' "$facts" | sed -n 2p)
  [[ "$name" == "$PEN_CLI_PACKAGE" ]] || { printf 'WHY\tthe package name is not %s\n' "$PEN_CLI_PACKAGE"; return 0; }
  [[ -n "$declared" ]] || { printf 'WHY\tthe package declares no pen bin\n'; return 0; }
  if ! expected=$(_realpath "$real_pkg/$declared") || [[ -z "$expected" ]]; then
    printf 'WHY\tthe declared pen bin is missing\n'; return 0
  fi
  [[ "$expected" == "$real_pkg"/* ]] || { printf 'WHY\tthe declared pen bin resolves outside the package directory\n'; return 0; }
  [[ -f "$expected" ]] || { printf 'WHY\tthe declared pen bin is not a regular file\n'; return 0; }
  if ! real_bin=$(_realpath "$bin") || [[ -z "$real_bin" ]]; then printf 'WHY\t.bin/pen is missing\n'; return 0; fi
  [[ "$real_bin" == "$expected" ]] || { printf 'WHY\t.bin/pen does not point at the package'"'"'s declared pen bin\n'; return 0; }
  printf 'OK\t%s\n' "$real_bin"
}

# Which engine prefix is used, mirroring findPenBinary(): the PASSWD home's prefix first (the ancestor
# exemption applies to it alone), then $HOME's when it differs (never exempt: a project env block can
# set HOME inside the project). The first candidate that passes wins; when none does, the cause comes
# from the first candidate that has a package installed, else from $HOME's (so the advice names a
# path the --auto install actually writes). An explicit prefix (the install staging directory) is
# inspected on its own, with the exemption only when $HOME is the passwd home.
_pen_inspect() { # [prefix]  (default: the candidate prefixes, passwd home first)
  local passwd_home line first_why="" last="" prefixes=() exempts=() i
  passwd_home=$(_passwd_home)
  if [[ -n "${1:-}" ]]; then
    if [[ -n "$passwd_home" && "$HOME" == "$passwd_home" ]]; then
      _pen_inspect_prefix "$1" "$HOME"
    else
      _pen_inspect_prefix "$1" ""
    fi
    return 0
  fi
  if [[ -n "$passwd_home" ]]; then prefixes+=("$passwd_home/.local/share/pen-cli"); exempts+=("$passwd_home"); fi
  if [[ "$HOME" != "$passwd_home" ]]; then prefixes+=("$PEN_CLI_PREFIX"); exempts+=(""); fi
  for i in "${!prefixes[@]}"; do
    line=$(_pen_inspect_prefix "${prefixes[$i]}" "${exempts[$i]}")
    case "${line%%$'\t'*}" in
      OK) printf '%s\n' "$line"; return 0 ;;
      WHY) [[ -n "$first_why" ]] || first_why="$line" ;;
    esac
    last="$line"
  done
  # None passed: the first installed-but-refused candidate explains it; else "not installed" under the
  # last candidate ($HOME's when it differs from the passwd home, the one --auto writes to).
  printf '%s\n' "${first_why:-$last}"
}

# Prints the resolved binary path and succeeds when the engine passes the identity rule.
detect_headless_cli() { # [prefix]
  local line
  line=$(_pen_inspect "${1:-}")
  [[ "${line%%$'\t'*}" == "OK" ]] || return 1
  printf '%s\n' "${line#*$'\t'}"
}

# The installed @pen.dev/cli version (empty when the package.json is missing or unreadable).
pen_cli_installed_version() {
  local pkgjson="$PEN_CLI_PREFIX/node_modules/$PEN_CLI_PACKAGE/package.json" facts
  [[ -f "$pkgjson" ]] || return 0
  facts=$(_pen_pkg_facts "$pkgjson") || return 0
  printf '%s\n' "$facts" | sed -n 3p
}

# True when an install exists at a version other than the pin. Without --auto that is only
# reported; under --auto it counts as "needs install" (the lockfile is the way back to the pin).
pen_cli_pin_drifted() {
  local installed
  installed=$(pen_cli_installed_version)
  [[ -n "$installed" && "$installed" != "$PEN_CLI_VERSION" ]]
}

# The sha256 of the committed engine lockfile (what the install is built from).
pen_cli_lock_sha() {
  sha256_of "$CHECK_DEPS_DIR/pen-cli/package-lock.json"
}

# True when the installed engine tree was built from the lockfile now committed (its stamp equals
# the lockfile hash). A tree with no stamp predates the stamp: an old install at the right VERSION
# still lacks later lockfile changes (the undici `overrides` entry), so it counts as not current.
pen_cli_lock_current() { # [prefix]
  local prefix="${1:-$PEN_CLI_PREFIX}" want have=""
  want=$(pen_cli_lock_sha)
  [[ -n "$want" ]] || return 1
  [[ -f "$prefix/node_modules/$LOCK_STAMP_NAME" ]] && have=$(cat "$prefix/node_modules/$LOCK_STAMP_NAME" 2>/dev/null)
  [[ "$want" == "$have" ]]
}

# An engine swap interrupted between its two renames leaves no engine at the prefix and the only
# working one in `<prefix>.old`. Put it back; nothing is deleted. Safe to call at any time.
restore_interrupted_engine_swap() {
  local old="$PEN_CLI_PREFIX.old"
  if [[ ! -e "$PEN_CLI_PREFIX" && -d "$old" ]]; then
    if mv -- "$old" "$PEN_CLI_PREFIX"; then
      echo "  [info] restored the previous $PEN_CLI_PACKAGE engine from $old (an earlier reinstall was interrupted before the swap finished)"
    else
      echo "  [FAILED] cannot restore the previous engine from $old to $PEN_CLI_PREFIX"
      return 1
    fi
  fi
  return 0
}

# True when --auto has something to do for the engine: not installed (or not trusted), off the
# pin, or built from another lockfile than the committed one.
pen_cli_needs_install() {
  ! detect_headless_cli >/dev/null || pen_cli_pin_drifted || ! pen_cli_lock_current
}

# One-line advisories about the install state. Never fatal, never uses the deprecated package.
warn_pen_cli_state() {
  local legacy_pkg="$HOME/.local/node_modules/@pencil.dev/cli"
  if [[ -d "$legacy_pkg" ]]; then
    # "It is not used" is only true of an adapter that targets the new engine. A stale installed
    # adapter may still resolve the deprecated package, so say how to sync it instead.
    local install_dir="${PENCIL_ADAPTER_INSTALL_DIR:-$HOME/.local/share/pencil-adapter}"
    if [[ -f "$install_dir/pencil-mcp-adapter.mjs" ]] && { ! adapter_drifted_modules "$install_dir" || [[ -n "$ADAPTER_DRIFTED" ]]; }; then
      echo "  [warn] Deprecated @pencil.dev/cli found under ~/.local/node_modules, and the installed adapter at $install_dir is out of date (it may still target it). Sync with: bash check_deps.sh --check-adapter-drift --auto"
    else
      echo "  [warn] Deprecated @pencil.dev/cli found under ~/.local/node_modules: it is not used. The headless tier runs $PEN_CLI_PACKAGE from $PEN_CLI_PREFIX. Remove with: npm uninstall --prefix ~/.local @pencil.dev/cli"
    fi
  fi
  local installed
  installed=$(pen_cli_installed_version)
  if [[ -n "$installed" && "$installed" != "$PEN_CLI_VERSION" ]]; then
    if [[ "$AUTO_INSTALL" == "true" ]]; then
      echo "  [warn] $PEN_CLI_PACKAGE $installed is installed but the pin is $PEN_CLI_VERSION; re-installing from the lockfile"
    else
      echo "  [warn] $PEN_CLI_PACKAGE $installed is installed but the pin is $PEN_CLI_VERSION; re-run with --auto to reinstall from the lockfile"
    fi
  elif [[ -n "$installed" ]] && ! pen_cli_lock_current; then
    # At the pin, but built from an older lockfile (or before the lock stamp existed): later lockfile
    # changes (a dependency override) are missing. Without --auto the engine is used as it is; with
    # --auto it is reinstalled (~1 GB), so say which of the two will happen.
    if [[ "$AUTO_INSTALL" == "true" ]]; then
      echo "  [warn] $PEN_CLI_PACKAGE $installed predates the committed lockfile (its lock stamp is missing or differs); --auto is re-installing it from the lockfile (~1 GB)"
    else
      echo "  [warn] $PEN_CLI_PACKAGE $installed predates the committed lockfile (its lock stamp is missing or differs); it is used as it is, and --auto will reinstall it from the lockfile (~1 GB)"
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
  local pen_bin inspected
  if ! pen_bin=$(detect_headless_cli); then
    # Say why the tier was skipped (the specific cause, not a generic message); a silent skip leaves
    # the user guessing. Under --auto the install already ran, so the hint would only repeat what
    # its own output says.
    inspected=$(_pen_inspect)
    if [[ "${inspected%%$'\t'*}" == "WHY" ]]; then
      echo "  [skip] $PEN_CLI_PACKAGE at $PEN_CLI_PREFIX failed the identity check: ${inspected#*$'\t'}"
      if [[ "$AUTO_INSTALL" == "true" ]]; then
        echo "    (the --auto reinstall above did not fix it)"
      else
        echo "    Re-run with --auto to reinstall it from the committed lockfile"
      fi
    elif [[ "$AUTO_INSTALL" != "true" ]]; then
      echo "  [info] Headless CLI ($PEN_CLI_PACKAGE) not installed; re-run with --auto to install it from the committed lockfile"
    fi
    return 1
  fi
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
  # The key reaches the child through a subshell's environment, never through an argument list:
  # `env NAME=value cmd` would put it in env's argv, readable by any local user via ps. The child
  # also gets a minimal environment (no unrelated tokens, no deprecated name), keeping what it
  # needs to run and reach the network.
  local esc
  esc=$(printf '\033')
  # `timeout` (GNU coreutils; `gtimeout` on macOS with coreutils) bounds an unreachable engine; with
  # neither installed the probe runs unbounded, as before.
  local tmo=""
  if command -v timeout >/dev/null 2>&1; then tmo="timeout 20"; elif command -v gtimeout >/dev/null 2>&1; then tmo="gtimeout 20"; fi
  if status_out=$(
       unset PENCIL_CLI_KEY
       for v in $(compgen -e); do
         case "$v" in
           HOME|PATH|LANG|LC_*|TERM|TMPDIR|TMP|TEMP|USER|LOGNAME|SHELL|XDG_*|*_PROXY|*_proxy|NODE_EXTRA_CA_CERTS|SSL_CERT_FILE|SSL_CERT_DIR|NO_COLOR|PEN_CLI_KEY) ;;
           *) unset "$v" 2>/dev/null ;;
         esac
       done
       PEN_CLI_KEY="$key"
       export PEN_CLI_KEY
       # shellcheck disable=SC2086  # $tmo is "timeout 20", "gtimeout 20" or empty
       exec $tmo "$node_bin" "$pen_bin" status 2>&1
     ) && printf '%s' "$status_out" | LC_ALL=C sed "s/${esc}\[[0-9;?:<=>]*[@-~]//g" | grep -q 'Active'; then
    :
  else
    echo "  [skip] Headless CLI found but could not confirm Active (key invalid or engine unreachable)"
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
  echo "  [installing] Headless CLI $PEN_CLI_PACKAGE@$PEN_CLI_VERSION to $PEN_CLI_PREFIX (lockfile, scripts ignored; ~1 GB, up to a few minutes on a cold cache)..."
  # Install into a STAGING prefix and swap it in only after it passes the identity rule: a failed
  # reinstall (offline, a bad lockfile) must never remove an engine that works. The staging tree is
  # a sibling of the prefix so the swap is a rename on one filesystem.
  local stage="$PEN_CLI_PREFIX.new" old="$PEN_CLI_PREFIX.old"
  # `$old` is NOT cleared here: after an interrupted swap it holds the only working engine, so it
  # is restored first and is deleted only once the new install has been accepted (below).
  restore_interrupted_engine_swap || return 1
  rm -rf -- "$stage"
  (umask 022; mkdir -p "$stage") || { echo "  [FAILED] cannot create $stage"; return 1; }
  local f
  for f in package.json package-lock.json; do
    install -m 0644 -- "$src_dir/$f" "$stage/$f" || { echo "  [FAILED] cannot copy $f"; rm -rf -- "$stage"; return 1; }
  done
  # `npm ci` from the pinned lockfile: every transitive version and integrity hash is fixed, and
  # the credential is removed from the environment so install-time code never sees it. Lifecycle
  # scripts are ignored (verified: the engine opens, exports and screenshots without them, see
  # engine-contract-probe.sh). The old ~/.local/node_modules tree is deliberately left alone.
  # Node's directory goes first on PATH so npm's `#!/usr/bin/env node` uses the vetted binary.
  # umask 022 (and the chmod below) because the adapter refuses a group- or world-writable package
  # directory: under a umask of 002 npm would otherwise create exactly that and lock the user out.
  # Only the tail of npm's output is shown (a failing resolve can print screens of it); the exit
  # status is the command's own, captured before the output is trimmed.
  local npm_out npm_rc
  npm_out=$(umask 022; cd "$stage" && env -u PEN_CLI_KEY -u PENCIL_CLI_KEY PATH="$(dirname "$node_bin"):$PATH" "$npm_bin" ci --ignore-scripts 2>&1)
  npm_rc=$?
  [[ -z "$npm_out" ]] || printf '%s\n' "$npm_out" | tail -20
  if [[ "$npm_rc" -ne 0 ]]; then
    echo "  [FAILED] npm ci returned non-zero"
    rm -rf -- "$stage"
    [[ ! -e "$PEN_CLI_PREFIX" ]] || echo "    The engine already installed at $PEN_CLI_PREFIX was left untouched."
    return 1
  fi
  # Whatever npm created (a hard-coded 775 included), nothing may stay group- or world-writable.
  chmod -R go-w "$stage/node_modules" 2>/dev/null || true
  local why
  if ! detect_headless_cli "$stage" >/dev/null; then
    why=$(_pen_inspect "$stage")
    echo "  [FAILED] Install succeeded but the $PEN_CLI_PACKAGE binary was not found or failed the identity check: ${why#*$'\t'}"
    rm -rf -- "$stage"
    [[ ! -e "$PEN_CLI_PREFIX" ]] || echo "    The engine already installed at $PEN_CLI_PREFIX was left untouched."
    return 1
  fi
  (umask 022; pen_cli_lock_sha > "$stage/node_modules/$LOCK_STAMP_NAME") 2>/dev/null || true
  # The new tree is proven. Only now is an `$old` left by an earlier attempt expendable.
  rm -rf -- "$old"
  if [[ -e "$PEN_CLI_PREFIX" ]]; then
    mv -- "$PEN_CLI_PREFIX" "$old" || { echo "  [FAILED] cannot move the existing engine aside"; rm -rf -- "$stage"; return 1; }
  fi
  if ! mv -- "$stage" "$PEN_CLI_PREFIX"; then
    echo "  [FAILED] cannot move the new engine into place"
    [[ ! -e "$old" ]] || mv -- "$old" "$PEN_CLI_PREFIX"
    rm -rf -- "$stage"
    return 1
  fi
  if ! detect_headless_cli >/dev/null; then
    why=$(_pen_inspect)
    echo "  [FAILED] Installed, but $PEN_CLI_PREFIX does not pass the identity check: ${why#*$'\t'}"
    # Roll back: the previous engine (if there was one) goes back; a rejected new tree is not kept.
    if [[ -d "$old" ]]; then
      rm -rf -- "$PEN_CLI_PREFIX"
      mv -- "$old" "$PEN_CLI_PREFIX" && echo "    The previous engine was restored."
    fi
    return 1
  fi
  rm -rf -- "$old"
  return 0
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

# -- Adapter drift check (short-circuits the tier flow) --
#
# Compares the installed adapter files at PENCIL_ADAPTER_INSTALL_DIR (default
# ~/.local/share/pencil-adapter) against the repo source. Exits:
#   0 + OK            - every file matches
#   3 + DRIFT         - a file differs or is missing, or node_modules was not built from the
#                       package-lock.json in place (unless --auto: installs the engine FIRST when it
#                       is missing, off the pin or built from another lockfile, then re-copies the
#                       adapter and its dependencies, then exits 0)
#   0 + NOT_INSTALLED - install dir absent
#   2                 - the file list is unreadable, or an --auto repair step failed (engine
#                       install: the installed adapter is left unchanged; adapter dependency
#                       install: the cause is printed)
#
# Exists because the installed adapter had drifted 24 days behind repo source, masking
# error-classification fixes and producing the #2630 silent-drop.
# Rule: ex-cq-pencil-mcp-silent-drop-diagnosis-checklist (retired id, kept as the provenance).
run_adapter_drift_check() {
  local install_dir="${PENCIL_ADAPTER_INSTALL_DIR:-$HOME/.local/share/pencil-adapter}"
  local installed_adapter="$install_dir/pencil-mcp-adapter.mjs"
  local repo_adapter="$CHECK_DEPS_DIR/pencil-mcp-adapter.mjs"

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
  local installed_sha repo_sha
  installed_sha=$(sha256_of "$installed_adapter")
  repo_sha=$(sha256_of "$repo_adapter")

  if ! adapter_drifted_modules "$install_dir"; then
    echo "ERROR: no adapter modules parsed from $CHECK_DEPS_DIR/copy_adapter.sh ADAPTER_FILES" >&2
    exit 2
  fi

  if [[ -z "$ADAPTER_DRIFTED" ]]; then
    echo "OK: installed adapter matches repo (sha ${repo_sha:0:12})"
    exit 0
  fi

  if [[ "$AUTO_INSTALL" == "true" ]]; then
    # Engine FIRST: the new adapter refuses to start without its engine, so the adapter is never
    # copied ahead of it. A failed engine install leaves the installed adapter (and any engine
    # that already worked, see attempt_headless_install) exactly as they were.
    if pen_cli_needs_install; then
      echo "  [info] Headless engine missing, not at the pin $PEN_CLI_VERSION, or built from another lockfile: installing it before the adapter is updated"
      if ! attempt_headless_install; then
        echo "ERROR: the headless engine ($PEN_CLI_PACKAGE@$PEN_CLI_VERSION) could not be installed; the installed adapter was NOT changed. Fix the cause above and re-run: bash check_deps.sh --check-adapter-drift --auto" >&2
        exit 2
      fi
    fi
    # Delegate the full sync to copy_adapter.sh: it copies the adapter AND its sibling modules
    # and manifests, and runs npm ci when the lockfile changed. A bare `cp` would leave the
    # adapter ahead of its dependencies.
    local copy_rc=0
    PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$CHECK_DEPS_DIR/copy_adapter.sh" || copy_rc=$?
    if [[ "$copy_rc" -ne 0 ]]; then
      case "$copy_rc" in
        3) echo "ERROR: copy_adapter.sh could not install the adapter's dependencies (npm ci failed, see above); the installed adapter and its node_modules were left unchanged. Re-run: bash check_deps.sh --check-adapter-drift --auto" >&2 ;;
        *) echo "ERROR: copy_adapter.sh failed (exit $copy_rc) during drift auto-repair" >&2 ;;
      esac
      exit 2
    fi
    local new_sha
    new_sha=$(sha256_of "$installed_adapter")
    echo "OK: re-copied adapter (was ${installed_sha:0:12} -> now ${new_sha:0:12})"
    exit 0
  fi

  echo "DRIFT: installed ${installed_sha:0:12} != repo ${repo_sha:0:12}; differing or missing:${ADAPTER_DRIFTED}"
  echo "       Run: bash $(basename "${BASH_SOURCE[0]}") --check-adapter-drift --auto   (also installs the engine when it is missing)"
  echo "       Or re-run /soleur:pencil-setup to refresh the installed adapter."
  exit 3
}

if [[ "$CHECK_ADAPTER_DRIFT" == "true" ]]; then
  run_adapter_drift_check
fi

# -- Main Flow --

echo "=== Pencil Setup Dependency Check ==="
echo

# An interrupted engine reinstall may have left the working engine in <prefix>.old
restore_interrupted_engine_swap || true

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
# --auto installs when the engine is missing, not trusted, installed at a version other than the pin
# (the version advice would otherwise be a dead end) or built from another lockfile than the
# committed one; the lockfile is the way back to the pin.
if [[ "$AUTO_INSTALL" == "true" ]] && pen_cli_needs_install; then
  attempt_headless_install || true
fi
try_headless_cli_tier || true
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
