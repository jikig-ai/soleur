#!/usr/bin/env bash
# The alternate is EMPTY: `${VAR:+}` expands to "" whether or not VAR is set, so the refusal never fires.
# Must be REPORTED (#7946 Guard 2).
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+}" ]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
