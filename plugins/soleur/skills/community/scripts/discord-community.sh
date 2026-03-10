#!/usr/bin/env bash
# discord-community.sh -- Discord Bot API wrapper for community operations
#
# Usage: discord-community.sh <command> [args]
# Commands:
#   messages <channel_id> [limit] [after_id]  - Fetch channel messages
#   members [limit]                            - Fetch guild members
#   guild-info                                 - Fetch guild metadata
#   channels                                   - List guild text channels
#
# Environment variables (required):
#   DISCORD_BOT_TOKEN  - Discord bot token for API authentication
#   DISCORD_GUILD_ID   - Discord guild (server) ID
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

DISCORD_API="https://discord.com/api/v10"

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- Validation ---

validate_env() {
  if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
    echo "Error: DISCORD_BOT_TOKEN is not set." >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Go to https://discord.com/developers/applications" >&2
    echo "  2. Select your bot application > Bot > Copy token" >&2
    echo "  3. export DISCORD_BOT_TOKEN=\"your-token-here\"" >&2
    exit 1
  fi

  # Bot tokens follow the pattern: base64.base64.base64
  if [[ ! "${DISCORD_BOT_TOKEN}" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
    echo "Error: DISCORD_BOT_TOKEN has invalid format." >&2
    echo "Expected format: base64.base64.base64" >&2
    exit 1
  fi

  if [[ -z "${DISCORD_GUILD_ID:-}" ]]; then
    echo "Error: DISCORD_GUILD_ID is not set." >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Enable Developer Mode in Discord (Settings > Advanced)" >&2
    echo "  2. Right-click your server name > Copy Server ID" >&2
    echo "  3. export DISCORD_GUILD_ID=\"your-guild-id\"" >&2
    exit 1
  fi

  if [[ ! "${DISCORD_GUILD_ID}" =~ ^[0-9]+$ ]]; then
    echo "Error: DISCORD_GUILD_ID must be numeric. Got: ${DISCORD_GUILD_ID}" >&2
    exit 1
  fi
}

# --- API helpers ---

discord_request() {
  local endpoint="$1"
  local depth="${2:-0}"

  if (( depth >= 3 )); then
    echo "Error: Discord API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  local response http_code body

  # Suppress stderr to prevent token leakage in curl debug output
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    "${DISCORD_API}${endpoint}" 2>/dev/null); then
    echo "Error: Failed to connect to Discord API (endpoint: ${endpoint})." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  case "$http_code" in
    2[0-9][0-9])
      # Validate JSON
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: Discord API returned malformed JSON for ${endpoint}" >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: Discord API returned 401 Unauthorized." >&2
      echo "Your bot token may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://discord.com/developers/applications" >&2
      echo "  2. Select your bot > Bot > Reset Token" >&2
      echo "  3. Update DISCORD_BOT_TOKEN with the new token" >&2
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
      discord_request "$endpoint" "$((depth + 1))"
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

validate_snowflake_id() {
  local id="$1"
  local label="$2"
  if [[ ! "$id" =~ ^[0-9]+$ ]]; then
    echo "Error: ${label} must be numeric. Got: ${id}" >&2
    exit 1
  fi
}

cmd_messages() {
  local channel_id="${1:?Usage: discord-community.sh messages <channel_id> [limit] [after_id]}"
  validate_snowflake_id "$channel_id" "channel_id"
  local limit="${2:-100}"
  local after_id="${3:-}"

  local all_messages="[]"
  local fetched=0
  local batch_size=100

  while (( fetched < limit )); do
    local remaining=$(( limit - fetched ))
    local this_batch=$(( remaining < batch_size ? remaining : batch_size ))
    local params="?limit=${this_batch}"

    if [[ -n "$after_id" ]]; then
      params="${params}&after=${after_id}"
    fi

    local batch
    batch=$(discord_request "/channels/${channel_id}/messages${params}")

    local count
    count=$(echo "$batch" | jq 'length')

    if (( count == 0 )); then
      break
    fi

    all_messages=$(echo "$all_messages" "$batch" | jq -s '.[0] + .[1]')
    fetched=$(( fetched + count ))

    # Get the oldest message ID for pagination
    after_id=$(echo "$batch" | jq -r 'last .id')

    # If we got fewer than requested, no more messages
    if (( count < this_batch )); then
      break
    fi
  done

  echo "$all_messages"
}

cmd_members() {
  local limit="${1:-1000}"
  local all_members="[]"
  local after="0"
  local batch_size=1000

  while true; do
    local this_batch=$(( limit < batch_size ? limit : batch_size ))
    local batch
    batch=$(discord_request "/guilds/${DISCORD_GUILD_ID}/members?limit=${this_batch}&after=${after}")

    local count
    count=$(echo "$batch" | jq 'length')

    if (( count == 0 )); then
      break
    fi

    all_members=$(echo "$all_members" "$batch" | jq -s '.[0] + .[1]')

    local total
    total=$(echo "$all_members" | jq 'length')

    if (( total >= limit )); then
      all_members=$(echo "$all_members" | jq ".[0:${limit}]")
      break
    fi

    after=$(echo "$batch" | jq -r 'last .user.id')

    if (( count < this_batch )); then
      break
    fi
  done

  echo "$all_members"
}

cmd_guild_info() {
  discord_request "/guilds/${DISCORD_GUILD_ID}?with_counts=true"
}

cmd_channels() {
  discord_request "/guilds/${DISCORD_GUILD_ID}/channels" | \
    jq '[.[] | select(.type == 0)]'  # type 0 = text channels
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: discord-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  messages <channel_id> [limit] [after_id]  - Fetch channel messages" >&2
    echo "  members [limit]                            - Fetch guild members" >&2
    echo "  guild-info                                 - Fetch guild metadata" >&2
    echo "  channels                                   - List guild text channels" >&2
    exit 1
  fi

  require_jq
  validate_env

  case "$command" in
    messages)  cmd_messages "$@" ;;
    members)   cmd_members "$@" ;;
    guild-info) cmd_guild_info ;;
    channels)  cmd_channels ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'discord-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
