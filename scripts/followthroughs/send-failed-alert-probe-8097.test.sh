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
# dispatches on the URL (alerts vs incidents, per page), records argv to calls.log, and can fail
# with a chosen rc; and a SEND_FAILED_PROBE_BQ mock that dispatches on the SQL's shape and
# RECORDS the SQL — the mock cannot see SQL content, so the load-bearing predicates (the web-1
# host scope on the control, PRIORITY 2 + the marker on the readback) are asserted from
# calls.log, not inferred from the verdict. Fixtures are synthesized
# (cq-test-fixtures-synthesized-only) and reproduce betterstack-query.sh's JSONEachRow shape.

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
CAUSE_PREFIX="SOLEUR_*_SEND_FAILED / _REFUSED row from a web-1 monitor unit"
CAUSE="${CAUSE_PREFIX} — the monitor's own Resend/Sentry send failed. Runbook: https://example.invalid/runbook"
# The control's newest row must be RECENT (the SUT's freshness gate is 2 h); a fixed date would
# trip it the day after authoring.
FRESH_MAX="$(date -u -d '-10 minutes' '+%F %T')"

# A minimal .tf carrying the three things the SUT reads (the real file's shape), plus a decoy
# comment line above the rev that a raw first-match grep would pick up.
write_tf() { # <rev> [name] [cause]
  cat > "$TF" <<EOF
locals {
  # was: monitor_send_failed_probe_rev = "9"
  monitor_send_failed_probe_rev = "$1"
}
resource "logtail_exploration_alert" "monitor_send_failed" {
  exploration_id = logtail_exploration.monitor_send_failed.id
  name           = "${2:-$ALERT_NAME}"
  incident_cause = "${3:-$CAUSE}"
  escalation_target {
    team_name = "Your team"
  }
}
EOF
}
write_tf 1

# ── curl stub: dispatches on URL (+page), honours -o and -w, records argv, fails on demand ────
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
    -w|-m|-H|--max-redirs|--proto|--noproxy) i=$((i+1)); [[ "${args[$((i-1))]}" == "-w" ]] && want_code=1 ;;
    https://*) url="${args[$i]}" ;;
  esac
done
rc_file="$cfg/curl.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && exit "$rc"; }
page="$(printf '%s' "$url" | sed -nE 's/.*[?&]page=([0-9]+).*/\1/p')"
case "$url" in
  https://telemetry.betterstack.com/api/v2/alerts*) body="$cfg/alerts.json"; code="$(cat "$cfg/alerts.code" 2>/dev/null || echo 200)" ;;
  https://uptime.betterstack.com/api/v2/incidents*)
    if [[ -n "$page" && -f "$cfg/incidents.p$page.json" ]]; then body="$cfg/incidents.p$page.json"; else body="$cfg/incidents.json"; fi; code=200 ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; printf '%s\n' "OFFHOST $url" >> "$cfg/calls.log"; exit 99 ;;
esac
[[ -n "$out" ]] && cp "$body" "$out"
[[ "$want_code" == 1 ]] && printf '%s' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"

# ── BQ mock: dispatches on the SQL shape, records the SQL ─────────────────────────────────
# order matters: the nonsynthetic count also contains count(); check the narrower shapes first.
cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
set -uo pipefail
cfg="$WORK"
sql="\${1:-}"
printf 'BQ %s\n' "\${sql//\$'\n'/ }" >> "\$cfg/calls.log"
[[ -f "\$cfg/bq.rc" ]] && { rc="\$(<"\$cfg/bq.rc")"; [[ "\$rc" != "0" ]] && { echo "curl: (22) The requested URL returned error: 403"; cat "\$cfg/bq.errbody" 2>/dev/null; exit "\$rc"; }; }
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
# <mode: none|both|name|cause> <started_at> [next-url]
incidents_json() {
  local mode="$1" at="$2" next="${3:-null}"; [[ "$next" != null ]] && next="\"$next\""
  local foreign='{"id":"9","type":"incident","attributes":{"name":"soleur apex","cause":"HTTP 503","started_at":"2026-09-13T14:40:00.000Z","resolved_at":null,"acknowledged_by":"SECRETISH_PERSON","screenshot_url":"https://x/SECRETISH_SHOT"}}'
  local n c
  case "$mode" in
    none)  printf '{"data":[%s],"pagination":{"next":%s}}' "$foreign" "$next"; return ;;
    both)  n="$ALERT_NAME"; c="$CAUSE" ;;
    name)  n="$ALERT_NAME"; c="Something else entirely" ;;
    cause) n="Some other display name"; c="$CAUSE" ;;
  esac
  printf '{"data":[%s,{"id":"42","type":"incident","attributes":{"name":"%s","cause":"%s","started_at":"%s","resolved_at":null,"acknowledged_by":"SECRETISH_PERSON","screenshot_url":"https://x/SECRETISH_SHOT"}}],"pagination":{"next":%s}}' "$foreign" "$n" "$c" "$at" "$next"
}
row_json() { # <host> <dt> [rev]
  printf '{"dt":"%s","host":"%s","msg":"SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=%s"}\n' "$2" "$1" "${3:-1}"
}
ROW_DT='2026-09-13 14:25:50.123'
INCIDENT_AT='2026-09-13T14:30:10.000Z'

set_fixtures() { # <alert-paused> <control-n> <readback-rows> <incidents-mode> <nonsynthetic-n>
  alert_json "$1" "$( [[ "$1" == true ]] && printf '"complexity issues, too many failures"' || printf 'null')" > "$WORK/alerts.json"
  printf '{"n":"%s","min_dt":"2026-09-01 00:00:00","max_dt":"%s"}\n' "$2" "$FRESH_MAX" > "$WORK/control.json"
  printf '%s' "$3" > "$WORK/readback.json"
  incidents_json "$4" "$INCIDENT_AT" > "$WORK/incidents.json"
  printf '{"n":"%s"}\n' "$5" > "$WORK/nonsynthetic.json"
  : > "$CALLS"; rm -f "$WORK/curl.rc" "$WORK/bq.rc" "$WORK/bq.errbody" "$WORK/alerts.code" "$WORK"/incidents.p*.json
  write_tf 1
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
expect_calls() { # <desc> <fixed-string that must appear in calls.log>
  if grep -qF -- "$2" "$CALLS"; then pass "$1"; else fail "$1 :: calls.log lacks '$2'"; fi
}
expect_no_calls() {
  if grep -qF -- "$2" "$CALLS"; then fail "$1 :: calls.log carries '$2'"; else pass "$1"; fi
}

# 1. PASS — alert live+unpaused, web-1 control present+fresh, synthetic row from web-1, incident
#    matching by BOTH keys. The recorded SQL pins the two load-bearing predicates the mock cannot see.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
run_case "row + web-1 control + matching incident -> PASS" 0
expect_out "PASS prints the verdict line" '^SOLEUR_SEND_FAILED_ALERT_PROBE verdict=pass detail="'
expect_out "PASS detail carries row_found/host/control/nonsynthetic/incident_id" 'row_found=1 host=soleur-web-platform .*control_rows_web1=731 .*nonsynthetic_rows=0 incident_id=42'
expect_out "PASS detail is quoted and timestamps carry no spaces" 'row_dt=2026-09-13T14:25:50.123 .*alert_paused=false"$'
expect_not_out "PASS never reprints raw incident fields (public comment)" 'SECRETISH_'
expect_calls "control SQL is web-1 SCOPED" "JSONExtractString(raw, 'host') = 'soleur-web-platform'"
expect_calls "readback SQL carries PRIORITY 2 + the marker" "JSONExtractString(raw, 'PRIORITY') = '2' AND JSONExtractString(raw, 'message') LIKE '%synthetic=1 probe_rev=1%'"
expect_calls "readback SQL reads hot ∪ archive" "s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1"
expect_calls "nonsynthetic SQL excludes the synthetic class" "NOT LIKE '%synthetic=1%'"

# 1b/1c. Each incident key ALONE must match (a fixture satisfying both pins neither arm).
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" name 0
run_case "incident matched by name only -> PASS" 0
expect_out "name arm credited" 'incident_match=name'
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" cause 0
run_case "incident matched by cause prefix only -> PASS" 0
expect_out "cause arm credited" 'incident_match=cause'

# 1d. The alert identity is READ FROM THE .tf: a renamed alert + reworded cause still passes when
#     the live objects carry the new values, and the decoy comment above the rev is ignored.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" none 0
write_tf 1 "soleur-renamed-prd" "Renamed cause prefix — tail"
printf '{"data":[{"id":"7","type":"incident","attributes":{"name":"x","cause":"Renamed cause prefix — tail","started_at":"%s","resolved_at":null}}],"pagination":{"next":null}}' "$INCIDENT_AT" > "$WORK/incidents.json"
printf '{"data":[{"id":"3","type":"alert","attributes":{"name":"soleur-renamed-prd","paused":false,"paused_reason":null}}],"pagination":{"next":null}}' > "$WORK/alerts.json"
run_case "alert name + cause derived from the .tf (renamed) -> PASS" 0
expect_out "derived cause prefix matched" 'incident_id=7 incident_match=cause'

# 2. alert_paused → 5, and the warehouse is NEVER queried (proves the ordering).
set_fixtures true 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
run_case "alert paused live -> ACTION REQUIRED (5)" 5
expect_out "alert_paused verdict names the projected paused_reason (quoted detail)" 'verdict=alert_paused detail="name=soleur-monitor-send-failed-prd paused_reason=complexity issues, too many failures"'
expect_no_calls "alert_paused: warehouse never queried" "BQ "
expect_no_calls "alert_paused: incidents never read" "api/v2/incidents"

# 3. alert_absent → 5.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '{"data":[{"id":"1","type":"alert","attributes":{"name":"Output utilization high","paused":true,"paused_reason":"Manually paused"}}],"pagination":{"next":null}}' > "$WORK/alerts.json"
run_case "alert missing from the live list -> ACTION REQUIRED (5)" 5
expect_out "alert_absent verdict" 'verdict=alert_absent'

# 3b. duplicate alert names: FIRST wins (newest-first listing) — documented, pinned.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '{"data":[{"id":"5","type":"alert","attributes":{"name":"%s","paused":true,"paused_reason":"stale duplicate"}},{"id":"2","type":"alert","attributes":{"name":"%s","paused":false,"paused_reason":null}}],"pagination":{"next":null}}' "$ALERT_NAME" "$ALERT_NAME" > "$WORK/alerts.json"
run_case "duplicate alert names: first listed wins -> alert_paused (5)" 5
expect_out "first-wins reason" 'paused_reason=stale duplicate'

# 4. channel_dark → 3 (web-1-scoped control is zero even though inngest rows would exist).
set_fixtures false 0 "" both 0
run_case "zero web-1 control rows -> CANNOT ESTABLISH (3), never row_absent" 3
expect_out "channel_dark verdict is host-scoped" 'verdict=channel_dark detail="host=soleur-web-platform reason=no-rows'
expect_not_out "channel_dark is not reported as row_absent" 'row_absent'

# 4b. control answered EMPTY (well-formed HTTP 200, no row) → unknown, NOT channel_dark.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
: > "$WORK/control.json"
run_case "empty control answer -> CANNOT ESTABLISH (3) as control-read-empty" 3
expect_out "empty control is an instrument fault, not a dark channel" 'verdict=unknown detail="control-read-empty"'
expect_not_out "empty control never reads as channel_dark" 'channel_dark'

# 4c. control present but STALE (newest row 3 h old) → channel_dark reason=stale, not row_absent.
set_fixtures false 731 "" both 0
printf '{"n":"731","min_dt":"2026-09-01 00:00:00","max_dt":"%s"}\n' "$(date -u -d '-3 hours' '+%F %T')" > "$WORK/control.json"
run_case "web-1 stopped shipping 3h ago, no row -> channel_dark reason=stale (3)" 3
expect_out "stale verdict" 'verdict=channel_dark detail="host=soleur-web-platform reason=stale'
expect_not_out "stale channel is not blamed on the probe" 'row_absent'

# 5. row_absent → 5 with the enumerated candidate causes.
set_fixtures false 731 "" both 0
run_case "web-1 control present+fresh but no synthetic row -> ACTION REQUIRED (5)" 5
expect_out "row_absent verdict" 'verdict=row_absent'
expect_out "row_absent names the ssh_token_gate green-skip cause" 'ssh_token_gate'
expect_out "row_absent names the main-apply-failed cause" 'main apply'
expect_out "row_absent names the journald/Vector match-fault cause" 'journald'

# 5b. rev terminator: a probe_rev=12 row must NOT satisfy rev 1.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT" 12)" both 0
run_case "probe_rev=12 row does not satisfy rev 1 -> row_absent (5)" 5
expect_out "prefix-match refused" 'verdict=row_absent'

# 6. row_present_no_incident → 5 (the verdict the feature exists to produce).
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" none 0
run_case "row present, no matching incident -> ACTION REQUIRED (5)" 5
expect_out "row_present_no_incident verdict" 'verdict=row_present_no_incident'
expect_out "prints the PROJECTED, windowed incident list" 'Incidents since the anchor \(projected, newest 20\): \[\{"id":"9"'
expect_not_out "projection withholds acknowledged_by/screenshot fields" 'SECRETISH_'

# 7. incident exists but started BEFORE the row's dt - 600s → not a match.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
incidents_json both "2026-09-13T13:00:00.000Z" > "$WORK/incidents.json"
run_case "matching incident too old for the row's dt anchor -> row_present_no_incident (5)" 5
expect_out "stale incident is not credited" 'verdict=row_present_no_incident'
expect_not_out "projected list is windowed to the anchor (old incident withheld)" '"id":"42"'

# 7b. incidents pagination is newest-first: 25 pages, match on page 1 → PASS, and the walk
#     STOPS once a page is older than the anchor (never reaches the page cap).
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" none 0
incidents_json both "$INCIDENT_AT" "https://uptime.betterstack.com/api/v2/incidents?page=2" > "$WORK/incidents.json"
for p in $(seq 2 25); do
  nxt="https://uptime.betterstack.com/api/v2/incidents?page=$((p+1))"; [[ $p -eq 25 ]] && nxt=null
  printf '{"data":[{"id":"%s","type":"incident","attributes":{"name":"old","cause":"old","started_at":"2026-08-01T00:00:00.000Z","resolved_at":"2026-08-01T01:00:00.000Z"}}],"pagination":{"next":%s}}' "$((100 + p))" "$( [[ "$nxt" == null ]] && echo null || echo "\"$nxt\"" )" > "$WORK/incidents.p$p.json"
done
run_case "25-page incident history, match on page 1 -> PASS" 0
n_inc="$(grep -c 'api/v2/incidents' "$CALLS")"
if [[ "$n_inc" -le 2 ]]; then pass "walk stopped at the first page older than the anchor ($n_inc GET(s))"; else fail "walk did not stop: $n_inc incident GETs"; fi

# 7c. a started_at with a +00:00 offset is parsed, not a verdict.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
incidents_json both "2026-09-13T14:30:10+00:00" > "$WORK/incidents.json"
run_case "+00:00 offset on started_at -> PASS" 0
# 7d. an unparseable started_at is an instrument fault (3), never row_present_no_incident (5).
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
incidents_json both "13/09/2026 14:30" > "$WORK/incidents.json"
run_case "unparseable started_at -> CANNOT ESTABLISH (3)" 3
expect_out "parse failure named" 'verdict=unknown detail="incident-parse-failed"'

# 7e. off-host pagination.next is REFUSED before any request leaves, host-only in the message.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" none 0
incidents_json none "$INCIDENT_AT" "https://uptime.betterstack.com@evil.example/api/v2/incidents?page=2" > "$WORK/incidents.json"
run_case "off-host pagination.next -> CANNOT ESTABLISH (3)" 3
expect_no_calls "the token never left the pinned host" "OFFHOST"
expect_out "refusal names the host only" 'refusing off-host pagination.next \(host=evil.example\)'
expect_not_out "refusal does not echo the full URL" 'api/v2/incidents\?page=2'

# 8. host mismatch is REPORTED, not failed on.
set_fixtures false 731 "$(row_json soleur-inngest "$ROW_DT")" both 0
run_case "row from a foreign host -> still PASS, host_mismatch reported" 0
expect_out "host mismatch attribute printed" 'host_mismatch=1'

# 9. nonsynthetic rows are surfaced.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 3
run_case "real firings in the window are counted" 0
expect_out "nonsynthetic_rows carried" 'nonsynthetic_rows=3'

# 10. curl rc≠0 on the alerts GET → TRANSIENT, exit 3 (never 5, never 1).
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '7' > "$WORK/curl.rc"
run_case "curl rc=7 on the alerts GET -> CANNOT ESTABLISH (3)" 3
expect_out "TRANSIENT prefix on the alerts-GET failure" 'TRANSIENT:'

# 11. non-2xx on the alerts GET → 3.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '502' > "$WORK/alerts.code"
run_case "HTTP 502 on the alerts GET -> CANNOT ESTABLISH (3)" 3

# 12. warehouse read fails (rc≠0) → 3, and a 516 auth body that names the QUERY USER is scrubbed
#     before it reaches the public comment.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '22' > "$WORK/bq.rc"
printf '{"exception":"Code: 516. DB::Exception: dummy-user: Authentication failed: password is incorrect, or there is no user with such name. (AUTHENTICATION_FAILED)\\n"}\n' > "$WORK/bq.errbody"
run_case "betterstack-query.sh transport failure -> CANNOT ESTABLISH (3)" 3
expect_not_out "a failed read is never row_absent" 'row_absent'
expect_not_out "the query username is scrubbed from the echoed error" 'dummy-user'
expect_out "the scrubbed error still names the class" 'Authentication failed'

# 12b. HTTP 200 + rc 0 + a bare ClickHouse exception line mid-stream (#7855 P1-B) → 3, never a verdict.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
printf '{"n":"731","min_dt":"2026-09-01 00:00:00","max_dt":"%s"}\nCode: 241. DB::Exception: Memory limit exceeded\n' "$FRESH_MAX" > "$WORK/control.json"
run_case "rc=0 mid-stream ClickHouse exception -> CANNOT ESTABLISH (3)" 3
expect_out "shape failure attributed to the control read" 'verdict=unknown detail="control-read-failed"'
expect_not_out "an exception is never channel_dark" 'channel_dark'

# 13. secrets unset → 3, never 1.
set_fixtures false 731 "$(row_json soleur-web-platform "$ROW_DT")" both 0
rc=0; out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" SEND_FAILED_PROBE_BQ="$MOCK" SEND_FAILED_PROBE_TF="$TF" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 3 ]]; then pass "no secrets -> CANNOT ESTABLISH (exit=3, never 1)"; else fail "no secrets -- expected 3 got $rc :: ${out:0:200}"; fi

# 14. probe_rev not greppable / identity not readable from the checkout → 3.
printf 'locals {\n  monitor_send_failed_probe_rev = "1a"\n}\n' > "$WORK/bad.tf"
run_case "non-digit probe_rev in the checkout -> CANNOT ESTABLISH (3)" 3 SEND_FAILED_PROBE_TF="$WORK/bad.tf"
printf 'locals {\n  monitor_send_failed_probe_rev = "1"\n}\n' > "$WORK/noalert.tf"
run_case "no alert block in the checkout -> CANNOT ESTABLISH (3)" 3 SEND_FAILED_PROBE_TF="$WORK/noalert.tf"
expect_out "identity failure named" 'alert-identity-unreadable'

# 15. xtrace refusal (#7797): runs under the inherited env by design (the guard is in the SUT).
rc=0; out="$(env BETTERSTACK_API_TOKEN=x bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "refuses to run under xtrace with a credential bound (exit=78)"
else fail "xtrace refusal -- expected 78 got $rc"; fi

# 16. never exit 1: a shell error inside the script must not surface as FAIL. Missing BQ → 3.
run_case "missing BQ path -> CANNOT ESTABLISH (3), not 1" 3 SEND_FAILED_PROBE_BQ="$WORK/nope.sh"

# Exact baseline, no slack (a whole case can otherwise vanish silently).
MIN_CASES=75
if [[ "$total" -ne "$MIN_CASES" ]]; then printf 'FATAL: %s assertions ran, expected exactly %s (re-pin MIN_CASES after a deliberate change)\n' "$total" "$MIN_CASES" >&2; exit 1; fi
if [[ "$fails" -gt 0 ]]; then echo "FAILED: $fails of $total case(s)" >&2; exit 1; fi
echo "OK: all $total send-failed-alert-probe-8097 arms passed"
