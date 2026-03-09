#!/usr/bin/env bash
# x-setup.sh -- X/Twitter API credential setup and validation
#
# SECURITY: Credentials MUST be in environment variables.
# Never pass tokens as CLI arguments (visible in ps/history).
#
# Usage: x-setup.sh <command> [args]
# Commands:
#   validate-credentials            - Verify all 4 env vars via GET /2/users/me
#   write-env                       - Write credentials to .env with chmod 600
#   verify                          - Source .env and run round-trip API check
#
# Environment variables (required for API commands):
#   X_API_KEY              - API key (consumer key)
#   X_API_SECRET           - API secret (consumer secret)
#   X_ACCESS_TOKEN         - Access token
#   X_ACCESS_TOKEN_SECRET  - Access token secret
#
# Exit codes:
#   0 - Success
#   1 - General error
#
# Output: JSON or plain text to stdout
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

# --- Commands ---

cmd_validate_credentials() {
  require_credentials

  local url="${X_API}/2/users/me"
  local auth_header
  auth_header=$(oauth_sign "GET" "$url")

  local response http_code body
  # Suppress stderr to prevent credential leakage
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "${url}" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      local user_id username name
      user_id=$(echo "$body" | jq -r '.data.id // empty')
      username=$(echo "$body" | jq -r '.data.username // empty')
      name=$(echo "$body" | jq -r '.data.name // empty')

      if [[ -z "$user_id" ]]; then
        echo "Error: Could not extract user info from X API response." >&2
        echo "Response: ${body}" >&2
        exit 1
      fi

      # Output user info as JSON on stdout
      echo "$body" | jq '.data'
      echo "Credentials valid. Account: @${username} (${name})" >&2
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
      echo "Error: X API rate limit exceeded." >&2
      echo "Wait and try again later." >&2
      exit 1
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

cmd_write_env() {
  require_credentials

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local env_file="${repo_root}/.env"

  # Remove existing X vars if .env exists
  if [[ -f "$env_file" ]]; then
    local tmp
    tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
    { grep -v '^X_API_KEY=' "$env_file" | \
      grep -v '^X_API_SECRET=' | \
      grep -v '^X_ACCESS_TOKEN=' | \
      grep -v '^X_ACCESS_TOKEN_SECRET='; } > "$tmp" || true
    mv "$tmp" "$env_file"
  fi

  # Set restrictive permissions BEFORE writing secrets
  touch "$env_file"
  chmod 600 "$env_file"

  # Append X vars
  {
    echo "X_API_KEY=${X_API_KEY}"
    echo "X_API_SECRET=${X_API_SECRET}"
    echo "X_ACCESS_TOKEN=${X_ACCESS_TOKEN}"
    echo "X_ACCESS_TOKEN_SECRET=${X_ACCESS_TOKEN_SECRET}"
  } >> "$env_file"

  echo "Wrote 4 variables to ${env_file} (permissions: 600)" >&2
}

cmd_verify() {
  # Verify .env configuration by running validate-credentials
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local env_file="${repo_root}/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "Error: .env file not found at ${env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a

  local missing=()
  [[ -z "${X_API_KEY:-}" ]] && missing+=("X_API_KEY")
  [[ -z "${X_API_SECRET:-}" ]] && missing+=("X_API_SECRET")
  [[ -z "${X_ACCESS_TOKEN:-}" ]] && missing+=("X_ACCESS_TOKEN")
  [[ -z "${X_ACCESS_TOKEN_SECRET:-}" ]] && missing+=("X_ACCESS_TOKEN_SECRET")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: .env is missing: ${missing[*]}" >&2
    exit 1
  fi

  # Validate via API
  cmd_validate_credentials
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: x-setup.sh <command>" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  validate-credentials  - Verify credentials via GET /2/users/me" >&2
    echo "  write-env             - Write credentials to .env with chmod 600" >&2
    echo "  verify                - Source .env and run round-trip check" >&2
    exit 1
  fi

  require_jq
  require_openssl

  case "$command" in
    validate-credentials) cmd_validate_credentials ;;
    write-env)            cmd_write_env ;;
    verify)               cmd_verify ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'x-setup.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
