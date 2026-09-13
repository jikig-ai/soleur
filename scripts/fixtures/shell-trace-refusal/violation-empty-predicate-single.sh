#!/usr/bin/env bash
# The other test syntax and quote style: `[[ -n '' ]]`. Same defect, same verdict.
set -uo pipefail
case "$-" in
  *x*)
    if [[ -n '' ]]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
