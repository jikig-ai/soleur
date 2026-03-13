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

# Growth target phase -- update manually when phases change.
# Phase 1: Weeks 1-4 (Mar 13 - Apr 10)  +15% WoW
# Phase 2: Weeks 5-8 (Apr 11 - May 9)   +10% WoW
# Phase 3: Weeks 9-16 (May 10 - Jul 4)  +7% WoW
CURRENT_PHASE="Phase 1: Content Traction"
CURRENT_TARGET="+15%"

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
