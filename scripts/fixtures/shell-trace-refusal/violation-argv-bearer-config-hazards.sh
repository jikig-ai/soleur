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
# Rule E MUST FIRE exactly three times. The bearer is NOT on argv in any of these:
# each call has a --config - form whose OWN hazards put it back in the open.
# 1) -v echoes the request headers, Authorization included, to stderr.
curl --disable --noproxy '*' -sS -v --config - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# 2) stdin is already the config; a stdin body cannot also be read from it.
curl --disable --noproxy '*' -sS --config - -d @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# 3) a here-string materialises the header in a temp file under bash.
cfg_line="header = \"Authorization: Bearer ${SENTRY_AUTH_TOKEN}\""
curl --disable --noproxy '*' -sS --config - "$SINK_URL" <<< "$cfg_line" || true
