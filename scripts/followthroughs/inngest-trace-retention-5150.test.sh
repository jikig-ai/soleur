#!/usr/bin/env bash
# Verdict matrix for inngest-trace-retention-5150.sh. Every row is synthetic.
# The fixture file is the only reader, so this suite opens no network.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/inngest-trace-retention-5150.sh"
passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1" >&2; }

[[ -f "$PROBE" ]] || { printf 'FATAL: probe missing\n' >&2; exit 1; }
bash -n "$PROBE" && pass || fail "probe bash -n"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OK_ROW='{"message":"INNGEST_TRACE_RETENTION_OUTCOME=ok","_SYSTEMD_UNIT":"inngest-trace-retention.service"}'
WRAPPED_OK='{"dt":"2026-10-27 00:00:00","raw":"{\"message\":\"INNGEST_TRACE_RETENTION_OUTCOME=ok\",\"_SYSTEMD_UNIT\":\"inngest-trace-retention.service\"}"}'
DOPPLER_QUOTE='{"message":"runbook quotes INNGEST_TRACE_RETENTION_OUTCOME=ok from inngest-trace-retention.service","_SYSTEMD_UNIT":"doppler.service","SYSLOG_IDENTIFIER":"doppler"}'
OTHER_UNIT='{"message":"INNGEST_TRACE_RETENTION_OUTCOME=ok","_SYSTEMD_UNIT":"inngest-server.service"}'
ECHO_ROW='{"message":"INNGEST_TRACE_RETENTION_OUTCOME=ok inngest-trace-retention.service","caller":"api"}'
ERROR_ROW='{"message":"INNGEST_TRACE_RETENTION_OUTCOME=error reason=seq_scan","_SYSTEMD_UNIT":"inngest-trace-retention.service"}'
ESCAPED_ECHO='{"raw":"INNGEST_TRACE_RETENTION_OUTCOME=ok inngest-trace-retention.service \"caller\":\"api\""}'

write_fix() {
  printf '%s\n' "$1" > "$WORK/rows.jsonl"
}

run_probe() {
  env -i PATH="$PATH" HOME="$WORK" \
    BETTERSTACK_QUERY_HOST=h \
    BETTERSTACK_QUERY_USERNAME=u \
    BETTERSTACK_QUERY_PASSWORD=p \
    INNGEST_TRACE_RETENTION_5150_FIXTURE="$WORK/rows.jsonl" \
    bash "$PROBE" >/dev/null 2>&1
}

write_fix "$OK_ROW"
run_probe
[[ $? -eq 0 ]] && pass || fail "qualifying row did not exit 0"

write_fix "$WRAPPED_OK"
run_probe
[[ $? -eq 0 ]] && pass || fail "wrapped qualifying row did not exit 0"

write_fix "$DOPPLER_QUOTE"
run_probe
[[ $? -eq 2 ]] && pass || fail "doppler quote did not exit 2"

write_fix ""
run_probe
[[ $? -eq 2 ]] && pass || fail "empty fixture did not exit 2"

write_fix "$OTHER_UNIT"
run_probe
[[ $? -eq 2 ]] && pass || fail "other unit did not exit 2"

write_fix "$ECHO_ROW"
run_probe
[[ $? -eq 2 ]] && pass || fail "webhook echo did not exit 2"

write_fix "$ESCAPED_ECHO"
run_probe
[[ $? -eq 2 ]] && pass || fail "escaped webhook echo did not exit 2"

write_fix "$ERROR_ROW"
run_probe
[[ $? -eq 2 ]] && pass || fail "error outcome did not exit 2"

write_fix "$ECHO_ROW"$'\n'"$OK_ROW"
run_probe
[[ $? -eq 0 ]] && pass || fail "qualifying row beside an echo did not exit 0"

env -i PATH="$PATH" HOME="$WORK" \
  INNGEST_TRACE_RETENTION_5150_FIXTURE="$WORK/rows.jsonl" \
  bash "$PROBE" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass || fail "missing creds did not exit 2"

env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  INNGEST_TRACE_RETENTION_5150_WINDOW=soon \
  INNGEST_TRACE_RETENTION_5150_FIXTURE="$WORK/rows.jsonl" \
  bash "$PROBE" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass || fail "bad window did not exit 2"

env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  INNGEST_TRACE_RETENTION_5150_FIXTURE="$WORK/missing.jsonl" \
  bash "$PROBE" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass || fail "missing fixture did not exit 2"

cat > "$WORK/q.sh" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
chmod +x "$WORK/q.sh"
env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  INNGEST_TRACE_RETENTION_5150_QUERY="$WORK/q.sh" \
  bash "$PROBE" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass || fail "query failure did not exit 2"

env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u \
  BETTERSTACK_QUERY_PASSWORD=sentinel-password-9f3a \
  bash -x "$PROBE" >"$WORK/xtrace.out" 2>&1
[[ $? -eq 78 ]] && pass || fail "xtrace did not exit 78"
if grep -F "sentinel-password-9f3a" "$WORK/xtrace.out" >/dev/null 2>&1; then
  fail "xtrace printed the credential"
else
  pass
fi

_pre="$passes"
pass
[[ "$passes" -eq $((_pre + 1)) ]] || fail "counter self-test: pass() did not increment"
_fpre="$fails"
fails=$((fails + 1))
if [[ "$fails" -eq $((_fpre + 1)) ]]; then
  fails=$((fails - 1))
  pass
else
  fails=$((fails - 1))
  fail "counter self-test: fails did not increment"
fi

MIN_ASSERTIONS=14
if [[ "$passes" -ge "$MIN_ASSERTIONS" ]]; then
  pass
else
  printf 'FLOOR: %s assertions < floor %s\n' "$passes" "$MIN_ASSERTIONS" >&2
  fails=$((fails + 1))
fi

printf 'inngest-trace-retention-5150.test.sh: %s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
