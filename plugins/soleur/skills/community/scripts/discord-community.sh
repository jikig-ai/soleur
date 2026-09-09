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

# (#7797) Xtrace refusal -- the FIRST thing after `set …`, so nothing above it is
# traced. This script ships to installed Soleur CLIs: the terminal it runs in
# belongs to the founder, and `bash -x` would print their live Discord
# credentials. The `:+x` form tests non-emptiness WITHOUT expanding the value, so
# the guard cannot leak the thing it is refusing over. CONDITIONAL, and that is
# measured rather than inherited: every credential this file handles is bound
# BEFORE the prologue runs (this script's own credential check reads them from
# the environment, it never acquires one at runtime), so the guard can never be
# empty while a credential is live -- and a founder tracing with none set keeps
# full tracing.
# Refusal goes to STDOUT, not stderr: agent runtimes surface stdout and swallow
# stderr (constitution.md > Code Style > Always), and a swallowed security refusal
# leaves the user with a bare `exit 78` and no text at all.
case "$-" in
  *x*)
    if [ -n "${DISCORD_BOT_TOKEN:+x}" ]; then
      printf 'Refusing to run under `bash -x`: DISCORD_BOT_TOKEN is set, and tracing would print it to your terminal. To trace safely, unset it and re-run.\n'
      exit 78
    fi
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy
# variables, but NEITHER touches the trust store or the TLS session-key log. On an
# installed CLI the environment belongs to someone who is not us, so
# `CURL_CA_BUNDLE=/tmp/attacker-ca.pem` is a clean MITM of the founder's platform
# token with every other guard fully intact, and `SSLKEYLOGFILE` is passive
# decryption with no MITM at all. Matches the line in scripts/betterstack-query.sh.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

# --- Transport-confinement diagnostics (#7873) --------------------------------
# Every credentialed `curl` below carries `--disable --noproxy '*'` and discards
# curl's own stderr (which can carry the URL). A failed request then has four
# competing causes the founder cannot tell apart: the xtrace refusal, the proxy
# this script deliberately bypassed, a ~/.curlrc that `--disable` dropped, or an
# ordinary network failure. So each failure emits ONE structured marker carrying
# all four discriminators, beside a human line that names the bypass instead of
# blaming the founder's connectivity.
SOLEUR_TRANSPORT_SCRIPT="discord-community.sh"
SOLEUR_TRANSPORT_PLATFORM="Discord"

# The request helpers below run inside `$(...)`, where fd 1 is the capture pipe.
# Save the script's real stdout so the marker reaches the founder's terminal (and
# the always-on PostToolUse Bash extractor) instead of being swallowed into a
# variable. The marker is on stdout BY DESIGN -- the call sites' `2>/dev/null` is
# what keeps curl's URL-carrying stderr out of the transcript, and it must not be
# able to suppress the diagnostic too.
exec 3>&1

# Which proxy variables are non-empty, or `none`.
proxy_env_names() {
  local names="" n
  for n in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy; do
    if [[ -n "${!n-}" ]]; then
      names="${names},${n}"
    fi
  done
  if [[ -z "$names" ]]; then
    printf 'none'
  else
    printf '%s' "${names#,}"
  fi
}

# True when a proxy this script deliberately bypasses is configured. NO_PROXY
# alone is not one -- it only ever narrows proxying, so it cannot be the cause.
proxy_bypassed() {
  [[ -n "${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${http_proxy:-}${https_proxy:-}${all_proxy:-}" ]]
}

# One line, eight fields, on the saved stdout.
#
# Two fields were literals in the first cut and are now MEASURED (#7898 review):
# `noproxy_applied` was the constant "true", which ASSERTS the property instead of
# observing it -- dropping --noproxy from a call site left the diagnostic still
# claiming it was applied. It now reports whether a proxy was actually configured
# for this request to bypass, which is the fact a reader needs. `refusal` was the
# constant "none" at every call site, so the cause it exists to discriminate could
# never appear; it now carries `env-rebind-refused` and `xtrace-credential-bound`.
#
# `tls_env_cleared` is new. The prologue unsets CURL_CA_BUNDLE/SSL_CERT_FILE et al,
# which is correct against an attacker and BREAKS a founder whose corporate CA
# arrives that way -- curl then exits 60 and, without this field, the event is
# indistinguishable from an ordinary network failure.
emit_transport_diag() {
  local curl_exit="$1" refusal="$2" surface="installed-cli" curlrc="false" noproxy="false"
  # The hosted sandbox always sets this (agent-env.ts > AGENT_ENV_OVERRIDES); an
  # installed CLI does not. A label on the event, not a gate on behaviour.
  if [[ -n "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" ]]; then
    surface="in-sandbox"
  fi
  if [[ -f "${HOME:-}/.curlrc" ]]; then
    curlrc="true"
  fi
  if proxy_bypassed; then
    noproxy="true"
  fi
  printf 'SOLEUR_TRANSPORT_DIAG surface=%s script=%s curl_exit=%s refusal=%s proxy_env=%s curlrc_present=%s noproxy_applied=%s tls_env_cleared=%s\n' \
    "$surface" "$SOLEUR_TRANSPORT_SCRIPT" "$curl_exit" "$refusal" \
    "$(proxy_env_names)" "$curlrc" "$noproxy" "true" >&3
}

# Replaces the bare "Check your network connection and try again." on a
# credentialed-curl failure. With a proxy set, that line blames the founder for a
# bypass this script chose.
report_transport_failure() {
  local curl_exit="${1:-unknown}"
  local detail="${2:-Failed to connect to the ${SOLEUR_TRANSPORT_PLATFORM} API.}"
  emit_transport_diag "$curl_exit" "none"
  echo "Error: ${detail}" >&2
  # Ordered by how specific the evidence is. Each arm names something THIS script
  # did, so the founder is never told to go debug their own network for a choice
  # made here. The bare "check your connection" line is the LAST resort, not the
  # default -- it was the default in the first cut, which meant a founder whose
  # corporate CA or curlrc we had just discarded was blamed for it (#7898 review).
  if [[ "$curl_exit" == "60" || "$curl_exit" == "35" || "$curl_exit" == "77" ]]; then
    # 60 peer-certificate, 35 TLS handshake, 77 CA-bundle unreadable.
    echo "This looks like a TLS trust failure. This script deliberately clears CURL_CA_BUNDLE, SSL_CERT_FILE, SSL_CERT_DIR and SSLKEYLOGFILE before the request, because those variables can redirect or expose a request carrying your ${SOLEUR_TRANSPORT_PLATFORM} credential." >&2
    echo "If your machine needs a corporate CA to reach ${SOLEUR_TRANSPORT_PLATFORM}, that is not currently supported -- please open an issue at https://github.com/jikig-ai/soleur/issues." >&2
  elif proxy_bypassed; then
    echo "This request deliberately bypasses your proxy ($(proxy_env_names)), because a proxy can redirect a request carrying your ${SOLEUR_TRANSPORT_PLATFORM} token." >&2
    echo "If you need Soleur to reach ${SOLEUR_TRANSPORT_PLATFORM} through your proxy, that is not currently supported -- please open an issue at https://github.com/jikig-ai/soleur/issues." >&2
  elif [[ -f "${HOME:-}/.curlrc" ]]; then
    echo "You have a ~/.curlrc, and this request deliberately ignores it (--disable), because a curlrc can redirect a request carrying your ${SOLEUR_TRANSPORT_PLATFORM} token. If it configures a proxy or a CA bundle you need, that is why this failed." >&2
    echo "That is not currently supported -- please open an issue at https://github.com/jikig-ai/soleur/issues." >&2
  else
    echo "Check your network connection and try again." >&2
  fi
}

# readonly (#7898 review): `cmd_verify` and friends run `set -a; source "$env_file"; set +a`
# BELOW this line, so a plain assignment here is rebindable by the repo's .env --
# which retargets the credentialed request while every transport flag stays intact.
# That is the "--disable and --noproxy are intact and irrelevant" shape this change
# exists to close, one layer up. readonly makes the destination non-rebindable.
readonly DISCORD_API="https://discord.com/api/v10"

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
  local __curl_rc=0
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    "${DISCORD_API}${endpoint}" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to connect to Discord API (endpoint: ${endpoint})."
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
