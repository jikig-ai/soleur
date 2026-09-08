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

# Rule D, destination limb: the variable is named SINK -- not *URL, *URI,
# *ENDPOINT or *HOST. The first cut of this limb gated on the NAME, so this call
# site scored FULLY COMPLIANT: transport-confined, credentialed, and pointed
# wherever $SINK says. A name is a claim about what an author called something;
# it is never a property of the code. `\b` after HOST also rejected
# $INGEST_HOSTNAME, so even the naming convention did not save it.
SINK="${FIXTURE_SINK:-https://example.invalid/}"

curl --disable --noproxy '*' --silent \
  --header "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "$SINK" || true
