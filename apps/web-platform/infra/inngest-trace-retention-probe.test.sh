#!/usr/bin/env bash
# The probe's --self-test is the discoverability command. It must print the
# success marker from a temporary SQLite file and must ignore a Postgres URI.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/inngest-trace-retention-probe.sh"
passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1" >&2; }

[[ -x "$PROBE" ]] && pass || fail "probe is not executable"
bash -n "$PROBE" && pass || fail "probe bash -n"

if grep -E 'date -d|timeout|flock|stat -c' "$PROBE" >/dev/null 2>&1; then
  fail "probe names a forbidden command"
else
  pass
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT" "$OUT.err"' EXIT
env -i PATH="$PATH" \
  INNGEST_POSTGRES_URI="postgres://retention:secret@127.0.0.1:9/inngest" \
  bash "$PROBE" --self-test >"$OUT" 2>"$OUT.err"
rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "self-test exited $rc"
if grep -F "INNGEST_TRACE_RETENTION_OUTCOME=ok" "$OUT" >/dev/null 2>&1; then
  pass
else
  fail "self-test did not print the success marker"
fi
if grep -F "postgres://retention:secret@127.0.0.1:9/inngest" "$OUT" "$OUT.err" >/dev/null 2>&1; then
  fail "self-test printed the URI"
else
  pass
fi
if grep -F "SENTINEL_EVENT_PAYLOAD_9f3a" "$OUT" "$OUT.err" >/dev/null 2>&1; then
  fail "self-test printed a payload sentinel"
else
  pass
fi
rm -f "$OUT" "$OUT.err"

bash "$PROBE" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass || fail "missing --self-test did not exit 2"

printf 'inngest-trace-retention-probe.test.sh: %s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
