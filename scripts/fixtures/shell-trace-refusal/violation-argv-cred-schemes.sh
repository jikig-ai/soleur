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

# Rules A/B/C/D are clean; Rule E must fire FOUR times. ANY `Authorization:` value is a
# credential because the vocabulary matches the header NAME, not a scheme list: `Bot`,
# `Digest`, and a scheme held in a variable (`${SCHEME}`) included.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

SCHEME="Token"
curl --disable --noproxy '*' -sS -H "Authorization: Bot ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "Authorization: Digest ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "Authorization: ${SCHEME} ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "authorization:${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
