#!/usr/bin/env bash
# linkedin-community.sh -- LinkedIn API wrapper for community operations
#
# Usage: linkedin-community.sh <command> [args]
# Commands:
#   post-content --text "<text>" [--author "<urn>"]  - Post to LinkedIn (person or company page)
#   fetch-metrics                  - Fetch account metrics (requires Marketing API)
#   fetch-activity                 - Fetch account activity (requires Marketing API)
#
# Environment variables (required):
#   LINKEDIN_ACCESS_TOKEN      - OAuth 2.0 Bearer token for personal posts (60-day TTL)
#   LINKEDIN_ORG_ACCESS_TOKEN  - OAuth 2.0 Bearer token for organization/company page posts
#                                (requires w_organization_social scope; required when
#                                --author is urn:li:organization:*)
#   LINKEDIN_PERSON_URN    - Person URN for posting (urn:li:person:{id}), optional if --author provided
#   LINKEDIN_ALLOW_POST    - Set to "true" to enable posting (safety guard, default: disabled)
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Retryable error (rate limit exhaustion)
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

LINKEDIN_API="https://api.linkedin.com"
LINKEDIN_API_VERSION="202602"
LINKEDIN_POST_MAX_LENGTH=3000

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- Credential validation ---

require_credentials() {
  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    echo "Error: Missing LinkedIn credentials: LINKEDIN_ACCESS_TOKEN" >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Run: linkedin-setup.sh generate-token" >&2
    echo "  2. Or set LINKEDIN_ACCESS_TOKEN manually" >&2
    echo "  3. Run: linkedin-setup.sh verify" >&2
    exit 1
  fi
}

# --- Response handler ---

# Handle HTTP response status codes from LinkedIn API
# Arguments: http_code body endpoint depth retry_cmd...
# On 2xx: validates JSON, echoes body to stdout
# On 429: sleeps and invokes retry_cmd (caller with incremented depth)
# On error: prints diagnostic to stderr, exits 1 (or 2 for rate limit exhaustion)
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  local depth="$4"
  shift 4
  local -a retry_cmd=("$@")

  case "$http_code" in
    2[0-9][0-9])
      # LinkedIn POST /rest/posts returns 201 with empty body -- that is valid
      if [[ -n "$body" ]] && ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: LinkedIn API returned malformed JSON for ${endpoint}" >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: LinkedIn API returned 401 Unauthorized for ${endpoint}." >&2
      echo "Your access token may be expired (60-day TTL)." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Run: linkedin-setup.sh validate-credentials" >&2
      echo "  2. If expired, run: linkedin-setup.sh generate-token" >&2
      exit 1
      ;;
    403)
      local message
      message=$(echo "$body" | jq -r '.message // .code // "Access denied"' 2>/dev/null || echo "Access denied")
      echo "Error: LinkedIn API returned 403 Forbidden for ${endpoint}: ${message}" >&2
      exit 1
      ;;
    429)
      if (( depth >= 3 )); then
        echo "Error: LinkedIn API rate limit exceeded after 3 retries for ${endpoint}." >&2
        exit 2
      fi
      echo "Rate limited. Retrying after 5s (attempt $((depth + 1))/3)..." >&2
      sleep 5
      "${retry_cmd[@]}"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.message // .code // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: LinkedIn API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- GET request helper ---

# Make an authenticated GET request to the LinkedIn API
# Arguments: endpoint [depth]
# Retries on 429 up to 3 times
get_request() {
  local endpoint="$1"
  local depth="${2:-0}"

  if (( depth >= 3 )); then
    echo "Error: LinkedIn API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${LINKEDIN_API}${endpoint}"

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}" \
    -H "X-Restli-Protocol-Version: 2.0.0" \
    -H "LinkedIn-Version: ${LINKEDIN_API_VERSION}" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to LinkedIn API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$((depth + 1))"
}

# --- POST request helper ---

# Make an authenticated POST request to the LinkedIn API
# Arguments: endpoint json_body [depth]
# Captures response headers via temp file to extract x-restli-id
# Only retries on 429 (POST is not idempotent)
post_request() {
  local endpoint="$1"
  local json_body="$2"
  local depth="${3:-0}"

  local url="${LINKEDIN_API}${endpoint}"

  local header_file
  header_file=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -f '$header_file'" EXIT

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -D "$header_file" \
    -H "Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}" \
    -H "X-Restli-Protocol-Version: 2.0.0" \
    -H "LinkedIn-Version: ${LINKEDIN_API_VERSION}" \
    -H "Content-Type: application/json" \
    -X POST -d "$json_body" \
    "$url" 2>/dev/null); then
    rm -f "$header_file"
    echo "Error: Failed to connect to LinkedIn API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  # On 429, retry (rate limit returned before post is created)
  if [[ "$http_code" == "429" ]]; then
    rm -f "$header_file"
    handle_response "$http_code" "$body" "$endpoint" "$depth" \
      post_request "$endpoint" "$json_body" "$((depth + 1))"
    return
  fi

  # For non-429 errors on POST, fail immediately (non-idempotent)
  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "$header_file"
    handle_response "$http_code" "$body" "$endpoint" "$depth"
    return
  fi

  # Success: extract x-restli-id from response headers
  local restli_id=""
  if [[ -f "$header_file" ]]; then
    restli_id=$(grep -i '^x-restli-id:' "$header_file" | sed 's/^[^:]*: *//' | tr -d '\r' || true)
  fi
  rm -f "$header_file"

  # Return JSON with post URN
  if [[ -n "$restli_id" ]]; then
    jq -n --arg id "$restli_id" '{"post_urn": $id}'
  else
    echo '{"post_urn": null}' >&2
    echo "Warning: Post created but x-restli-id header not found in response." >&2
    # Still return valid JSON
    echo '{}'
  fi
}

# --- Commands ---

cmd_post_content() {
  # Guard: require explicit opt-in to post.
  if [[ "${LINKEDIN_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: LINKEDIN_ALLOW_POST is not set to 'true'." >&2
    echo "Set LINKEDIN_ALLOW_POST=true to enable posting." >&2
    return 1
  fi

  local text=""
  local author_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text)
        text="${2:-}"
        if [[ -z "$text" ]]; then
          echo "Error: --text requires a non-empty value." >&2
          exit 1
        fi
        shift 2
        ;;
      --author)
        author_override="${2:-}"
        if [[ -z "$author_override" ]]; then
          echo "Error: --author requires a non-empty value." >&2
          exit 1
        fi
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        echo "Usage: linkedin-community.sh post-content --text \"<text>\" [--author \"<urn>\"]" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$text" ]]; then
    echo "Error: --text is required." >&2
    echo "Usage: linkedin-community.sh post-content --text \"<text>\"" >&2
    exit 1
  fi

  if (( ${#text} > LINKEDIN_POST_MAX_LENGTH )); then
    echo "Error: Post text is ${#text} characters, exceeds LinkedIn's ${LINKEDIN_POST_MAX_LENGTH}-character limit." >&2
    exit 1
  fi

  # Build request body (--author overrides default LINKEDIN_PERSON_URN)
  local author="${author_override:-${LINKEDIN_PERSON_URN:-}}"
  if [[ -z "$author" ]]; then
    echo "Error: No author specified. Provide --author or set LINKEDIN_PERSON_URN." >&2
    exit 1
  fi

  # Normalize bare person IDs: LinkedIn API requires full URN (urn:li:person:<id>).
  # LINKEDIN_PERSON_URN is often stored as just the ID portion without the prefix.
  if [[ "$author" != urn:* ]]; then
    author="urn:li:person:${author}"
  fi

  # Organization posts require w_organization_social scope -- use LINKEDIN_ORG_ACCESS_TOKEN.
  if [[ "$author" == urn:li:organization:* ]]; then
    if [[ -z "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]]; then
      echo "Error: LINKEDIN_ORG_ACCESS_TOKEN is required for organization posts (w_organization_social scope)." >&2
      echo "Set LINKEDIN_ORG_ACCESS_TOKEN to a token with w_organization_social scope." >&2
      exit 1
    fi
    LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"
  fi

  local json_body
  json_body=$(jq -n \
    --arg author "$author" \
    --arg text "$text" \
    '{
      author: $author,
      commentary: $text,
      visibility: "PUBLIC",
      distribution: {
        feedDistribution: "MAIN_FEED",
        targetEntities: [],
        thirdPartyDistributionChannels: []
      },
      lifecycleState: "PUBLISHED",
      isReshareDisabledByAuthor: false
    }')

  local result
  result=$(post_request "/rest/posts" "$json_body")

  echo "$result"
  echo "Post created successfully." >&2
}

cmd_fetch_metrics() {
  echo "Error: fetch-metrics requires Marketing API credentials (MDP partner approval)." >&2
  echo "Apply at: https://learn.microsoft.com/en-us/linkedin/marketing/" >&2
  exit 1
}

cmd_fetch_activity() {
  echo "Error: fetch-activity requires Marketing API credentials (MDP partner approval)." >&2
  echo "Apply at: https://learn.microsoft.com/en-us/linkedin/marketing/" >&2
  exit 1
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: linkedin-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  post-content --text \"<text>\" [--author \"<urn>\"]  - Post to LinkedIn" >&2
    echo "  fetch-metrics                 - Fetch account metrics (Marketing API)" >&2
    echo "  fetch-activity                - Fetch account activity (Marketing API)" >&2
    exit 1
  fi

  require_jq

  # Stubs don't need credentials -- they exit before calling any API
  case "$command" in
    fetch-metrics)   cmd_fetch_metrics ;;
    fetch-activity)  cmd_fetch_activity ;;
    post-content)
      require_credentials
      cmd_post_content "$@"
      ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'linkedin-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

# Guard: allow sourcing without executing main (for test harness)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
