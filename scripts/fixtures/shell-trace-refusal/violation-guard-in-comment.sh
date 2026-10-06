#!/usr/bin/env bash
# A two-credential file whose second `${VAR:+x}` limb survives only in a COMMENT inside the
# arm. A window that keeps comment lines counts it as a guard and the file passes with one
# credential unguarded. Must be REPORTED (Rule C: unguarded BETTERSTACK_API_TOKEN).
set -uo pipefail
case "$-" in
  *x*)
    # was: if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}${BETTERSTACK_API_TOKEN:+x}" ]; then
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a credential set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS --config - https://example.invalid/ < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_ACTIONS_RO_TOKEN") || true
curl --disable --noproxy '*' -sS --config - https://example.invalid/ < <(printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_API_TOKEN") || true
