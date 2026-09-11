#!/usr/bin/env bash
# The bare spelling of the empty predicate: `[ "" ]` (implicit -n) can never be true.
# Must be REPORTED (#7946 Guard 2).
set -uo pipefail
case "$-" in
  *x*)
    # shellcheck disable=SC2078  # the constant expression IS the defect under test
    if [ "" ]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
