#!/usr/bin/env bash
# linkedin-setup.sh -- LinkedIn API credential setup and validation
#
# SECURITY: Credentials MUST be in environment variables.
# Never pass tokens as CLI arguments (visible in ps/history).
#
# Usage: linkedin-setup.sh <command> [args]
# Commands:
#   validate-credentials [--warn-days N]  - Verify token via introspection API
#   generate-token                        - OAuth authorization code exchange
#   write-env                             - Write credentials to .env with chmod 600
#   verify                                - Source .env and run round-trip check
#
# Environment variables (required for API commands):
#   LINKEDIN_CLIENT_ID      - LinkedIn Developer App client ID
#   LINKEDIN_CLIENT_SECRET  - LinkedIn Developer App client secret
#   LINKEDIN_ACCESS_TOKEN   - OAuth 2.0 Bearer token (60-day TTL)
#
# Exit codes:
#   0 - Success
#   1 - General error
#
# Output: JSON or plain text to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

LINKEDIN_OAUTH="https://www.linkedin.com/oauth/v2"
LINKEDIN_API="https://api.linkedin.com"
LINKEDIN_DEFAULT_REDIRECT_URI="https://localhost:8080/callback"

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- Credential validation ---

require_client_credentials() {
  local missing=()

  if [[ -z "${LINKEDIN_CLIENT_ID:-}" ]]; then
    missing+=("LINKEDIN_CLIENT_ID")
  fi
  if [[ -z "${LINKEDIN_CLIENT_SECRET:-}" ]]; then
    missing+=("LINKEDIN_CLIENT_SECRET")
  fi
  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    missing+=("LINKEDIN_ACCESS_TOKEN")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing LinkedIn credentials: ${missing[*]}" >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Create an app at https://www.linkedin.com/developers/apps" >&2
    echo "  2. Add 'Sign In with LinkedIn using OpenID Connect' product" >&2
    echo "  3. Add 'Share on LinkedIn' product" >&2
    echo "  4. Export LINKEDIN_CLIENT_ID and LINKEDIN_CLIENT_SECRET" >&2
    echo "  5. Run: linkedin-setup.sh generate-token" >&2
    exit 1
  fi
}

# --- Commands ---

cmd_validate_credentials() {
  require_client_credentials

  local warn_days=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --warn-days)
        warn_days="${2:-}"
        if [[ -z "$warn_days" ]] || [[ ! "$warn_days" =~ ^[0-9]+$ ]]; then
          echo "Error: --warn-days requires a positive integer." >&2
          exit 1
        fi
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  local response http_code body
  # Token introspection uses client credentials as POST body params (not Bearer)
  if ! response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -d "client_id=${LINKEDIN_CLIENT_ID}" \
    -d "client_secret=${LINKEDIN_CLIENT_SECRET}" \
    -d "token=${LINKEDIN_ACCESS_TOKEN}" \
    "${LINKEDIN_OAUTH}/introspectToken" 2>/dev/null); then
    echo "Error: Failed to connect to LinkedIn OAuth API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    local message
    message=$(echo "$body" | jq -r '.error_description // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo "Error: LinkedIn OAuth API returned HTTP ${http_code}: ${message}" >&2
    exit 1
  fi

  if ! echo "$body" | jq . >/dev/null 2>&1; then
    echo "Error: LinkedIn OAuth API returned malformed JSON." >&2
    exit 1
  fi

  local active expires_at scope
  active=$(echo "$body" | jq -r '.active // false')
  expires_at=$(echo "$body" | jq -r '.expires_at // 0')
  scope=$(echo "$body" | jq -r '.scope // "unknown"')

  if [[ "$active" != "true" ]]; then
    echo "Error: LinkedIn access token is expired or invalid." >&2
    echo "" >&2
    echo "To renew:" >&2
    echo "  Run: linkedin-setup.sh generate-token" >&2
    exit 1
  fi

  local now days_remaining
  now=$(date +%s)
  days_remaining=$(( (expires_at - now) / 86400 ))

  # Output token info as JSON
  jq -n \
    --argjson active true \
    --argjson days_remaining "$days_remaining" \
    --arg scope "$scope" \
    --argjson expires_at "$expires_at" \
    '{
      active: $active,
      days_remaining: $days_remaining,
      scope: $scope,
      expires_at: $expires_at
    }'

  echo "Token valid. ${days_remaining} days remaining. Scopes: ${scope}" >&2

  # Warn-days check: exit non-zero if below threshold
  if (( warn_days > 0 && days_remaining < warn_days )); then
    echo "Warning: Token expires in ${days_remaining} days (threshold: ${warn_days})." >&2
    echo "Run: linkedin-setup.sh generate-token" >&2
    exit 1
  fi
}

cmd_generate_token() {
  if [[ -z "${LINKEDIN_CLIENT_ID:-}" ]]; then
    echo "Error: LINKEDIN_CLIENT_ID is required for token generation." >&2
    echo "Export it from your LinkedIn Developer App settings." >&2
    exit 1
  fi
  if [[ -z "${LINKEDIN_CLIENT_SECRET:-}" ]]; then
    echo "Error: LINKEDIN_CLIENT_SECRET is required for token generation." >&2
    echo "Export it from your LinkedIn Developer App settings." >&2
    exit 1
  fi

  local redirect_uri="${LINKEDIN_REDIRECT_URI:-$LINKEDIN_DEFAULT_REDIRECT_URI}"
  local scopes="openid%20profile%20w_member_social"
  local auth_url="${LINKEDIN_OAUTH}/authorization?response_type=code&client_id=${LINKEDIN_CLIENT_ID}&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${redirect_uri}', safe=''))" 2>/dev/null || echo "${redirect_uri}")&scope=${scopes}"

  echo "=== LinkedIn OAuth Token Generation ===" >&2
  echo "" >&2
  echo "1. Open this URL in your browser:" >&2
  echo "   ${auth_url}" >&2
  echo "" >&2

  # Try to open the URL automatically
  if command -v xdg-open &>/dev/null; then
    xdg-open "$auth_url" 2>/dev/null || true
    echo "   (Opened in browser)" >&2
  elif command -v open &>/dev/null; then
    open "$auth_url" 2>/dev/null || true
    echo "   (Opened in browser)" >&2
  fi

  echo "2. Log in and authorize the application" >&2
  echo "3. Copy the 'code' parameter from the redirect URL" >&2
  echo "   (It looks like: https://localhost:8080/callback?code=AQ...)" >&2
  echo "" >&2

  local auth_code
  read -rp "Paste the authorization code: " auth_code

  if [[ -z "$auth_code" ]]; then
    echo "Error: Authorization code is required." >&2
    exit 1
  fi

  echo "" >&2
  echo "Exchanging authorization code for access token..." >&2

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -d "grant_type=authorization_code" \
    -d "code=${auth_code}" \
    -d "client_id=${LINKEDIN_CLIENT_ID}" \
    -d "client_secret=${LINKEDIN_CLIENT_SECRET}" \
    -d "redirect_uri=${redirect_uri}" \
    "${LINKEDIN_OAUTH}/accessToken" 2>/dev/null); then
    echo "Error: Failed to connect to LinkedIn OAuth API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    local message
    message=$(echo "$body" | jq -r '.error_description // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo "Error: Token exchange failed (HTTP ${http_code}): ${message}" >&2
    exit 1
  fi

  local access_token
  access_token=$(echo "$body" | jq -r '.access_token // empty')

  if [[ -z "$access_token" ]]; then
    echo "Error: No access_token in response." >&2
    exit 1
  fi

  # Resolve person URN
  echo "Resolving person URN..." >&2
  local userinfo_response userinfo_code userinfo_body
  if ! userinfo_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${access_token}" \
    "${LINKEDIN_API}/v2/userinfo" 2>/dev/null); then
    echo "Error: Failed to resolve person URN." >&2
    exit 1
  fi

  userinfo_code=$(echo "$userinfo_response" | tail -1)
  userinfo_body=$(echo "$userinfo_response" | sed '$d')

  if [[ ! "$userinfo_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "Error: Failed to fetch user info (HTTP ${userinfo_code})." >&2
    exit 1
  fi

  local person_id
  person_id=$(echo "$userinfo_body" | jq -r '.sub // empty')

  if [[ -z "$person_id" ]]; then
    echo "Error: Could not extract person ID from userinfo response." >&2
    exit 1
  fi

  local person_urn="urn:li:person:${person_id}"

  # Export for write-env
  export LINKEDIN_ACCESS_TOKEN="$access_token"
  export LINKEDIN_PERSON_URN="$person_urn"

  cmd_write_env

  echo "" >&2
  echo "Token generated successfully." >&2
  echo "Person URN: ${person_urn}" >&2
  echo "Run 'linkedin-setup.sh verify' to confirm." >&2
}

cmd_write_env() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local env_file="${repo_root}/.env"

  # Require all vars to be set
  local missing=()
  [[ -z "${LINKEDIN_CLIENT_ID:-}" ]] && missing+=("LINKEDIN_CLIENT_ID")
  [[ -z "${LINKEDIN_CLIENT_SECRET:-}" ]] && missing+=("LINKEDIN_CLIENT_SECRET")
  [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]] && missing+=("LINKEDIN_ACCESS_TOKEN")
  [[ -z "${LINKEDIN_PERSON_URN:-}" ]] && missing+=("LINKEDIN_PERSON_URN")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing variables for write-env: ${missing[*]}" >&2
    exit 1
  fi

  # Remove existing LINKEDIN_ vars if .env exists
  if [[ -f "$env_file" ]]; then
    local tmp
    tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
    grep -v '^LINKEDIN_' "$env_file" > "$tmp" || true
    mv "$tmp" "$env_file"
  fi

  # Set restrictive permissions BEFORE writing secrets
  touch "$env_file"
  chmod 600 "$env_file"

  # Append LinkedIn vars
  {
    echo "LINKEDIN_CLIENT_ID=${LINKEDIN_CLIENT_ID}"
    echo "LINKEDIN_CLIENT_SECRET=${LINKEDIN_CLIENT_SECRET}"
    echo "LINKEDIN_ACCESS_TOKEN=${LINKEDIN_ACCESS_TOKEN}"
    echo "LINKEDIN_PERSON_URN=${LINKEDIN_PERSON_URN}"
  } >> "$env_file"

  echo "Wrote 4 variables to ${env_file} (permissions: 600)" >&2
}

cmd_verify() {
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

  cmd_validate_credentials
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: linkedin-setup.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  validate-credentials [--warn-days N]  - Verify token via introspection" >&2
    echo "  generate-token                        - OAuth authorization code exchange" >&2
    echo "  write-env                             - Write credentials to .env" >&2
    echo "  verify                                - Source .env and validate" >&2
    exit 1
  fi

  require_jq

  case "$command" in
    validate-credentials) cmd_validate_credentials "$@" ;;
    generate-token)       cmd_generate_token ;;
    write-env)            cmd_write_env ;;
    verify)               cmd_verify ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'linkedin-setup.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
