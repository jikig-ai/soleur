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

# Rule D MUST PASS: the bearer reaches curl ONLY on stdin via `--config -`, fed by
# a process substitution OUTSIDE any $(...). The token inside <(...) is data on
# curl's stdin, never a curl operand, so it is not a destination. Reading it as
# one failed the destination-pin limb with "sends to $SENTRY_AUTH_TOKEN".
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
curl --disable --noproxy '*' -sS --max-time 20 --config - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
