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

# MUST PASS (Rules A-E clean): `-u` / `--user` that are NOT a curl basic-auth pair. Only curl
# invocation segments are scanned, so `sort -u`, `docker run --user`, `git -u` and `id -u` are not
# read; and on curl itself `--url` and `--user-agent` are different flags (case-sensitive,
# whole-word match), as is `-U` (the proxy credential, pinned in its own fixture).
readonly SINK_URL_PINNED="https://pinned.example/ingest"
SINK_URL="${FIXTURE_SINK_URL:-$SINK_URL_PINNED}"
if [ "$SINK_URL" != "https://pinned.example/ingest" ]; then
  printf 'refusing an unpinned destination\n' >&2
  exit 2
fi

printf 'b\na\nb\n' | sort -u
docker run --rm --user 1000:1000 busybox true || true
git push -u origin HEAD || true
id -u
curl --disable --noproxy '*' -sS --url "$SINK_URL" || true
curl --disable --noproxy '*' -sS --user-agent "fixture/1.0" "$SINK_URL" || true
curl --disable --noproxy '*' -sS -A "fixture/1.0" -L "$SINK_URL" || true
# `sort -u` is an earlier stage of a pipeline whose LAST stage is the curl: the arm judges the curl's own
# invocation segment, never the whole pipeline assembly.
printf 'b\na\nb\n' | sort -u | curl --disable --noproxy '*' -sS -X POST --data-binary @- "$SINK_URL" || true
