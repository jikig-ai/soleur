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

# MUST PASS (Rules A-E clean): the Rule D flags are first at RUNTIME, declared with a plain
# `local curl_args=(` (no `-a`). A declaration regex that only knows `local -a` loses the
# declaration and reports a FALSE Rule D finding here (--disable no longer first). The token
# travels on stdin.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

send() {
  local data="${1:-}"
  local curl_args=(
    --disable --noproxy '*' -sS --config -
  )
  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi
  curl "${curl_args[@]}" "$SINK_URL" < <(printf 'header = "Authorization: Bot %s"\n' "$SENTRY_AUTH_TOKEN") || true
}
send
