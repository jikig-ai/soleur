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

# MUST PASS (Rules A-E clean): the basic-auth pair on curl's stdin config, fed by a process
# substitution, bare and inside $(...). Not the canonical-only member: the user key shares a
# config with a header line.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true
code="$(curl --disable --noproxy '*' -sS -o /dev/null -w '%{http_code}' --config - "$SINK_URL" < <(printf 'user = "svc:%s"\nheader = "Accept: application/json"\n' "$SENTRY_AUTH_TOKEN") || true)"
printf '%s\n' "$code"
