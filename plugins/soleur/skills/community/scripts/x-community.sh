#!/usr/bin/env bash
# x-community.sh -- X/Twitter API v2 wrapper for community operations
#
# Usage: x-community.sh <command> [args]
# Commands:
#   fetch-metrics                                    - Fetch account metrics (followers, following, tweets)
#   fetch-mentions [--max-results N] [--since-id ID] - Fetch recent mentions of the authenticated user
#   fetch-timeline [--max N]                         - Fetch recent tweets (paid API)
#   fetch-user-timeline <user_id> [--max N]          - Fetch another user's recent tweets
#   post-tweet <text> [--reply-to ID]                - Post a tweet (optionally as a reply)
#
# Environment variables (required):
#   X_API_KEY              - API key (consumer key)
#   X_API_SECRET           - API secret (consumer secret)
#   X_ACCESS_TOKEN         - Access token
#   X_ACCESS_TOKEN_SECRET  - Access token secret
#   X_ALLOW_POST           - Set to "true" to enable posting (defense-in-depth guard)
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

# --- Response handler ---

# Handle HTTP response status codes from X API
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
        # CONTRACT: community-manager agent matches on this string for 403 fallback detection.
        # Changing this message requires updating agents/support/community-manager.md Capability 4 Step 1b.
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
      "${retry_cmd[@]}"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- POST request helper ---

# Make an authenticated POST request to the X API
# Arguments: endpoint [json_body] [depth]
# Retries on 429 up to 3 times
post_request() {
  local endpoint="$1"
  local json_body="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: X API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${X_API}${endpoint}"
  local auth_header
  auth_header=$(oauth_sign "POST" "$url")

  local -a curl_args=(
    -s -w "\n%{http_code}"
    -H "Authorization: ${auth_header}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$json_body" ]]; then
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

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    post_request "$endpoint" "$json_body" "$((depth + 1))"
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
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$query_params" "$((depth + 1))"
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

# --- Shared helpers ---

# Fetch tweets for a given user ID and return the data array.
# Arguments: user_id max_results
_fetch_tweets_for_user() {
  local user_id="$1"
  local max_results="$2"
  local query_params="tweet.fields=created_at,public_metrics,text&max_results=${max_results}"
  local body
  body=$(get_request "/2/users/${user_id}/tweets" "$query_params")
  echo "$body" | jq '.data // []'
}

# --- Anomaly detection ---

# Detect anomalous public_metrics patterns and emit warnings to stderr.
# Shell boolean convention: returns 0 (true) if anomaly exists, 1 (false) if normal.
# Arguments: metrics_json (JSON object with followers_count, following_count, tweet_count)
_has_metrics_anomaly() {
  local metrics_json="$1"

  local followers following tweets
  read -r followers following tweets < <(
    echo "$metrics_json" | jq -r '[.followers_count // 0, .following_count // 0, .tweet_count // 0] | @tsv'
  )

  # Fail safe on non-numeric jq output (malformed API response)
  if [[ ! "$followers" =~ ^[0-9]+$ ]] || [[ ! "$following" =~ ^[0-9]+$ ]] || [[ ! "$tweets" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  # Genuinely new/empty account: all zeros is not anomalous
  if (( followers == 0 && following == 0 && tweets == 0 )); then
    return 1
  fi

  # All-zeros degradation: followers=0, following=0, but tweets>0
  if (( followers == 0 && following == 0 && tweets > 0 )); then
    echo "Warning: X API returned all-zero social metrics for account with ${tweets} tweets. Possible API degradation." | head -c 200 >&2
    return 0
  fi

  # Active account with zero followers: followers=0 but tweets>0 and following>0
  if (( followers == 0 && tweets > 0 && following > 0 )); then
    echo "Warning: X API returned 0 followers for active account (${tweets} tweets, ${following} following). This may indicate unfollows, spam cleanup, or API degradation." | head -c 200 >&2
    return 0
  fi

  return 1
}

# --- Commands ---

cmd_fetch_metrics() {
  local body
  body=$(get_request "/2/users/me" "user.fields=public_metrics,description,created_at")

  local output metrics_json
  output=$(echo "$body" | jq '{
    username: .data.username,
    name: .data.name,
    description: .data.description,
    created_at: .data.created_at,
    metrics: .data.public_metrics
  }')
  metrics_json=$(echo "$output" | jq '.metrics // {}')

  # Run anomaly check (warnings go to stderr, stdout unchanged)
  _has_metrics_anomaly "$metrics_json" || true

  echo "$output"
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
  user_id=$(resolve_user_id)

  # Build query parameters
  local query_params="max_results=${max_results}&tweet.fields=author_id,created_at,conversation_id,referenced_tweets&expansions=author_id&user.fields=username,name,profile_image_url,public_metrics"
  if [[ -n "$since_id" ]]; then
    query_params="${query_params}&since_id=${since_id}"
  fi

  # Use shared GET helper with retry and enhanced error handling
  local body
  body=$(get_request "/2/users/${user_id}/mentions" "$query_params")

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
          author_id: .author_id,
          author_username: ($user.username // "unknown"),
          author_name: ($user.name // "unknown"),
          author_profile_image_url: ($user.profile_image_url // null),
          author_followers_count: ($user.public_metrics.followers_count // 0),
          created_at: .created_at,
          conversation_id: .conversation_id,
          referenced_tweets: (.referenced_tweets // null)
        }
      ],
      meta: {
        newest_id: (.meta.newest_id // null),
        result_count: (.meta.result_count // 0)
      }
    }'
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

  # Validate --max is a positive integer (prevents query param injection)
  if [[ ! "$max_results" =~ ^[0-9]+$ ]]; then
    echo "Error: --max must be a positive integer, got '${max_results}'" >&2
    exit 1
  fi

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

  _fetch_tweets_for_user "$user_id" "$max_results"
}

cmd_fetch_user_timeline() {
  local user_id="${1:-}"
  shift || true

  if [[ -z "$user_id" ]]; then
    echo "Error: fetch-user-timeline requires a user_id argument." >&2
    echo "Usage: x-community.sh fetch-user-timeline <user_id> [--max N]" >&2
    exit 1
  fi

  # Validate user_id is a positive integer (prevents path traversal)
  if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
    echo "Error: user_id must be a positive integer, got '${user_id}'." >&2
    exit 1
  fi

  local max_results=5

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

  # Validate --max is a positive integer
  if [[ ! "$max_results" =~ ^[0-9]+$ ]]; then
    echo "Error: --max must be a positive integer, got '${max_results}'" >&2
    exit 1
  fi

  # Clamp max_results to API range 5-100
  if (( max_results < 5 )); then
    echo "Warning: --max ${max_results} is below API minimum of 5, clamping to 5." >&2
    max_results=5
  elif (( max_results > 100 )); then
    echo "Warning: --max ${max_results} is above API maximum of 100, clamping to 100." >&2
    max_results=100
  fi

  _fetch_tweets_for_user "$user_id" "$max_results"
}

cmd_post_tweet() {
  # Guard: require explicit opt-in to post.
  if [[ "${X_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: X_ALLOW_POST is not set to 'true'." >&2
    echo "Set X_ALLOW_POST=true to enable posting." >&2
    return 1
  fi

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
  result=$(post_request "/2/tweets" "$json_body")

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
    echo "  fetch-timeline [--max N]                         - Fetch recent tweets (paid API)" >&2
    echo "  fetch-user-timeline <user_id> [--max N]          - Fetch another user's tweets" >&2
    echo "  post-tweet <text> [--reply-to ID]                - Post a tweet" >&2
    exit 1
  fi

  require_jq
  require_openssl
  require_credentials

  case "$command" in
    fetch-metrics)  cmd_fetch_metrics ;;
    fetch-mentions) cmd_fetch_mentions "$@" ;;
    fetch-timeline)      cmd_fetch_timeline "$@" ;;
    fetch-user-timeline) cmd_fetch_user_timeline "$@" ;;
    post-tweet)          cmd_post_tweet "$@" ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'x-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

# Guard: allow sourcing without executing main (for test harness)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
