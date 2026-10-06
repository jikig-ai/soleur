# shellcheck shell=bash
# _cf-admin-token.sh — shared Cloudflare admin-token verify + self-revoke
# helpers. Sourced (NEVER executed) by:
#   - apps/cla-evidence/scripts/gdpr-override.sh   (GDPR Art. 17 erasure driver)
#   - apps/cla-evidence/infra/bootstrap.sh         (one-shot post-merge bootstrap)
#
# Extracted per issue #3950 item 3 (the two call sites overlapped ~70%). The
# verify function adopts gdpr-override's MORE-DEFENSIVE empty-id hard-fail —
# bootstrap previously captured the id with `// ""` and continued on empty,
# silently disabling its own self-revoke. Hard-failing on empty id is the
# "more defensive" behavior the issue calls out as the upgrade bootstrap gains.
#
# Sourcing preconditions (both callers satisfy these BEFORE the `source` line):
#   - `red`, `green`, `yellow` log helpers are defined (callers keep their own
#     stream/format conventions; the helper does not hard-code colors).
#   - `curl` and `jq` are on PATH.
# Optional: CF_API may be set to override the API base; defaults to the
# canonical Cloudflare v4 base. Any other value is refused (the bearer is sent to
# that base, so an env override must not redirect it).
#
# The bearer rides curl's stdin config channel (`--config -`), never its argv:
# argv is world-readable via /proc/<pid>/cmdline for the life of the process.
# This file is sourced, so it carries no xtrace self-refusal of its own (a
# sourced `exit` would kill the caller); the caller's prologue is the trace
# defense. `printf` below is the shell builtin, so the value never reaches an
# exec argv.

# Token-shape guard: refuses an empty value or any byte outside the Cloudflare
# token alphabet (alphanumeric plus `_-`; `.~+/=` tolerated). A newline in the
# value would otherwise inject a curl config directive on the stdin channel.
# Never echoes the value.
_cf_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# _cf_admin_curl <bearer> <url> [curl args...]
#   The ONE curl wrapper: owns --disable (first argument; skips ~/.curlrc),
#   --noproxy '*', the token-shape guard, the destination pin and the stdin
#   header. Returns 2 (zero curl calls) when the token is unusable or the URL is
#   not under the pinned Cloudflare API base.
_cf_admin_curl() {
  local bearer="$1" url="$2"
  shift 2
  _cf_bearer_ok "$bearer" || return 2
  case "$url" in
    https://api.cloudflare.com/client/v4/*) ;;
    *) return 2 ;;
  esac
  curl --disable --noproxy '*' "$@" --config - "$url" 2>/dev/null \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$bearer")
}

# cf_token_verify <bearer>
#   Verifies the bearer is an active CF token and echoes its token id to stdout.
#   Returns non-zero (so callers' `|| exit`/`|| ...` branches fire) on:
#     - verify request failure (curl non-zero),
#     - status != "active",
#     - empty token id (the defensive upgrade — id is required for self-revoke).
cf_token_verify() {
  local bearer="$1"
  local cf_api="${CF_API:-https://api.cloudflare.com/client/v4}"
  local verify status id
  if ! verify=$(_cf_admin_curl "$bearer" "$cf_api/user/tokens/verify" --max-time 30 -fsS); then
    red "::error::admin token verify failed; rotate and retry"
    return 1
  fi
  status=$(printf '%s' "$verify" | jq -r '.result.status // "unknown"')
  if [[ "$status" != "active" ]]; then
    red "::error::admin token status=$status (expected active)"
    return 1
  fi
  id=$(printf '%s' "$verify" | jq -r '.result.id // ""')
  if [[ -z "$id" ]]; then
    red "::error::could not capture admin token id (needed for self-revoke)"
    return 1
  fi
  printf '%s' "$id"
}

# cf_token_self_revoke <bearer> <token_id>
#   Best-effort self-revoke. Warns (never hard-fails) on curl error; warns and
#   returns 0 on empty id. Mirrors the prior inline bodies at
#   gdpr-override.sh _self_revoke and bootstrap.sh's post-run revoke block.
cf_token_self_revoke() {
  local bearer="$1" id="$2"
  local cf_api="${CF_API:-https://api.cloudflare.com/client/v4}"
  if [[ -z "$id" ]]; then
    yellow "  WARN: no admin-token id captured; revoke manually in CF dashboard."
    return 0
  fi
  if _cf_admin_curl "$bearer" "$cf_api/user/tokens/$id" --max-time 30 -fsS -X DELETE >/dev/null 2>&1; then
    green "  admin token self-revoked"
  else
    yellow "  WARN: self-revoke failed; revoke $id manually in CF dashboard."
  fi
  return 0
}
