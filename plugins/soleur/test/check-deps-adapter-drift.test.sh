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
# Owning trap installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every direct run (#8659). The
# `:-` guard keeps it a no-op if the suite exits before allocating the scratch dir
# (e.g. the git-location tripwire's exit 97 inside the source line itself).
trap '[[ -z "${tmp_dir:-}" ]] || rm -rf "$tmp_dir"' EXIT INT TERM HUP
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

repo_adapter="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

# Each case gets an isolated install dir so a failure in one case cannot
# cascade through shared state into the next case's assertions.

# --- Case 1: installed adapter matches repo → no drift, exit 0 ---
case1_dir="$tmp_dir/case1"
mkdir -p "$case1_dir"
scripts_dir="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts"
cp "$scripts_dir"/*.mjs "$case1_dir/"
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

# --- Case 2b: a stale SIBLING module next to a fresh adapter is drift too ---
# The save sentinel and the REPL surface table are siblings; hashing only the
# main file reported OK while the guards were stale.
case2b_dir="$tmp_dir/case2b"
mkdir -p "$case2b_dir"
cp "$scripts_dir"/*.mjs "$case2b_dir/"
echo "// stale" >> "$case2b_dir/pencil-save-gate.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2b_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "stale sibling: exit 3"
assert_contains "$out" "pencil-save-gate.mjs" "stale sibling: names the drifted module"

# --- Case 2c: a MISSING sibling is drift ---
case2c_dir="$tmp_dir/case2c"
mkdir -p "$case2c_dir"
cp "$scripts_dir"/*.mjs "$case2c_dir/"
rm "$case2c_dir/pencil-repl-surface.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2c_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "missing sibling: exit 3"
assert_contains "$out" "pencil-repl-surface.mjs" "missing sibling: names the missing module"

# --- Case 2c: an unparseable module list is an error, never a clean OK ---
case2c_scripts="$tmp_dir/case2c-scripts"
case2c_dir="$tmp_dir/case2c"
mkdir -p "$case2c_scripts" "$case2c_dir"
cp "$CHECK_DEPS" "$case2c_scripts/check_deps.sh"
cp "$repo_adapter" "$case2c_scripts/pencil-mcp-adapter.mjs"
cp "$repo_adapter" "$case2c_dir/pencil-mcp-adapter.mjs"
echo "# no module list here" > "$case2c_scripts/copy_adapter.sh"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2c_dir" bash "$case2c_scripts/check_deps.sh" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "2" "$rc" "empty module list: exit 2"
assert_contains "$out" "no adapter modules parsed" "empty module list: says why"

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
