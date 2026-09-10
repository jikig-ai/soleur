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

# (#7797) Xtrace refusal -- the FIRST thing after `set …`, so nothing above it is
# traced. This script ships to installed Soleur CLIs: the terminal it runs in
# belongs to the founder, and `bash -x` would print their live LinkedIn
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
    printf 'Refusing to run under `bash -x`: this script loads LINKEDIN_CLIENT_ID, LINKEDIN_CLIENT_SECRET, LINKEDIN_ACCESS_TOKEN from your .env at runtime, and tracing would print them to your terminal. Unsetting them first does not help -- the .env is the source. Re-run without `bash -x`.\n'
    exit 78
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
# competing causes the founder cannot tell apart: the xtrace refusal, the proxy
# this script deliberately bypassed, a ~/.curlrc that `--disable` dropped, or an
# ordinary network failure. So each failure emits ONE structured marker carrying
# all four discriminators, beside a human line that names the bypass instead of
# blaming the founder's connectivity.
SOLEUR_TRANSPORT_SCRIPT="linkedin-setup.sh"
SOLEUR_TRANSPORT_PLATFORM="LinkedIn"

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
readonly LINKEDIN_OAUTH="https://www.linkedin.com/oauth/v2"
readonly LINKEDIN_API="https://api.linkedin.com"
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
  local __curl_rc=0
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -X POST \
    --data-urlencode "client_id=${LINKEDIN_CLIENT_ID}" \
    --data-urlencode "client_secret=${LINKEDIN_CLIENT_SECRET}" \
    --data-urlencode "token=${LINKEDIN_ACCESS_TOKEN}" \
    "${LINKEDIN_OAUTH}/introspectToken" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to connect to LinkedIn OAuth API."
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
  # w_organization_social is REQUIRED to post as a Company Page (author
  # urn:li:organization:<id>). Without it the /rest/posts call fails with
  # HTTP 400 "Organization Or Events permissions must be used when using
  # organization as author" (#4046 — surfaced when a member-only token was
  # rotated in and the Phase-6 test post hit this). The app must have the
  # Community Management API product approved for LinkedIn to grant it.
  local scopes="openid%20profile%20w_member_social%20w_organization_social"
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
  local __curl_rc=0
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -X POST \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=${auth_code}" \
    --data-urlencode "client_id=${LINKEDIN_CLIENT_ID}" \
    --data-urlencode "client_secret=${LINKEDIN_CLIENT_SECRET}" \
    --data-urlencode "redirect_uri=${redirect_uri}" \
    "${LINKEDIN_OAUTH}/accessToken" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to connect to LinkedIn OAuth API."
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
  local __curl_rc=0
  userinfo_response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${access_token}" \
    "${LINKEDIN_API}/v2/userinfo" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to resolve person URN."
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
