#!/usr/bin/env bash

# T2.4 — check_deps.sh must detect when the installed adapter at
# ~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs diverges from the
# repo source. A 24-day-stale install is what surfaced as #2630's
# "silent drop" — the installed copy lacked recent error-classification
# fixes, so failures passed through as unclassified text.
#
# The drift check is exposed via `check_deps.sh --check-adapter-drift`,
# which exits 3 on drift (distinct from the general detection exit codes)
# and prints DRIFT plus both sha prefixes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECK_DEPS="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/check_deps.sh"

echo "=== check_deps.sh adapter drift detection ==="
echo ""

assert_file_exists "$CHECK_DEPS" "check_deps.sh exists"

# ---------------------------------------------------------------------------
# Set up a temp home with a deliberately-drifted adapter copy and run
# the drift check against it. PENCIL_ADAPTER_INSTALL_DIR overrides the
# default ~/.local/share/pencil-adapter so the test stays hermetic.
# ---------------------------------------------------------------------------
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

install_dir="$tmp_dir/installed"
mkdir -p "$install_dir"
repo_adapter="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

# --- Case 1: installed adapter matches repo → no drift, exit 0 ---
cp "$repo_adapter" "$install_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "matching sha: exit 0"
assert_contains "$out" "OK" "matching sha: prints OK marker"

# --- Case 2: installed adapter differs from repo → drift, exit 3 ---
echo "// drift" >> "$install_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "drifted sha: exit 3"
assert_contains "$out" "DRIFT" "drifted sha: prints DRIFT marker"

# --- Case 3: --auto re-copies and then exits 0 ---
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$CHECK_DEPS" --check-adapter-drift --auto 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "--auto re-copy: exit 0"
installed_sha=$(sha256sum "$install_dir/pencil-mcp-adapter.mjs" | awk '{print $1}')
repo_sha=$(sha256sum "$repo_adapter" | awk '{print $1}')
assert_eq "$repo_sha" "$installed_sha" "--auto re-copy: installed sha now matches repo"

# --- Case 4: install dir absent → exit 0 with NOT_INSTALLED marker ---
rm -rf "$install_dir"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$install_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "absent install: exit 0"
assert_contains "$out" "NOT_INSTALLED" "absent install: prints NOT_INSTALLED marker"

print_results
