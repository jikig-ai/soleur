#!/usr/bin/env bash
# hmac-sha1-b64.sh -- RFC 2104 HMAC-SHA1 in bash, for OAuth 1.0a request signing.
# Sourced by x-community.sh (lazily, inside oauth_sign at EACH signature (oauth_sign runs in a
# command-substitution subshell, so nothing is cached between calls), so a trace-safe run with no
# credentials set is never refused over this file) and by x-setup.sh (at load; its own prologue refuses
# `bash -x` unconditionally). Defines ONE function and runs nothing.
#
# WHY THIS EXISTS (#9597). The signing key (the API secret and the token secret, joined
# with an ampersand) used to be handed to `openssl dgst` as the operand of its key option,
# so it sat in /proc/<pid>/cmdline, readable by every local user, for the life of the
# process. The runner image has no python3 and x-community.sh runs hosted (the Inngest
# community crons), so the python route the rest of the sweep uses is not available here;
# the plugin depends only on bash, openssl, jq and curl, and this keeps it that way.
#
# HOW. The key lives only in bash builtins and pipes, never on an exec argument. The two 64-byte
# pads are built as printf byte-ESCAPE TEXT (`\x36...`) in function-local variables (_hs_ip,
# _hs_op, the key hex _hs_kh, the inner digest _hs_ih/_hs_oh) and emitted by the printf builtin
# straight into a pipe; the variables hold escape text rather than raw bytes because a pad can
# hold a NUL byte, which a bash variable cannot. `openssl dgst -sha1 -binary` reads stdin only;
# its argument list is the constant `dgst -sha1 -binary`. No temp file, no here-string and no
# heredoc is used on key-derived data (bash older than 5.1, including macOS 3.2, writes those to
# a temp file).
#
# USAGE: the message arrives on STDIN; the KEY is passed by the NAME of the variable that
# holds it (never as an expansion, so a traced call line shows only the name). The
# function prints the base64 of the 20-byte digest, one line.
#   signature=$(printf '%s' "$message" | hmac_sha1_b64 key_variable_name) || handle_failure
#
# CONTRACT:
#   - returns 0 on success. Non-zero on any failure, with NOTHING on stdout:
#       2  bad or unset variable name (an unset key is not an empty key; an empty key is valid)
#       78 refused under xtrace (tracing would print the key)
#       1  a tool failed (openssl, od, tr, base64 missing or erroring)
#   - never calls the shell's exit builtin, and never prints the credential-refusal marker:
#     the caller decides its own exit code and its own diagnostics.
#   - the work runs in a subshell. Inside it allexport is turned off and the variable the caller
#     NAMED (the derived signing key) is unexported, and this file's own working variables (all
#     prefixed with _hs_) are never exported, so under a caller's `set -a` (a sourced .env)
#     neither the derived key variable nor a _hs_ variable reaches the environment of openssl,
#     od, tr or base64. What the function does NOT control: a variable the caller exported
#     earlier. The raw API secret and token secret the key is built from stay in those children's
#     environment when the caller exported them (a sourced .env, the hosted environment); that is
#     readable by the same user and root only, and on no argument list. The caller's shell
#     options are untouched.
#   - LC_ALL=C inside, so every byte is one character.
#   - portable to bash 3.2 and BSD od/base64: the shell features used are printf -v,
#     substring expansion, indirect expansion and arithmetic; the external tools are
#     openssl, od, tr and base64 (a digest is 28 characters, so GNU line wrapping never
#     applies).

case "$-" in
  *x*)
    # Load-time refusal, first in the file (the xtrace lint's prologue rule, #7797): sourcing
    # this under `bash -x` and then calling it would print the key. It is UNCONDITIONAL because
    # this file names its key indirectly (`${!1}`), so there is no literal credential name for a
    # conditional `${VAR:+x}` hatch to test. That is why x-community.sh sources it lazily, at each
    # signature, after its own conditional prologue has already allowed the run. A sourced
    # file returns; the `|| exit` arm runs only if the file is EXECUTED instead of sourced. The
    # refusal goes to STDOUT here, like the other prologues: agent runtimes surface stdout and
    # swallow stderr. A caller that sources this inside a command substitution redirects the
    # source command's stdout to its saved real stdout.
    printf 'Refusing to load the HMAC helper under `bash -x`: tracing would print the signing key. Re-run without `bash -x`.\n'
    return 78 2>/dev/null || exit 78
    ;;
esac

hmac_sha1_b64() {
  # Its own xtrace refusal at CALL time too: tracing can be switched on after this file was
  # loaded. Refusal goes to stderr because stdout is the digest pipe.
  case "$-" in
    *x*)
      printf 'Refusing to compute an HMAC under `bash -x`: tracing would print the signing key. Re-run without `bash -x`.\n' >&2
      return 78
      ;;
  esac
  case "${1-}" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) return 2 ;;
  esac
  [ -n "${!1+x}" ] || return 2
  (
    set +a
    set +e
    set -o pipefail
    # shellcheck disable=SC2163
    export -n -- "$1" 2>/dev/null
    LC_ALL=C
    export LC_ALL
    # The key as hex text. A key longer than the 64-byte block is replaced by its digest.
    _hs_kh=$(printf '%s' "${!1}" | od -An -v -tx1 | tr -d ' \n') || return 1
    if (( ${#_hs_kh} > 128 )); then
      _hs_kh=$(printf '%s' "${!1}" | openssl dgst -sha1 -binary | od -An -v -tx1 | tr -d ' \n') || return 1
    fi
    printf -v _hs_z '%0128d' 0
    _hs_kh="${_hs_kh}${_hs_z:${#_hs_kh}}"
    # The two pads as printf byte-escape strings (the key XOR 0x36 and XOR 0x5c).
    _hs_i=0
    _hs_ip=''
    _hs_op=''
    while (( _hs_i < 64 )); do
      _hs_b=$((16#${_hs_kh:2*_hs_i:2}))
      printf -v _hs_t '\\x%02x' $(( _hs_b ^ 54 ))
      _hs_ip+=$_hs_t
      printf -v _hs_t '\\x%02x' $(( _hs_b ^ 92 ))
      _hs_op+=$_hs_t
      _hs_i=$((_hs_i + 1))
    done
    # Inner digest over (inner pad, message); the message is this function's stdin.
    # shellcheck disable=SC2059
    _hs_ih=$( { printf -- "$_hs_ip"; cat; } | openssl dgst -sha1 -binary | od -An -v -tx1 | tr -d ' \n' ) || return 1
    [ "${#_hs_ih}" -eq 40 ] || return 1
    _hs_i=0
    _hs_oh=''
    while (( _hs_i < 20 )); do
      printf -v _hs_t '\\x%s' "${_hs_ih:2*_hs_i:2}"
      _hs_oh+=$_hs_t
      _hs_i=$((_hs_i + 1))
    done
    # Outer digest over (outer pad, inner digest), as base64.
    # shellcheck disable=SC2059
    { printf -- "$_hs_op"; printf -- "$_hs_oh"; } | openssl dgst -sha1 -binary | base64
  )
}
