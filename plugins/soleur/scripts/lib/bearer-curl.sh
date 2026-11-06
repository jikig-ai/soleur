#!/usr/bin/env bash
# shellcheck disable=SC2034  # BC_* are the helper's outputs, read by the sourcing script
# bearer-curl.sh -- SOURCED helper (never executed): read ONE read-only bearer token from the secret store and send ONE
# hardened HTTPS GET with it. Consumer: skills/ship/scripts/hold-gate-eval.sh (the `web-acceptance` gate). Suite:
# plugins/soleur/test/bearer-curl.test.sh. Precedent for the token handling: skills/trigger-cron/scripts/trigger.sh.
#
# Why this file exists beside scripts/lib/bearer-curl.sh (the repository-root helper, `bc_curl`, used by the workflow YAML
# and CI): this plugin ships to customer machines, which have the plugin directory and nothing of the repository root, so
# it cannot source a repo-root script (ADR-280 already records that the plugin cannot source scripts/lib). Same name, a
# different helper: the repo-root one SENDS a request for a workflow; this one reads ONE secret by name and sends ONE GET.
# Both hide the same family of curl environment variables (the list below is kept equal to _bc_send's in the root helper).
# ADR-280's stdin-config form (`--config -`) is not used here: the 0600 config file lives in a private 0700 scratch
# directory the caller made (hold-gate-eval.sh uses mktemp -d) and is removed right after curl returns, on every path.
# bc_read_token and bc_get are GENERIC: any UPPER_SNAKE secret name and any https URL. The closed union of secret names
# that may be read lives in the TypeScript reader (apps/web-platform/lib/internal-auth-named.ts), not here.
#
# API (all return 0 on success, non-zero on ANY failure; no function prints anything on stdout):
#   bc_read_token <SECRET_NAME>   reads `doppler secrets get <name> --plain --project soleur --config prd` (project and
#                                 config are fixed here, never a parameter, never the environment), applies the shape
#                                 guard and leaves the value in BC_TOKEN (unexported). The value is never printed.
#   bc_get <scratch-dir> <url>    GET <url> with the bearer on a 0600 curl config written under <scratch-dir> (never on
#                                 argv). Sets BC_STATUS (3-digit HTTP status, 000 when curl did not get one), BC_RC (curl's
#                                 exit status) and BC_BODY (path of the response body). Returns 0 only when curl itself
#                                 succeeded and produced a status; the HTTP status is the CALLER's to interpret (this
#                                 function never reads a 4xx or 5xx as success or failure).
#   bc_clear                      forgets the token.
#   BC_ERR                        why bc_read_token returned non-zero, for the caller's wording (never the value): `missing` (no
#                                 secret-store tool, a bad name, the read failed or was empty), `shape` (a value was read but
#                                 failed the 48 to 256 character guard) or `xtrace`. Empty after a success. Set silently.
#
# Hardening, in one place: refuse under xtrace (a traced run would print the credential), a token-shape guard (48 to 256
# characters of [A-Za-z0-9._~+/=-], the same bounds as TOKEN_RE in the verify route; the token is written into a curl config
# line, so a quote or newline would inject a directive), `--disable` first (no ~/.curlrc),
# `--noproxy '*'`, `--proto =https`, `--max-redirs 0` (a redirect is a status, never followed), bounded connect time,
# total time and body size, no retry (a retry turns a throttled answer into a later success), and the environment
# variables that subvert TLS, name resolution or the loaded libraries hidden from curl only (the caller's own environment is not mutated).

# Refuse to be loaded under xtrace. `return` ends a `source`; `exit` covers a direct execution.
case "$-" in
  *x*)
    printf 'bearer-curl: refusing to run under xtrace: this helper handles a live credential and -x would print it (see #7797). No secret has been read.\n' >&2
    return 78 2>/dev/null || exit 78 # mut:xtrace-source
    ;;
esac

BC_TOKEN=""; BC_STATUS="000"; BC_RC=1; BC_BODY=""; BC_ERR=""

bc_shape_ok() { # <value>: 0 only for a plausible bearer token (never echoes it)
  local LC_ALL=C
  [ "${#1}" -ge 48 ] || return 1
  [ "${#1}" -le 256 ] || return 1
  case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac
  return 0
}

bc_clear() { BC_TOKEN=""; }

bc_read_token() { # <SECRET_NAME>
  local name="${1:-}" tok="" to=()
  BC_TOKEN=""; BC_ERR="missing"
  case "$-" in *x*) BC_ERR="xtrace"; return 1 ;; esac # mut:xtrace-read
  case "$name" in ''|*[!A-Z0-9_]*) return 1 ;; esac
  command -v doppler >/dev/null 2>&1 || return 1
  if command -v timeout >/dev/null 2>&1; then to=(timeout 10); elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout 10); fi
  tok="$(${to[@]+"${to[@]}"} doppler secrets get "$name" --plain --project soleur --config prd 2>/dev/null </dev/null)" || return 1
  if [ -n "$tok" ] && ! bc_shape_ok "$tok"; then BC_ERR="shape"; fi # mut:err-shape
  bc_shape_ok "$tok" || return 1 # mut:shape
  BC_TOKEN="$tok"; BC_ERR=""
  return 0
}

bc_get() { # <scratch-dir> <https-url>
  local scratch="${1:-}" url="${2:-}" cfg body
  BC_STATUS="000"; BC_RC=1; BC_BODY=""
  case "$-" in *x*) return 1 ;; esac
  [ -n "$BC_TOKEN" ] || return 1
  [ -d "$scratch" ] || return 1
  case "$url" in https://*) ;; *) return 1 ;; esac # mut:scheme
  cfg="$scratch/bc.cfg"; body="$scratch/bc.body"
  rm -f "$cfg" "$body"
  ( umask 077 && printf 'header = "Authorization: Bearer %s"\n' "$BC_TOKEN" > "$cfg" ) || { rm -f "$cfg"; return 1; }
  BC_STATUS="$(env -u SSLKEYLOGFILE -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR -u CURL_HOME -u HOSTALIASES -u LOCALDOMAIN -u RES_OPTIONS -u OPENSSL_CONF -u OPENSSL_MODULES -u LD_PRELOAD -u LD_AUDIT -u LD_LIBRARY_PATH curl --disable --noproxy '*' --proto =https --max-redirs 0 --connect-timeout 5 --max-time 15 --max-filesize 4096 -sS -o "$body" -w '%{http_code}' --config "$cfg" "$url" 2>/dev/null </dev/null)"; BC_RC=$?
  rm -f "$cfg"
  [[ "$BC_STATUS" =~ ^[0-9]{3}$ ]] || BC_STATUS="000"
  [ -f "$body" ] && BC_BODY="$body"
  [ "$BC_RC" -eq 0 ] && [ "$BC_STATUS" != "000" ]
}
