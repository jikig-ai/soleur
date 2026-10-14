#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf "[FATAL] refusing to trace with SENTRY_AUTH_TOKEN set (#7797)\n" >&2
      exit 78
    fi
    ;;
esac

# Rules A/B/C/D are clean; Rule E must fire ONCE. This is the shape of
# plugins/soleur/skills/community/scripts/discord-setup.sh: a MULTI-LINE
# `local curl_args=(` declaration (no `-a`) holding an `Authorization: Bot` header, then a
# conditional `curl_args+=(` append, then the expansion.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

send() {
  local data="${1:-}"
  local curl_args=(
    --disable --noproxy '*' -sS
    -H "Authorization: Bot ${SENTRY_AUTH_TOKEN}"
    -H "Content-Type: application/json"
  )
  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi
  curl "${curl_args[@]}" "$SINK_URL" || true
}
