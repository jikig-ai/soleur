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

# (#7843) The access token is parsed out of an API reply, so it is RESPONSE-DERIVED:
# untrusted bytes. It rides curl's STDIN config channel (`--config -`), never its
# argument list (readable by every local user in /proc/<pid>/cmdline). That channel is
# line-oriented, so a token holding a quote and a newline could append a `url = "..."`
# directive and make curl issue a second request. This guard refuses anything outside the
# token alphabet BEFORE the value is formatted into the stream, and never echoes it.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# (#9597) The OAuth client secret and the access token being introspected are form
# fields, not bearers, so `_bearer_ok`'s alphabet does not fit them. They still must
# not ride curl's argument list, so they go on the stdin config channel as
# `data-urlencode = "name=value"` lines. A config string is one line with `\` and `"`
# as its only escapes, so a value holding a control character (CR/LF would end the
# directive and let the next bytes act as a new one), a quote or a backslash is refused
# BEFORE it is formatted into the stream; `_cfg_q` still escapes what reaches it.
_cfg_ok() { local LC_ALL=C; case "${1:-}" in ''|*[[:cntrl:]]*|*'"'*|*'\'*) return 1 ;; esac; }
_cfg_q() { local v="${1-}"; v=${v//\\/\\\\}; v=${v//\"/\\\"}; printf '%s' "$v"; }

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
  if ! _cfg_ok "$LINKEDIN_CLIENT_SECRET" || ! _cfg_ok "$LINKEDIN_ACCESS_TOKEN"; then
    echo "Error: LinkedIn client secret or access token has an unexpected shape; refusing to send it." >&2
    exit 1
  fi
  local __curl_rc=0
  # The secret and the token ride curl's stdin config channel, never its argument list.
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" --config - \
    -X POST \
    --data-urlencode "client_id=${LINKEDIN_CLIENT_ID}" \
    "${LINKEDIN_OAUTH}/introspectToken" 2>/dev/null \
    < <(printf 'data-urlencode = "client_secret=%s"\ndata-urlencode = "token=%s"\n' \
      "$(_cfg_q "$LINKEDIN_CLIENT_SECRET")" "$(_cfg_q "$LINKEDIN_ACCESS_TOKEN")")) || __curl_rc=$?
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
  local auth_url="${LINKEDIN_OAUTH}/authorization?response_type=code&client_id=${LINKEDIN_CLIENT_ID}&redirect_uri=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${redirect_uri}" 2>/dev/null || echo "${redirect_uri}")&scope=${scopes}"

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
  if ! _cfg_ok "$LINKEDIN_CLIENT_SECRET"; then
    echo "Error: LINKEDIN_CLIENT_SECRET has an unexpected shape; refusing to send it." >&2
    exit 1
  fi
  local __curl_rc=0
  # The client secret rides curl's stdin config channel, never its argument list.
  response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" --config - \
    -X POST \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=${auth_code}" \
    --data-urlencode "client_id=${LINKEDIN_CLIENT_ID}" \
    --data-urlencode "redirect_uri=${redirect_uri}" \
    "${LINKEDIN_OAUTH}/accessToken" 2>/dev/null \
    < <(printf 'data-urlencode = "client_secret=%s"\n' "$(_cfg_q "$LINKEDIN_CLIENT_SECRET")")) || __curl_rc=$?
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

  if ! _bearer_ok "$access_token"; then
    echo "Error: access_token in the response has an unexpected shape; refusing to use it." >&2
    exit 1
  fi

  # Resolve person URN
  echo "Resolving person URN..." >&2
  local userinfo_response userinfo_code userinfo_body
  local __curl_rc=0
  # The bearer rides curl's stdin config channel, never its argument list.
  userinfo_response=$(curl --disable --noproxy '*' -s -w "\n%{http_code}" --config - \
    "${LINKEDIN_API}/v2/userinfo" 2>/dev/null \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$access_token")) || __curl_rc=$?
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

# (#10091) write-env commit: ONE helper, byte-identical in the four setup scripts (a drift row pins
# it, from this comment line through the closing brace of `_wenv_write`). `_wenv_write <env_file>
# <remove-ERE> <KEY=VALUE>...` replaces the old remove-then-append, which raced (two writers each read
# the file, each rewrote it, the later mv lost the earlier's keys), was not atomic (the append hit the
# live file after the mv) and widened a new file before the chmod.
# The edit is built in a temp file `<.env>.wenv.XXXXXX` beside the RESOLVED .env (same filesystem, so the
# final `mv -f` is one atomic rename; a namespace of its own, so the sweep below touches only that
# namespace (a file there that is not a regular file this user owns is left alone), never the operator
# library's `.env.tmp.*` temps) under `umask 077` (0600 from birth), serialized by
# ONE mutual-exclusion mechanism on every platform: an owner-pid `mkdir` lock directory
# (`<.env>.lock.d`) that is held until AFTER that rename. No flock (a flock run and a mkdir run exclude
# nothing against each other, flock without a timeout blocks forever, and `exec {fd}<` needs bash 4.1
# while macOS ships 3.2).
# Stale-lock recovery is serialized as well, by a second `mkdir` mutex `<.env>.lock.d.recover`. A waiter
# judges a lock stale when its owner pid is dead (or its owner file stayed empty for _WENV_EMPTY_POLLS
# passes), then tries to take the mutex; a waiter that loses it keeps waiting. The winner RE-READS the
# owner of the lock UNDER the mutex (the snapshot it judged on is never trusted; the re-read narrows the
# window to the few instructions between the read and the removal, it does not close it), removes the lock
# only if the owner is still a dead pid, or if the snapshot AND the re-read (after a short pause) both found
# no pid, ALWAYS releases the mutex, and goes round the loop again. A lock whose owner turned from a dead pid
# into nothing has changed hands and is left alone. A recovering waiter never writes while it recovers,
# nothing is renamed away and put back, and the lock path is never empty while a live holder exists, so two
# waiters cannot both hold the lock. A SOLEUR_WENV_LOCK_TICKS below 2 never attempts recovery.
# The wait is ONE bounded loop. Every failed `mkdir` pass either sleeps one tick (0.1 s; 1 s where
# `sleep` takes no fraction) or fails at once, and every pass counts against SOLEUR_WENV_LOCK_TICKS
# (digits only, at most _WENV_TICKS_MAX, else _WENV_TICKS_DEFAULT): about 10 s by default with a
# fractional `sleep`, about 100 s without one. It FAILS CLOSED: no write, a value-free marker, exit 1,
# .env untouched. A lock path that exists but is not a directory fails at once (env_lock_not_dir). grep
# exit 1 (nothing left) is normal; exit 2 (an unreadable .env) aborts, because swallowing it would
# install an empty file over the credentials. A symlinked .env is resolved first (the real target is
# rewritten, the link survives); a dangling link or a non-regular target is refused.
# Signals: this helper owns the EXIT, INT, TERM and HUP traps for its duration and restores nothing (no
# caller installs one today; a caller that needs its own must chain them). On those four it removes its
# temp and its recovery mutex and releases the lock, and it removes the lock ONLY when the owner file
# reads exactly this process. Residual, stated: SIGKILL leaves its lock (recovered by the next run
# through the dead pid), its temp (swept by the next run, under the lock) and, if it died mid-recovery,
# `<.env>.lock.d.recover`, which the next runs report after the bounded wait ("remove that directory");
# a recycled pid can keep a dead owner looking live until the wait times out; the owner check uses
# `kill -0`, so a lock held by another user reads as dead; a holder stalled between its `mkdir` and its
# owner write for longer than the empty-owner window can be treated as ownerless and recovered.
_WENV_TICK=0.1          # seconds per wait tick (a `sleep` without fractions falls back to 1 s)
_WENV_TICKS_DEFAULT=100 # the default bound: about 10 s
_WENV_TICKS_MAX=1000    # the largest SOLEUR_WENV_LOCK_TICKS accepted: about 100 s
_WENV_EMPTY_POLLS=30    # passes an ownerless lock directory is waited on before recovery is tried: about 3 s
_WENV_EMPTY_PAUSE=0.3   # pause between the two owner reads under the recovery mutex when the owner is not a pid
_WENV_LOCK="" _WENV_TMP="" _WENV_REC=""
_wenv_unlock() { # idempotent: remove our temp and recovery mutex; release the lock ONLY if its owner file reads exactly this process
  local _wo=""
  if [[ -n "$_WENV_TMP" ]]; then rm -f -- "$_WENV_TMP"; _WENV_TMP=""; fi
  if [[ -n "$_WENV_REC" ]]; then rmdir -- "$_WENV_REC" 2>/dev/null || true; _WENV_REC=""; fi
  if [[ -n "$_WENV_LOCK" ]]; then
    { read -r _wo < "$_WENV_LOCK/owner"; } 2>/dev/null || _wo=""
    if [[ "$_wo" == "$$" ]]; then rm -rf -- "$_WENV_LOCK"; fi
    _WENV_LOCK=""
  fi
}
_wenv_fail() { # <reason> <human text>: value-free marker on stderr, one human line on stdout, exit 1
  printf 'SOLEUR_CREDENTIAL_REFUSED script=%s reason=%s var=ENV_FILE phase=write-env\n' "$SOLEUR_TRANSPORT_SCRIPT" "$1" >&2
  echo "Error: $2 Nothing was written and your existing .env is unchanged."
  exit 1
}
_wenv_write() {
  local _wf="$1" _wre="$2" _wr _wl _wm _wd _wi=0 _ws=0 _wt _wown _wo2 _wsnap="" _wstale _wgone _wwhy="" _wn _wrc _wum
  shift 2
  if _wr="$(readlink -f -- "$_wf" 2>/dev/null)" && [[ -n "$_wr" ]]; then
    :
  elif [[ -L "$_wf" ]]; then
    _wenv_fail env_unresolvable "The .env link at ${_wf} could not be resolved."
  else
    _wr="$_wf"
  fi
  if [[ -L "$_wf" && ! -e "$_wr" ]]; then
    _wenv_fail env_dangling_link "The .env at ${_wf} is a link to a file that does not exist."
  fi
  if [[ -e "$_wr" && ! -f "$_wr" ]]; then
    _wenv_fail env_not_regular "The .env at ${_wf} is not a regular file."
  fi
  _wl="${_wr}.lock.d"
  _wm="${_wl}.recover"
  _wt="${SOLEUR_WENV_LOCK_TICKS:-$_WENV_TICKS_DEFAULT}"
  if [[ "$_wt" =~ ^[0-9]{1,4}$ ]] && (( 10#$_wt <= _WENV_TICKS_MAX )); then _wt=$((10#$_wt)); else _wt=$_WENV_TICKS_DEFAULT; fi
  _wum="$(umask)"
  umask 077
  trap '_wenv_unlock' EXIT
  trap '_wenv_unlock; exit 130' INT
  trap '_wenv_unlock; exit 143' TERM
  trap '_wenv_unlock; exit 129' HUP
  while :; do
    if mkdir -- "$_wl" 2>/dev/null; then
      _WENV_LOCK="$_wl"
      if ! printf '%s\n' "$$" > "$_wl/owner"; then
        rm -rf -- "$_wl"; _WENV_LOCK=""
        _wenv_fail env_write_failed "The lock at ${_wl} could not be recorded."
      fi
      break
    fi
    if [[ -L "$_wl" || -f "$_wl" ]]; then
      _wenv_fail env_lock_not_dir "The lock path ${_wl} exists but is not a directory; remove it."
    fi
    _wi=$((_wi + 1))
    _wstale=0
    if [[ ! -d "$_wl" ]]; then
      # mkdir failed with the path absent: the lock was released in between, or mkdir fails for another
      # reason (a name too long, no space): a pass that made no progress, so it sleeps below like any other.
      _ws=0; _wwhy=""
      _wd="${_wr%/*}"; [[ "$_wd" != "$_wr" ]] || _wd=.
      [[ -d "$_wd" && -w "$_wd" ]] || _wenv_fail env_dir_unwritable "The directory of ${_wf} does not allow a lock to be created."
    else
      _wown=""
      { read -r _wown < "$_wl/owner"; } 2>/dev/null || _wown=""
      if [[ "$_wown" =~ ^[0-9]+$ ]]; then
        _ws=0; _wsnap=pid
        if [[ "$_wown" == "$$" ]] || ! kill -0 "$_wown" 2>/dev/null; then _wstale=1; _wwhy=stale; else _wwhy=live; fi
      else
        _ws=$((_ws + 1)); _wwhy=""; _wsnap=empty
        if (( _ws > _WENV_EMPTY_POLLS )); then _wstale=1; fi
      fi
    fi
    if (( _wstale == 1 && _wi < _wt )); then
      if mkdir -- "$_wm" 2>/dev/null; then
        _WENV_REC="$_wm"
        _wo2=""
        { read -r _wo2 < "$_wl/owner"; } 2>/dev/null || _wo2=""
        if [[ "$_wsnap" == empty && ! "$_wo2" =~ ^[0-9]+$ ]]; then
          sleep "$_WENV_EMPTY_PAUSE" 2>/dev/null || sleep 1
          { read -r _wo2 < "$_wl/owner"; } 2>/dev/null || _wo2=""
        fi
        _wgone=0
        if [[ "$_wo2" =~ ^[0-9]+$ ]]; then
          if [[ "$_wo2" == "$$" ]] || ! kill -0 "$_wo2" 2>/dev/null; then rm -rf -- "$_wl"; _ws=0; _wgone=1; fi
        elif [[ "$_wsnap" == empty ]]; then
          rm -rf -- "$_wl"; _ws=0; _wgone=1
        fi
        _wenv_unlock
        if (( _wgone == 1 )); then continue; fi
      fi
    fi
    if (( _wi >= _wt )); then
      if [[ "$_wwhy" != live && -d "$_wm" ]]; then _wwhy=recover; fi
      case "$_wwhy" in
        live) _wenv_fail env_lock_timeout "Another write-env run is still holding the lock at ${_wl}; wait for it to finish and run this again. If no other run is active, remove that directory." ;;
        recover) _wenv_fail env_lock_timeout "A lock recovery is in progress or was interrupted (${_wm} exists); waited and gave up. If no other run is active, remove that directory." ;;
        *) _wenv_fail env_lock_timeout "The lock at ${_wl} could not be taken or recovered; waited and gave up. If no other run is active, remove that directory." ;;
      esac
    fi
    sleep "$_WENV_TICK" 2>/dev/null || sleep 1
  done
  for _wn in "${_wr}".wenv.??????; do
    if [[ -f "$_wn" && ! -L "$_wn" && -O "$_wn" ]]; then rm -f -- "$_wn"; fi
  done
  _WENV_TMP="$(mktemp "${_wr}.wenv.XXXXXX")" || _wenv_fail env_write_failed "A temp file could not be created beside ${_wf}."
  if [[ -f "$_wr" ]]; then
    _wrc=0
    LC_ALL=C grep -a -v -E "$_wre" "$_wr" > "$_WENV_TMP" || _wrc=$?
    if (( _wrc > 1 )); then
      _wenv_fail env_unreadable "The existing .env at ${_wf} could not be read."
    fi
  fi
  printf '%s\n' "$@" >> "$_WENV_TMP" || _wenv_fail env_write_failed "The new values could not be written beside ${_wf}."
  chmod 600 "$_WENV_TMP" || _wenv_fail env_write_failed "The temp file beside ${_wf} could not be restricted to mode 600."
  mv -f -- "$_WENV_TMP" "$_wr" || _wenv_fail env_write_failed "The new .env could not be moved into place at ${_wf}."
  _WENV_TMP=""
  _wenv_unlock
  trap - EXIT INT TERM HUP
  umask "$_wum"
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

  # Every value is checked BEFORE the first write (see the allow-list above).
  _wenv_validate LINKEDIN_CLIENT_ID LINKEDIN_CLIENT_SECRET LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN

  # One atomic, serialized, mode-600-from-birth write (see _wenv_write above). The remove-ERE names exactly
  # the four keys written below: LINKEDIN_ORG_ACCESS_TOKEN, LINKEDIN_ORG_ID, LINKEDIN_ALLOW_POST and
  # LINKEDIN_POST_MAX_LENGTH are read by linkedin-community.sh from the same .env and must survive.
  _wenv_write "$env_file" '^(LINKEDIN_CLIENT_ID|LINKEDIN_CLIENT_SECRET|LINKEDIN_ACCESS_TOKEN|LINKEDIN_PERSON_URN)=' \
    "LINKEDIN_CLIENT_ID=${LINKEDIN_CLIENT_ID}" \
    "LINKEDIN_CLIENT_SECRET=${LINKEDIN_CLIENT_SECRET}" \
    "LINKEDIN_ACCESS_TOKEN=${LINKEDIN_ACCESS_TOKEN}" \
    "LINKEDIN_PERSON_URN=${LINKEDIN_PERSON_URN}"

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
