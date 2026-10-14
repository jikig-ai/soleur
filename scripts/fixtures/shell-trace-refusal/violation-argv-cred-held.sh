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

# Derived from violation-argv-bearer-variable-held.sh. Rules A/B/C/D are clean, so only
# Rule E (#9597, credential header on curl argv) can fire here: it must fire ONCE. The
# header is NOT an Authorization header: it is the Cloudflare Access client-id header,
# built into a variable far from the call (held-name capture read site).
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

cf_hdr="CF-Access-Client-Id: ${SENTRY_AUTH_TOKEN}"
curl --disable --noproxy '*' -sS -H "$cf_hdr" "$SINK_URL" || true
