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

# Rule E must fire FOUR times: `-u` behind a bundle of curl's no-argument short flags, with the value
# glued to the bundle (`-sSu"U:P"`, `-fsSLusvc:"$TOK"`, `-suU:P`) and with the value in the NEXT word
# behind a bundle that starts with a digit flag (`-4u "U:P"`). Every spelling is real curl basic auth
# (the suite pins each against curl's own --libcurl output).
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# (The glued bundles sit right after `--disable`, ahead of `--noproxy '*'`: Rule D reads an operand as a token that
# is not preceded by a dash-led token, so a glued flag behind `'*'` would add an unrelated destination-pin finding.)
# Compliant FIRST member (the credential pair rides curl's stdin config): a check that stops at the
# first curl, or that is satisfied by one compliant call, reads this file clean.
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable -sSu"svc:${SENTRY_AUTH_TOKEN}" --noproxy '*' "$SINK_URL" || true
curl --disable -fsSLusvc:"${SENTRY_AUTH_TOKEN}" --noproxy '*' "$SINK_URL" || true
curl --disable -suU:"${SENTRY_AUTH_TOKEN}" --noproxy '*' "$SINK_URL" || true
curl --disable --noproxy '*' -4u "svc:${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
