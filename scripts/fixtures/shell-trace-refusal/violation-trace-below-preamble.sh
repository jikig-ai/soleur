#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing\n' >&2; exit 78 ;;
esac

set -x

curl -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
