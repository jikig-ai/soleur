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

# (#7797) Xtrace refusal -- the FIRST thing after `set …`, so nothing above it is
# traced. This script ships to installed Soleur CLIs: the terminal it runs in
# belongs to the founder, and `bash -x` would print their live X
# credentials. UNCONDITIONAL, and that is measured rather than inherited:
# `cmd_verify` does `set -a; source "$env_file"; set +a`, loading the founder's
# .env at RUNTIME, AFTER this prologue. A conditional hatch keyed on whether the
# credential is already set would therefore be empty at guard time and open, and
# `source` under xtrace echoes EVERY assignment in the file -- so the leak would
# be the whole .env, not one token. (Written without the literal parameter
# expansion on purpose: a bare-token grep for it cannot tell this comment from
# real code, and the 4-vs-11 arm split is asserted by exactly such a grep.)
# Refusal goes to STDOUT, not stderr: agent runtimes surface stdout and swallow
# stderr (constitution.md > Code Style > Always), and a swallowed security refusal
# leaves the user with a bare `exit 78` and no text at all.
case "$-" in
  *x*)
    printf 'Refusing to run under `bash -x`: this script loads X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET from your .env at runtime, and tracing would print them to your terminal. Unsetting them first does not help -- the .env is the source. Re-run without `bash -x`.\n'
    exit 78
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
SOLEUR_TRANSPORT_SCRIPT="x-setup.sh"
SOLEUR_TRANSPORT_PLATFORM="X"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/resolve-git-root.sh"

# readonly (#7898 review): `cmd_verify` and friends run `set -a; source "$env_file"; set +a`
# BELOW this line, so a plain assignment here is rebindable by the repo's .env --
# which retargets the credentialed request while every transport flag stays intact.
# That is the "--disable and --noproxy are intact and irrelevant" shape this change
# exists to close, one layer up. readonly makes the destination non-rebindable.
readonly X_API="https://api.x.com"

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
  local __curl_rc=0
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "${url}" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to connect to X API."
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

  local repo_root="$GIT_ROOT"
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
  local repo_root="$GIT_ROOT"
  local env_file="${repo_root}/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "Error: .env file not found at ${env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  # The API base above is `readonly` (#7898 review), so if this .env tries to
  # rebind it `source` returns non-zero. Do NOT let `set -e` abort here: that
  # would be a silent death on the credential-loading path. Capture the status,
  # report it, and continue -- the credentials in the same file still load, and
  # the pinned destination keeps its legitimate value.
  _env_rc=0
  source "$env_file" || _env_rc=$?
  set +a
  if (( _env_rc != 0 )); then
    printf 'Note: at least one assignment in %s was refused. A pinned request destination cannot be overridden from .env -- your credentials loaded normally and the request still goes to the real API.\n' "$env_file"
    emit_transport_diag "none" "env-rebind-refused"
  fi

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
