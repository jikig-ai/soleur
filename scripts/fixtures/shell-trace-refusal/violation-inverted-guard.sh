#!/usr/bin/env bash
# The guard INVERTED: `-z` refuses only while the credential is EMPTY and traces once it is set.
# Must be REPORTED (#7946 Guard 2).
set -uo pipefail
case "$-" in
  *x*)
    if [ -z "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
