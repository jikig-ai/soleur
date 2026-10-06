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

# Derived from compliant-ruled-pinned-destination.sh: Rules A/B/C/D are clean, so
# only Rule E (#9597, bearer token on curl argv) can fire here.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
# Rule E MUST FIRE exactly once. The first call is the compliant canonical form
# (bearer on stdin); the SECOND call in the same script leaks it on argv. A rule that
# stops at the first curl, or that lets a compliant neighbour launder the call
# below it, reads this fixture as clean.
curl --disable --noproxy '*' -sS --max-time 20 --config - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
