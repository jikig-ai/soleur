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
# Source of truth: knowledge-base/marketing/marketing-strategy.md lines 335-339
# Update both files in the same PR when phases change.
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

# Format change values with sign
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
SECONDS_PER_WEEK=$((7 * 86400))

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

if [[ ! -f "$TREND_FILE" ]]; then
  cat > "$TREND_FILE" <<'TREND_HEADER'
# Weekly Analytics Trend Summary

| Week | Date | Visitors | WoW % | Target % | Status |
|------|------|----------|-------|----------|--------|
TREND_HEADER
fi

# Idempotency: skip if this date already has a row
if ! grep -q "$SNAPSHOT_DATE" "$TREND_FILE" 2>/dev/null; then
  local_snapshot_epoch=$(date -u -d "$SNAPSHOT_DATE" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$SNAPSHOT_DATE" +%s 2>/dev/null)
  local_p1_start_epoch=$(date -u -d "$PHASE1_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_START" +%s 2>/dev/null)
  week_number=$(( (local_snapshot_epoch - local_p1_start_epoch) / SECONDS_PER_WEEK + 1 ))
  status=$(determine_status "${VISITORS_CHANGE:-}" "${TARGET_NUMERIC:-}")
  echo "| ${week_number} | ${SNAPSHOT_DATE} | ${VISITORS:-0} | ${VISITORS_DELTA} | ${CURRENT_TARGET:-N/A} | ${status} |" >> "$TREND_FILE"
  echo "Trend summary updated: Week ${week_number}, status: ${status}"
fi

# --- KPI Miss Detection ---

emit_kpi_status() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

if [[ -n "${TARGET_NUMERIC:-}" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
    emit_kpi_status "kpi_phase" "$CURRENT_PHASE"
    emit_kpi_status "kpi_target" "$CURRENT_TARGET"
    emit_kpi_status "kpi_actual" "$VISITORS_DELTA"
    emit_kpi_status "kpi_visitors" "${VISITORS:-0}"
    echo "KPI miss detected: ${CURRENT_PHASE} target ${CURRENT_TARGET} WoW, actual ${VISITORS_DELTA}" >&2
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi
