#!/usr/bin/env bash
# Follow-through for #5150. Closes the issue only after a Better Stack row whose
# decoded _SYSTEMD_UNIT is inngest-trace-retention.service and whose message is
# exactly INNGEST_TRACE_RETENTION_OUTCOME=ok. A row that only quotes those tokens
# does not qualify. The old image cannot emit that pair.
#
# Exit semantics (sweep-followthroughs.sh):
#   0 = PASS       one qualifying row
#   2 = TRANSIENT  creds unset, query fault, or no qualifying row yet
#   78 = refused under xtrace (#7797)
#
# Required env: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME,
#   BETTERSTACK_QUERY_PASSWORD.
# Test seam: INNGEST_TRACE_RETENTION_5150_FIXTURE is a file of synthetic
#   JSONEachRow lines. When it is set, this script reads that file and does
#   not call betterstack-query.sh. INNGEST_TRACE_RETENTION_5150_QUERY overrides
#   the query binary for the live path's failure arm.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.
#
# ENROLLMENT is posted at ship, not by this script:
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-trace-retention-5150.sh earliest=<replace+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# RETIREMENT: when #5150 closes, delete this file and its .test.sh, drop the
# run_suite line in scripts/test-all.sh, and remove the directive.

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
set -uo pipefail
export LC_ALL=C

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  printf 'TRANSIENT: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not all set\n' >&2
  exit 2
fi

WINDOW="${INNGEST_TRACE_RETENTION_5150_WINDOW:-14d}"
if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  printf 'TRANSIENT: invalid window\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${INNGEST_TRACE_RETENTION_5150_FIXTURE:-}"

if [[ -n "$FIXTURE" ]]; then
  if [[ ! -r "$FIXTURE" ]]; then
    printf 'TRANSIENT: fixture is not readable\n' >&2
    exit 2
  fi
  rows="$(cat "$FIXTURE")" || {
    printf 'TRANSIENT: fixture read failed\n' >&2
    exit 2
  }
else
  BQ="${INNGEST_TRACE_RETENTION_5150_QUERY:-$SCRIPT_DIR/../betterstack-query.sh}"
  if [[ ! -x "$BQ" ]]; then
    printf 'TRANSIENT: betterstack query is not executable\n' >&2
    exit 2
  fi
  rows="$("$BQ" --since "$WINDOW" --grep 'INNGEST_TRACE_RETENTION_OUTCOME=ok' --limit 200 2>/dev/null)" || {
    printf 'TRANSIENT: Better Stack query failed\n' >&2
    exit 2
  }
fi

count="$(printf '%s\n' "$rows" | python3 -c "$(cat <<'PY'
import json
import sys
n = 0
unit = "inngest-trace-retention.service"
outcome = "INNGEST_TRACE_RETENTION_OUTCOME=ok"
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(obj, dict):
        continue
    raw = obj.get("raw")
    if isinstance(raw, str):
        try:
            inner = json.loads(raw)
        except json.JSONDecodeError:
            inner = None
        if isinstance(inner, dict):
            obj = inner
    message = obj.get("message")
    if isinstance(message, str):
        message = message.strip()
    if message != outcome:
        continue
    if obj.get("_SYSTEMD_UNIT") != unit:
        continue
    n += 1
print(n)
PY
)")" || {
  printf 'TRANSIENT: row scan failed\n' >&2
  exit 2
}

if ! [[ "$count" =~ ^[0-9]+$ ]]; then
  printf 'TRANSIENT: row scan returned a non-count\n' >&2
  exit 2
fi

if (( count > 0 )); then
  printf 'PASS: %s qualifying inngest-trace-retention.service row(s) carry INNGEST_TRACE_RETENTION_OUTCOME=ok\n' "$count"
  exit 0
fi

printf 'TRANSIENT: no qualifying retention row yet\n' >&2
exit 2
