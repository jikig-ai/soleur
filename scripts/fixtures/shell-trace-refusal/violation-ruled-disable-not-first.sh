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

# Rule D: BOTH flags present, but --disable is not first -- so curl has already
# parsed ~/.curlrc by the time it is read. A presence-only check passes this.
curl -sS --disable --noproxy '*' -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
