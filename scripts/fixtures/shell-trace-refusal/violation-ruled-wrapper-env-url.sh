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

# Derived from compliant-ruled-pinned-destination.sh: SINK_URL below is pinned and
# the stdin bearer keeps Rule E clean, so ONLY Rule D can fire -- on the wrapper CALL
# whose env-settable "$API_URL" destination is never compared against a literal. The
# wrapper's own curl line names no destination (`"$@"`), so without wrapper awareness
# this reads fully compliant.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true

API_URL="${FIXTURE_API_URL:-https://api.example/v1}"
api_get() { curl --disable --noproxy '*' -sS --max-time 20 --config - "$@" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true; }
api_get "$API_URL"
