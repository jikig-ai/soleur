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

# Rules A/B/C/D are clean; Rule E must fire ONCE, from the call-level check alone: the
# non-Bearer Authorization header travels on STDIN (safe), and a second credential header
# (`apikey:`) rides argv beside it.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

printf 'Authorization: Bot %s\n' "$SENTRY_AUTH_TOKEN" | curl --disable --noproxy '*' -sS -H @- -H "apikey: ${SUPABASE_ANON_KEY}" "$SINK_URL" || true
