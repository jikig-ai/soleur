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
#   write-env <guild_id>            - Write to .env with chmod 600 (webhook URL from the environment)
#   verify                          - Run guild-info check
#
# Environment variables:
#   DISCORD_BOT_TOKEN_INPUT              - Bot token (required for API commands)
#   DISCORD_WEBHOOK_URL_INPUT            - Webhook URL (required, write-env only; never an argument)
#   DISCORD_RELEASES_WEBHOOK_URL_INPUT   - Releases channel webhook (optional, write-env only)
#   DISCORD_BLOG_WEBHOOK_URL_INPUT       - Blog channel webhook (optional, write-env only)
#
# write-env no longer takes the webhook URL as an argument (it would sit in the process list
# and the shell history). Set it in the environment without echoing it. In a terminal:
#   read -rs DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT
# `read -rs` needs a terminal. With no terminal (an agent runtime, a pipe, a script) use either
# the inline assignment (the value is in this one process's environment, on no argument list):
#   DISCORD_WEBHOOK_URL_INPUT=<webhook-url> discord-setup.sh write-env <guild_id>
# or read it from a pipe (printf is a shell builtin, so the value is on no argument list):
#   printf '%s' "$URL" | { read -r DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT; discord-setup.sh write-env <guild_id>; }
# Every value written to .env is checked against an allow-list first (see _wenv_validate).
#
# Exit codes:
#   0 - Success
#   1 - General error (including a write-env value outside the allow-list: the stderr marker
#       SOLEUR_CREDENTIAL_REFUSED carries `var=<NAME> phase=write-env`, the one human line is on stdout)
#   2 - Retryable error (e.g., webhook limit on channel)
#   64 - Usage error (write-env: the webhook URL passed as an argument, or
#        DISCORD_WEBHOOK_URL_INPUT or DISCORD_BOT_TOKEN_INPUT missing or empty). The usage text,
#        including the remedy, is printed on STDOUT.
#
# Output: JSON or plain text to stdout
# Errors: Messages to stderr, exit 1 (write-env usage and allow-list text: stdout, see above)

set -euo pipefail

# (#7797) Xtrace refusal -- the FIRST thing after `set …`, so nothing above it is
# traced. This script ships to installed Soleur CLIs: the terminal it runs in
# belongs to the founder, and `bash -x` would print their live Discord bot token.
# The `:+x` form tests non-emptiness WITHOUT expanding the value, so the guard
# cannot leak the thing it is refusing over. CONDITIONAL, and that is measured
# rather than inherited: the token is bound BEFORE the prologue runs (it arrives in
# DISCORD_BOT_TOKEN_INPUT, or DISCORD_BOT_TOKEN for a caller that already holds it),
# so the guard can never be empty while one is live. The one runtime acquisition is
# `verify`, which sources the repo's .env -- cmd_verify carries its own refusal for
# that path. A founder tracing with none set keeps full tracing.
# Refusal goes to STDOUT, not stderr: agent runtimes surface stdout and swallow
# stderr (constitution.md > Code Style > Always), and a swallowed security refusal
# leaves the user with a bare `exit 78` and no text at all.
case "$-" in
  *x*)
    if [ -n "${DISCORD_BOT_TOKEN_INPUT:+x}${DISCORD_BOT_TOKEN:+x}${DISCORD_WEBHOOK_URL_INPUT:+x}${DISCORD_RELEASES_WEBHOOK_URL_INPUT:+x}${DISCORD_BLOG_WEBHOOK_URL_INPUT:+x}" ]; then
      printf 'Refusing to run under `bash -x`: a Discord bot token or webhook URL is set, and tracing would print it to your terminal. To trace safely, unset them and re-run.\n'
      exit 78
    fi
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy
# variables, but NEITHER touches the trust store or the TLS session-key log. On an
# installed CLI the environment belongs to someone who is not us, so
# a substituted `CURL_CA_BUNDLE` is a clean MITM of the founder's platform
# token with every other guard fully intact, and `SSLKEYLOGFILE` is passive
# decryption with no MITM at all. Matches the line in scripts/betterstack-query.sh.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

# --- Transport-confinement diagnostics (#7873) --------------------------------
# Every credentialed `curl` below carries `--disable --noproxy '*'` and discards
# curl's own stderr (which can carry the URL). A failed request then has four
# competing causes the founder cannot tell apart: the proxy this script
# deliberately bypassed, a ~/.curlrc that `--disable` dropped, a TLS trust
# variable it cleared, or an ordinary network failure. So each failure emits ONE
# structured marker carrying the discriminators, beside a human line that names
# the bypass instead of blaming the founder's connectivity.
SOLEUR_TRANSPORT_SCRIPT="discord-setup.sh"
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
# never appear; the field stays for a caller that can refuse for a named cause, and
# this script has none, so it passes "none".
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/resolve-git-root.sh"

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

# (#9597) The Bot token rides curl's STDIN config channel (`--config -`), never its
# argument list (readable by every local user in /proc/<pid>/cmdline). That channel is
# line-oriented, so a token holding a quote or a newline could append a `url = "..."`
# directive and make curl issue a second request. This guard refuses anything outside
# the base64url.base64url.base64url shape BEFORE the value is formatted into the stream.
# (The same check discord-community.sh's validate_env runs; the `=~` runs in the C locale
# so the ranges are ASCII.) The refusal line is fixed and value-free (never the
# token), goes to stderr, and exits 1; it is not a connect failure.
_discord_token_ok() {
  local LC_ALL=C t="${1:-}"
  [[ "$t" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
}
refuse_token_shape() {
  printf 'SOLEUR_CREDENTIAL_REFUSED script=%s reason=token_shape\n' "$SOLEUR_TRANSPORT_SCRIPT" >&2
  echo "Error: DISCORD_BOT_TOKEN_INPUT is not shaped like a Discord bot token, so nothing was sent. Expected three dot-separated base64url segments (letters, digits, '-' and '_'), with no 'Bot ' prefix, quotes, spaces, or line breaks (including a trailing CR or newline). The value is not shown." >&2
  exit 1
}

# (#9597) write-env value allow-list. `.env` values are written UNQUOTED and later SOURCED
# (`verify`, the community scripts), so a value holding a command substitution, a backtick, a
# quote, a semicolon, a space or a newline would execute or split on the next source, and a leading
# tilde would silently change a stored credential (tilde expansion on source). Validation is an
# allow-list, fail-closed, and runs for EVERY value BEFORE the first write: a refused value prints
# the value-free marker plus ONE human line naming only the VARIABLE, writes nothing, exits 1 and
# leaves any existing .env untouched. A value outside the list that is legitimate is added to .env
# by hand (a thread-scoped webhook URL with a query string is outside the list). The glob runs
# under LC_ALL=C and is not grep, which is line-oriented and lets a multi-line value through.
_wenv_class() { # <value>: 0 allowed, 1 outside the allow-list or empty, 2 holds a control character
  local LC_ALL=C
  case "${1-}" in
    '') return 1 ;;
    *[[:cntrl:]]*) return 2 ;;
    *[!A-Za-z0-9._:/@%+=,-]*) return 1 ;;
  esac
  return 0
}
_wenv_refuse() { # <reason> <VARIABLE>
  printf 'SOLEUR_CREDENTIAL_REFUSED script=%s reason=%s var=%s phase=write-env\n' "$SOLEUR_TRANSPORT_SCRIPT" "$1" "$2" >&2
  echo "Error: ${2} holds a character this script does not write to .env (allowed: letters, digits and . _ : / @ % + = , -), so nothing was written and your existing .env is unchanged. The value is not shown. If the value is legitimate, add it to .env by hand."
  exit 1
}
# _wenv_validate <VARIABLE>...: every NON-EMPTY named variable passes the allow-list. The required
# variables are checked non-empty by the caller before this runs; an empty optional one is skipped.
_wenv_validate() {
  local _wn _wrc
  for _wn in "$@"; do
    [[ -n "${!_wn:-}" ]] || continue
    _wrc=0
    _wenv_class "${!_wn}" || _wrc=$?
    case "$_wrc" in
      0) ;;
      2) _wenv_refuse control_char "$_wn" ;;
      *) _wenv_refuse token_shape "$_wn" ;;
    esac
  done
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
  local depth="${4:-0}"

  if (( depth >= 3 )); then
    echo "Error: Discord API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  # The guard sits IMMEDIATELY before the call it protects.
  _discord_token_ok "${DISCORD_BOT_TOKEN_INPUT}" || refuse_token_shape

  local response http_code body
  # The bot token is NOT in this array (an array on argv is the same /proc/<pid>/cmdline
  # surface) -- it is fed to `--config -` below. `--disable --noproxy '*'` stay literal on
  # the call, first, where the transport-confinement lint (Rule D) can see them.
  local curl_args=(
    -s -w "\n%{http_code}"
    --config -
    -X "$method"
    -H "Content-Type: application/json"
  )

  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi

  # Suppress stderr to prevent token leakage in curl debug output
  local __curl_rc=0
  response=$(curl --disable --noproxy '*' "${curl_args[@]}" "${DISCORD_API}${endpoint}" 2>/dev/null \
      < <(printf 'header = "Authorization: Bot %s"\n' "$DISCORD_BOT_TOKEN_INPUT")) || __curl_rc=$?
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
      discord_request "$endpoint" "$method" "$data" "$((depth + 1))"
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
    # The value is never echoed: a caller that put a secret (the webhook URL) in this slot would
    # otherwise see it printed.
    echo "Error: ${label} must be numeric. The value is not shown." >&2
    exit 1
  fi
}

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
  validate_snowflake_id "$guild_id" "guild_id"
  require_token

  discord_request "/guilds/${guild_id}/channels" | \
    jq '[.[] | select(.type == 0) | {id, name, position}] | sort_by(.position)'
}

cmd_create_webhook() {
  local channel_id="${1:?Usage: discord-setup.sh create-webhook <channel_id>}"
  validate_snowflake_id "$channel_id" "channel_id"
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

# The remedy for a write-env usage error (exit 64). Printed on STDOUT: it is a signal the caller
# must act on and the command has no stdout payload, and agent runtimes surface stdout and swallow
# stderr. The interactive form needs a terminal, so when stdin is not one the two forms that work
# without it are named too. Nothing here prints the value, and the placeholders are literal text.
_print_webhook_env_remedy() {
  echo "Pass it in the environment, without echoing it. In a terminal:"
  echo "  read -rs DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT"
  echo "  discord-setup.sh write-env <guild_id>"
  if [ ! -t 0 ]; then
    echo "Your stdin is not a terminal, so read -rs has nothing to read. Use one of these instead:"
    echo "  DISCORD_WEBHOOK_URL_INPUT=<webhook-url> discord-setup.sh write-env <guild_id>"
    echo "  printf '%s' \"\$URL\" | { read -r DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT; discord-setup.sh write-env <guild_id>; }"
  fi
}

cmd_write_env() {
  # (#9597) The webhook URL is a write-capable secret, so it never rides this command line (the
  # process list, the shell history). A second positional is refused BEFORE anything else reads
  # it, whether or not the environment variable is also set (the secret is already on this
  # command line). The argument is never echoed. Exit 64 (usage) is distinct from the exit 1
  # of a value outside the .env allow-list, and covers every missing REQUIRED input of this
  # command (the webhook URL and the bot token), so the exit code names the class.
  if [[ $# -ge 2 ]]; then
    echo "Error: write-env no longer takes the webhook URL as an argument, because an argument is visible in the process list and your shell history."
    _print_webhook_env_remedy
    echo "The argument you passed is not shown. It was already on this command line, so rotate that webhook if anyone else can read your process list or shell history."
    exit 64
  fi
  local guild_id="${1:?Usage: discord-setup.sh write-env <guild_id>  (the webhook URL goes in DISCORD_WEBHOOK_URL_INPUT)}"
  if [[ -z "${DISCORD_WEBHOOK_URL_INPUT:-}" ]]; then
    echo "Usage: discord-setup.sh write-env <guild_id>"
    echo "Error: DISCORD_WEBHOOK_URL_INPUT is not set (or is empty). Pass the webhook URL in that environment variable, not as an argument."
    _print_webhook_env_remedy
    exit 64
  fi
  validate_snowflake_id "$guild_id" "guild_id"
  if [[ -z "${DISCORD_BOT_TOKEN_INPUT:-}" ]]; then
    echo "Usage: discord-setup.sh write-env <guild_id>"
    echo "Error: DISCORD_BOT_TOKEN_INPUT is not set (or is empty). Pass the bot token in that environment variable, not as an argument."
    exit 64
  fi
  # Every value is checked BEFORE the first write (see the allow-list above).
  _wenv_validate DISCORD_BOT_TOKEN_INPUT DISCORD_WEBHOOK_URL_INPUT DISCORD_RELEASES_WEBHOOK_URL_INPUT DISCORD_BLOG_WEBHOOK_URL_INPUT

  local repo_root="$GIT_ROOT"
  local env_file="${repo_root}/.env"

  # Remove existing Discord vars if .env exists
  if [[ -f "$env_file" ]]; then
    local tmp
    tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
    grep -v '^DISCORD_BOT_TOKEN=' "$env_file" | \
      grep -v '^DISCORD_GUILD_ID=' | \
      grep -v '^DISCORD_WEBHOOK_URL=' | \
      grep -v '^DISCORD_RELEASES_WEBHOOK_URL=' | \
      grep -v '^DISCORD_BLOG_WEBHOOK_URL=' > "$tmp" || true
    mv "$tmp" "$env_file"
  fi

  # Set restrictive permissions BEFORE writing secrets
  touch "$env_file"
  chmod 600 "$env_file"

  # Append Discord vars (file already has correct permissions)
  local var_count=3
  {
    echo "DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN_INPUT}"
    echo "DISCORD_GUILD_ID=${guild_id}"
    echo "DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL_INPUT}"
  } >> "$env_file"

  # Optional: write channel-specific webhooks if provided
  if [[ -n "${DISCORD_RELEASES_WEBHOOK_URL_INPUT:-}" ]]; then
    echo "DISCORD_RELEASES_WEBHOOK_URL=${DISCORD_RELEASES_WEBHOOK_URL_INPUT}" >> "$env_file"
    var_count=$((var_count + 1))
  fi
  if [[ -n "${DISCORD_BLOG_WEBHOOK_URL_INPUT:-}" ]]; then
    echo "DISCORD_BLOG_WEBHOOK_URL=${DISCORD_BLOG_WEBHOOK_URL_INPUT}" >> "$env_file"
    var_count=$((var_count + 1))
  fi

  echo "Wrote ${var_count} variables to ${env_file} (permissions: 600)" >&2
}

cmd_verify() {
  # Verify .env configuration by running guild-info
  local repo_root="$GIT_ROOT"
  local env_file="${repo_root}/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "Error: .env file not found at ${env_file}" >&2
    exit 1
  fi

  # `source` binds DISCORD_BOT_TOKEN at runtime, AFTER the prologue's guard ran, so the
  # prologue cannot see it. Refuse tracing here, before the credential is bound.
  case "$-" in
    *x*)
      printf 'Refusing to run under `bash -x`: sourcing %s would bind a Discord bot token and tracing would print it to your terminal. To trace safely, re-run without -x.\n' "$env_file"
      exit 78
      ;;
  esac

  # shellcheck disable=SC1090
  set -a
  source "$env_file"
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
    echo "  write-env <guild_id>            - Write to .env with chmod 600 (webhook URL in DISCORD_WEBHOOK_URL_INPUT)" >&2
    echo "                                    with no terminal: DISCORD_WEBHOOK_URL_INPUT=<webhook-url> discord-setup.sh write-env <guild_id>" >&2
    echo "  verify                         - Run guild-info check" >&2
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
