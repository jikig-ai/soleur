#!/usr/bin/env bash
# test-weekly-analytics.sh -- Unit tests for weekly-analytics.sh functions.
# Sources the production script (guarded by BASH_SOURCE) to test real code.
#
# Usage: bash scripts/test-weekly-analytics.sh
#   Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source production functions (main body is guarded by BASH_SOURCE check)
# shellcheck source=weekly-analytics.sh
source "$SCRIPT_DIR/weekly-analytics.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label}: expected '${expected}', got '${actual}'" >&2
  fi
}

# ============================================================
# Test Suite: to_epoch
# ============================================================

echo "--- to_epoch tests ---"

epoch=$(to_epoch "2026-03-13")
assert_eq "to_epoch-valid" "true" "$([[ "$epoch" -gt 0 ]] && echo "true" || echo "false")"

# Invalid date format should fail
if to_epoch "not-a-date" >/dev/null 2>&1; then
  FAIL=$((FAIL + 1))
  echo "FAIL: to_epoch-invalid: should have failed on bad input" >&2
else
  PASS=$((PASS + 1))
fi

# ============================================================
# Test Suite: detect_phase
# ============================================================

echo "--- detect_phase tests ---"

# Invalid date format
if detect_phase "not-a-date" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL: detect_phase-invalid-format: should reject non-date" >&2
else
  PASS=$((PASS + 1))
fi

# Pre-Phase 1
detect_phase "2026-03-12"
assert_eq "pre-phase-1: phase" "Pre-Phase 1" "$CURRENT_PHASE"
assert_eq "pre-phase-1: target" "" "$CURRENT_TARGET"
assert_eq "pre-phase-1: numeric" "" "$TARGET_NUMERIC"

# Phase 1 start (first day)
detect_phase "2026-03-13"
assert_eq "phase-1-start: phase" "Phase 1: Content Traction" "$CURRENT_PHASE"
assert_eq "phase-1-start: target" "+15%" "$CURRENT_TARGET"
assert_eq "phase-1-start: numeric" "15" "$TARGET_NUMERIC"

# Phase 1 mid
detect_phase "2026-03-20"
assert_eq "phase-1-mid: phase" "Phase 1: Content Traction" "$CURRENT_PHASE"
assert_eq "phase-1-mid: target" "+15%" "$CURRENT_TARGET"

# Phase 1 last day (boundary inclusive)
detect_phase "2026-04-10"
assert_eq "phase-1-end: phase" "Phase 1: Content Traction" "$CURRENT_PHASE"

# Phase 2 first day
detect_phase "2026-04-11"
assert_eq "phase-2-start: phase" "Phase 2: Content Velocity" "$CURRENT_PHASE"
assert_eq "phase-2-start: target" "+10%" "$CURRENT_TARGET"
assert_eq "phase-2-start: numeric" "10" "$TARGET_NUMERIC"

# Phase 2 mid
detect_phase "2026-04-15"
assert_eq "phase-2-mid: phase" "Phase 2: Content Velocity" "$CURRENT_PHASE"

# Phase 2 last day (boundary inclusive)
detect_phase "2026-05-09"
assert_eq "phase-2-end: phase" "Phase 2: Content Velocity" "$CURRENT_PHASE"

# Phase 3 first day
detect_phase "2026-05-10"
assert_eq "phase-3-start: phase" "Phase 3: Organic Growth" "$CURRENT_PHASE"
assert_eq "phase-3-start: target" "+7%" "$CURRENT_TARGET"
assert_eq "phase-3-start: numeric" "7" "$TARGET_NUMERIC"

# Phase 3 mid
detect_phase "2026-05-15"
assert_eq "phase-3-mid: phase" "Phase 3: Organic Growth" "$CURRENT_PHASE"

# Phase 3 last day (boundary inclusive)
detect_phase "2026-07-04"
assert_eq "phase-3-end: phase" "Phase 3: Organic Growth" "$CURRENT_PHASE"

# Post-Phase 3
detect_phase "2026-07-05"
assert_eq "post-phase-3: phase" "Post-Phase 3" "$CURRENT_PHASE"
assert_eq "post-phase-3: target" "" "$CURRENT_TARGET"
assert_eq "post-phase-3: numeric" "" "$TARGET_NUMERIC"

# SNAPSHOT_EPOCH and P1_START_EPOCH are exported
detect_phase "2026-03-20"
assert_eq "exports-snapshot-epoch" "true" "$([[ -n "$SNAPSHOT_EPOCH" && "$SNAPSHOT_EPOCH" -gt 0 ]] && echo "true" || echo "false")"
assert_eq "exports-p1-start-epoch" "true" "$([[ -n "$P1_START_EPOCH" && "$P1_START_EPOCH" -gt 0 ]] && echo "true" || echo "false")"

# ============================================================
# Test Suite: determine_status
# ============================================================

echo "--- determine_status tests ---"

assert_eq "on-track (exceeds)" "on-track" "$(determine_status "20" "15")"
assert_eq "on-track (exact)" "on-track" "$(determine_status "15" "15")"
assert_eq "below-target" "below-target" "$(determine_status "5" "15")"
assert_eq "negative change" "below-target" "$(determine_status "-50" "15")"
assert_eq "no target" "N/A" "$(determine_status "20" "")"
assert_eq "no change" "N/A" "$(determine_status "" "15")"
assert_eq "null change" "N/A" "$(determine_status "null" "15")"

# ============================================================
# Test Suite: append_trend_row
# ============================================================

echo "--- append_trend_row tests ---"

TREND_DIR=$(mktemp -d)
TREND_FILE="$TREND_DIR/trend-summary.md"

# Test: file creation on first run
detect_phase "2026-03-20"
append_trend_row "$TREND_FILE" "2026-03-20" "42" "+20%" "20" "+15%" "15" "$SNAPSHOT_EPOCH" "$P1_START_EPOCH"

assert_eq "trend-file-created" "true" "$([[ -f "$TREND_FILE" ]] && echo "true" || echo "false")"
assert_eq "trend-has-header" "true" "$(grep -q 'Weekly Analytics Trend Summary' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-has-data-row" "true" "$(grep -q '2026-03-20' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-week-number" "true" "$(grep -q '| 2 |' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-status-on-track" "true" "$(grep -q 'on-track' "$TREND_FILE" && echo "true" || echo "false")"

row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-row-count" "1" "$row_count"

# Test: idempotency (same date should not add duplicate)
append_trend_row "$TREND_FILE" "2026-03-20" "42" "+20%" "20" "+15%" "15" "$SNAPSHOT_EPOCH" "$P1_START_EPOCH"

row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-idempotency" "1" "$row_count"

# Test: new date appends
detect_phase "2026-03-27"
append_trend_row "$TREND_FILE" "2026-03-27" "55" "+31%" "31" "+15%" "15" "$SNAPSHOT_EPOCH" "$P1_START_EPOCH"

row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-append-new-date" "2" "$row_count"

rm -rf "$TREND_DIR"

# ============================================================
# Test Suite: check_kpi_miss
# ============================================================

echo "--- check_kpi_miss tests ---"

run_kpi_test() {
  local label="$1" target="$2" change="$3" expected_key="$4" expected_val="$5"
  shift 5

  local kpi_dir
  kpi_dir=$(mktemp -d)
  GITHUB_OUTPUT="$kpi_dir/github-output"
  > "$GITHUB_OUTPUT"

  check_kpi_miss "$target" "$change" "Phase 1: Content Traction" "+15%" "+${change}%" "30" 2>/dev/null

  local result
  result="$(grep -q "${expected_key}=${expected_val}" "$GITHUB_OUTPUT" && echo "true" || echo "false")"
  assert_eq "$label" "true" "$result"

  rm -rf "$kpi_dir"
}

# KPI miss (actual < target)
run_kpi_test "kpi-miss-detected" "15" "5" "kpi_miss" "true"

# KPI hit (actual >= target)
run_kpi_test "kpi-hit" "15" "20" "kpi_miss" "false"

# Negative change (traffic drop)
run_kpi_test "kpi-negative-change" "15" "-50" "kpi_miss" "true"

# No target (post-phase)
run_kpi_test "kpi-no-target" "" "20" "kpi_miss" "false"

# Empty change (first week)
run_kpi_test "kpi-empty-change" "15" "" "kpi_miss" "false"

# Null change
run_kpi_test "kpi-null-change" "15" "null" "kpi_miss" "false"

# Verify KPI miss includes phase details
kpi_dir=$(mktemp -d)
GITHUB_OUTPUT="$kpi_dir/github-output"
> "$GITHUB_OUTPUT"
check_kpi_miss "15" "5" "Phase 1: Content Traction" "+15%" "+5%" "30" 2>/dev/null
assert_eq "kpi-miss-has-phase" "true" "$(grep -q 'kpi_phase=Phase 1' "$GITHUB_OUTPUT" && echo "true" || echo "false")"
assert_eq "kpi-miss-has-target" "true" "$(grep -q 'kpi_target=+15%' "$GITHUB_OUTPUT" && echo "true" || echo "false")"
assert_eq "kpi-miss-has-actual" "true" "$(grep -q 'kpi_actual=+5%' "$GITHUB_OUTPUT" && echo "true" || echo "false")"
assert_eq "kpi-miss-has-visitors" "true" "$(grep -q 'kpi_visitors=30' "$GITHUB_OUTPUT" && echo "true" || echo "false")"
rm -rf "$kpi_dir"

# ============================================================
# Results
# ============================================================

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
