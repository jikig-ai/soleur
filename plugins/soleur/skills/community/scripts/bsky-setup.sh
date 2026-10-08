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
#   1 - General error, including missing credentials and a write-env value outside the .env
#       allow-list. The two are told apart by the stderr marker: an allow-list refusal prints
#       `SOLEUR_CREDENTIAL_REFUSED ... var=<NAME> phase=write-env` (value-free); its one human
#       line is on stdout.
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1 (the write-env allow-list line: stdout)

set -euo pipefail

# (#7797) Xtrace refusal -- the FIRST thing after `set …`, so nothing above it is
# traced. This script ships to installed Soleur CLIs: the terminal it runs in
# belongs to the founder, and `bash -x` would print their live Bluesky
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
    printf 'Refusing to run under `bash -x`: this script loads BSKY_HANDLE, BSKY_APP_PASSWORD from your .env at runtime, and tracing would print them to your terminal. Unsetting them first does not help -- the .env is the source. Re-run without `bash -x`.\n'
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
SOLEUR_TRANSPORT_SCRIPT="bsky-setup.sh"
SOLEUR_TRANSPORT_PLATFORM="Bluesky"

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
readonly BSKY_API="https://bsky.social/xrpc"

# (#7843) The session token is parsed out of an API reply, so it is RESPONSE-DERIVED:
# untrusted bytes. It rides curl's STDIN config channel (`--config -`), never its
# argument list (readable by every local user in /proc/<pid>/cmdline). That channel is
# line-oriented, so a token holding a quote and a newline could append a `url = "..."`
# directive and make curl issue a second request. This guard refuses anything outside the
# JWT/base64url alphabet BEFORE the value is formatted into the stream, and never echoes it.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# --- createSession body transport (#9597) ---
# The createSession body carries the app password and a user-supplied handle. Neither may
# ride curl's argument list (readable by every local user in /proc/<pid>/cmdline). The
# createSession call has no bearer config, so curl's stdin is free: `jq` builds the body and
# pipes it to `curl --data-binary @-` (NOT `-d @-`, which strips CR/LF). The values reach
# `jq` through its ENVIRONMENT as an inline assignment prefix (`$ENV.X`), never `jq --arg`
# (jq's own argv is world-readable too). The BSKY_ID / BSKY_PW aliases are never `export`ed:
# they live on the one jq child only. RESIDUAL: `verify` sources the .env under `set -a`, so
# every OTHER variable in that file is exported to later children; the two credential names
# are un-exported again right after (`export -n`), but that is the only thing narrowed.
# No file, no trap: the secret exists only in the processes' memory and the pipe.

# A control character can never be part of a handle or an app password. Refusing one
# before anything is sent keeps garbage off the wire; jq escapes everything else (a handle
# holding a double quote is escaped, never injected into the JSON).
_bsky_cred_ok() { local LC_ALL=C; case "${1:-}" in ''|*[[:cntrl:]]*) return 1 ;; esac; }

# A fixed, value-free marker plus ONE human line on stderr, naming only which FIELD was
# refused (never the handle or the password), and a non-zero exit. $2 is the variable name.
# Exit 1 (never 0): this script has no `post`; the hosted content-publisher path lives in
# bsky-community.sh, which carries the same refusal shape.
bsky_refuse() {
  printf 'SOLEUR_CREDENTIAL_REFUSED script=%s reason=%s\n' "$SOLEUR_TRANSPORT_SCRIPT" "$1" >&2
  echo "Error: ${2} is empty or contains a control character (for example a stray carriage return or newline from a copy-paste or a CRLF .env file), so nothing was sent. Remove it and retry. The value is not shown." >&2
  exit 1
}

# (#9597) write-env value allow-list. `.env` values are written UNQUOTED and later SOURCED
# (`verify`, the community scripts), so a value holding a command substitution, a backtick, a
# quote, a semicolon, a space or a newline would execute or split on the next source, and a leading
# tilde would silently change a stored credential (tilde expansion on source). Validation is an
# allow-list, fail-closed, and runs for EVERY value BEFORE the first write: a refused value prints
# the value-free marker plus ONE human line naming only the VARIABLE, writes nothing, exits 1 and
# leaves any existing .env untouched. A value outside the list that is legitimate is added to .env
# by hand. The glob runs under LC_ALL=C and is not grep, which is line-oriented and lets a
# multi-line value through.
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
  # Every value is checked BEFORE the first write (see the allow-list above).
  _wenv_validate BSKY_HANDLE BSKY_APP_PASSWORD

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
  # The API base above is `readonly` (#7898 review), so if this .env tries to
  # rebind it `source` returns non-zero. Do NOT let `set -e` abort here: that
  # would be a silent death on the credential-loading path. Capture the status,
  # report it, and continue -- the credentials in the same file still load, and
  # the pinned destination keeps its legitimate value.
  _env_rc=0
  source "$env_file" || _env_rc=$?
  set +a
  # `set -a` exported everything the .env defined; stop the two credentials riding every
  # later child's environment (the curl calls need neither). The value stays bound.
  export -n BSKY_HANDLE BSKY_APP_PASSWORD
  if (( _env_rc != 0 )); then
    printf 'Note: at least one assignment in %s was refused. A pinned request destination cannot be overridden from .env -- your credentials loaded normally and the request still goes to the real API.\n' "$env_file"
    emit_transport_diag "none" "env-rebind-refused"
  fi

  require_credentials

  # Create session to verify credentials
  local response http_code body
  local __curl_rc=0
  # Refuse BEFORE the body is built so a refused value never reaches a child process.
  _bsky_cred_ok "${BSKY_HANDLE:-}" || bsky_refuse control_char BSKY_HANDLE
  _bsky_cred_ok "${BSKY_APP_PASSWORD:-}" || bsky_refuse control_char BSKY_APP_PASSWORD
  # The body is built into a variable FIRST, so a jq failure is classified as what it is (a
  # body-build failure) and never reaches curl: it does not depend on `pipefail`, and it can
  # never read as a transport failure or as a successful empty POST. The credentials reach jq
  # only through its inline environment prefix; `printf` is a builtin, so the body (which holds
  # the password) is on no argv; curl reads it from stdin.
  local req_body
  req_body=$(BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD" \
    jq -n '{identifier: $ENV.BSKY_ID, password: $ENV.BSKY_PW}') || {
    echo "Error: could not build the Bluesky createSession request body (jq failed); nothing was sent." >&2
    exit 1
  }
  response=$(printf '%s' "$req_body" \
    | curl --disable --noproxy '*' -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "${BSKY_API}/com.atproto.server.createSession" 2>/dev/null) || __curl_rc=$?
  if (( __curl_rc != 0 )); then
    report_transport_failure "$__curl_rc" "Failed to connect to Bluesky API."
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
      access_jwt=$(echo "$body" | jq -r '.accessJwt // empty')
      if ! _bearer_ok "$access_jwt"; then
        echo "Error: Session response carried an accessJwt that is missing or has an unexpected shape; refusing to use it." >&2
        exit 1
      fi

      local profile_response profile_code profile_body
      local __curl_rc=0
      # The bearer rides curl's stdin config channel, never its argument list.
      profile_response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" --config - \
        "${BSKY_API}/app.bsky.actor.getProfile?actor=${did}" 2>/dev/null \
        < <(printf 'header = "Authorization: Bearer %s"\n' "$access_jwt")) || __curl_rc=$?
      if (( __curl_rc != 0 )); then
        # A WARNING, not a failure -- the session was created, so the credentials
        # are proven and this path still exits 0. It gets the marker and the
        # proxy-aware line anyway: `--noproxy '*'` is as capable of cutting THIS
        # request as the one above, and without the line the founder reads a
        # deliberate bypass as an unexplained partial success.
        emit_transport_diag "$__curl_rc" "none"
        echo "Warning: Session created but profile fetch failed." >&2
        if proxy_bypassed; then
          echo "This request deliberately bypasses your proxy ($(proxy_env_names)), because a proxy can redirect a request carrying your ${SOLEUR_TRANSPORT_PLATFORM} token." >&2
          echo "If you need Soleur to reach ${SOLEUR_TRANSPORT_PLATFORM} through your proxy, that is not currently supported -- please open an issue at https://github.com/jikig-ai/soleur/issues." >&2
        fi
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
