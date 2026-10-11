#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}${SUPABASE_ANON_KEY:+x}" ]; then
      printf "[FATAL] refusing to trace with a live credential set (#7797)\n" >&2
      exit 78
    fi
    ;;
esac

# Rule E must fire ONCE: the `-u` pair sits in a plain `local curl_args=(` array (no `-a`) with a
# conditional `+=(` append; the inliner puts it on the curl at the expansion.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# Compliant FIRST member (the credential pair rides curl's stdin config): a check that stops at the
# first curl, or that is satisfied by one compliant call, reads this file clean.
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true

send() {
  local data="${1:-}"
  local curl_args=(
    --disable --noproxy '*' -sS
    -u "svc:${SENTRY_AUTH_TOKEN}"
  )
  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi
  curl "${curl_args[@]}" "$SINK_URL" || true
}
