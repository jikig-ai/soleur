#!/usr/bin/env bash
# bsky-setup.sh -- Bluesky AT Protocol credential setup and validation
#
# SECURITY: Credentials MUST be in environment variables.
# Never pass tokens as CLI arguments (visible in ps/history).
#
# Usage: bsky-setup.sh <command>
# Commands:
#   write-env  - Write credentials to .env with chmod 600
#   verify     - Source .env and verify via session creation + profile fetch
#
# Environment variables (required):
#   BSKY_HANDLE        - Bluesky handle (e.g., soleur.bsky.social)
#   BSKY_APP_PASSWORD  - App password (generate at bsky.app/settings/app-passwords)
#
# Exit codes:
#   0 - Success
#   1 - General error
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/resolve-git-root.sh"

BSKY_API="https://bsky.social/xrpc"

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

# --- Commands ---

cmd_write_env() {
  require_credentials

  local repo_root="$GIT_ROOT"
  local env_file="${repo_root}/.env"

  # Remove existing Bluesky vars if .env exists
  if [[ -f "$env_file" ]]; then
    local tmp
    tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
    { grep -v '^BSKY_HANDLE=' "$env_file" | \
      grep -v '^BSKY_APP_PASSWORD='; } > "$tmp" || true
    mv "$tmp" "$env_file"
  fi

  # Set restrictive permissions BEFORE writing secrets
  touch "$env_file"
  chmod 600 "$env_file"

  # Append Bluesky vars
  {
    echo "BSKY_HANDLE=${BSKY_HANDLE}"
    echo "BSKY_APP_PASSWORD=${BSKY_APP_PASSWORD}"
  } >> "$env_file"

  echo "Wrote 2 variables to ${env_file} (permissions: 600)" >&2
}

cmd_verify() {
  local repo_root="$GIT_ROOT"
  local env_file="${repo_root}/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "Error: .env file not found at ${env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a

  require_credentials

  # Create session to verify credentials
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
        echo "Error: Bluesky API returned malformed JSON." >&2
        exit 1
      fi

      local did handle
      did=$(echo "$body" | jq -r '.did // empty')
      handle=$(echo "$body" | jq -r '.handle // empty')

      if [[ -z "$did" ]]; then
        echo "Error: Could not extract DID from session response." >&2
        exit 1
      fi

      # Fetch profile to confirm identity
      local access_jwt
      access_jwt=$(echo "$body" | jq -r '.accessJwt')

      local profile_response profile_code profile_body
      if ! profile_response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${access_jwt}" \
        "${BSKY_API}/app.bsky.actor.getProfile?actor=${did}" 2>/dev/null); then
        echo "Warning: Session created but profile fetch failed." >&2
        echo "$body" | jq '{did, handle}'
        exit 0
      fi

      profile_code=$(echo "$profile_response" | tail -1)
      profile_body=$(echo "$profile_response" | sed '$d')

      if [[ "$profile_code" =~ ^2 ]]; then
        echo "$profile_body" | jq '{did: .did, handle: .handle, displayName: .displayName, followersCount: .followersCount, followsCount: .followsCount, postsCount: .postsCount}'
        echo "Credentials valid. Account: @${handle} (DID: ${did})" >&2
      else
        echo "$body" | jq '{did, handle}'
        echo "Session created. Profile fetch returned HTTP ${profile_code}." >&2
      fi
      ;;
    401)
      echo "Error: Bluesky returned 401 Unauthorized." >&2
      echo "Your handle or app password may be incorrect." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Verify your handle (e.g., yourname.bsky.social)" >&2
      echo "  2. Generate a new app password at https://bsky.app/settings/app-passwords" >&2
      echo "  3. Update BSKY_HANDLE and BSKY_APP_PASSWORD environment variables" >&2
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

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: bsky-setup.sh <command>" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  write-env  - Write credentials to .env with chmod 600" >&2
    echo "  verify     - Source .env and verify via session + profile" >&2
    exit 1
  fi

  require_jq

  case "$command" in
    write-env) cmd_write_env ;;
    verify)    cmd_verify ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'bsky-setup.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
