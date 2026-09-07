#!/usr/bin/env bash
set -euo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf "[FATAL] refusing to trace with SENTRY_AUTH_TOKEN set (#7797)\n" >&2
      exit 78
    fi
    ;;
esac

# Rule D, env-settable limb: the destination is assigned from another variable
# with NO default. All three original spellings contained `:-` or `:=`, so
# dropping the default was a ONE-TOKEN evasion -- `INGEST_URL="${FIXTURE_URL:-x}"`
# was caught and `INGEST_URL="$FIXTURE_URL"` was not, for the identical
# destination and the identical credential.
INGEST_URL="$FIXTURE_INGEST_URL"

curl --disable --noproxy '*' --silent \
  -u "svc:${SENTRY_AUTH_TOKEN}" \
  "$INGEST_URL" || true
