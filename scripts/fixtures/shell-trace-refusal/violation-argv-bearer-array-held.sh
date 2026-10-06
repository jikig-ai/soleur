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

# Derived from compliant-ruled-pinned-destination.sh: Rules A/B/C/D are clean, so
# only Rule E (#9597, bearer token on curl argv) can fire here.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
# Rule E MUST FIRE three times (three call sites, one per array spelling): the bearer is
# held in an array that the call site expands, so the curl line names no header. The
# third array is assigned after `&&`, which the call-site inliner cannot see.
_auth=(--disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}")
curl "${_auth[@]}" "$SINK_URL" || true

curl_args=(--disable --noproxy '*' -sS)
curl_args+=(-H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}")
curl "${curl_args[@]}" "$SINK_URL" || true

send_gated() {
  local -a _gate=()
  [ -n "${SENTRY_AUTH_TOKEN:-}" ] && _gate=(--disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}")
  curl "${_gate[@]}" "$SINK_URL" || true
}
