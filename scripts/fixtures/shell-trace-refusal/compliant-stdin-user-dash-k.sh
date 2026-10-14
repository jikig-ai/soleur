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

# MUST PASS (Rules A-E clean): the other safe spellings of the stdin config carrying a `user` key.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS -K - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") "$SINK_URL" || true
