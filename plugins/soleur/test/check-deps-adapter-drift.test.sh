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
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP

repo_adapter="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

# Each case gets an isolated install dir so a failure in one case cannot
# cascade through shared state into the next case's assertions.

# --- Case 1: installed adapter matches repo → no drift, exit 0 ---
case1_dir="$tmp_dir/case1"
mkdir -p "$case1_dir"
cp "$repo_adapter" "$case1_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case1_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "matching sha: exit 0"
assert_contains "$out" "OK" "matching sha: prints OK marker"

# --- Case 2: installed adapter differs from repo → drift, exit 3 ---
case2_dir="$tmp_dir/case2"
mkdir -p "$case2_dir"
cp "$repo_adapter" "$case2_dir/pencil-mcp-adapter.mjs"
echo "// drift" >> "$case2_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "drifted sha: exit 3"
assert_contains "$out" "DRIFT" "drifted sha: prints DRIFT marker"

# --- Case 3: --auto re-copies and then exits 0 ---
case3_dir="$tmp_dir/case3"
mkdir -p "$case3_dir"
cp "$repo_adapter" "$case3_dir/pencil-mcp-adapter.mjs"
echo "// drift" >> "$case3_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case3_dir" bash "$CHECK_DEPS" --check-adapter-drift --auto 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "--auto re-copy: exit 0"
installed_sha=$(sha256sum "$case3_dir/pencil-mcp-adapter.mjs" | awk '{print $1}')
repo_sha=$(sha256sum "$repo_adapter" | awk '{print $1}')
assert_eq "$repo_sha" "$installed_sha" "--auto re-copy: installed sha now matches repo"

# --- Case 4: install dir absent → exit 0 with NOT_INSTALLED marker ---
case4_dir="$tmp_dir/case4-absent"
# Deliberately do NOT create case4_dir
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case4_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "absent install: exit 0"
assert_contains "$out" "NOT_INSTALLED" "absent install: prints NOT_INSTALLED marker"

print_results
