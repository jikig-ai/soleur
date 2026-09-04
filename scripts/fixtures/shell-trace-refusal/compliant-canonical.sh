#!/usr/bin/env bash
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). `$-` is the load-bearing arm: bash applies
# an env-supplied SHELLOPTS/BASH_ENV before line 1, so `x` is already set here.
case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with SENTRY_AUTH_TOKEN set (#7797). Re-run with SENTRY_AUTH_TOKEN= to trace safely.\n' >&2
      exit 78
    fi
    ;;
esac

curl -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
