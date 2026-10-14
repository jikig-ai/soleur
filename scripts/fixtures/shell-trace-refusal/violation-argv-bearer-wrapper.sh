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
# only Rule E (#9597, bearer token on curl argv) can fire here -- and ONLY through
# wrapper awareness: no line below carries a literal `curl ... -H` bearer.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

# Rule E MUST FIRE exactly SIX times, once per call site below. Every call site sits
# ABOVE the definition of the wrapper it calls (legal: run_probe is invoked at the
# bottom), so a lint that only knows wrappers defined before their use reads 0.
run_probe() {
  # 1: a direct call of a wrapper defined later in the file.
  api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL"
  # 2: a TRANSITIVE wrapper (api_status calls api_get, which calls curl).
  api_status -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL"
  # 3: a call after `||`; the call BEFORE it carries no bearer and is clean.
  api_get -sS -o /dev/null "$SINK_URL" || api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL"
  # 4: a call inside $(...).
  out=$(api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL")
  # 5: a call negated by `!` and chained after `&&`.
  true && ! api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL"
  # 6: a call inside a backtick substitution.
  out2=`api_get -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "$SINK_URL"`
  printf '%s%s\n' "$out" "$out2"
}

api_get() { curl --disable --noproxy '*' -sS --max-time 20 "$@" || true; }
api_status() {
  api_get -o /dev/null -w '%{http_code}' "$@"
}

run_probe
