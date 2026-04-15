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
#   0 - Goals provisioned, or graceful skip (missing credentials, plan lacks Sites API)
#   1 - API error or missing dependency

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Configuration ---

PLAUSIBLE_BASE_URL="${PLAUSIBLE_BASE_URL:-https://plausible.io}"

# --- Dependency Check ---

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install it: https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

# --- Input Validation ---

if [[ -z "${PLAUSIBLE_API_KEY:-}" ]]; then
  echo "PLAUSIBLE_API_KEY not set, skipping goal provisioning"
  exit 0
fi

if [[ -z "${PLAUSIBLE_SITE_ID:-}" ]]; then
  echo "PLAUSIBLE_SITE_ID not set, skipping goal provisioning"
  exit 0
fi

if [[ ! "$PLAUSIBLE_BASE_URL" =~ ^https:// ]]; then
  echo "Error: PLAUSIBLE_BASE_URL must use HTTPS" >&2
  exit 1
fi

if [[ ! "$PLAUSIBLE_SITE_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: PLAUSIBLE_SITE_ID contains invalid characters" >&2
  exit 1
fi

# --- Helper Functions ---

api_request() {
  local method="$1"
  local endpoint="$2"
  local payload="${3:-}"
  local url="${PLAUSIBLE_BASE_URL}${endpoint}"
  local http_code
  local response_file
  response_file=$(mktemp)
  trap 'rm -f "$response_file"' RETURN

  local curl_args=(-s -o "$response_file" -w "%{http_code}")
  curl_args+=(-H "Authorization: Bearer ${PLAUSIBLE_API_KEY}")

  if [[ "$method" == "PUT" ]]; then
    curl_args+=(-X PUT -H "Content-Type: application/json" -d "$payload")
  fi

  # Suppress stderr to prevent Bearer token leakage
  if ! http_code=$(curl "${curl_args[@]}" "$url" 2>/dev/null); then
    echo "Error: Failed to connect to ${url}" >&2
    exit 1
  fi

  case "$http_code" in
    2*)
      if ! jq . "$response_file" >/dev/null 2>&1; then
        echo "Error: Plausible API returned HTTP ${http_code} with malformed JSON body" >&2
        exit 1
      fi
      cat "$response_file"
      ;;
    401)
      echo "Plausible API returned 401 -- Sites API may require a higher plan." >&2
      exit 1
      ;;
    402)
      echo "Plausible API returned 402 -- this API endpoint requires a higher plan." >&2
      exit 1
      ;;
    429)
      echo "Error: Plausible API rate limited (HTTP 429). Try again later." >&2
      exit 1
      ;;
    *)
      local error_msg
      error_msg=$(jq -r '.error // "Unknown error"' "$response_file" 2>/dev/null || echo "Unknown error")
      echo "Error: Plausible API error (HTTP ${http_code}): ${error_msg}" >&2
      exit 1
      ;;
  esac
}

provision_goal() {
  local goal_type="$1"
  local value="${2:?provision_goal requires 2 arguments: goal_type and value}"
  local payload

  if [[ "$goal_type" == "event" ]]; then
    payload=$(jq -n --arg sid "$PLAUSIBLE_SITE_ID" --arg en "$value" \
      '{site_id: $sid, goal_type: "event", event_name: $en}')
  elif [[ "$goal_type" == "page" ]]; then
    payload=$(jq -n --arg sid "$PLAUSIBLE_SITE_ID" --arg pp "$value" \
      '{site_id: $sid, goal_type: "page", page_path: $pp}')
  else
    echo "Error: Unknown goal_type '${goal_type}' (expected 'event' or 'page')" >&2
    exit 1
  fi

  local response
  response=$(api_request PUT "/api/v1/sites/goals" "$payload")

  local display_name
  display_name=$(echo "$response" | jq -r '.display_name' 2>/dev/null || echo "$value")

  echo "[ok] Goal ready: ${display_name}"
}

# --- Preflight: Check API Plan Access ---
# api_request is called inside $() (subshell) where exit only exits the subshell,
# so plan-limitation checks must happen here before any $() calls.

_preflight_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
  "${PLAUSIBLE_BASE_URL}/api/v1/sites/goals?site_id=${PLAUSIBLE_SITE_ID}" 2>/dev/null)
if [[ "$_preflight_code" == "401" || "$_preflight_code" == "402" ]]; then
  echo "Plausible API returned ${_preflight_code} -- Sites/Goals API requires a higher plan."
  echo "Skipping goal provisioning. Goals can be configured manually in the dashboard."
  echo "This workflow will provision goals automatically once the plan includes API access."
  exit 0
fi

# --- Provision Goals ---

echo "Provisioning Plausible goals for ${PLAUSIBLE_SITE_ID}..."

provision_goal "event" "Newsletter Signup"
provision_goal "event" "Waitlist Signup"
provision_goal "page"  "/pages/getting-started.html"
provision_goal "page"  "/blog/*"
provision_goal "event" "Outbound Link: Click"

# kb-chat-sidebar (#2345) — selection → quoted-chat flow.
# Emitted from apps/web-platform via /api/analytics/track → Plausible.
provision_goal "event" "kb.chat.opened"
provision_goal "event" "kb.chat.selection_sent"
provision_goal "event" "kb.chat.thread_resumed"

# --- Verify Goals ---

echo ""
echo "Verifying goals..."

goal_list=$(api_request GET "/api/v1/sites/goals?site_id=${PLAUSIBLE_SITE_ID}")
goal_count=$(echo "$goal_list" | jq '.goals | length // 0' 2>/dev/null || echo "0")

echo "[ok] Verified: ${goal_count} goals configured for ${PLAUSIBLE_SITE_ID}"
