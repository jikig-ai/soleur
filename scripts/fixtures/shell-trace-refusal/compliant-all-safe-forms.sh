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

# Derived from compliant-ruled-pinned-destination.sh: Rules A/B/C/D are clean, so
# only Rule E (#9597, bearer token on curl argv) could fire here. It MUST NOT:
# every call below is a safe form.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# `--header @<(...)`: the header is read from a process substitution.
curl --disable --noproxy '*' -sS --header @<(printf 'Authorization: Bearer %s' "$SENTRY_AUTH_TOKEN") "$SINK_URL" || true
# `-K -`: the short spelling of `--config -`.
curl --disable --noproxy '*' -sS -K - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# `--config <(...)`: the config itself is a process substitution.
curl --disable --noproxy '*' -sS --config <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") "$SINK_URL" || true
# A bearer in a TRAILING COMMENT is not an executed argument.
curl --disable --noproxy '*' -sS "$SINK_URL" || true  # was: -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}"
# The standalone anon-key call: a public, non-bearer credential, no second header.
curl --disable --noproxy '*' -sS -H "apikey: ${SUPABASE_ANON_KEY}" "$SINK_URL" || true
