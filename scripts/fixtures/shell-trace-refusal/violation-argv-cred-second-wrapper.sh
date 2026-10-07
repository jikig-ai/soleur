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

# Rules A/B/C/D are clean; Rule E must fire ONCE, from the wrapper-site check alone: the
# wrapper keeps the Authorization header on stdin (safe), and the CALL adds a second
# credential header (`apikey:`) on argv.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

run_probe() {
  api_get -H "apikey: ${SUPABASE_ANON_KEY}" "$SINK_URL"
}

api_get() {
  curl --disable --noproxy '*' -sS --max-time 20 --config - "$@" < <(printf 'header = "Authorization: Bot %s"\n' "$SENTRY_AUTH_TOKEN") || true
}

run_probe
