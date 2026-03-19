#!/usr/bin/env bash
# bsky-community.sh -- Bluesky AT Protocol wrapper for community operations
#
# Usage: bsky-community.sh <command> [args]
# Commands:
#   create-session                                           - Test auth, output session JSON
#   post <text> [--reply-to-uri URI --reply-to-cid CID       - Create a post (optionally as reply)
#                --root-uri URI --root-cid CID]
#   get-metrics                                              - Fetch profile stats (followers, etc.)
#   get-notifications [--limit N] [--cursor CURSOR]          - Fetch mention notifications
#
# Environment variables (required):
#   BSKY_HANDLE        - Bluesky handle (e.g., soleur.bsky.social)
#   BSKY_APP_PASSWORD  - App password
#   BSKY_ALLOW_POST    - Set to "true" to enable posting (defense-in-depth guard)
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Rate limit exhausted after retries
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

BSKY_API="https://bsky.social/xrpc"

# --- Session state (per-invocation, not cached) ---

ACCESS_JWT=""
USER_DID=""

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

require_credentials() {
  local missing=()

  if [[ -z "${BSKY_HANDLE:-}" ]]; then
    missing+=("BSKY_HANDLE")
  fi
  if [[ -z "${BSKY_APP_PASSWORD:-}" ]]; then
    missing+=("BSKY_APP_PASSWORD")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing Bluesky credentials: ${missing[*]}" >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Create an account at https://bsky.app" >&2
    echo "  2. Go to Settings > App Passwords > Add App Password" >&2
    echo "  3. Export BSKY_HANDLE and BSKY_APP_PASSWORD as environment variables" >&2
    exit 1
  fi
}

# --- Session management ---

# Create a fresh session. Sets ACCESS_JWT and USER_DID globals.
create_session() {
  local response http_code body

  if ! response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"identifier\": \"${BSKY_HANDLE}\", \"password\": \"${BSKY_APP_PASSWORD}\"}" \
    "${BSKY_API}/com.atproto.server.createSession" 2>/dev/null); then
    echo "Error: Failed to connect to Bluesky API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: Bluesky API returned malformed JSON for createSession." >&2
        exit 1
      fi
      ACCESS_JWT=$(echo "$body" | jq -r '.accessJwt // empty')
      USER_DID=$(echo "$body" | jq -r '.did // empty')
      if [[ -z "$ACCESS_JWT" || -z "$USER_DID" ]]; then
        echo "Error: Session response missing accessJwt or DID." >&2
        exit 1
      fi
      ;;
    401)
      echo "Error: Bluesky returned 401 Unauthorized." >&2
      echo "Your handle or app password may be incorrect." >&2
      exit 1
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.message // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: Bluesky API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- Response handling ---

# Handle HTTP response from Bluesky API
# Arguments: http_code body endpoint depth retry_cmd...
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  local depth="$4"
  shift 4
  local -a retry_cmd=("$@")

  case "$http_code" in
    2[0-9][0-9])
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: Bluesky API returned malformed JSON for ${endpoint}." >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: Bluesky API returned 401 Unauthorized for ${endpoint}." >&2
      echo "Your credentials may be expired or invalid." >&2
      exit 1
      ;;
    429)
      # Bluesky uses ratelimit-reset header (Unix timestamp).
      # In curl response body, fall back to a sensible default.
      local retry_after=5
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      "${retry_cmd[@]}"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.message // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: Bluesky API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- Request helpers ---

# Make an authenticated GET request
# Arguments: endpoint [query_string] [depth]
get_request() {
  local endpoint="$1"
  local query_string="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: Bluesky API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${BSKY_API}/${endpoint}"
  if [[ -n "$query_string" ]]; then
    url="${url}?${query_string}"
  fi

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_JWT}" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to Bluesky API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$query_string" "$((depth + 1))"
}

# Make an authenticated POST request
# Arguments: endpoint [json_body] [depth]
post_request() {
  local endpoint="$1"
  local json_body="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: Bluesky API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${BSKY_API}/${endpoint}"
  local -a curl_args=(
    -s -w "\n%{http_code}"
    -H "Authorization: Bearer ${ACCESS_JWT}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$json_body" ]]; then
    curl_args+=(-X POST -d "$json_body")
  fi

  local response http_code body
  if ! response=$(curl "${curl_args[@]}" "$url" 2>/dev/null); then
    echo "Error: Failed to connect to Bluesky API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    post_request "$endpoint" "$json_body" "$((depth + 1))"
}

# --- Commands ---

cmd_create_session() {
  create_session
  echo "{\"did\": \"${USER_DID}\", \"handle\": \"${BSKY_HANDLE}\"}" | jq .
  echo "Session created for @${BSKY_HANDLE} (${USER_DID})" >&2
}

cmd_post() {
  # Guard: require explicit opt-in to post.
  if [[ "${BSKY_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: BSKY_ALLOW_POST is not set to 'true'." >&2
    echo "Set BSKY_ALLOW_POST=true to enable posting." >&2
    return 1
  fi

  local text=""
  local reply_to_uri="" reply_to_cid="" root_uri="" root_cid=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reply-to-uri) reply_to_uri="$2"; shift 2 ;;
      --reply-to-cid) reply_to_cid="$2"; shift 2 ;;
      --root-uri)     root_uri="$2"; shift 2 ;;
      --root-cid)     root_cid="$2"; shift 2 ;;
      *)
        if [[ -z "$text" ]]; then
          text="$1"
        else
          echo "Error: Unexpected argument '$1'" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$text" ]]; then
    echo "Error: Post text is required." >&2
    echo "Usage: bsky-community.sh post <text> [--reply-to-uri URI --reply-to-cid CID --root-uri URI --root-cid CID]" >&2
    exit 1
  fi

  # Validate length (codepoint count as grapheme approximation)
  local char_count
  char_count=$(printf '%s' "$text" | wc -m)
  if (( char_count > 300 )); then
    echo "Error: Post exceeds 300 character limit (${char_count} characters)." >&2
    exit 1
  fi

  create_session

  # Build record JSON
  local created_at
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  local record
  record=$(jq -n \
    --arg type "app.bsky.feed.post" \
    --arg text "$text" \
    --arg created_at "$created_at" \
    '{
      "$type": $type,
      "text": $text,
      "createdAt": $created_at
    }')

  # Add reply references if provided
  if [[ -n "$reply_to_uri" && -n "$reply_to_cid" ]]; then
    # If root not specified, parent is the root (first reply in thread)
    if [[ -z "$root_uri" ]]; then
      root_uri="$reply_to_uri"
      root_cid="$reply_to_cid"
    fi

    record=$(echo "$record" | jq \
      --arg parent_uri "$reply_to_uri" \
      --arg parent_cid "$reply_to_cid" \
      --arg root_uri "$root_uri" \
      --arg root_cid "$root_cid" \
      '. + {
        "reply": {
          "root": {"uri": $root_uri, "cid": $root_cid},
          "parent": {"uri": $parent_uri, "cid": $parent_cid}
        }
      }')
  fi

  local request_body
  request_body=$(jq -n \
    --arg repo "$USER_DID" \
    --arg collection "app.bsky.feed.post" \
    --argjson record "$record" \
    '{
      "repo": $repo,
      "collection": $collection,
      "record": $record
    }')

  local result
  result=$(post_request "com.atproto.repo.createRecord" "$request_body")

  # Return uri and cid for thread chaining
  echo "$result" | jq '{uri, cid}'
}

cmd_get_metrics() {
  create_session

  local body
  body=$(get_request "app.bsky.actor.getProfile" "actor=${USER_DID}")

  echo "$body" | jq '{
    handle: .handle,
    displayName: .displayName,
    followersCount: .followersCount,
    followsCount: .followsCount,
    postsCount: .postsCount,
    description: .description
  }'
}

cmd_get_notifications() {
  local limit=50
  local cursor=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit)  limit="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  create_session

  local query="limit=${limit}"
  if [[ -n "$cursor" ]]; then
    query="${query}&cursor=${cursor}"
  fi

  local body
  body=$(get_request "app.bsky.notification.listNotifications" "$query")

  # Filter for mentions only and extract relevant fields
  echo "$body" | jq '{
    notifications: [.notifications[] | select(.reason == "mention") | {
      uri: .uri,
      cid: .cid,
      author_handle: .author.handle,
      author_name: (.author.displayName // .author.handle),
      text: (.record.text // ""),
      created_at: .indexedAt,
      reason: .reason
    }],
    cursor: .cursor
  }'
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: bsky-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  create-session                  - Test auth, output session info" >&2
    echo "  post <text> [reply flags]       - Create a post" >&2
    echo "  get-metrics                     - Fetch profile stats" >&2
    echo "  get-notifications [--limit N]   - Fetch mention notifications" >&2
    exit 1
  fi

  require_jq
  require_credentials

  case "$command" in
    create-session)    cmd_create_session ;;
    post)              cmd_post "$@" ;;
    get-metrics)       cmd_get_metrics ;;
    get-notifications) cmd_get_notifications "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'bsky-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

# Guard: allow sourcing without executing main (for test harness)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
