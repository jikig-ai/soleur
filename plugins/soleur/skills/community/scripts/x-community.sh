#!/usr/bin/env bash
# x-community.sh -- X/Twitter API v2 wrapper for community operations
#
# Usage: x-community.sh <command> [args]
# Commands:
#   fetch-metrics                              - Fetch account metrics (followers, following, tweets)
#   fetch-mentions [--since ISO8601] [--max N] - Fetch recent @mentions (paid API)
#   fetch-timeline [--max N]                   - Fetch recent tweets (paid API)
#   post-tweet <text> [--reply-to ID]          - Post a tweet (optionally as a reply)
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

# --- GET request helper ---

# Make an authenticated GET request to the X API with query params
# Arguments: endpoint query_params [depth]
# Query params are included in the OAuth signature
# Retries on 429 up to 3 times
get_request() {
  local endpoint="$1"
  local query_params="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: X API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${X_API}${endpoint}"

  # Build OAuth signature with query params included
  local auth_header
  if [[ -n "$query_params" ]]; then
    # Split query_params on & and pass as varargs to oauth_sign
    local -a param_args=()
    local param
    while IFS= read -r param; do
      [[ -n "$param" ]] && param_args+=("$param")
    done <<< "${query_params//&/$'\n'}"
    auth_header=$(oauth_sign "GET" "$url" "${param_args[@]}")
  else
    auth_header=$(oauth_sign "GET" "$url")
  fi

  # Build request URL with query string
  local request_url="$url"
  if [[ -n "$query_params" ]]; then
    request_url="${url}?${query_params}"
  fi

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "$request_url" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
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
      echo "Error: X API returned 401 Unauthorized for ${endpoint}." >&2
      echo "Your credentials may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
      echo "  2. Regenerate your Access Token and Secret" >&2
      echo "  3. Update environment variables" >&2
      exit 1
      ;;
    403)
      local reason
      reason=$(echo "$body" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")
      echo "Error: X API returned 403 Forbidden for ${endpoint}." >&2
      if [[ "$reason" == "client-not-enrolled" ]]; then
        echo "This endpoint requires paid API access." >&2
        echo "Visit https://developer.x.com to purchase credits." >&2
      elif [[ "$reason" == "official-client-forbidden" ]]; then
        echo "Your app may lack the required permissions." >&2
      else
        echo "Your app may lack the required permissions or your account may be suspended." >&2
      fi
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
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      get_request "$endpoint" "$query_params" "$((depth + 1))"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}

# Resolve the authenticated user's numeric ID
resolve_user_id() {
  local response
  response=$(get_request "/2/users/me" "")

  local user_id
  user_id=$(echo "$response" | jq -r '.data.id' 2>/dev/null || echo "")

  if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
    echo "Error: Failed to resolve user ID from /2/users/me." >&2
    echo "Response did not contain a valid numeric ID." >&2
    exit 1
  fi

  echo "$user_id"
}

# --- Commands ---

cmd_fetch_metrics() {
  local body
  body=$(get_request "/2/users/me" "user.fields=public_metrics,description,created_at")

  echo "$body" | jq '{
    username: .data.username,
    name: .data.name,
    description: .data.description,
    created_at: .data.created_at,
    metrics: .data.public_metrics
  }'
}

cmd_fetch_mentions() {
  local since=""
  local max_results=10

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)
        since="${2:?--since requires an ISO 8601 timestamp}"
        shift 2
        ;;
      --max)
        max_results="${2:?--max requires a number}"
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  # Clamp max_results to API range 5-100
  if (( max_results < 5 )); then
    echo "Warning: --max ${max_results} is below API minimum of 5, clamping to 5." >&2
    max_results=5
  elif (( max_results > 100 )); then
    echo "Warning: --max ${max_results} is above API maximum of 100, clamping to 100." >&2
    max_results=100
  fi

  local user_id
  user_id=$(resolve_user_id)

  local query_params="tweet.fields=created_at,author_id,public_metrics,text&max_results=${max_results}"
  if [[ -n "$since" ]]; then
    query_params="${query_params}&start_time=${since}"
  fi

  local body
  body=$(get_request "/2/users/${user_id}/mentions" "$query_params")

  echo "$body" | jq '.data // []'
}

cmd_fetch_timeline() {
  local max_results=10

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max)
        max_results="${2:?--max requires a number}"
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  # Clamp max_results to API range 5-100
  if (( max_results < 5 )); then
    echo "Warning: --max ${max_results} is below API minimum of 5, clamping to 5." >&2
    max_results=5
  elif (( max_results > 100 )); then
    echo "Warning: --max ${max_results} is above API maximum of 100, clamping to 100." >&2
    max_results=100
  fi

  local user_id
  user_id=$(resolve_user_id)

  local query_params="tweet.fields=created_at,public_metrics,text&max_results=${max_results}"

  local body
  body=$(get_request "/2/users/${user_id}/tweets" "$query_params")

  echo "$body" | jq '.data // []'
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
    echo "  fetch-metrics                              - Fetch account metrics" >&2
    echo "  fetch-mentions [--since ISO8601] [--max N] - Fetch recent @mentions (paid API)" >&2
    echo "  fetch-timeline [--max N]                   - Fetch recent tweets (paid API)" >&2
    echo "  post-tweet <text> [--reply-to ID]          - Post a tweet" >&2
    exit 1
  fi

  require_jq
  require_openssl
  require_credentials

  case "$command" in
    fetch-metrics)  cmd_fetch_metrics ;;
    fetch-mentions) cmd_fetch_mentions "$@" ;;
    fetch-timeline) cmd_fetch_timeline "$@" ;;
    post-tweet)     cmd_post_tweet "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'x-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
