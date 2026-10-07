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

# Rules A/B/C/D are clean; Rule E must fire ONCE. The Cloudflare Access client-secret
# header is held in an array assigned after `&&`, which the call-site inliner cannot
# see, so only the file-wide array-capture read site can report it.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

send_gated() {
  local -a _gate=()
  [ -n "${SENTRY_AUTH_TOKEN:-}" ] && _gate=(--disable --noproxy '*' -sS -H "CF-Access-Client-Secret: ${SENTRY_AUTH_TOKEN}")
  curl "${_gate[@]}" "$SINK_URL" || true
}
