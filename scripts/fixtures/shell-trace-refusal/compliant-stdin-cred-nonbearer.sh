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

# MUST PASS (Rules A-E clean): the new header names on the SAFE spellings. The vocabulary
# widening must flag them only when they are on argv, never on stdin.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'header = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$SENTRY_AUTH_TOKEN" "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'header = "X-Signature-256: sha256=%s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'header = "Authorization: Bot %s"\n' "$SENTRY_AUTH_TOKEN") || true
printf 'X-API-Key: %s\n' "$SENTRY_AUTH_TOKEN" | curl --disable --noproxy '*' -sS -H @- "$SINK_URL" || true
