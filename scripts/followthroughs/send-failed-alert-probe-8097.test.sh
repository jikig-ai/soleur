#!/usr/bin/env bash
# Exit-code harness for send-failed-alert-probe-8097.sh (#8097 readback follow-through).
#
# The follow-through's exit code IS its authorization artifact: sweep-followthroughs.sh closes
# #8097 on 0, comments ACTION REQUIRED on 5, CANNOT ESTABLISH on 3, and would treat a 1 as FAIL
# (reopening a human-closed issue) — so the script must never exit 1. The cardinal sins are a
# vacuous 0 that closes #8097 before the synthetic row AND its incident were both observed, and
# a 5 that names a cause the run never measured. Every case pins one arm, in the ORDER the
# script evaluates them (alert → control → row → incident), so each verdict names ONE cause.
#
# The SUT runs under `env -i` exactly as the sweeper runs it, with a PATH-shimmed `curl` that
# dispatches on the URL (alerts vs incidents), records argv to calls.log, and can fail with a
# chosen rc; and a SEND_FAILED_PROBE_BQ mock that dispatches on the SQL's shape (control count /
# nonsynthetic count / readback). Fixtures are synthesized (cq-test-fixtures-synthesized-only)
# and reproduce betterstack-query.sh's JSONEachRow output shape.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/send-failed-alert-probe-8097.sh"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

WORK="$(mktemp -d -t sfa-ft.XXXXXXXX)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/bin"
MOCK="$WORK/mock-bq.sh"
TF="$WORK/betterstack-logs-alerts.tf"
CALLS="$WORK/calls.log"

ALERT_NAME="soleur-monitor-send-failed-prd"
CAUSE="SOLEUR_*_SEND_FAILED / _REFUSED row from a web-1 monitor unit — the monitor's own Resend/Sentry send failed. Runbook: https://example.invalid/runbook"

# A minimal .tf carrying the rev the script greps (the real file's shape).
printf 'locals {\n  monitor_send_failed_probe_rev = "1"\n}\n' > "$TF"

# ── curl stub: dispatches on URL, honours -o and -w, records argv, fails on demand ──────────
# Config is read from files next to the stub because the SUT runs under `env -i`.
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf '%s\n' "$*" >> "$cfg/calls.log"
out=""; url=""; want_code=0
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; i=$((i+1)) ;;
    -w) want_code=1; i=$((i+1)) ;;
    https://*) url="${args[$i]}" ;;
  esac
done
rc_file="$cfg/curl.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && exit "$rc"; }
case "$url" in
  https://telemetry.betterstack.com/api/v2/alerts*) body="$cfg/alerts.json"; code="$(cat "$cfg/alerts.code" 2>/dev/null || echo 200)" ;;
  https://uptime.betterstack.com/api/v2/incidents*) body="$cfg/incidents.json"; code=200 ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; exit 99 ;;
esac
[[ -n "$out" ]] && cp "$body" "$out"
[[ "$want_code" == 1 ]] && printf '%s' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"

# ── BQ mock: dispatches on the SQL shape ────────────────────────────────────────────────
# order matters: the nonsynthetic count also contains count(); check the narrower shapes first.
cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
set -uo pipefail
cfg="$WORK"
sql="\${1:-}"
printf 'BQ %s\n' "\${sql//\$'\n'/ }" >> "\$cfg/calls.log"
[[ -f "\$cfg/bq.rc" ]] && { rc="\$(<"\$cfg/bq.rc")"; [[ "\$rc" != "0" ]] && { echo "Code: 241. DB::Exception: synthetic" ; exit "\$rc"; }; }
case "\$sql" in
  *"NOT LIKE '%synthetic=1%'"*) cat "\$cfg/nonsynthetic.json" ;;
  *"synthetic=1 probe_rev="*)   cat "\$cfg/readback.json" ;;
  *"count()"*)                  cat "\$cfg/control.json" ;;
  *) echo "mock: unrecognised SQL" >&2; exit 64 ;;
esac
exit 0
MOCKEOF
chmod 0755 "$MOCK"

alert_json() { # <paused> <paused_reason-or-null>
  printf '{"data":[{"id":"1","type":"alert","attributes":{"name":"Output utilization high","paused":true,"paused_reason":"Manually paused"}},{"id":"2","type":"alert","attributes":{"name":"%s","paused":%s,"paused_reason":%s}}],"pagination":{"next":null}}' "$ALERT_NAME" "$1" "$2"
}
incidents_json() { # <n-matching-by-cause> <started_at>
  if [[ "$1" == "0" ]]; then
    printf '{"data":[{"id":"9","type":"incident","attributes":{"name":"soleur apex","cause":"HTTP 503","started_at":"2026-09-13T10:00:00.000Z","resolved_at":null,"acknowledged_by":"SECRETISH_PERSON","screenshot_url":"https://x/SECRETISH_SHOT"}}],"pagination":{"next":null}}'
  else
    printf '{"data":[{"id":"9","type":"incident","attributes":{"name":"soleur apex","cause":"HTTP 503","started_at":"2026-09-13T10:00:00.000Z","resolved_at":null}},{"id":"42","type":"incident","attributes":{"name":"%s","cause":"%s","started_at":"%s","resolved_at":null,"acknowledged_by":"SECRETISH_PERSON","screenshot_url":"https://x/SECRETISH_SHOT"}}],"pagination":{"next":null}}' "$ALERT_NAME" "$CAUSE" "$2"
  fi
}
row_json() { # <host> <dt>
  printf '{"dt":"%s","host":"%s","msg":"SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=1"}\n' "$2" "$1"
}

set_fixtures() { # <alert-paused> <control-n> <readback-rows-file-content> <incidents-match> <nonsynthetic-n>
  alert_json "$1" "$( [[ "$1" == true ]] && printf '"complexity issues, too many failures"' || printf 'null')" > "$WORK/alerts.json"
  printf '{"n":"%s","min_dt":"2026-09-01 00:00:00","max_dt":"2026-09-13 14:00:00"}\n' "$2" > "$WORK/control.json"
  printf '%s' "$3" > "$WORK/readback.json"
  incidents_json "$4" "2026-09-13T14:30:10.000Z" > "$WORK/incidents.json"
  printf '{"n":"%s"}\n' "$5" > "$WORK/nonsynthetic.json"
  : > "$CALLS"; rm -f "$WORK/curl.rc" "$WORK/bq.rc" "$WORK/alerts.code"
}

# run_case <desc> <expected-rc> [extra env assignments...]
run_case() {
  local desc="$1" expected="$2"; shift 2
  local rc=0 out
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
      BETTERSTACK_QUERY_HOST=dummy-host BETTERSTACK_QUERY_USERNAME=dummy-user BETTERSTACK_QUERY_PASSWORD=dummy-pass \
      BETTERSTACK_API_TOKEN=dummy-token SEND_FAILED_PROBE_BQ="$MOCK" SEND_FAILED_PROBE_TF="$TF" "$@" "$SUT" 2>&1)" || rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc (exit=$rc)"
  else fail "$desc -- expected exit=$expected got exit=$rc :: ${out:0:400}"; fi
}
expect_out() { # <desc> <grep-pattern>
  if printf '%s' "$LAST_OUT" | grep -qE -- "$2"; then pass "$1"; else fail "$1 :: ${LAST_OUT:0:400}"; fi
}
expect_not_out() {
  if printf '%s' "$LAST_OUT" | grep -qE -- "$2"; then fail "$1 :: ${LAST_OUT:0:400}"; else pass "$1"; fi
}

# 1. PASS — alert live+unpaused, web-1 control present, synthetic row from web-1, matching incident.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
run_case "row + web-1 control + matching incident -> PASS" 0
expect_out "PASS prints the verdict line" '^SOLEUR_SEND_FAILED_ALERT_PROBE verdict=pass detail='
expect_out "PASS detail carries row_found/host/control/nonsynthetic/incident_id" 'row_found=1 host=soleur-web-platform .*control_rows_web1=731 .*nonsynthetic_rows=0 incident_id=42'
expect_out "PASS names which incident field matched" 'incident_match=(name|cause)'
expect_not_out "PASS never reprints raw incident fields (public comment)" 'SECRETISH_'
grep -q '^BQ ' "$CALLS" || fail "PASS queried the warehouse"

# 2. alert_paused → 5, and the warehouse is NEVER queried (proves the ordering).
set_fixtures true 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
run_case "alert paused live -> ACTION REQUIRED (5)" 5
expect_out "alert_paused verdict names the projected paused_reason" 'verdict=alert_paused .*paused_reason=complexity issues, too many failures'
if grep -q '^BQ ' "$CALLS"; then fail "alert_paused still queried the warehouse (ordering broken)"; else pass "alert_paused: warehouse never queried"; fi
if grep -q 'api/v2/incidents' "$CALLS"; then fail "alert_paused still read incidents"; else pass "alert_paused: incidents never read"; fi

# 3. alert_absent → 5.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
printf '{"data":[{"id":"1","type":"alert","attributes":{"name":"Output utilization high","paused":true,"paused_reason":"Manually paused"}}],"pagination":{"next":null}}' > "$WORK/alerts.json"
run_case "alert missing from the live list -> ACTION REQUIRED (5)" 5
expect_out "alert_absent verdict" 'verdict=alert_absent'

# 4. channel_dark → 3 (web-1-scoped control is zero even though inngest rows would exist).
set_fixtures false 0 "" 1 0
run_case "zero web-1 control rows -> CANNOT ESTABLISH (3), never row_absent" 3
expect_out "channel_dark verdict is host-scoped" 'verdict=channel_dark .*host=soleur-web-platform'
expect_not_out "channel_dark is not reported as row_absent" 'row_absent'

# 5. row_absent → 5 with the enumerated candidate causes.
set_fixtures false 731 "" 1 0
run_case "web-1 control present but no synthetic row -> ACTION REQUIRED (5)" 5
expect_out "row_absent verdict" 'verdict=row_absent'
expect_out "row_absent names the ssh_token_gate green-skip cause" 'ssh_token_gate'
expect_out "row_absent names the main-apply-failed cause" 'main apply'
expect_out "row_absent names the journald/Vector match-fault cause" 'journald'

# 6. row_present_no_incident → 5 (the verdict the feature exists to produce).
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 0 0
run_case "row present, no matching incident -> ACTION REQUIRED (5)" 5
expect_out "row_present_no_incident verdict" 'verdict=row_present_no_incident'
expect_out "prints the PROJECTED incident list" '"id":"9"'
expect_not_out "projection withholds acknowledged_by/screenshot fields" 'SECRETISH_'

# 7. incident exists but started BEFORE the row's dt - 600s → not a match.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
incidents_json 1 "2026-09-13T13:00:00.000Z" > "$WORK/incidents.json"
run_case "matching incident too old for the row's dt anchor -> row_present_no_incident (5)" 5
expect_out "stale incident is not credited" 'verdict=row_present_no_incident'

# 8. host mismatch is REPORTED, not failed on.
set_fixtures false 731 "$(row_json soleur-inngest '2026-09-13 14:25:50.123')" 1 0
run_case "row from a foreign host -> still PASS, host_mismatch reported" 0
expect_out "host mismatch attribute printed" 'host_mismatch=1'

# 9. nonsynthetic rows are surfaced.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 3
run_case "real firings in the window are counted" 0
expect_out "nonsynthetic_rows carried" 'nonsynthetic_rows=3'

# 10. curl rc≠0 on the alerts GET → TRANSIENT, exit 3 (never 5, never 1).
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
printf '7' > "$WORK/curl.rc"
run_case "curl rc=7 on the alerts GET -> CANNOT ESTABLISH (3)" 3
expect_out "TRANSIENT prefix on the alerts-GET failure" 'TRANSIENT:'

# 11. non-2xx on the alerts GET → 3.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
printf '502' > "$WORK/alerts.code"
run_case "HTTP 502 on the alerts GET -> CANNOT ESTABLISH (3)" 3

# 12. warehouse read fails (rc≠0 / non-answer) → 3, never a verdict.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
printf '22' > "$WORK/bq.rc"
run_case "betterstack-query.sh transport failure -> CANNOT ESTABLISH (3)" 3
expect_not_out "a failed read is never row_absent" 'row_absent'

# 13. secrets unset → 3, never 1.
set_fixtures false 731 "$(row_json soleur-web-platform '2026-09-13 14:25:50.123')" 1 0
rc=0; out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" SEND_FAILED_PROBE_BQ="$MOCK" SEND_FAILED_PROBE_TF="$TF" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 3 ]]; then pass "no secrets -> CANNOT ESTABLISH (exit=3, never 1)"; else fail "no secrets -- expected 3 got $rc :: ${out:0:200}"; fi

# 14. probe_rev not greppable from the checkout → 3.
printf 'locals {\n  monitor_send_failed_probe_rev = "1a"\n}\n' > "$WORK/bad.tf"
run_case "non-digit probe_rev in the checkout -> CANNOT ESTABLISH (3)" 3 SEND_FAILED_PROBE_TF="$WORK/bad.tf"

# 15. xtrace refusal (#7797).
rc=0; out="$(env BETTERSTACK_API_TOKEN=x bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "refuses to run under xtrace with a credential bound (exit=78)"
else fail "xtrace refusal -- expected 78 got $rc"; fi

# 16. never exit 1: a shell error inside the script must not surface as FAIL. Missing BQ → 3.
run_case "missing BQ path -> CANNOT ESTABLISH (3), not 1" 3 SEND_FAILED_PROBE_BQ="$WORK/nope.sh"

MIN_CASES=30
if [[ "$total" -lt "$MIN_CASES" ]]; then printf 'FATAL: only %s assertions ran (floor %s)\n' "$total" "$MIN_CASES" >&2; exit 1; fi
if [[ "$fails" -gt 0 ]]; then echo "FAILED: $fails of $total case(s)" >&2; exit 1; fi
echo "OK: all $total send-failed-alert-probe-8097 arms passed"
