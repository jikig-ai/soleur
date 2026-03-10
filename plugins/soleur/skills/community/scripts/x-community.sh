#!/usr/bin/env bash
# x-community.sh -- X/Twitter API v2 wrapper for community operations
#
# Usage: x-community.sh <command> [args]
# Commands:
#   fetch-metrics                                    - Fetch account metrics (followers, following, tweets)
#   fetch-mentions [--max-results N] [--since-id ID] - Fetch recent mentions of the authenticated user
#   post-tweet <text> [--reply-to ID]                - Post a tweet (optionally as a reply)
#
# Environment variables (required):
#   X_API_KEY              - API key (consumer key)
#   X_API_SECRET           - API secret (consumer secret)
#   X_ACCESS_TOKEN         - Access token
#   X_ACCESS_TOKEN_SECRET  - Access token secret
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Retryable error (rate limit)
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

X_API="https://api.x.com"

# --- Dependency checks ---

require_openssl() {
  if ! command -v openssl &>/dev/null; then
    echo "Error: openssl is required for OAuth 1.0a signing but not found." >&2
    echo "Install it via your package manager (e.g., apt install openssl)." >&2
    exit 1
  fi
}

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- Credential validation ---

require_credentials() {
  local missing=()

  if [[ -z "${X_API_KEY:-}" ]]; then
    missing+=("X_API_KEY")
  fi
  if [[ -z "${X_API_SECRET:-}" ]]; then
    missing+=("X_API_SECRET")
  fi
  if [[ -z "${X_ACCESS_TOKEN:-}" ]]; then
    missing+=("X_ACCESS_TOKEN")
  fi
  if [[ -z "${X_ACCESS_TOKEN_SECRET:-}" ]]; then
    missing+=("X_ACCESS_TOKEN_SECRET")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing X API credentials: ${missing[*]}" >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
    echo "  2. Create or select a project and app" >&2
    echo "  3. Generate API Key, API Secret, Access Token, and Access Token Secret" >&2
    echo "  4. Export them as environment variables" >&2
    exit 1
  fi
}

# --- OAuth 1.0a signing ---

# URL-encode a string per RFC 3986
urlencode() {
  local string="$1"
  local encoded=""
  local i c o
  for (( i = 0; i < ${#string}; i++ )); do
    c="${string:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) encoded+="$c" ;;
      *)
        o=$(printf '%02X' "'$c")
        encoded+="%${o}"
        ;;
    esac
  done
  echo "$encoded"
}

# Generate OAuth 1.0a signature for a request
# Arguments: method url [param_key=param_value ...]
oauth_sign() {
  local method="$1"
  local url="$2"
  shift 2

  local oauth_nonce
  oauth_nonce=$(openssl rand -hex 16)
  local oauth_timestamp
  oauth_timestamp=$(date +%s)

  # Collect all parameters (OAuth + request params)
  local -a params=()
  params+=("oauth_consumer_key=$(urlencode "${X_API_KEY}")")
  params+=("oauth_nonce=$(urlencode "${oauth_nonce}")")
  params+=("oauth_signature_method=HMAC-SHA1")
  params+=("oauth_timestamp=${oauth_timestamp}")
  params+=("oauth_token=$(urlencode "${X_ACCESS_TOKEN}")")
  params+=("oauth_version=1.0")

  # Add request parameters
  local param
  for param in "$@"; do
    local key="${param%%=*}"
    local val="${param#*=}"
    params+=("$(urlencode "$key")=$(urlencode "$val")")
  done

  # Sort parameters lexicographically
  local sorted_params
  sorted_params=$(printf '%s\n' "${params[@]}" | sort)

  # Build parameter string
  local param_string=""
  while IFS= read -r line; do
    if [[ -n "$param_string" ]]; then
      param_string+="&"
    fi
    param_string+="$line"
  done <<< "$sorted_params"

  # Build signature base string
  local base_string="${method}&$(urlencode "$url")&$(urlencode "$param_string")"

  # Build signing key
  local signing_key="$(urlencode "${X_API_SECRET}")&$(urlencode "${X_ACCESS_TOKEN_SECRET}")"

  # Generate HMAC-SHA1 signature
  local signature
  signature=$(printf '%s' "$base_string" | openssl dgst -sha1 -hmac "$signing_key" -binary | base64)

  # Build Authorization header
  local auth_header="OAuth "
  auth_header+="oauth_consumer_key=\"$(urlencode "${X_API_KEY}")\", "
  auth_header+="oauth_nonce=\"$(urlencode "${oauth_nonce}")\", "
  auth_header+="oauth_signature=\"$(urlencode "$signature")\", "
  auth_header+="oauth_signature_method=\"HMAC-SHA1\", "
  auth_header+="oauth_timestamp=\"${oauth_timestamp}\", "
  auth_header+="oauth_token=\"$(urlencode "${X_ACCESS_TOKEN}")\", "
  auth_header+="oauth_version=\"1.0\""

  echo "$auth_header"
}

# --- API helper ---

# Make an authenticated request to the X API
# Arguments: method endpoint [json_body]
# Retries on 429 up to 3 times
x_request() {
  local method="$1"
  local endpoint="$2"
  local json_body="${3:-}"
  local depth="${4:-0}"

  if (( depth >= 3 )); then
    echo "Error: X API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  local url="${X_API}${endpoint}"
  local auth_header
  auth_header=$(oauth_sign "$method" "$url")

  local -a curl_args=(
    -s -w "\n%{http_code}"
    -H "Authorization: ${auth_header}"
    -H "Content-Type: application/json"
  )

  if [[ "$method" == "POST" && -n "$json_body" ]]; then
    curl_args+=(-X POST -d "$json_body")
  fi

  local response http_code body
  # Suppress stderr to prevent credential leakage
  if ! response=$(curl "${curl_args[@]}" "$url" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      # Validate JSON
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: X API returned malformed JSON for ${endpoint}" >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: X API returned 401 Unauthorized." >&2
      echo "Your credentials may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
      echo "  2. Regenerate your Access Token and Secret" >&2
      echo "  3. Update environment variables" >&2
      exit 1
      ;;
    403)
      echo "Error: X API returned 403 Forbidden." >&2
      echo "Your app may lack the required permissions or your account may be suspended." >&2
      exit 1
      ;;
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null || echo "5")
      # Clamp retry_after to sane range [1, 60]
      # Use printf to truncate float to integer for arithmetic comparison
      # (sleep accepts floats natively, but bash (( )) does not)
      local retry_int
      retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
      if (( retry_int > 60 )); then
        retry_after=60
      elif (( retry_int < 1 )); then
        retry_after=1
      fi
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      x_request "$method" "$endpoint" "$json_body" "$((depth + 1))"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- Commands ---

# Resolve the authenticated user's numeric ID via GET /2/users/me
get_authenticated_user_id() {
  local url="${X_API}/2/users/me"

  local auth_header
  auth_header=$(oauth_sign "GET" "$url")

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      local user_id
      user_id=$(echo "$body" | jq -r '.data.id // empty' 2>/dev/null)
      if [[ -z "${user_id:-}" ]]; then
        echo "Error: Could not extract user ID from /2/users/me response." >&2
        exit 1
      fi
      echo "$user_id"
      ;;
    401)
      echo "Error: X API returned 401 Unauthorized." >&2
      echo "Your credentials may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
      echo "  2. Regenerate your Access Token and Secret" >&2
      echo "  3. Update environment variables" >&2
      exit 1
      ;;
    403)
      echo "Error: X API returned 403 Forbidden." >&2
      echo "Your app may lack the required permissions." >&2
      exit 1
      ;;
    429)
      echo "Error: X API rate limit exceeded while resolving user ID." >&2
      exit 2
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

cmd_fetch_mentions() {
  local max_results=10
  local since_id=""

  # Parse optional arguments
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --max-results)
        local mr_val="${2:-}"
        if [[ -z "$mr_val" ]]; then
          echo "Error: --max-results requires a numeric value." >&2
          exit 1
        fi
        if ! [[ "$mr_val" =~ ^[0-9]+$ ]]; then
          echo "Error: --max-results must be a numeric value, got '${mr_val}'." >&2
          exit 1
        fi
        if (( mr_val < 5 || mr_val > 100 )); then
          echo "Error: --max-results must be between 5 and 100, got ${mr_val}." >&2
          exit 1
        fi
        max_results="$mr_val"
        shift 2
        ;;
      --since-id)
        local si_val="${2:-}"
        if [[ -z "$si_val" ]]; then
          echo "Error: --since-id requires a numeric value." >&2
          exit 1
        fi
        if ! [[ "$si_val" =~ ^[0-9]+$ ]]; then
          echo "Error: --since-id must be a numeric value, got '${si_val}'." >&2
          exit 1
        fi
        since_id="$si_val"
        shift 2
        ;;
      *)
        echo "Error: Unknown option '${1:-}'" >&2
        echo "Usage: x-community.sh fetch-mentions [--max-results N] [--since-id ID]" >&2
        exit 1
        ;;
    esac
  done

  # Resolve authenticated user ID
  local user_id
  user_id=$(get_authenticated_user_id)

  # Build query parameters for OAuth signing and URL
  local base_url="${X_API}/2/users/${user_id}/mentions"
  local -a query_params=()
  query_params+=("max_results=${max_results}")
  query_params+=("tweet.fields=author_id,created_at,conversation_id")
  query_params+=("expansions=author_id")
  query_params+=("user.fields=username,name")

  if [[ -n "$since_id" ]]; then
    query_params+=("since_id=${since_id}")
  fi

  # Sign request with all query params included in signature
  local auth_header
  auth_header=$(oauth_sign "GET" "$base_url" "${query_params[@]}")

  # Build query string for URL
  local query_string=""
  local qp
  for qp in "${query_params[@]}"; do
    local qk="${qp%%=*}"
    local qv="${qp#*=}"
    if [[ -n "$query_string" ]]; then
      query_string+="&"
    fi
    query_string+="$(urlencode "$qk")=$(urlencode "$qv")"
  done

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "${base_url}?${query_string}" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: X API returned malformed JSON for /2/users/${user_id}/mentions" >&2
        exit 1
      fi

      # Handle empty data (no mentions)
      local data_count
      data_count=$(echo "$body" | jq '.data | length // 0' 2>/dev/null || echo "0")
      if [[ "$data_count" == "0" ]] || [[ "$data_count" == "null" ]]; then
        echo '{"mentions":[],"meta":{"newest_id":null,"result_count":0}}'
        return 0
      fi

      # Transform: join includes.users to data by author_id
      # Use INDEX to build a lookup map so tweets without a matching user
      # are preserved with "unknown" fallbacks (not silently dropped)
      echo "$body" | jq '
        ((.includes.users // []) | INDEX(.id)) as $users |
        {
          mentions: [
            .data[] |
            ($users[.author_id] // {}) as $user |
            {
              id: .id,
              text: .text,
              author_username: ($user.username // "unknown"),
              author_name: ($user.name // "unknown"),
              created_at: .created_at,
              conversation_id: .conversation_id
            }
          ],
          meta: {
            newest_id: (.meta.newest_id // null),
            result_count: (.meta.result_count // 0)
          }
        }'
      ;;
    401)
      echo "Error: X API returned 401 Unauthorized." >&2
      echo "Your credentials may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
      echo "  2. Regenerate your Access Token and Secret" >&2
      echo "  3. Update environment variables" >&2
      exit 1
      ;;
    403)
      echo "Error: X API returned 403 Forbidden." >&2
      echo "Your app may lack the required permissions or your account may be suspended." >&2
      exit 1
      ;;
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null || echo "5")
      local retry_int
      retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
      if (( retry_int > 60 )); then
        retry_after=60
      elif (( retry_int < 1 )); then
        retry_after=1
      fi
      echo "Error: X API rate limit exceeded. Retry after ${retry_after}s." >&2
      exit 2
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

cmd_fetch_metrics() {
  local url="/2/users/me"
  local fields="user.fields=public_metrics,description,created_at"

  # OAuth params need to include query string params for signing
  local auth_header
  auth_header=$(oauth_sign "GET" "${X_API}${url}" "${fields}")

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "${X_API}${url}?${fields}" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      # Extract and format metrics
      echo "$body" | jq '{
        username: .data.username,
        name: .data.name,
        description: .data.description,
        created_at: .data.created_at,
        metrics: .data.public_metrics
      }'
      ;;
    401)
      echo "Error: X API returned 401 Unauthorized." >&2
      exit 1
      ;;
    429)
      echo "Error: X API rate limit exceeded." >&2
      exit 2
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

cmd_post_tweet() {
  local text="${1:?Usage: x-community.sh post-tweet <text> [--reply-to TWEET_ID]}"
  shift

  local reply_to=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reply-to)
        reply_to="${2:?--reply-to requires a tweet ID}"
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  # Build JSON body
  local json_body
  if [[ -n "$reply_to" ]]; then
    json_body=$(jq -n --arg text "$text" --arg reply "$reply_to" \
      '{text: $text, reply: {in_reply_to_tweet_id: $reply}}')
  else
    json_body=$(jq -n --arg text "$text" '{text: $text}')
  fi

  local result
  result=$(x_request "POST" "/2/tweets" "$json_body")

  # Output the created tweet
  echo "$result" | jq '{
    id: .data.id,
    text: .data.text
  }'

  echo "Tweet posted successfully." >&2
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: x-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  fetch-metrics                                    - Fetch account metrics" >&2
    echo "  fetch-mentions [--max-results N] [--since-id ID] - Fetch recent mentions" >&2
    echo "  post-tweet <text> [--reply-to ID]                - Post a tweet" >&2
    exit 1
  fi

  require_jq
  require_openssl
  require_credentials

  case "$command" in
    fetch-metrics)  cmd_fetch_metrics ;;
    fetch-mentions) cmd_fetch_mentions "$@" ;;
    post-tweet)     cmd_post_tweet "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'x-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
