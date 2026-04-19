#!/usr/bin/env bash

# T2.1 — Adapter must hard-fail (exit non-zero) when PENCIL_CLI_KEY is absent.
# Silent warn-and-continue is what let /ship Phase 5.5 commit empty .pen files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ADAPTER="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

# The adapter's Node gate rejects <22.9.0. Locate a usable Node 22+ binary.
NODE_BIN=""
for candidate in \
  "$HOME/.local/node22/bin/node" \
  "$HOME/.local/bin/node" \
  "$(command -v node 2>/dev/null || true)"; do
  if [[ -x "$candidate" ]]; then
    version=$("$candidate" --version 2>/dev/null | sed 's/^v//')
    major=${version%%.*}
    minor=$(echo "$version" | cut -d. -f2)
    if [[ "$major" -gt 22 || ("$major" -eq 22 && "$minor" -ge 9) ]]; then
      NODE_BIN="$candidate"
      break
    fi
  fi
done

if [[ -z "$NODE_BIN" ]]; then
  echo "SKIP: Node >= 22.9.0 not found (tried ~/.local/node22, ~/.local/bin, PATH)"
  exit 0
fi

echo "=== pencil-adapter auth hard-fail ==="
echo "Adapter: $ADAPTER"
echo "Node:    $NODE_BIN"
echo ""

assert_file_exists "$ADAPTER" "adapter exists"

# ---------------------------------------------------------------------------
# Spawn adapter with PENCIL_CLI_KEY explicitly unset. Must exit non-zero
# within 3 seconds. Must emit an ERROR (not just WARNING) on stderr.
# Stdin is closed immediately to avoid the adapter blocking on MCP handshake.
# ---------------------------------------------------------------------------
tmp_stderr=$(mktemp)
set +e
timeout 3 env -u PENCIL_CLI_KEY "$NODE_BIN" "$ADAPTER" </dev/null 2>"$tmp_stderr" >/dev/null
rc=$?
set -e

stderr_content=$(cat "$tmp_stderr")
rm -f "$tmp_stderr"

echo "Exit code: $rc"
echo "Stderr:"
echo "$stderr_content" | sed 's/^/  /'
echo ""

# Exit code 124 = timeout fired. Exit 0 = clean success = BUG (silent).
# Any non-zero that isn't 124 = adapter refused to start = PASS.
if [[ "$rc" == "0" ]]; then
  assert_eq "nonzero" "0 (silent success)" "adapter exits non-zero without PENCIL_CLI_KEY"
elif [[ "$rc" == "124" ]]; then
  assert_eq "nonzero-fast" "124 (timeout — adapter stayed alive)" "adapter exits non-zero without PENCIL_CLI_KEY"
else
  assert_eq "nonzero" "nonzero" "adapter exits non-zero without PENCIL_CLI_KEY (rc=$rc)"
fi

assert_contains "$stderr_content" "ERROR" "stderr contains ERROR (not just WARNING)"
assert_contains "$stderr_content" "PENCIL_CLI_KEY" "stderr mentions PENCIL_CLI_KEY"

print_results
