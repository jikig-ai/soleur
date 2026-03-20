#!/usr/bin/env bash
# weekly-analytics.sh -- Pull weekly metrics from Plausible Analytics API v1
# and generate a markdown snapshot in knowledge-base/marketing/analytics/.
#
# Usage: weekly-analytics.sh
#   No arguments. Reads environment variables for configuration.
#
# Environment variables:
#   PLAUSIBLE_API_KEY   - Plausible API key (required; exits 0 if empty)
#   PLAUSIBLE_SITE_ID   - Plausible site ID, typically the domain e.g. soleur.ai (required; exits 0 if empty)
#   PLAUSIBLE_BASE_URL  - Plausible API base URL (optional; defaults to https://plausible.io)
#
# Exit codes:
#   0 - Snapshot generated, or graceful skip (missing credentials)
#   1 - API error (triggers Discord failure notification in CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/knowledge-base/marketing/analytics"

# --- Configuration ---

PLAUSIBLE_BASE_URL="${PLAUSIBLE_BASE_URL:-https://plausible.io}"

# --- Phase Configuration ---
# Source of truth: knowledge-base/marketing/marketing-strategy.md lines 343-347
# Update this file and the strategy doc in the same PR when phases change.
PHASE1_START="2026-03-13"
PHASE1_END="2026-04-10"
PHASE1_NAME="Phase 1: Content Traction"
PHASE1_TARGET=15

PHASE2_END="2026-05-09"
PHASE2_NAME="Phase 2: Content Velocity"
PHASE2_TARGET=10

PHASE3_END="2026-07-04"
PHASE3_NAME="Phase 3: Organic Growth"
PHASE3_TARGET=7

# --- Shared Functions (sourceable by test-weekly-analytics.sh) ---

to_epoch() {
  local date_str="$1"
  date -u -d "$date_str" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null
}

detect_phase() {
  local snapshot_date="$1"
  if [[ ! "$snapshot_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "detect_phase: invalid date format '${snapshot_date}'" >&2
    return 1
  fi

  SNAPSHOT_EPOCH=$(to_epoch "$snapshot_date")
  P1_START_EPOCH=$(to_epoch "$PHASE1_START")

  local p1_end_epoch p2_end_epoch p3_end_epoch
  p1_end_epoch=$(to_epoch "$PHASE1_END")
  p2_end_epoch=$(to_epoch "$PHASE2_END")
  p3_end_epoch=$(to_epoch "$PHASE3_END")

  if [[ "$SNAPSHOT_EPOCH" -lt "$P1_START_EPOCH" ]]; then
    CURRENT_PHASE="Pre-Phase 1"
    CURRENT_TARGET=""
    TARGET_NUMERIC=""
  elif [[ "$SNAPSHOT_EPOCH" -le "$p1_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE1_NAME"
    CURRENT_TARGET="+${PHASE1_TARGET}%"
    TARGET_NUMERIC="$PHASE1_TARGET"
  elif [[ "$SNAPSHOT_EPOCH" -le "$p2_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE2_NAME"
    CURRENT_TARGET="+${PHASE2_TARGET}%"
    TARGET_NUMERIC="$PHASE2_TARGET"
  elif [[ "$SNAPSHOT_EPOCH" -le "$p3_end_epoch" ]]; then
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

format_change() {
  local val="${1:-}"
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "N/A"
  elif [[ "$val" -gt 0 ]]; then
    echo "+${val}%"
  else
    echo "${val}%"
  fi
}

append_trend_row() {
  local trend_file="$1"
  local snapshot_date="$2"
  local visitors="${3:-0}"
  local visitors_delta="$4"
  local visitors_change="${5:-}"
  local current_target="${6:-}"
  local target_numeric="${7:-}"
  local snapshot_epoch="${8:-}"
  local p1_start_epoch="${9:-}"

  if [[ ! -f "$trend_file" ]]; then
    cat > "$trend_file" <<'TREND_HEADER'
# Weekly Analytics Trend Summary

| Week | Date | Visitors | WoW % | Target % | Status |
|------|------|----------|-------|----------|--------|
TREND_HEADER
  fi

  if grep -q "$snapshot_date" "$trend_file" 2>/dev/null; then
    return
  fi

  # Week number uses integer division (floors), so late re-runs
  # within the same week still produce the correct week number.
  local seconds_per_week=$((7 * 86400))
  local week_number=$(( (snapshot_epoch - p1_start_epoch) / seconds_per_week + 1 ))
  local status
  status=$(determine_status "$visitors_change" "$target_numeric")
  echo "| ${week_number} | ${snapshot_date} | ${visitors} | ${visitors_delta} | ${current_target:-N/A} | ${status} |" >> "$trend_file"
  echo "Trend summary updated: Week ${week_number}, status: ${status}"
}

emit_kpi_status() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

check_kpi_miss() {
  local target_numeric="${1:-}"
  local visitors_change="${2:-}"
  local current_phase="${3:-}"
  local current_target="${4:-}"
  local visitors_delta="${5:-}"
  local visitors="${6:-0}"

  if [[ -n "$target_numeric" && -n "$visitors_change" && "$visitors_change" != "null" ]]; then
    if [[ "$visitors_change" -lt "$target_numeric" ]]; then
      emit_kpi_status "kpi_miss" "true"
      emit_kpi_status "kpi_phase" "$current_phase"
      emit_kpi_status "kpi_target" "$current_target"
      emit_kpi_status "kpi_actual" "$visitors_delta"
      emit_kpi_status "kpi_visitors" "$visitors"
      echo "KPI miss detected: ${current_phase} target ${current_target} WoW, actual ${visitors_delta}" >&2
    else
      emit_kpi_status "kpi_miss" "false"
    fi
  else
    emit_kpi_status "kpi_miss" "false"
  fi
}

# --- Main (guarded for sourcing by tests) ---

main() {
  # --- Credential Check ---

  if [[ -z "${PLAUSIBLE_API_KEY:-}" ]]; then
    echo "PLAUSIBLE_API_KEY not set, skipping analytics snapshot"
    exit 0
  fi

  if [[ -z "${PLAUSIBLE_SITE_ID:-}" ]]; then
    echo "PLAUSIBLE_SITE_ID not set, skipping analytics snapshot"
    exit 0
  fi

  # --- Helper Functions ---

  api_get() {
    local endpoint="$1"
    local url="${PLAUSIBLE_BASE_URL}${endpoint}"
    local http_code
    local response_file
    response_file=$(mktemp)

    http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
      -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
      "$url")

    if [[ "$http_code" == "401" ]]; then
      echo "Plausible API authentication failed (HTTP 401). Check PLAUSIBLE_API_KEY." >&2
      rm -f "$response_file"
      exit 1
    fi

    if [[ "$http_code" == "429" ]]; then
      echo "Plausible API rate limited (HTTP 429). Try again later." >&2
      rm -f "$response_file"
      exit 1
    fi

    if [[ ! "$http_code" =~ ^2 ]]; then
      echo "Plausible API error (HTTP $http_code) for $url" >&2
      cat "$response_file" >&2
      rm -f "$response_file"
      exit 1
    fi

    cat "$response_file"
    rm -f "$response_file"
  }

  format_duration() {
    local seconds="$1"
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))
    if [[ "$mins" -gt 0 ]]; then
      echo "${mins}m ${secs}s"
    else
      echo "${secs}s"
    fi
  }

  # --- Fetch Data ---

  echo "Fetching Plausible analytics for ${PLAUSIBLE_SITE_ID}..."

  AGGREGATE=$(api_get "/api/v1/stats/aggregate?site_id=${PLAUSIBLE_SITE_ID}&period=7d&metrics=visitors,pageviews&compare=previous_period")
  TOP_PAGES=$(api_get "/api/v1/stats/breakdown?site_id=${PLAUSIBLE_SITE_ID}&period=7d&property=event:page&limit=10")
  TOP_SOURCES=$(api_get "/api/v1/stats/breakdown?site_id=${PLAUSIBLE_SITE_ID}&period=7d&property=visit:source&limit=10")

  # --- Parse Aggregate Metrics ---

  VISITORS=$(echo "$AGGREGATE" | jq '.results.visitors.value // empty')
  VISITORS_CHANGE=$(echo "$AGGREGATE" | jq '.results.visitors.change // empty')
  PAGEVIEWS=$(echo "$AGGREGATE" | jq '.results.pageviews.value // empty')
  PAGEVIEWS_CHANGE=$(echo "$AGGREGATE" | jq '.results.pageviews.change // empty')

  VISITORS_DELTA=$(format_change "$VISITORS_CHANGE")
  PAGEVIEWS_DELTA=$(format_change "$PAGEVIEWS_CHANGE")

  # --- Parse Top Pages ---

  PAGE_COUNT=$(echo "$TOP_PAGES" | jq '.results | length // 0')
  if [[ "$PAGE_COUNT" -eq 0 ]]; then
    PAGES_TABLE="| (No data) | - |"
  else
    PAGES_TABLE=$(echo "$TOP_PAGES" | jq -r '.results[] | "| \(.page // empty) | \(.visitors // 0) |"')
  fi

  # --- Parse Top Sources ---

  SOURCE_COUNT=$(echo "$TOP_SOURCES" | jq '.results | length // 0')
  if [[ "$SOURCE_COUNT" -eq 0 ]]; then
    SOURCES_TABLE="| (No data) | - |"
  else
    SOURCES_TABLE=$(echo "$TOP_SOURCES" | jq -r '.results[] | "| \(.source // empty) | \(.visitors // 0) |"')
  fi

  # --- Generate Snapshot ---

  SNAPSHOT_DATE=$(date -u +%Y-%m-%d)
  detect_phase "$SNAPSHOT_DATE"
  PERIOD_END="$SNAPSHOT_DATE"
  PERIOD_START=$(date -u -d "$SNAPSHOT_DATE - 6 days" +%Y-%m-%d 2>/dev/null || date -u -v-6d +%Y-%m-%d 2>/dev/null || echo "unknown")

  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/${SNAPSHOT_DATE}-weekly-analytics.md"

  cat > "$OUTPUT_FILE" <<SNAPSHOT
# Weekly Analytics: ${SNAPSHOT_DATE}

**Period:** ${PERIOD_START} to ${PERIOD_END}
**Generated:** automated

## Traffic

| Metric | This Week | Change |
|--------|-----------|--------|
| Unique visitors | ${VISITORS:-0} | ${VISITORS_DELTA} |
| Total pageviews | ${PAGEVIEWS:-0} | ${PAGEVIEWS_DELTA} |

**Growth target:** ${CURRENT_PHASE} -- target ${CURRENT_TARGET} WoW, actual ${VISITORS_DELTA}.

## Top Pages

| Page | Visitors |
|------|----------|
${PAGES_TABLE}

## Top Sources

| Source | Visitors |
|--------|----------|
${SOURCES_TABLE}
SNAPSHOT

  echo "Snapshot written to ${OUTPUT_FILE}"

  # --- Trend Summary ---

  TREND_FILE="$OUTPUT_DIR/trend-summary.md"
  append_trend_row "$TREND_FILE" "$SNAPSHOT_DATE" "${VISITORS:-0}" "$VISITORS_DELTA" \
    "${VISITORS_CHANGE:-}" "${CURRENT_TARGET:-}" "${TARGET_NUMERIC:-}" \
    "$SNAPSHOT_EPOCH" "$P1_START_EPOCH"

  # --- KPI Miss Detection ---

  check_kpi_miss "${TARGET_NUMERIC:-}" "${VISITORS_CHANGE:-}" \
    "$CURRENT_PHASE" "$CURRENT_TARGET" "$VISITORS_DELTA" "${VISITORS:-0}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
