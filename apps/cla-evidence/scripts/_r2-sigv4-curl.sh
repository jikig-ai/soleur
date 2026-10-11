# shellcheck shell=bash
# _r2-sigv4-curl.sh — the ONE curl that carries the R2 SigV4 key id and secret in
# apps/cla-evidence (#9756). Sourced (NEVER executed) by:
#   - apps/cla-evidence/scripts/r2-conditional-put.sh  (covers upload-{evidence,bypass}.sh)
#   - apps/cla-evidence/infra/bootstrap.sh              (the Step 1 probe PUT)
#
# The pair rides curl's stdin config channel (`--config -`), never its argv: argv is
# world-readable through /proc/<pid>/cmdline and `ps` for the life of the process. The
# config line is fed by a process substitution, never a pipe (a stub or a curl that never
# reads would turn a pipe into SIGPIPE under `pipefail`). Same shape as _cf-admin-token.sh
# (_cf_admin_curl) and ADR-280; the shared library scripts/lib/bearer-curl.sh builds header
# lines only and is deliberately untouched.
#
# This file is sourced, so it carries no xtrace self-refusal and no `exit` of its own (a sourced
# exit would kill the caller); the caller's prologue is the trace defence, and EVERY caller MUST
# carry one (under `set -x` the call line itself traces the values before this body runs; the suite
# asserts it for each file that calls into this helper). `printf` below is the shell builtin, so a
# value never reaches an exec argv. Values are judged as given: nothing is trimmed (a value with a
# trailing newline is refused as control_char), because both callers hold the exact 32/64 length.
#
# Refusal contract. A malformed value makes ZERO requests: a value-free `::error::` annotation
# and `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>` go to stderr and
# the function returns 2. Status 2 is also curl's own init-failure code, so no caller may branch
# on it: the marker, not the status, is the discriminator (ADR-280 Decision 3). A refused
# destination or argument returns 64 (a different fault class, no credential marker).

# Token-alphabet guard: refuses an empty value or any byte outside [A-Za-z0-9._~+/=-]. That
# closes the three bytes that change how a quoted `user = "..."` value parses (a double quote,
# a backslash, a newline) and the colon that would split the pair. It is not a vendor-format
# guard: the exact 32/64 length preflight stays in the caller.
_r2_cred_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# _r2_refuse <script> <variable-name> <value> — print the annotation and the marker; never the value.
# The variable name is the CALLER's (its operator reads this line), so it is a parameter of the judge.
_r2_refuse() {
  local LC_ALL=C script="$1" name="$2" reason=token_shape
  case "$3" in *[[:cntrl:]]*) reason=control_char ;; esac
  echo "::error::${script}: ${name} unusable" >&2
  echo "SOLEUR_CREDENTIAL_REFUSED script=${script} reason=${reason}" >&2
}

# r2_sigv4_judge <script> <id> <secret> [<id-variable-name> <secret-variable-name>]
#   Returns 0 when both values pass the alphabet guard, else prints the refusal and returns 2.
#   The two names default to the cla-evidence workflow's variables; bootstrap passes its own.
#   <script> is forced to the safe alphabet (the marker feeds log parsing): anything else prints
#   as `unknown`, so a caller passing free text cannot inject a line or a workflow command.
r2_sigv4_judge() {
  local LC_ALL=C script="${1:-}" id="${2:-}" secret="${3:-}"
  local id_name="${4:-R2_CLA_EVIDENCE_ACCESS_KEY_ID}" secret_name="${5:-R2_CLA_EVIDENCE_SECRET}"
  case "$script" in ''|*[!A-Za-z0-9._-]*) script=unknown ;; esac
  if ! _r2_cred_ok "$id"; then
    _r2_refuse "$script" "$id_name" "$id"
    return 2
  fi
  if ! _r2_cred_ok "$secret"; then
    _r2_refuse "$script" "$secret_name" "$secret"
    return 2
  fi
  return 0
}

# _r2_args_ok <curl args...> — position-aware allowlist of exactly what the two callers pass.
#   Flags: -s -S -sS. Value options (the next token is the value): -o -w --max-time -X -H
#   --data-binary, where a -H, -w or --data-binary value must not start with `@` (curl reads a
#   file or stdin there) and a value option left dangling at the end is refused (it would swallow
#   the --aws-sigv4 that follows). Anything else is refused: a deny-list of spellings misses
#   `--user=x:y`, `-Kf`, `-sSK f`, long-option prefixes and everything that redirects or
#   multiplies the credentialed request (--url, a second URL, --connect-to, --resolve, -k, -L).
_r2_args_ok() {
  local a
  while [[ $# -gt 0 ]]; do
    a="$1"; shift
    case "$a" in
      -s|-S|-sS) ;;
      -o|--max-time|-X)
        [[ $# -ge 1 ]] || return 1
        shift ;;
      -w|-H|--data-binary)
        [[ $# -ge 1 ]] || return 1
        case "$1" in @*) return 1 ;; esac
        shift ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# r2_sigv4_curl <script> <id> <secret> <url> [curl args...]
#   Runs `curl --disable --noproxy '*' <args> --aws-sigv4 aws:amz:auto:s3 --globoff
#   --proto =https --config - <url>` with `user = "<id>:<secret>"` on stdin. The URL stays the
#   LAST curl argument. Returns 64 (usage, destination, argument) or 2 (credential) before any
#   request; otherwise curl's own status. The request's stderr is dropped (it was before this
#   change); the refusal lines above are printed outside that redirect, so they stay visible.
r2_sigv4_curl() {
  if [[ $# -lt 4 ]]; then
    echo "::error::r2_sigv4_curl: usage: <script> <id> <secret> <url> [curl args...]" >&2
    return 64
  fi
  local LC_ALL=C script="$1" id="$2" secret="$3" url="$4"
  shift 4
  # The pin is in-file and anchored, the shape the Rule D linter recognises. It matches the
  # default-jurisdiction hostname of _r2-endpoint.sh only: a .eu. or .fedramp. host is refused
  # by both, loudly, so a jurisdiction move is a deliberate change here.
  if ! [[ "$url" =~ ^https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com/ ]]; then
    echo "::error::r2_sigv4_curl: destination is not a canonical R2 origin (https://<32-hex>.r2.cloudflarestorage.com/...)" >&2
    return 64
  fi
  if ! _r2_args_ok "$@"; then
    echo "::error::r2_sigv4_curl: a curl argument is outside the allowlist" >&2
    return 64
  fi
  r2_sigv4_judge "$script" "$id" "$secret" || return $?
  # `env -u` scrubs TLS-trust, key-log, library-load and resolution redirection inherited from an
  # earlier step (the first thirteen are scripts/lib/bearer-curl.sh's list; the suite asserts that
  # list stays a subset of this one) and keeps the pair out of curl's own /proc/<pid>/environ (the
  # last four).
  env -u SSLKEYLOGFILE -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR -u CURL_HOME \
      -u OPENSSL_CONF -u OPENSSL_MODULES -u LD_PRELOAD -u LD_AUDIT -u LD_LIBRARY_PATH \
      -u HOSTALIASES -u LOCALDOMAIN -u RES_OPTIONS \
      -u R2_CLA_EVIDENCE_ACCESS_KEY_ID -u R2_CLA_EVIDENCE_SECRET \
      -u R2_S3_ACCESS_KEY_ID -u R2_S3_SECRET_ACCESS_KEY \
    curl --disable --noproxy '*' "$@" --aws-sigv4 'aws:amz:auto:s3' --globoff --proto '=https' --config - "$url" 2>/dev/null \
    < <(printf 'user = "%s:%s"\n' "$id" "$secret" 2>/dev/null)
}
