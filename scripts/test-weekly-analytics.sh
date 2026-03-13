#!/usr/bin/env bash
# test-weekly-analytics.sh -- Unit tests for weekly-analytics.sh functions.
# Tests detect_phase(), determine_status(), trend summary, and KPI miss logic.
#
# Usage: bash scripts/test-weekly-analytics.sh
#   Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

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

# --- Phase Configuration (duplicated from weekly-analytics.sh to isolate tests) ---

PHASE1_START="2026-03-13"
PHASE1_END="2026-04-10"
PHASE1_NAME="Phase 1: Content Traction"
PHASE1_TARGET=15

PHASE2_START="2026-04-11"
PHASE2_END="2026-05-09"
PHASE2_NAME="Phase 2: Content Velocity"
PHASE2_TARGET=10

PHASE3_START="2026-05-10"
PHASE3_END="2026-07-04"
PHASE3_NAME="Phase 3: Organic Growth"
PHASE3_TARGET=7

# --- Functions under test (copied to avoid sourcing the full script) ---

detect_phase() {
  local snapshot_date="$1"
  local snapshot_epoch
  snapshot_epoch=$(date -u -d "$snapshot_date" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$snapshot_date" +%s 2>/dev/null)

  local p1_start_epoch p1_end_epoch p2_end_epoch p3_end_epoch
  p1_start_epoch=$(date -u -d "$PHASE1_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_START" +%s 2>/dev/null)
  p1_end_epoch=$(date -u -d "$PHASE1_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_END" +%s 2>/dev/null)
  p2_end_epoch=$(date -u -d "$PHASE2_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE2_END" +%s 2>/dev/null)
  p3_end_epoch=$(date -u -d "$PHASE3_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE3_END" +%s 2>/dev/null)

  if [[ "$snapshot_epoch" -lt "$p1_start_epoch" ]]; then
    CURRENT_PHASE="Pre-Phase 1"
    CURRENT_TARGET=""
    TARGET_NUMERIC=""
  elif [[ "$snapshot_epoch" -le "$p1_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE1_NAME"
    CURRENT_TARGET="+${PHASE1_TARGET}%"
    TARGET_NUMERIC="$PHASE1_TARGET"
  elif [[ "$snapshot_epoch" -le "$p2_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE2_NAME"
    CURRENT_TARGET="+${PHASE2_TARGET}%"
    TARGET_NUMERIC="$PHASE2_TARGET"
  elif [[ "$snapshot_epoch" -le "$p3_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE3_NAME"
    CURRENT_TARGET="+${PHASE3_TARGET}%"
    TARGET_NUMERIC="$PHASE3_TARGET"
  else
    CURRENT_PHASE="Post-Phase 3"
    CURRENT_TARGET=""
    TARGET_NUMERIC=""
  fi
}

determine_status() {
  local wow_change="${1:-}"
  local target="${2:-}"

  if [[ -z "$target" || -z "$wow_change" || "$wow_change" == "null" ]]; then
    echo "N/A"
    return
  fi

  if [[ "$wow_change" -ge "$target" ]]; then
    echo "on-track"
  else
    echo "below-target"
  fi
}

# ============================================================
# Test Suite: detect_phase
# ============================================================

echo "--- detect_phase tests ---"

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
# Test Suite: Trend summary
# ============================================================

echo "--- trend summary tests ---"

TREND_DIR=$(mktemp -d)
TREND_FILE="$TREND_DIR/trend-summary.md"
SECONDS_PER_WEEK=$((7 * 86400))

# Test: file creation on first run
SNAPSHOT_DATE="2026-03-20"
detect_phase "$SNAPSHOT_DATE"
VISITORS=42
VISITORS_CHANGE=20
VISITORS_DELTA="+20%"

if [[ ! -f "$TREND_FILE" ]]; then
  cat > "$TREND_FILE" <<'TREND_HEADER'
# Weekly Analytics Trend Summary

| Week | Date | Visitors | WoW % | Target % | Status |
|------|------|----------|-------|----------|--------|
TREND_HEADER
fi

if ! grep -q "$SNAPSHOT_DATE" "$TREND_FILE" 2>/dev/null; then
  local_snapshot_epoch=$(date -u -d "$SNAPSHOT_DATE" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$SNAPSHOT_DATE" +%s 2>/dev/null)
  local_p1_start_epoch=$(date -u -d "$PHASE1_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_START" +%s 2>/dev/null)
  week_number=$(( (local_snapshot_epoch - local_p1_start_epoch) / SECONDS_PER_WEEK + 1 ))
  status=$(determine_status "${VISITORS_CHANGE:-}" "${TARGET_NUMERIC:-}")
  echo "| ${week_number} | ${SNAPSHOT_DATE} | ${VISITORS:-0} | ${VISITORS_DELTA} | ${CURRENT_TARGET:-N/A} | ${status} |" >> "$TREND_FILE"
fi

assert_eq "trend-file-created" "true" "$([[ -f "$TREND_FILE" ]] && echo "true" || echo "false")"
assert_eq "trend-has-header" "true" "$(grep -q 'Weekly Analytics Trend Summary' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-has-data-row" "true" "$(grep -q '2026-03-20' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-week-number" "true" "$(grep -q '| 2 |' "$TREND_FILE" && echo "true" || echo "false")"
assert_eq "trend-status-on-track" "true" "$(grep -q 'on-track' "$TREND_FILE" && echo "true" || echo "false")"

# Count data rows (lines starting with | that aren't header/separator)
row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-row-count" "1" "$row_count"

# Test: idempotency (same date should not add duplicate)
if ! grep -q "$SNAPSHOT_DATE" "$TREND_FILE" 2>/dev/null; then
  echo "| 2 | ${SNAPSHOT_DATE} | 42 | +20% | +15% | on-track |" >> "$TREND_FILE"
fi

row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-idempotency" "1" "$row_count"

# Test: new date appends
SNAPSHOT_DATE="2026-03-27"
detect_phase "$SNAPSHOT_DATE"
VISITORS=55
VISITORS_CHANGE=31
VISITORS_DELTA="+31%"

if ! grep -q "$SNAPSHOT_DATE" "$TREND_FILE" 2>/dev/null; then
  local_snapshot_epoch=$(date -u -d "$SNAPSHOT_DATE" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$SNAPSHOT_DATE" +%s 2>/dev/null)
  local_p1_start_epoch=$(date -u -d "$PHASE1_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_START" +%s 2>/dev/null)
  week_number=$(( (local_snapshot_epoch - local_p1_start_epoch) / SECONDS_PER_WEEK + 1 ))
  status=$(determine_status "${VISITORS_CHANGE:-}" "${TARGET_NUMERIC:-}")
  echo "| ${week_number} | ${SNAPSHOT_DATE} | ${VISITORS:-0} | ${VISITORS_DELTA} | ${CURRENT_TARGET:-N/A} | ${status} |" >> "$TREND_FILE"
fi

row_count=$(grep -c '^| [0-9]' "$TREND_FILE" || true)
assert_eq "trend-append-new-date" "2" "$row_count"

rm -rf "$TREND_DIR"

# ============================================================
# Test Suite: KPI miss detection
# ============================================================

echo "--- KPI miss detection tests ---"

KPI_DIR=$(mktemp -d)
GITHUB_OUTPUT="$KPI_DIR/github-output"

emit_kpi_status() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

# Test: KPI miss (actual < target)
> "$GITHUB_OUTPUT"
TARGET_NUMERIC="15"
VISITORS_CHANGE="5"
CURRENT_PHASE="Phase 1: Content Traction"
CURRENT_TARGET="+15%"
VISITORS_DELTA="+5%"
VISITORS="30"

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
    emit_kpi_status "kpi_phase" "$CURRENT_PHASE"
    emit_kpi_status "kpi_target" "$CURRENT_TARGET"
    emit_kpi_status "kpi_actual" "$VISITORS_DELTA"
    emit_kpi_status "kpi_visitors" "${VISITORS:-0}"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-miss-detected" "true" "$(grep -q 'kpi_miss=true' "$GITHUB_OUTPUT" && echo "true" || echo "false")"
assert_eq "kpi-miss-phase" "true" "$(grep -q 'kpi_phase=Phase 1' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

# Test: KPI hit (actual >= target)
> "$GITHUB_OUTPUT"
VISITORS_CHANGE="20"
VISITORS_DELTA="+20%"

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-hit" "true" "$(grep -q 'kpi_miss=false' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

# Test: KPI miss with negative change (traffic drop)
> "$GITHUB_OUTPUT"
VISITORS_CHANGE="-50"

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-negative-change" "true" "$(grep -q 'kpi_miss=true' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

# Test: No target (post-phase) => kpi_miss=false
> "$GITHUB_OUTPUT"
TARGET_NUMERIC=""
VISITORS_CHANGE="20"

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-no-target" "true" "$(grep -q 'kpi_miss=false' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

# Test: Empty change (first week) => kpi_miss=false
> "$GITHUB_OUTPUT"
TARGET_NUMERIC="15"
VISITORS_CHANGE=""

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-empty-change" "true" "$(grep -q 'kpi_miss=false' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

# Test: null change => kpi_miss=false
> "$GITHUB_OUTPUT"
VISITORS_CHANGE="null"

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi

assert_eq "kpi-null-change" "true" "$(grep -q 'kpi_miss=false' "$GITHUB_OUTPUT" && echo "true" || echo "false")"

rm -rf "$KPI_DIR"

# ============================================================
# Results
# ============================================================

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
