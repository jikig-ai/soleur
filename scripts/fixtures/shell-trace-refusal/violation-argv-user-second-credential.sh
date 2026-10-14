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

# Rule E must fire ONCE with BOTH reasons: the `-u` pair is a credential in its own right, and the
# `apikey:` header beside it on argv is a second credential (the call-level check).
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# Compliant FIRST member (the credential pair rides curl's stdin config): a check that stops at the
# first curl, or that is satisfied by one compliant call, reads this file clean.
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS -u "svc:${SENTRY_AUTH_TOKEN}" -H "apikey: ${SUPABASE_ANON_KEY}" "$SINK_URL" || true
