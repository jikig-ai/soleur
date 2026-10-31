#!/usr/bin/env bash
# Playwright webServer wrapper: makes a mid-run dev-server exit observable in
# the CI job log (#9167). Playwright pipes webServer stderr but never reports
# the child's exit status — a mid-run death reads as bare
# net::ERR_CONNECTION_REFUSED (measured: merge-group run 37435711833).
set -uo pipefail

# --selftest: run the real spawn+wait+marker path against `true`, marker on
# stdout. The production path emits on stderr — Playwright's webServer pipes
# stderr by default while `stdout` defaults to `ignore` — but a stdout probe
# is what an unauthenticated local check can read.
marker_fd=2
if [[ "${1:-}" == "--selftest" ]]; then
  marker_fd=1
  set -- true
fi

if [[ $# -lt 1 ]]; then
  echo "usage: web-server.sh [--selftest] <command> [args...]" >&2
  exit 2
fi

start_ts=$(date +%s)
"$@" &
child=$!
wait "$child"
rc=$?
elapsed=$(( $(date +%s) - start_ts ))
# rc is 128+N on death-by-signal N (137=SIGKILL e.g. OOM, 143=SIGTERM).
echo "e2e-webserver: exited rc=${rc} port=${PORT:-?} distdir=${NEXT_DIST_DIR:-?} uptime=${elapsed}s" >&"$marker_fd"
exit "$rc"
