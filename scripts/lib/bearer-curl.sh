#!/usr/bin/env bash
# bearer-curl.sh — send a credentialed request WITHOUT putting the credential on any argument list.
#
# A header passed as `-H "Authorization: Bearer ..."` is an argument of the transfer process, readable
# by every local user in /proc/<pid>/cmdline and `ps` for the life of the request. This library is the
# one tested implementation of the stdin-config form (`--config -`) for workflow steps and composite
# actions (tracker #9597, parent #7797). ADR-280 records the contract. SOURCE it; it defines functions
# only and never calls `exit`, so a failure is the caller's to route.
#
#   source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh" || { ::error:: ...; exit 1; }
#   bc_curl NAME 'Authorization:Bearer :TOKEN' -- -sS --max-time 30 -o /dev/null -w '%{http_code}' "$URL"
#   SIG="$(printf '%s' "$BODY" | bc_hmac_sha256_hex WEBHOOK_KEY)" || SIG=""
#
# bc_curl SCRIPT SPEC... -- CURL_ARGS...
#   SCRIPT  short caller name, only used in the refusal marker (`$0` is a temp file in a runner step).
#   SPEC    NAME:PREFIX:VAR  — header NAME, literal PREFIX ("Bearer ", "sha256=", or empty), and the
#           NAME of the variable that holds the value. The value is read by indirect expansion only
#           inside this file, so the caller's source line never carries it.
#   Every value is judged BEFORE the first byte is sent. A value that is empty, unset, or outside
#   [A-Za-z0-9._~+/=-] (which also closes the injection a quote or newline would open on the config
#   channel: a second `url = ...` directive) makes the call return 2 with zero requests made, one
#   value-free stderr line naming only the variable, and the marker
#       SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>
#   rc 2 collides with curl's own exit 2 (init failure): no caller may branch on rc == 2, the marker
#   is the discriminator. No default timeout is added (byte-neutral per call site); a caller that
#   had `--max-time` keeps it. Return codes: curl's own, 2 refused, 64 bad call shape, 78 xtrace on.
#
# bc_refuse SCRIPT VAR — print the same value-free line and marker for a site's own pre-guard, return 2.
#
# bc_hmac_sha256_hex KEYVAR — message on stdin; prints 64 lowercase hex or returns 1. The key reaches
#   a `python3 -I` child by per-command environment prefix only (never argv); an empty key or a
#   missing python3 returns 1, it never signs with an empty key. Use `|| SIG=""` at the call site so
#   a failure reaches the caller's shape check instead of aborting mute under `set -e`.
#
# Tracing refusal: each function that binds a credential refuses (rc 78) when `set -x` is on, because
# a traced expansion prints the value. A sourced library cannot rely on its caller's prologue.

# A value is usable iff non-empty and drawn from the token alphabet the 68 inline copies used.
bc_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# Announce a refused credential: one value-free line naming only the variable, and the marker. Used by
# the chokepoint below and by a site's own pre-guard (where a bare rc 2 would fold into a different
# verdict arm). Always returns 2. Reads the value only to classify control_char vs token_shape.
bc_refuse() {
  case "$-" in *x*) printf 'bc_refuse: refusing to bind a credential while xtrace is on\n' >&2; return 78 ;; esac
  local _bc_script="${1:-}" _bc_var="${2:-}" _bc_val="" _bc_reason=token_shape
  [[ "$_bc_script" =~ ^[A-Za-z0-9._-]+$ ]] || _bc_script="unknown"
  if [[ "$_bc_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then _bc_val="${!_bc_var:-}"; else _bc_var="unknown"; fi
  case "$_bc_val" in *[[:cntrl:]]*) _bc_reason=control_char ;; esac
  printf 'bc_curl: %s unusable\n' "$_bc_var" >&2
  printf 'SOLEUR_CREDENTIAL_REFUSED script=%s reason=%s\n' "$_bc_script" "$_bc_reason" >&2
  return 2
}

# The single place a request is made.
_bc_send() {
  local LC_ALL=C _bc_script="${1:-}" _bc_spec _bc_name _bc_rest _bc_prefix _bc_var _bc_val
  shift
  [[ "$_bc_script" =~ ^[A-Za-z0-9._-]+$ ]] || _bc_script="unknown"
  local -a _bc_fields=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    _bc_spec="$1"
    shift
    [[ "$_bc_spec" == *:*:* ]] || { printf 'bc_curl: malformed header spec\n' >&2; return 64; }
    _bc_name="${_bc_spec%%:*}"
    _bc_rest="${_bc_spec#*:}"
    _bc_prefix="${_bc_rest%%:*}"
    _bc_var="${_bc_rest#*:}"
    [[ "$_bc_name" =~ ^[A-Za-z0-9-]+$ ]] || { printf 'bc_curl: malformed header name\n' >&2; return 64; }
    [[ "$_bc_prefix" =~ ^[A-Za-z0-9=_\ .-]*$ ]] || { printf 'bc_curl: malformed header prefix\n' >&2; return 64; }
    [[ "$_bc_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { printf 'bc_curl: malformed variable name\n' >&2; return 64; }
    _bc_val="${!_bc_var:-}"
    bc_ok "$_bc_val" || { bc_refuse "$_bc_script" "$_bc_var"; return 2; }
    _bc_fields+=("$_bc_name" "$_bc_prefix" "$_bc_val")
  done
  [ "${1:-}" = "--" ] || { printf 'bc_curl: missing -- separator\n' >&2; return 64; }
  shift
  [ "${#_bc_fields[@]}" -gt 0 ] || { printf 'bc_curl: no header spec\n' >&2; return 64; }
  # Process substitution, never a pipe: with `pipefail` a consumer that exits first turns the
  # writer's SIGPIPE into 141. The writer's stderr is silenced INSIDE the substitution so a closed
  # pipe prints no broken-pipe line under a runner that ignores SIGPIPE.
  curl --disable --noproxy '*' "$@" --config - \
    < <(printf 'header = "%s: %s%s"\n' "${_bc_fields[@]}" 2>/dev/null)
}

bc_curl() {
  case "$-" in *x*) printf 'bc_curl: refusing to bind a credential while xtrace is on\n' >&2; return 78 ;; esac
  _bc_send "$@"
}

bc_hmac_sha256_hex() {
  case "$-" in *x*) printf 'bc_hmac_sha256_hex: refusing to bind a credential while xtrace is on\n' >&2; return 78 ;; esac
  local _bc_keyvar="${1:-}" _bc_out
  [[ "$_bc_keyvar" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { printf 'bc_hmac_sha256_hex: malformed variable name\n' >&2; return 64; }
  _bc_out="$(HMAC_KEY="${!_bc_keyvar:-}" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null)" || return 1
  [[ "$_bc_out" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$_bc_out"
}
