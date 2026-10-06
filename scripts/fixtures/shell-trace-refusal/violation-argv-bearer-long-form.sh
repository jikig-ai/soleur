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
# Rule E MUST FIRE exactly three times, once per call site below. Each spelling
# is a distinct evasion of a `-H "Authorization: Bearer` pattern match.
# 1) the long flag, single-quoted, lower case. (A single-quoted value cannot expand,
#    so it carries a synthesized token; the spelling is the point.)
curl --disable --noproxy '*' -sS --header 'authorization: bearer FAKE' "$SINK_URL" || true
# 2) the short flag with NO space before its value.
curl --disable --noproxy '*' -sS -H"Authorization:Bearer${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
# 3) the header AFTER the URL.
curl --disable --noproxy '*' -sS "$SINK_URL" -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" || true
