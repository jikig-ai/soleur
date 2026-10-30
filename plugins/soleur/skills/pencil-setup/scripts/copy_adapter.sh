#!/usr/bin/env bash
# copy_adapter.sh — sync the repo pencil MCP adapter into the user's install
# location so that `claude mcp add`-style registrations that reference the
# installed path receive every repo-level fix. Addresses the #2630 drift gap.
#
# Usage:
#   bash copy_adapter.sh                   # copy to ~/.local/share/pencil-adapter
#   PENCIL_ADAPTER_INSTALL_DIR=/path bash copy_adapter.sh
#
# Exit codes:
#   0  copy succeeded (or repo already matches install)
#   1  repo adapter or one of its sibling modules missing (should never happen inside the plugin)
#   2  install directory not writable
#   3  the adapter's dependency install (`npm ci`) failed: the installed adapter files and its
#      node_modules were left exactly as they were (the install runs in <dir>.new and is swapped in
#      only on success), so a working older adapter keeps working; re-run, or:
#      bash check_deps.sh --check-adapter-drift --auto

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ADAPTER_DIR="$SCRIPT_DIR"
INSTALL_DIR="${PENCIL_ADAPTER_INSTALL_DIR:-$HOME/.local/share/pencil-adapter}"

# Files the adapter imports at runtime. Keep in sync with the dynamic imports
# at the top of pencil-mcp-adapter.mjs.
ADAPTER_FILES=(
  "pencil-mcp-adapter.mjs"
  "pencil-error-enrichment.mjs"
  "sanitize-filename.mjs"
  "pencil-response-classify.mjs"
  "pencil-save-gate.mjs"
  "pencil-repl-surface.mjs"
  "package.json"
  "package-lock.json"
)

if [[ ! -f "$REPO_ADAPTER_DIR/pencil-mcp-adapter.mjs" ]]; then
  echo "ERROR: repo adapter not found at $REPO_ADAPTER_DIR/pencil-mcp-adapter.mjs" >&2
  exit 1
fi

# Validate EVERY source before copying ANY: a hard error mid-loop would leave a
# mixed-version install (new adapter, old guards) that fails far from the cause.
for file in "${ADAPTER_FILES[@]}"; do
  if [[ ! -f "$REPO_ADAPTER_DIR/$file" ]]; then
    echo "ERROR: missing repo file $REPO_ADAPTER_DIR/$file — refusing a partial install" >&2
    exit 1
  fi
done

mkdir -p "$INSTALL_DIR" || {
  echo "ERROR: cannot create install dir $INSTALL_DIR" >&2
  exit 2
}

# The adapter also needs its own node_modules for the MCP SDK and zod. They are installed FIRST, into
# a staging directory beside the install dir (<dir>.new), and swapped in only when `npm ci` succeeded;
# the adapter files are copied after that. `npm ci` deletes node_modules before it installs, so
# installing in place (and copying the new files first) would turn a working older adapter into a dead
# new one whenever the install fails (offline, a registry error): now a failure leaves the old files
# and the old node_modules exactly as they were.
#
# An install is needed when node_modules is missing or was not built from the lockfile now in the repo:
# the stamp inside node_modules records the sha256 of the package-lock.json it was installed from
# (node_modules with no stamp counts as unknown and is rebuilt once). Keyed on the hash, not on
# node_modules existing, so a dependency bump actually reaches the install. The manifests installed
# from are the REPO's own copies (never a package.json an install dir could have planted), with
# --ignore-scripts so no pre/postinstall script runs, and the credential names are removed from npm's
# environment so install-time code never sees them.
lock_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | awk '{print $1}'; else shasum -a 256 -- "$1" | awk '{print $1}'; fi
}
INSTALL_DIR="${INSTALL_DIR%/}"
[[ -n "$INSTALL_DIR" ]] || { echo "ERROR: install dir resolves to the filesystem root" >&2; exit 2; }
NM="$INSTALL_DIR/node_modules"
NM_OLD="$INSTALL_DIR/.node_modules.old"
STAGE="$INSTALL_DIR.new"
LOCK_STAMP="$NM/.soleur-package-lock.sha256"

# A swap interrupted between its two renames leaves no node_modules and the working one in the backup:
# put it back before anything else (nothing is deleted).
if [[ ! -e "$NM" && -d "$NM_OLD" ]]; then
  mv -- "$NM_OLD" "$NM" && echo "Restored the previous node_modules from $NM_OLD (an earlier install was interrupted)"
fi

npm_failed=0
want_sha=$(lock_sha "$REPO_ADAPTER_DIR/package-lock.json")
have_sha=""
[[ -f "$LOCK_STAMP" ]] && have_sha=$(cat "$LOCK_STAMP")
if [[ ! -d "$NM" ]] || [[ -z "$want_sha" ]] || [[ "$want_sha" != "$have_sha" ]]; then
  echo "Installing adapter dependencies in $INSTALL_DIR..."
  rm -rf -- "$STAGE"
  if ! (umask 022; mkdir -p "$STAGE") || ! cp -- "$REPO_ADAPTER_DIR/package.json" "$REPO_ADAPTER_DIR/package-lock.json" "$STAGE/"; then
    rm -rf -- "$STAGE"
    echo "ERROR: cannot prepare the staging directory $STAGE; the installed adapter was left unchanged" >&2
    exit 2
  fi
  # The exit status is npm's own, captured before the output is trimmed (a pipeline into `tail`
  # would report tail's status and turn a failed install into a success). umask 022 so the
  # packages are never group-writable (a umask of 002 would otherwise do that).
  npm_out=$(umask 022; cd "$STAGE" && env -u PEN_CLI_KEY -u PENCIL_CLI_KEY npm ci --ignore-scripts --silent 2>&1) && npm_rc=0 || npm_rc=$?
  [[ -z "$npm_out" ]] || printf '%s\n' "$npm_out" | tail -5
  if [[ "$npm_rc" -eq 0 && -d "$STAGE/node_modules" ]]; then
    [[ -z "$want_sha" ]] || printf '%s\n' "$want_sha" > "$STAGE/node_modules/.soleur-package-lock.sha256" 2>/dev/null || true
    rm -rf -- "$NM_OLD"
    swap_ok=1
    if [[ -e "$NM" ]]; then mv -- "$NM" "$NM_OLD" || swap_ok=0; fi
    if [[ "$swap_ok" -eq 1 ]] && ! mv -- "$STAGE/node_modules" "$NM"; then
      swap_ok=0
      [[ ! -e "$NM_OLD" ]] || mv -- "$NM_OLD" "$NM"
    fi
    rm -rf -- "$STAGE"
    if [[ "$swap_ok" -eq 1 ]]; then
      rm -rf -- "$NM_OLD"
    else
      echo "ERROR: cannot move the new node_modules into place in $INSTALL_DIR; the installed adapter was left unchanged" >&2
      exit 2
    fi
  else
    rm -rf -- "$STAGE"
    echo "WARN: npm ci failed (exit $npm_rc) for the adapter's dependencies: the installed adapter and its node_modules were left unchanged in $INSTALL_DIR. Re-run, or: bash check_deps.sh --check-adapter-drift --auto" >&2
    npm_failed=1
  fi
fi

if [[ "$npm_failed" -ne 0 ]]; then
  echo "ERROR: adapter dependencies were not installed (npm ci failed); nothing was copied" >&2
  exit 3
fi

copied=0
for file in "${ADAPTER_FILES[@]}"; do
  src="$REPO_ADAPTER_DIR/$file"
  dst="$INSTALL_DIR/$file"
  if [[ -f "$dst" ]] && ! [[ -L "$dst" ]] && cmp -s -- "$src" "$dst"; then
    continue
  fi
  # Refuse to follow pre-planted symlinks at $dst — a local attacker with
  # write on $INSTALL_DIR could otherwise redirect the copy to e.g.
  # ~/.ssh/authorized_keys. `rm -f` unlinks the symlink itself; the
  # subsequent `cp` creates a fresh regular file.
  if [[ -L "$dst" ]]; then
    rm -f -- "$dst"
  fi
  cp -- "$src" "$dst"
  copied=$((copied + 1))
done

if [[ "$copied" -eq 0 ]]; then
  echo "OK: adapter already in sync at $INSTALL_DIR"
else
  echo "OK: copied $copied file(s) to $INSTALL_DIR"
fi
