#!/usr/bin/env bash
set -euo pipefail

# Tests for orphan-reaper.sh.
# Uses the same mock architecture as disk-monitor.test.sh:
# - Subshell isolation per test
# - Temp directory workspaces with controlled mtime
# - Environment toggles for behavior control

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAPER_SCRIPT="$SCRIPT_DIR/orphan-reaper.sh"

PASS=0
FAIL=0
TOTAL=0

echo "=== orphan-reaper.sh tests ==="
echo ""

echo "--- Normal operation ---"

# Test: no orphaned dirs produces clean exit with message
test_no_orphaned_dirs() {
  TOTAL=$((TOTAL + 1))
  local description="no orphaned dirs produces clean exit with message"
  local mock_dir
  mock_dir=$(mktemp -d)

  # Create a workspace root with no orphaned dirs
  mkdir -p "$mock_dir/workspaces"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "No orphaned workspaces"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_no_orphaned_dirs

# Test: missing workspace root exits 0 with message
test_missing_workspace_root() {
  TOTAL=$((TOTAL + 1))
  local description="missing workspace root exits 0 with message"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="/nonexistent/path/workspaces"
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "does not exist"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

test_missing_workspace_root

echo ""
echo "--- Age-based cleanup ---"

# Test: old orphaned dirs are removed
test_old_orphaned_removed() {
  TOTAL=$((TOTAL + 1))
  local description="orphaned dirs older than MAX_AGE_HOURS are removed"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  # Create an orphaned dir and backdate it to 25 hours ago
  mkdir -p "$mock_dir/workspaces/workspace-abc.orphaned-1700000000"
  touch -d "25 hours ago" "$mock_dir/workspaces/workspace-abc.orphaned-1700000000"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ ! -d "$mock_dir/workspaces/workspace-abc.orphaned-1700000000" ]] && \
     printf '%s\n' "$output" | grep -qF "Cleaned up 1"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, dir exists: $(test -d "$mock_dir/workspaces/workspace-abc.orphaned-1700000000" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_old_orphaned_removed

# Test: recent orphaned dirs are NOT removed
test_recent_orphaned_kept() {
  TOTAL=$((TOTAL + 1))
  local description="orphaned dirs younger than MAX_AGE_HOURS are kept"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  # Create an orphaned dir just now (0 hours old)
  mkdir -p "$mock_dir/workspaces/workspace-def.orphaned-1700000000"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ -d "$mock_dir/workspaces/workspace-def.orphaned-1700000000" ]] && \
     printf '%s\n' "$output" | grep -qF "No orphaned workspaces"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, dir exists: $(test -d "$mock_dir/workspaces/workspace-def.orphaned-1700000000" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_recent_orphaned_kept

# Test: multiple old orphaned dirs are all removed
test_multiple_orphaned_removed() {
  TOTAL=$((TOTAL + 1))
  local description="multiple old orphaned dirs are all removed"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  mkdir -p "$mock_dir/workspaces/ws-1.orphaned-1700000001"
  mkdir -p "$mock_dir/workspaces/ws-2.orphaned-1700000002"
  mkdir -p "$mock_dir/workspaces/ws-3.orphaned-1700000003"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-1.orphaned-1700000001"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-2.orphaned-1700000002"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-3.orphaned-1700000003"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ ! -d "$mock_dir/workspaces/ws-1.orphaned-1700000001" ]] && \
     [[ ! -d "$mock_dir/workspaces/ws-2.orphaned-1700000002" ]] && \
     [[ ! -d "$mock_dir/workspaces/ws-3.orphaned-1700000003" ]] && \
     printf '%s\n' "$output" | grep -qF "Cleaned up 3"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_multiple_orphaned_removed

echo ""
echo "--- Safety checks ---"

# Test: non-orphaned dirs are not touched
test_non_orphaned_preserved() {
  TOTAL=$((TOTAL + 1))
  local description="non-orphaned dirs are not touched"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  # Normal workspace dir (no .orphaned- in name)
  mkdir -p "$mock_dir/workspaces/workspace-abc"
  touch -d "48 hours ago" "$mock_dir/workspaces/workspace-abc"
  # Dir with "orphaned" but not matching the pattern
  mkdir -p "$mock_dir/workspaces/orphaned-leftover"
  touch -d "48 hours ago" "$mock_dir/workspaces/orphaned-leftover"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ -d "$mock_dir/workspaces/workspace-abc" ]] && \
     [[ -d "$mock_dir/workspaces/orphaned-leftover" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        workspace-abc exists: $(test -d "$mock_dir/workspaces/workspace-abc" && echo yes || echo no)"
    echo "        orphaned-leftover exists: $(test -d "$mock_dir/workspaces/orphaned-leftover" && echo yes || echo no)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_non_orphaned_preserved

# Test: mix of old orphaned, recent orphaned, and normal dirs
test_selective_cleanup() {
  TOTAL=$((TOTAL + 1))
  local description="only old orphaned dirs removed; recent orphaned and normal dirs preserved"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  # Old orphaned (should be removed)
  mkdir -p "$mock_dir/workspaces/ws-old.orphaned-1700000000"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-old.orphaned-1700000000"
  # Recent orphaned (should be kept)
  mkdir -p "$mock_dir/workspaces/ws-new.orphaned-1700099999"
  # Normal dir (should be kept)
  mkdir -p "$mock_dir/workspaces/ws-normal"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-normal"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ ! -d "$mock_dir/workspaces/ws-old.orphaned-1700000000" ]] && \
     [[ -d "$mock_dir/workspaces/ws-new.orphaned-1700099999" ]] && \
     [[ -d "$mock_dir/workspaces/ws-normal" ]] && \
     printf '%s\n' "$output" | grep -qF "Cleaned up 1"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        ws-old.orphaned exists: $(test -d "$mock_dir/workspaces/ws-old.orphaned-1700000000" && echo yes || echo no)"
    echo "        ws-new.orphaned exists: $(test -d "$mock_dir/workspaces/ws-new.orphaned-1700099999" && echo yes || echo no)"
    echo "        ws-normal exists: $(test -d "$mock_dir/workspaces/ws-normal" && echo yes || echo no)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_selective_cleanup

# Test: orphaned dirs with contents are fully removed
test_orphaned_with_contents() {
  TOTAL=$((TOTAL + 1))
  local description="orphaned dirs with nested contents are fully removed"
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/workspaces"
  mkdir -p "$mock_dir/workspaces/ws-full.orphaned-1700000000/subdir/nested"
  echo "some file" > "$mock_dir/workspaces/ws-full.orphaned-1700000000/subdir/nested/file.txt"
  echo "root file" > "$mock_dir/workspaces/ws-full.orphaned-1700000000/root.txt"
  touch -d "48 hours ago" "$mock_dir/workspaces/ws-full.orphaned-1700000000"

  local output actual_exit
  output=$(
    export WORKSPACE_ROOT="$mock_dir/workspaces"
    export MAX_AGE_HOURS=24
    bash "$REAPER_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && \
     [[ ! -d "$mock_dir/workspaces/ws-full.orphaned-1700000000" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, dir exists: $(test -d "$mock_dir/workspaces/ws-full.orphaned-1700000000" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_orphaned_with_contents

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
