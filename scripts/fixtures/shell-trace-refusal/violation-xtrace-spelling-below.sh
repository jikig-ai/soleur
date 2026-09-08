#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing\n' >&2; exit 78 ;;
esac

set -o xtrace

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
