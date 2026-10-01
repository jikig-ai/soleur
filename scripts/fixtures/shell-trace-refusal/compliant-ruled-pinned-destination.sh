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

# Rule D MUST PASS: transport-confined AND the env-settable destination is
# adjudicated against a LITERAL. Without this must-PASS row, making
# `_adjudicated` return False unconditionally left the suite fully green -- the
# pin limb had no fixture in the passing direction at all.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
