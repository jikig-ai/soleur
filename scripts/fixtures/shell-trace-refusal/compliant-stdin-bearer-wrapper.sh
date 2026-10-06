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

# Derived from compliant-ruled-pinned-destination.sh. Rule E and Rule D MUST BOTH PASS:
# the wrapper owns the transport flags and puts the bearer on curl's STDIN behind a
# charset guard, and every call site passes only a URL and plain flags.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

api_get() {
  case "$SENTRY_AUTH_TOKEN" in
    '' | *[!A-Za-z0-9._~+/=-]*)
      printf 'refusing an unusable token\n' >&2
      return 1
      ;;
  esac
  curl --disable --noproxy '*' -sS --max-time 20 --config - "$@" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
}
api_status() {
  api_get -o /dev/null -w '%{http_code}' "$@"
}

api_get "$SINK_URL"
body=$(api_get -sS "$SINK_URL")
code=$(api_status "$SINK_URL")
# A wrapper NAME used as an argument or inside printed text is not a call: only a
# command-position match is. Matching the name anywhere reads this line as a bearer
# on argv.
echo api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL" >/dev/null
printf '%s %s\n' "$body" "$code"
