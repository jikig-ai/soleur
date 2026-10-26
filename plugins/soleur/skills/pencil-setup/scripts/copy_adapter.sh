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

# The adapter also needs its own node_modules for the MCP SDK and zod. Install when the install
# dir has a package.json and either no node_modules or a node_modules that was not built from the
# lockfile now in place: the stamp inside node_modules records the sha256 of the package-lock.json
# it was installed from (node_modules with no stamp counts as unknown and is rebuilt once). Keyed
# on the hash, not on node_modules existing, so a dependency bump actually reaches the install.
# --ignore-scripts so a hostile package.json in a user-supplied PENCIL_ADAPTER_INSTALL_DIR cannot
# execute pre/postinstall scripts; the credential names are removed from npm's environment so
# install-time code never sees them.
lock_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | awk '{print $1}'; else shasum -a 256 -- "$1" | awk '{print $1}'; fi
}
LOCK_STAMP="$INSTALL_DIR/node_modules/.soleur-package-lock.sha256"
if [[ -f "$INSTALL_DIR/package.json" ]]; then
  want_sha=""
  [[ -f "$INSTALL_DIR/package-lock.json" ]] && want_sha=$(lock_sha "$INSTALL_DIR/package-lock.json")
  have_sha=""
  [[ -f "$LOCK_STAMP" ]] && have_sha=$(cat "$LOCK_STAMP")
  if [[ ! -d "$INSTALL_DIR/node_modules" ]] || [[ -z "$want_sha" ]] || [[ "$want_sha" != "$have_sha" ]]; then
    echo "Installing adapter dependencies in $INSTALL_DIR..."
    if (cd "$INSTALL_DIR" && env -u PEN_CLI_KEY -u PENCIL_CLI_KEY npm ci --ignore-scripts --silent 2>&1 | tail -5); then
      [[ -z "$want_sha" ]] || printf '%s\n' "$want_sha" > "$LOCK_STAMP" 2>/dev/null || true
    else
      echo "WARN: npm ci failed — run manually in $INSTALL_DIR (or: bash check_deps.sh --check-adapter-drift --auto)" >&2
    fi
  fi
fi

if [[ "$copied" -eq 0 ]]; then
  echo "OK: adapter already in sync at $INSTALL_DIR"
else
  echo "OK: copied $copied file(s) to $INSTALL_DIR"
fi
