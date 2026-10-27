#!/usr/bin/env bash
# Discoverability probe for the 7-day status-gated trace retention job (#5150).
# --self-test builds a temporary SQLite file, runs the retention runner against
# that file only, and prints the runner's outcome line. It does not open a
# network connection and it does not read a Postgres URI.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
set -euo pipefail

if [[ "${1-}" != "--self-test" ]]; then
  printf 'usage: inngest-trace-retention-probe.sh --self-test\n' >&2
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/inngest-trace-retention.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/inngest-trace-retention-probe.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT

python3 - "$WORK/main.db" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
conn = sqlite3.connect(path)
conn.executescript(
    """
    CREATE TABLE trace_runs (
      run_id TEXT PRIMARY KEY,
      ended_at INTEGER,
      status INTEGER
    );
    CREATE TABLE spans (
      span_id TEXT,
      trace_id TEXT,
      run_id TEXT
    );
    CREATE TABLE traces (
      trace_id TEXT,
      span_id TEXT,
      run_id TEXT
    );
    CREATE TABLE event_batches (
      id TEXT PRIMARY KEY,
      run_id TEXT
    );
    CREATE TABLE function_finishes (
      run_id BLOB,
      status TEXT,
      created_at TEXT
    );
    CREATE TABLE function_runs (
      run_id BLOB,
      event_id BLOB
    );
    CREATE TABLE history (
      run_id BLOB,
      event_id BLOB
    );
    CREATE TABLE events (
      internal_id BLOB,
      received_at TEXT,
      event_data TEXT
    );
    """
)
conn.execute(
    "INSERT INTO trace_runs (run_id, ended_at, status) VALUES ('probe-old', 0, 300)"
)
conn.commit()
conn.close()
PY

# The child must not see a live store pointer. env -u drops the URI for this
# process only. The marker and the SQLite file both live in the temp directory.
env -u INNGEST_POSTGRES_URI \
  INNGEST_TRACE_RETENTION_SQLITE="$WORK/main.db" \
  INNGEST_TRACE_RETENTION_MARKER="$WORK/marker" \
  bash "$RUNNER"
