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
#   1  repo adapter missing (should never happen inside the plugin)
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
  "package.json"
  "package-lock.json"
)

if [[ ! -f "$REPO_ADAPTER_DIR/pencil-mcp-adapter.mjs" ]]; then
  echo "ERROR: repo adapter not found at $REPO_ADAPTER_DIR/pencil-mcp-adapter.mjs" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR" || {
  echo "ERROR: cannot create install dir $INSTALL_DIR" >&2
  exit 2
}

copied=0
for file in "${ADAPTER_FILES[@]}"; do
  src="$REPO_ADAPTER_DIR/$file"
  dst="$INSTALL_DIR/$file"
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing repo file $src — skipping" >&2
    continue
  fi
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

# The adapter also needs its own node_modules for the MCP SDK and zod.
# If the install dir has a package.json but no node_modules, run npm ci
# with --ignore-scripts so a hostile package.json in a user-supplied
# PENCIL_ADAPTER_INSTALL_DIR cannot execute pre/postinstall scripts.
if [[ -f "$INSTALL_DIR/package.json" ]] && [[ ! -d "$INSTALL_DIR/node_modules" ]]; then
  echo "Installing adapter dependencies in $INSTALL_DIR..."
  (cd "$INSTALL_DIR" && npm ci --ignore-scripts --silent 2>&1 | tail -5) || {
    echo "WARN: npm ci failed — run manually in $INSTALL_DIR" >&2
  }
fi

if [[ "$copied" -eq 0 ]]; then
  echo "OK: adapter already in sync at $INSTALL_DIR"
else
  echo "OK: copied $copied file(s) to $INSTALL_DIR"
fi
