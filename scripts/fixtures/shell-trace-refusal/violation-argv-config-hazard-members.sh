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

# Derived from violation-argv-bearer-config-hazards.sh: Rules A/B/C/D are clean, so only Rule E
# (#9597, credential header on curl argv) can fire here. It must fire ONCE PER SITE, 21 times in
# all: every call is a `--config -` form (the credential is on stdin, safe) carrying EXACTLY ONE
# stdin-hazard spelling, one site per MEMBER of the hazard vocabulary. The suite deletes the
# members one at a time (the alternation members of E_STDIN_BODY and E_VERBOSE, and each inline
# spelling in _e_scan) and expects a mutant to print exactly 20 messages. Keep ONE hazard per
# call and ONE call per line: a second hazard on a line would hide a deleted member.
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi
# E_STDIN_BODY members (a body read from stdin)
curl --disable --noproxy '*' -sS --config - -d @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data-binary @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data-raw @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data-ascii @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data-urlencode @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --json @- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - -F f=@- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --form f=@- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --form-string f=@- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# inline stdin-body spellings of _e_scan (-d@-, --data*=@-, -T -, --upload-file -, -T-)
curl --disable --noproxy '*' -sS --config - -d@- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --data-binary=@- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - -T - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --upload-file - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - -T- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# E_VERBOSE members (-v/--verbose/--trace* print the config's headers)
curl --disable --noproxy '*' -sS --config - --verbose "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --trace /dev/stderr "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - -v "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
# inline header-dump spellings of _e_scan (-D -, --dump-header -, -D-)
curl --disable --noproxy '*' -sS --config - -D - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - --dump-header - "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
curl --disable --noproxy '*' -sS --config - -D- "$SINK_URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
