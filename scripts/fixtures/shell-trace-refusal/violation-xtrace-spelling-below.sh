#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing\n' >&2; exit 78 ;;
esac

set -o xtrace

curl --disable --noproxy '*' -sS --config - https://example.invalid/ < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
