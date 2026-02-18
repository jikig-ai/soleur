#!/usr/bin/env bash
# discord-setup.sh -- Discord bot setup API operations
#
# SECURITY: Token MUST be in DISCORD_BOT_TOKEN_INPUT env var.
# Never pass tokens as CLI arguments (visible in ps/history).
#
# Usage: discord-setup.sh <command> [args]
# Commands:
#   validate-token                  - Verify token via API, output app ID
#   discover-guilds                 - List guilds as JSON
#   list-channels <guild_id>        - List text channels as JSON
#   create-webhook <channel_id>     - Create webhook, output webhook URL
#   write-env <guild_id> <webhook>  - Write to .env with chmod 600
#   verify                          - Run guild-info check
#
# Environment variables:
#   DISCORD_BOT_TOKEN_INPUT  - Bot token (required for API commands)
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Retryable error (e.g., webhook limit on channel)
#
# Output: JSON or plain text to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

DISCORD_API="https://discord.com/api/v10"

# --- Helpers ---

require_token() {
  if [[ -z "${DISCORD_BOT_TOKEN_INPUT:-}" ]]; then
    echo "Error: DISCORD_BOT_TOKEN_INPUT env var is not set." >&2
    echo "Pass the token via environment variable, not as a CLI argument." >&2
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

# Make a Discord API request. Suppresses curl stderr to prevent token leakage
# in debug output. Returns body on 2xx, handles errors.
#
# For create-webhook (POST to /channels/{id}/webhooks), HTTP 400 returns
# exit code 2 so the SKILL.md orchestrator can retry with a different channel.
discord_request() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="${3:-}"
  local response http_code body
  local curl_args=(
    -s -w "\n%{http_code}"
    -X "$method"
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN_INPUT}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi

  # Suppress stderr to prevent token leakage in curl debug output
  if ! response=$(curl "${curl_args[@]}" "${DISCORD_API}${endpoint}" 2>/dev/null); then
    echo "Error: Failed to connect to Discord API (endpoint: ${endpoint})." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      echo "$body"
      ;;
    401)
      echo "Error: Invalid or expired bot token." >&2
      exit 1
      ;;
    400)
      local message
      message=$(echo "$body" | jq -r '.message // "Bad request"' 2>/dev/null || echo "Bad request")
      echo "Error: Discord API returned HTTP 400: ${message}" >&2
      exit 2
      ;;
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null)
      if [[ -z "$retry_after" ]] || [[ "$retry_after" == "null" ]]; then
        retry_after=5
      fi
      echo "Rate limited. Retrying after ${retry_after}s..." >&2
      sleep "$retry_after"
      discord_request "$endpoint" "$method" "$data"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: Discord API returned HTTP ${http_code}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- Commands ---

cmd_validate_token() {
  require_token

  # Verify token via /users/@me
  discord_request "/users/@me" > /dev/null

  # Get application info for app ID
  local app_info
  app_info=$(discord_request "/oauth2/applications/@me")

  local app_id app_name
  app_id=$(echo "$app_info" | jq -r '.id // empty')
  app_name=$(echo "$app_info" | jq -r '.name // empty')

  if [[ -z "$app_id" ]]; then
    echo "Error: Could not extract application ID from Discord API response." >&2
    exit 1
  fi

  # Output app ID on stdout (used by SKILL.md for OAuth2 URL)
  echo "${app_id}"
  echo "Token valid. Application: ${app_name}" >&2
}

cmd_discover_guilds() {
  require_token

  discord_request "/users/@me/guilds?with_counts=true" | \
    jq '[.[] | {id, name, approximate_member_count}]'
}

cmd_list_channels() {
  local guild_id="${1:?Usage: discord-setup.sh list-channels <guild_id>}"
  require_token

  discord_request "/guilds/${guild_id}/channels" | \
    jq '[.[] | select(.type == 0) | {id, name, position}] | sort_by(.position)'
}

cmd_create_webhook() {
  local channel_id="${1:?Usage: discord-setup.sh create-webhook <channel_id>}"
  require_token

  local result
  result=$(discord_request "/channels/${channel_id}/webhooks" "POST" '{"name":"soleur-community"}')

  local webhook_id webhook_token
  webhook_id=$(echo "$result" | jq -r '.id // empty')
  webhook_token=$(echo "$result" | jq -r '.token // empty')

  if [[ -z "$webhook_id" ]] || [[ -z "$webhook_token" ]]; then
    echo "Error: Could not extract webhook ID or token from API response." >&2
    exit 1
  fi

  # Output the full webhook URL
  echo "https://discord.com/api/webhooks/${webhook_id}/${webhook_token}"
}

cmd_write_env() {
  local guild_id="${1:?Usage: discord-setup.sh write-env <guild_id> <webhook_url>}"
  local webhook_url="${2:?Usage: discord-setup.sh write-env <guild_id> <webhook_url>}"
  require_token

  local env_file=".env"

  # Remove existing Discord vars if .env exists
  if [[ -f "$env_file" ]]; then
    local tmp
    tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
    grep -v '^DISCORD_BOT_TOKEN=' "$env_file" | \
      grep -v '^DISCORD_GUILD_ID=' | \
      grep -v '^DISCORD_WEBHOOK_URL=' > "$tmp" || true
    mv "$tmp" "$env_file"
  fi

  # Set restrictive permissions BEFORE writing secrets
  touch "$env_file"
  chmod 600 "$env_file"

  # Append Discord vars (file already has correct permissions)
  {
    echo "DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN_INPUT}"
    echo "DISCORD_GUILD_ID=${guild_id}"
    echo "DISCORD_WEBHOOK_URL=${webhook_url}"
  } >> "$env_file"

  echo "Wrote 3 variables to ${env_file} (permissions: 600)" >&2
}

cmd_verify() {
  # Verify .env configuration by running guild-info
  if [[ ! -f ".env" ]]; then
    echo "Error: .env file not found." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  set -a
  source .env
  set +a

  if [[ -z "${DISCORD_BOT_TOKEN:-}" ]] || [[ -z "${DISCORD_GUILD_ID:-}" ]]; then
    echo "Error: .env is missing DISCORD_BOT_TOKEN or DISCORD_GUILD_ID." >&2
    exit 1
  fi

  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"

  local community_script="${script_dir}/discord-community.sh"
  if [[ ! -x "$community_script" ]]; then
    echo "Error: Required script not found: ${community_script}" >&2
    exit 1
  fi

  local guild_info
  guild_info=$("${community_script}" guild-info)

  local name member_count
  name=$(echo "$guild_info" | jq -r '.name // empty')
  member_count=$(echo "$guild_info" | jq -r '.approximate_member_count // empty')

  if [[ -z "$name" ]]; then
    echo "Error: Could not extract guild info from API response." >&2
    exit 1
  fi

  echo "${name}"
  echo "${member_count:-0}"
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: discord-setup.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  validate-token                  - Verify token via API, output app ID" >&2
    echo "  discover-guilds                 - List guilds as JSON" >&2
    echo "  list-channels <guild_id>        - List text channels as JSON" >&2
    echo "  create-webhook <channel_id>     - Create webhook, output webhook URL" >&2
    echo "  write-env <guild_id> <webhook>  - Write to .env with chmod 600" >&2
    echo "  verify                          - Run guild-info check" >&2
    exit 1
  fi

  require_jq

  case "$command" in
    validate-token)  cmd_validate_token ;;
    discover-guilds) cmd_discover_guilds ;;
    list-channels)   cmd_list_channels "$@" ;;
    create-webhook)  cmd_create_webhook "$@" ;;
    write-env)       cmd_write_env "$@" ;;
    verify)          cmd_verify ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'discord-setup.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
