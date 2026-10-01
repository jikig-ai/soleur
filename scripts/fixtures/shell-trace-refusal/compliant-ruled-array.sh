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

# Rule D MUST PASS: the flags are first at RUNTIME even though the curl line
# names none of them. Appending the array body instead of substituting it at
# position made this a false positive (measured on zot-inventory.sh), which is
# how a guard teaches its reader to baseline files that are already correct.
args=(
  --disable --noproxy '*'
  -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}"
)
curl "${args[@]}" https://example.invalid/ || true
