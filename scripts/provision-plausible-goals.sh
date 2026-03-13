#!/usr/bin/env bash
# provision-plausible-goals.sh -- Provision Plausible conversion goals via the Goals API
#
# Usage: provision-plausible-goals.sh
#   No arguments. Reads environment variables for configuration.
#
# Environment variables:
#   PLAUSIBLE_API_KEY   - Plausible API key (required; exits 0 if empty)
#   PLAUSIBLE_SITE_ID   - Plausible site ID, typically the domain e.g. soleur.ai (required; exits 0 if empty)
#   PLAUSIBLE_BASE_URL  - Plausible API base URL (optional; defaults to https://plausible.io)
#
# Exit codes:
#   0 - Goals provisioned, or graceful skip (missing credentials)
#   1 - API error or missing dependency

set -euo pipefail

# --- Configuration ---

PLAUSIBLE_BASE_URL="${PLAUSIBLE_BASE_URL:-https://plausible.io}"

# --- Dependency Check ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

require_jq

# --- Credential Check ---

if [[ -z "${PLAUSIBLE_API_KEY:-}" ]]; then
  echo "PLAUSIBLE_API_KEY not set, skipping goal provisioning"
  exit 0
fi

if [[ -z "${PLAUSIBLE_SITE_ID:-}" ]]; then
  echo "PLAUSIBLE_SITE_ID not set, skipping goal provisioning"
  exit 0
fi

# --- Helper Functions ---

api_put() {
  local endpoint="$1"
  local payload="$2"
  local url="${PLAUSIBLE_BASE_URL}${endpoint}"
  local http_code
  local response_file
  response_file=$(mktemp)

  # Transport layer: suppress stderr to prevent Bearer token leakage
  if ! http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to ${url}" >&2
    rm -f "$response_file"
    exit 1
  fi

  # Response status layer
  case "$http_code" in
    2*)
      # Validate JSON on 2xx before consuming
      if ! jq . "$response_file" >/dev/null 2>&1; then
        echo "Error: Plausible API returned HTTP ${http_code} with malformed JSON body" >&2
        rm -f "$response_file"
        exit 1
      fi
      cat "$response_file"
      ;;
    401)
      echo "Error: Plausible API authentication failed (HTTP 401). Check PLAUSIBLE_API_KEY." >&2
      rm -f "$response_file"
      exit 1
      ;;
    429)
      echo "Error: Plausible API rate limited (HTTP 429). Try again later." >&2
      rm -f "$response_file"
      exit 1
      ;;
    *)
      local error_msg
      error_msg=$(jq -r '.error // "Unknown error"' "$response_file" 2>/dev/null || echo "Unknown error")
      echo "Error: Plausible API error (HTTP ${http_code}): ${error_msg}" >&2
      rm -f "$response_file"
      exit 1
      ;;
  esac

  rm -f "$response_file"
}

api_get() {
  local endpoint="$1"
  local url="${PLAUSIBLE_BASE_URL}${endpoint}"
  local http_code
  local response_file
  response_file=$(mktemp)

  if ! http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
    -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to ${url}" >&2
    rm -f "$response_file"
    exit 1
  fi

  case "$http_code" in
    2*)
      if ! jq . "$response_file" >/dev/null 2>&1; then
        echo "Error: Plausible API returned HTTP ${http_code} with malformed JSON body" >&2
        rm -f "$response_file"
        exit 1
      fi
      cat "$response_file"
      ;;
    401)
      echo "Error: Plausible API authentication failed (HTTP 401). Check PLAUSIBLE_API_KEY." >&2
      rm -f "$response_file"
      exit 1
      ;;
    429)
      echo "Error: Plausible API rate limited (HTTP 429). Try again later." >&2
      rm -f "$response_file"
      exit 1
      ;;
    *)
      local error_msg
      error_msg=$(jq -r '.error // "Unknown error"' "$response_file" 2>/dev/null || echo "Unknown error")
      echo "Error: Plausible API error (HTTP ${http_code}): ${error_msg}" >&2
      rm -f "$response_file"
      exit 1
      ;;
  esac

  rm -f "$response_file"
}

provision_goal() {
  local goal_type="$1"
  local label="$2"
  local payload

  if [[ "$goal_type" == "event" ]]; then
    local event_name="$3"
    payload=$(jq -n --arg sid "$PLAUSIBLE_SITE_ID" --arg en "$event_name" \
      '{site_id: $sid, goal_type: "event", event_name: $en}')
  elif [[ "$goal_type" == "page" ]]; then
    local page_path="$3"
    payload=$(jq -n --arg sid "$PLAUSIBLE_SITE_ID" --arg pp "$page_path" \
      '{site_id: $sid, goal_type: "page", page_path: $pp}')
  fi

  local response
  response=$(api_put "/api/v1/sites/goals" "$payload")

  local display_name
  display_name=$(echo "$response" | jq -r '.display_name // "unknown"' 2>/dev/null || echo "$label")

  echo "[ok] Goal ready: ${display_name}"
}

# --- Provision Goals ---

echo "Provisioning Plausible goals for ${PLAUSIBLE_SITE_ID}..."

provision_goal "event" "Newsletter Signup" "Newsletter Signup"
provision_goal "page"  "Getting Started pageview" "/pages/getting-started.html"
provision_goal "page"  "Blog article pageviews" "/blog/*"
provision_goal "event" "Outbound Link: Click" "Outbound Link: Click"

# --- Verify Goals ---

echo ""
echo "Verifying goals..."

goal_list=$(api_get "/api/v1/sites/goals?site_id=${PLAUSIBLE_SITE_ID}")
goal_count=$(echo "$goal_list" | jq '.goals | length // 0' 2>/dev/null || echo "0")

echo "[ok] Verified: ${goal_count} goals configured for ${PLAUSIBLE_SITE_ID}"
