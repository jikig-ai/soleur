#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}${SUPABASE_ANON_KEY:+x}" ]; then
      printf "[FATAL] refusing to trace with a live credential set (#7797)\n" >&2
      exit 78
    fi
    ;;
esac

# Rule E must fire ONCE with BOTH reasons, through wrapper awareness: the `-u` pair AND an `apikey:` header are
# arguments of a CALL to a file-local function that runs curl, and NOTHING here is a bearer-class credential
# header (the wrapper's own curl line carries none, the call carries none). So the second-credential reason
# at the wrapper-site check fires only because `user_argv` is part of its condition.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# Compliant FIRST member (the credential pair rides curl's stdin config): a check that stops at the
# first curl, or that is satisfied by one compliant call, reads this file clean.
curl --disable --noproxy '*' -sS --config - "$SINK_URL" < <(printf 'user = "svc:%s"\n' "$SENTRY_AUTH_TOKEN") || true

run_probe() {
  api_get -u "svc:${SENTRY_AUTH_TOKEN}" -H "apikey: ${SUPABASE_ANON_KEY}" "$SINK_URL"
}

api_get() { curl --disable --noproxy '*' -sS --max-time 20 "$@" || true; }

run_probe
