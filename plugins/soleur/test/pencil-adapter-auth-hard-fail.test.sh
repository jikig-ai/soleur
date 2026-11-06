#!/usr/bin/env bash

# T2.1 — Adapter must hard-fail (exit non-zero) when no credential is set: neither PEN_CLI_KEY
# nor the deprecated PENCIL_CLI_KEY fallback, an empty or whitespace-only value counting as unset.
# Silent warn-and-continue is what let /ship Phase 5.5 commit empty .pen files.

set -euo pipefail
SUITE_TMP=$(mktemp -d)
[[ "$SUITE_TMP" == /* ]] || { echo "FATAL: SUITE_TMP is not absolute: $SUITE_TMP" >&2; exit 2; }
trap 'rm -rf "$SUITE_TMP"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ADAPTER="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

# The adapter's Node gate rejects <22.19.0 (the @pen.dev/cli engines floor). Locate a usable
# binary with a numeric major.minor.patch compare (22.100.0 is above the floor, 22.9.0 is not).
NODE_BIN=""
for candidate in \
  "$HOME/.local/node22/bin/node" \
  "$HOME/.local/bin/node" \
  "$(command -v node 2>/dev/null || true)"; do
  if [[ -x "$candidate" ]]; then
    version=$("$candidate" --version 2>/dev/null | sed 's/^v//')
    major=${version%%.*}
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3 | sed 's/[^0-9].*//')
    if [[ "$major" -gt 22 || ("$major" -eq 22 && ("$minor" -gt 19 || ("$minor" -eq 19 && "${patch:-0}" -ge 0))) ]]; then
      NODE_BIN="$candidate"
      break
    fi
  fi
done

if [[ -z "$NODE_BIN" ]]; then
  echo "UNRESOLVED: node>=22.19.0 missing — this suite asserted nothing; install node >= 22.19.0 (tried ~/.local/node22, ~/.local/bin, PATH)"
  exit 3
fi

echo "=== pencil-adapter auth hard-fail ==="
echo "Adapter: $ADAPTER"
echo "Node:    $NODE_BIN"
echo ""

assert_file_exists "$ADAPTER" "adapter exists"

# ---------------------------------------------------------------------------
# Spawn adapter with both credential names explicitly unset. Must exit non-zero
# within 3 seconds. Must emit an ERROR (not just WARNING) on stderr.
# Stdin is closed immediately to avoid the adapter blocking on MCP handshake.
# ---------------------------------------------------------------------------
tmp_stderr=$(mktemp -p "$SUITE_TMP")
set +e
timeout 3 env -u PEN_CLI_KEY -u PENCIL_CLI_KEY "$NODE_BIN" "$ADAPTER" </dev/null 2>"$tmp_stderr" >/dev/null
rc=$?
set -e

stderr_content=$(cat "$tmp_stderr")
rm -f "$tmp_stderr"

echo "Exit code: $rc"
echo "Stderr:"
echo "$stderr_content" | sed 's/^/  /'
echo ""

# Exit code 124 = timeout fired (adapter stayed alive — BUG). Exit 0 =
# clean success (silent BUG). The only acceptable outcome is fast failure:
# a non-zero exit that is NOT 124. A generic "nonzero" assertion would
# accept the timeout-hang regression.
if [[ "$rc" == "0" ]]; then
  assert_eq "nonzero-fast" "0 (silent success)" "adapter exits non-zero without a credential"
elif [[ "$rc" == "124" ]]; then
  assert_eq "nonzero-fast" "124 (timeout — adapter stayed alive)" "adapter exits non-zero fast (not timeout) without a credential"
else
  assert_eq "nonzero-fast" "nonzero-fast" "adapter exits non-zero fast without a credential (rc=$rc)"
fi

assert_contains "$stderr_content" "ERROR" "stderr contains ERROR (not just WARNING)"
assert_contains "$stderr_content" "PEN_CLI_KEY" "stderr mentions PEN_CLI_KEY"

# Empty and whitespace-only values count as unset, under either name, and must fail just as fast.
for label in "empty PEN_CLI_KEY" "both names empty" "both names whitespace-only"; do
  case "$label" in
    "empty PEN_CLI_KEY")           credvars=("PEN_CLI_KEY=") ;;
    "both names empty")            credvars=("PEN_CLI_KEY=" "PENCIL_CLI_KEY=") ;;
    *)                             credvars=("PEN_CLI_KEY=   " "PENCIL_CLI_KEY=  ") ;;
  esac
  tmp_stderr=$(mktemp -p "$SUITE_TMP")
  set +e
  timeout 3 env -u PEN_CLI_KEY -u PENCIL_CLI_KEY "${credvars[@]}" "$NODE_BIN" "$ADAPTER" </dev/null 2>"$tmp_stderr" >/dev/null
  rc=$?
  set -e
  empty_stderr=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  if [[ "$rc" == "0" || "$rc" == "124" ]]; then
    assert_eq "nonzero-fast" "rc=$rc" "$label exits non-zero fast"
  else
    assert_eq "nonzero-fast" "nonzero-fast" "$label exits non-zero fast (rc=$rc)"
  fi
  assert_contains "$empty_stderr" "PEN_CLI_KEY" "$label: stderr mentions PEN_CLI_KEY"
done

print_results 10
