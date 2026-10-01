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

# Rule D: transport-confined, but the "pin" is a `case` whose only arm is bare
# `*`, which matches every destination. A pin that adjudicates nothing must not
# count -- and an earlier _pin_re accepted exactly this.
SINK_URL="${FIXTURE_SINK_URL:-https://example.invalid/}"
case "$SINK_URL" in
  *) : ;;
esac
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL" || true
