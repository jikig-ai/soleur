#!/usr/bin/env bash
# The correct guard spelled with an OUTER negation: `! [ -z "${VAR:+x}" ]` refuses when
# the credential is SET. Not inverted; must be ACCEPTED (Guard 2 false-positive control).
set -uo pipefail
case "$-" in
  *x*)
    if ! [ -z "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
