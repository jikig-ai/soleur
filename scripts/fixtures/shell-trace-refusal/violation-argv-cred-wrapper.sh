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

# Rules A/B/C/D are clean; Rule E must fire ONCE, through wrapper awareness: the header is
# an argument of a CALL to a file-local function (defined after its use) that runs curl.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

run_probe() {
  api_get -H "X-Signature-256: sha256=${SENTRY_AUTH_TOKEN}" "$SINK_URL"
}

api_get() { curl --disable --noproxy '*' -sS --max-time 20 "$@" || true; }

run_probe
