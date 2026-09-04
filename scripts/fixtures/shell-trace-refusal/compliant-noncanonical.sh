#!/usr/bin/env bash
set -euo pipefail

# Refuses tracing while a credential is live. Wording deliberately unlike the
# canonical fixture, to prove the lint matches shape rather than a fixed string.
case $- in
  *x*)
    [ -z "${BETTERSTACK_API_TOKEN_READONLY:+x}" ] || {
      echo "will not trace with a live token in scope" >&2
      exit 78
    }
    ;;
esac

readonly ENDPOINT="https://example.invalid/"
printf 'header = "Authorization: Bearer %s"\n' "${BETTERSTACK_API_TOKEN_READONLY}" \
  | curl -sS --config - "$ENDPOINT" || true
