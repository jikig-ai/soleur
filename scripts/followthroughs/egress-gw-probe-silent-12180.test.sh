#!/usr/bin/env bash
# Exit-code harness for egress-gw-probe-silent-12180.sh (#12180 soak follow-through).
#
# The follow-through's exit code IS its authorization artifact: sweep-followthroughs.sh CLOSES the
# tracker on 0, comments ACTION REQUIRED on 5, retries on 2/3/78, and reads a 1 as FAIL (reopening
# a human-closed tracker). The cardinal sins this suite pins: a vacuous 0 (a PASS on an unanswered
# read, a truncated incident list, a resolved-too-recently incident, a missing canary incident, a
# canary still declared, or a recurrence), an exit 1, and a public comment that echoes a response
# body or a credential.
#
# Guard 2 of knowledge-base/project/plans/2026-11-05-fix-egress-gw-probe-silent-invert-metric-plan.md
# (verdict matrix, 11 rows + harness rows). The SUT runs under `env -i` exactly as the sweeper runs
# it, with a PATH-shimmed `curl` that dispatches on the URL (single incident, incident list per
# page, alert list) and records argv + the stdin config channel, and an
# EGRESS_GW_SILENT_BQ mock that RECORDS the SQL (the mock cannot see SQL content, so the
# load-bearing predicates are asserted from calls.log, not inferred from the verdict). The clock is
# the SUT's EGRESS_GW_SILENT_NOW_EPOCH seam so the 4 h window boundary is exact, never flaky.
# Boundary fixtures sit on NON-collinear points: each boundary case varies ids and timestamps, not
# only the boundary, so a probe that hard-codes one canonical fixture cannot pass them
# (learning 2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator).
# cq-test-fixtures-synthesized-only: every payload below is synthesized in this file.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/egress-gw-probe-silent-12180.sh"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Assertion-count floor lives at the bottom, on the line directly above its `if`, so
# guard-vacuity-floor.test.sh can slice it into a mutant (a threshold bound far above is unbound there).

[[ -f "$SUT" ]] || { printf 'FATAL: SUT not found at %s\n' "$SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { printf 'FATAL: SUT not executable at %s\n' "$SUT" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

WORK="$(mktemp -d -t egs-ft.XXXXXXXX)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/bin"
MOCK="$WORK/mock-bq.sh"
TF="$WORK/betterstack-logs-alerts.tf"
CALLS="$WORK/calls.log"

PROD_NAME="soleur-egress-gw-probe-silent-prd"
CANARY_NAME="soleur-egress-gw-probe-silent-canary-prd"
NOW=1793836817            # fixed clock (the SUT's EGRESS_GW_SILENT_NOW_EPOCH seam)
H4=14400
STALE_S=15300             # the SUT's open-incident staleness horizon (4 h + 15 min grace)

iso() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%S.000Z'; }

# ── curl stub: dispatches on URL (+page), honours -o and -w, records argv + stdin ─────────────
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf '%s\n' "$*" >> "$cfg/calls.log"
out=""; url=""; want_code=0
args=("$@")
for a in "${args[@]}"; do [[ "$a" == "-" ]] && { cat >> "$cfg/stdin.log"; break; }; done
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; i=$((i+1)) ;;
    -w|-m|-H|--max-redirs|--proto|--noproxy) i=$((i+1)); [[ "${args[$((i-1))]}" == "-w" ]] && want_code=1 ;;
    https://*) url="${args[$i]}" ;;
  esac
done
rc_file="$cfg/curl.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && exit "$rc"; }
# curl.term: signal the PROBE's main shell (this stub's grandparent: probe -> $( ) subshell -> curl), then keep it waiting
if [[ -f "$cfg/curl.term" ]]; then
  kill -TERM "$(ps -o ppid= -p "$PPID" | tr -d ' ')" 2>/dev/null
  sleep 1
fi
page="$(printf '%s' "$url" | sed -nE 's/.*[?&]page=([0-9]+).*/\1/p')"
code=200
case "$url" in
  https://telemetry.betterstack.com/api/v2/alerts*) body="$cfg/alerts.json"; [[ -f "$cfg/alerts.code" ]] && code="$(<"$cfg/alerts.code")" ;;
  https://uptime.betterstack.com/api/v2/incidents/*) body="$cfg/single.json"; [[ -f "$cfg/single.code" ]] && code="$(<"$cfg/single.code")" ;;
  https://uptime.betterstack.com/api/v2/incidents*)
    if [[ -n "$page" ]]; then
      if [[ -f "$cfg/incidents.p$page.json" ]]; then body="$cfg/incidents.p$page.json"
      else body="$cfg/err500.json"; code=500; fi
    else
      body="$cfg/incidents.json"; [[ -f "$cfg/incidents.code" ]] && code="$(<"$cfg/incidents.code")"
    fi ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; printf '%s\n' "OFFHOST $url" >> "$cfg/calls.log"; exit 99 ;;
esac
[[ -n "$out" ]] && cp "$body" "$out"
[[ "$want_code" == 1 ]] && printf '%s' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"
printf '%s' '{"error":"server exploded; Bearer dummy-token-SECRETISH leaked BETTERSTACK_API_TOKEN=dummy-token"}' > "$WORK/err500.json"

# ── BQ mock: records the SQL, answers from bq.json, fails on demand ────────────────────────
cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
set -uo pipefail
cfg="$WORK"
sql="\${1:-}"
printf 'BQ %s\n' "\${sql//\$'\n'/ }" >> "\$cfg/calls.log"
[[ -f "\$cfg/bq.rc" ]] && { rc="\$(<"\$cfg/bq.rc")"; [[ "\$rc" != "0" ]] && { echo "DB::Exception: dummy-user: Authentication failed dummy-pass"; exit "\$rc"; }; }
cat "\$cfg/bq.json"
exit 0
MOCKEOF
chmod 0755 "$MOCK"

# ── fixture builders (jq-built, so the JSON is always well-formed) ────────────────────────────
inc() { # <id> <name> <started_epoch> [resolved_epoch-or-empty] [cause] [resolved_by: none|actor]
  local r=""; [[ -n "${4:-}" ]] && r="$(iso "$4")"
  jq -nc --arg id "$1" --arg n "$2" --arg s "$(iso "$3")" --arg r "$r" --arg c "${5:-HTTP 503 SECRETISH_CAUSE}" --arg by "${6:-none}" \
    '{id:$id,type:"incident",attributes:{name:$n,cause:$c,started_at:$s,resolved_at:(if $r=="" then null else $r end),status:(if $r=="" then "Started" else "Resolved" end),acknowledged_by:"SECRETISH_PERSON",resolved_by:(if $by=="actor" then "SECRETISH_RESOLVER" else null end),screenshot_url:"https://x/SECRETISH_SHOT"}}'
}
alert() { # <name> <paused> [operator] [value] [created_epoch]
  jq -nc --arg n "$1" --argjson p "${2:-false}" --arg op "${3:-higher_than}" --argjson v "${4:-0}" --arg ca "$(iso "${5:-$((NOW - 100000))}")" \
    '{id:"1",type:"alert",attributes:{name:$n,paused:$p,operator:$op,value:$v,created_at:$ca}}'
}

reset_defaults() {
  ANCHOR_ID=1047829421
  A_START=$((NOW - 30017))
  A_RES=$((NOW - H4 - 3601))     # resolved well over 4 h ago -> compliant by default
  CANARY_INC=1                   # a canary incident exists
  CANARY_AGE=20000               # ... that started this many seconds before NOW
  NEWER=0                        # no later production incident
  ALERT_LIVE=0                   # canary alert is NOT in the live listing (the real end state: deleted after it fired)
  CANARY_PAUSED=false            # when the canary alert is listed, is it paused
  CANARY_ALERT_AGE=100000        # ... and how old is it
  PROD_ALERT=ok                  # ok | absent | paused | shape (operator/value reverted)
  RBY=none                       # who resolved the anchor: none (the alert) | actor
  DECLARED=0                     # canary no longer declared in the .tf
  ROSTER_BQ='[]'
  PAGES=1
}

write_tf() { # <declared 0|1>
  {
    printf 'locals {\n  egress_gw_probe_silent_sql = "x"\n}\n'
    printf '# resource "logtail_exploration_alert" "egress_gw_probe_silent_canary" {   <- a comment, not a declaration\n'
    printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent" {\n  name = "%s"\n}\n' "$PROD_NAME"
    printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent_canary_old" {\n  name = "decoy"\n}\n'
    if [[ "$1" == 1 ]]; then
      printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent_canary" {\n  name = "%s"\n}\n' "$CANARY_NAME"
    fi
  } > "$TF"
}

build_fixtures() {
  local objs=() old_id=1031046761
  objs+=("$(inc "$ANCHOR_ID" "$PROD_NAME" "$A_START" "$([[ "$A_RES" == open ]] && echo '' || echo "$A_RES")" "HTTP 503 SECRETISH_CAUSE" "$RBY")")
  objs+=("$(inc "$old_id" "$PROD_NAME" $((A_START - 1728000)) $((A_START - 600)))")
  objs+=("$(inc 7001 "soleur apex" $((NOW - 13000)) "" "HTTP 503")")
  # exact-name decoys: a name that merely CONTAINS the prod name, and a cause that quotes it.
  objs+=("$(inc 7002 "${PROD_NAME}-copy" $((NOW - 12000)) "" "x")")
  objs+=("$(inc 7003 "Some other alert" $((NOW - 11000)) "" "quotes ${PROD_NAME} and ${CANARY_NAME} in its cause")")
  [[ "$CANARY_INC" == 1 ]] && objs+=("$(inc 5555 "$CANARY_NAME" $((NOW - CANARY_AGE)) "" "THROWAWAY CANARY (#12180)")")
  [[ "$NEWER" == 1 ]] && objs+=("$(inc 9090 "$PROD_NAME" $((NOW - 9000)) "" "recurrence")")
  local all; all="$(printf '%s\n' "${objs[@]}" | jq -sc 'sort_by(.attributes.started_at) | reverse')"
  if [[ "$PAGES" == 1 ]]; then
    jq -nc --argjson d "$all" '{data:$d,pagination:{next:null}}' > "$WORK/incidents.json"
  else
    # page 1 = the newest 3, page 2 = the rest (carries the anchor); page 2 points at a page 3 that
    # does NOT exist: a probe that does not stop at the anchor would request it and read a 500.
    jq -nc --argjson d "$all" '{data:$d[:3],pagination:{next:"https://uptime.betterstack.com/api/v2/incidents?page=2"}}' > "$WORK/incidents.json"
    jq -nc --argjson d "$all" '{data:$d[3:],pagination:{next:"https://uptime.betterstack.com/api/v2/incidents?page=3"}}' > "$WORK/incidents.p2.json"
  fi
  jq -nc --argjson d "$(inc "$ANCHOR_ID" "$PROD_NAME" "$A_START" "$([[ "$A_RES" == open ]] && echo '' || echo "$A_RES")" "HTTP 503 SECRETISH_CAUSE" "$RBY")" '{data:$d}' > "$WORK/single.json"
  {
    alert "Output utilization high" true
    case "$PROD_ALERT" in
      ok) alert "$PROD_NAME" false ;;
      paused) alert "$PROD_NAME" true ;;
      shape) alert "$PROD_NAME" false lower_than 2 ;;
      absent) : ;;
    esac
    alert "${CANARY_NAME}-old" false
    [[ "$ALERT_LIVE" == 1 ]] && alert "$CANARY_NAME" "$CANARY_PAUSED" higher_than 0 $((NOW - CANARY_ALERT_AGE))
  } | jq -sc '{data:.,pagination:{next:null}}' > "$WORK/alerts.json"
  printf '%s' "$ROSTER_BQ" | jq -r '.[] | tojson' > "$WORK/bq.json"
  : > "$CALLS"; : > "$WORK/stdin.log"
  rm -f "$WORK/curl.rc" "$WORK/curl.term" "$WORK/bq.rc" "$WORK/alerts.code" "$WORK/single.code" "$WORK/incidents.code" "$WORK"/incidents.p3.json
  write_tf "$DECLARED"
}

# run_case <desc> <expected-rc> [extra env assignments...]
run_case() {
  local desc="$1" expected="$2"; shift 2
  local rc=0 out
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
      BETTERSTACK_QUERY_HOST=dummy-host BETTERSTACK_QUERY_USERNAME=dummy-user BETTERSTACK_QUERY_PASSWORD=dummy-pass \
      BETTERSTACK_API_TOKEN=dummy-token EGRESS_GW_SILENT_BQ="$MOCK" EGRESS_GW_SILENT_TF="$TF" \
      EGRESS_GW_SILENT_NOW_EPOCH="$NOW" EGRESS_GW_SILENT_ANCHOR_ID="$ANCHOR_ID" \
      EGRESS_GW_SILENT_ROSTER="soleur-web-platform soleur-web-2" "$@" "$SUT" 2>&1)" || rc=$?
  LAST_OUT="$out"; LAST_RC="$rc"
  if [[ "$rc" -eq 1 ]]; then fail "$desc -- exit 1 is FORBIDDEN (the sweeper reads it as FAIL) :: ${out:0:300}"; return; fi
  if [[ "$expected" == any ]]; then pass "$desc (exit=$rc)"
  elif [[ "$rc" -eq "$expected" ]]; then pass "$desc (exit=$rc)"
  else fail "$desc -- expected exit=$expected got exit=$rc :: ${out:0:500}"; fi
}
expect_out() { # <desc> <grep -E pattern>
  if printf '%s' "$LAST_OUT" | grep -cE >/dev/null -- "$2"; then pass "$1"; else fail "$1 :: ${LAST_OUT:0:500}"; fi
}
expect_not_out() {
  if printf '%s' "$LAST_OUT" | grep -cE >/dev/null -- "$2"; then fail "$1 :: ${LAST_OUT:0:500}"; else pass "$1"; fi
}
expect_calls() { if grep -qF -- "$2" "$CALLS"; then pass "$1"; else fail "$1 :: calls.log lacks '$2'"; fi; }
expect_no_calls() { if grep -qF -- "$2" "$CALLS"; then fail "$1 :: calls.log carries '$2'"; else pass "$1"; fi; }
verdict_is() { # <verdict> -> asserts the SOLEUR_EGRESS_GW_SILENT_SOAK line names it
  expect_out "verdict line says verdict=$1" "^SOLEUR_EGRESS_GW_SILENT_SOAK verdict=$1 "
}
field_is() { # <field=value>
  expect_out "verdict line carries $1" "^SOLEUR_EGRESS_GW_SILENT_SOAK .* $1( |\$)"
}

# ── 0. The canonical PASS and the full verdict-line format ───────────────────────────────────
reset_defaults; A_RES=$((NOW - H4 - 3601)); build_fixtures
run_case "compliant fixture -> PASS" 0
verdict_is pass
expect_out "PASS verdict line has every field in the pinned order" \
  '^SOLEUR_EGRESS_GW_SILENT_SOAK verdict=pass prod_incident=resolved resolved_age_s=[0-9]+ newer_prod_incident=0 canary=fired canary_alert_live=0 canary_declared=0 prod_alert=ok anchor_resolved_by=none rows_in_window=[^ ]+$'
field_is "prod_incident=resolved"; field_is "resolved_age_s=$((H4 + 3601))"; field_is "newer_prod_incident=0"
field_is "canary=fired"; field_is "canary_alert_live=0"; field_is "canary_declared=0"; field_is "rows_in_window=na"; field_is "prod_alert=ok"; field_is "anchor_resolved_by=none"
expect_not_out "output never reprints raw incident fields (public comment)" 'SECRETISH_'
expect_not_out "output never carries the credentials" 'dummy-(token|user|pass)'
expect_no_calls "no warehouse read when the production incident is resolved and nothing is newer" "BQ "
if grep -qF -- 'header = "Authorization: Bearer dummy-token"' "$WORK/stdin.log"; then pass "the bearer header arrives on curl stdin"; else fail "the bearer header arrives on curl stdin"; fi
expect_no_calls "the token is absent from every curl argv" "dummy-token"
expect_calls "the single-incident read targets the anchor id" "/api/v2/incidents/1047829421"
expect_calls "the live alert listing is read from the telemetry host" "telemetry.betterstack.com/api/v2/alerts"
expect_no_calls "no request leaves the two pinned hosts" "OFFHOST"

# The canary alert still LIVE after its incident was seen and the declaration is gone: the deletion did not apply -> action_required.
reset_defaults; ALERT_LIVE=1; build_fixtures
run_case "canary incident seen, declaration gone, but the canary alert is still live -> action_required (the deletion did not apply)" 5
field_is "canary_alert_live=1"; expect_out "the message says to delete the canary" 'ACTION REQUIRED:.*delete the canary'
# The soak is measured from the apply, not from an earlier resolve: a canary incident younger than 4 h -> not_yet even with an old resolve.
reset_defaults; CANARY_AGE=$((H4 - 1000)); build_fixtures
run_case "anchor resolved long ago but the canary incident is 4 h minus 1000 s old -> not_yet" 2
reset_defaults; CANARY_AGE=$H4; build_fixtures
run_case "canary incident exactly 4 h old, everything else true -> PASS" 0

# ── Guard 2 row 1/2 + must-PASS non-canonical: window boundary on non-collinear points ──────
reset_defaults; A_START=$((NOW - 55555)); A_RES=$((NOW - H4 + 1)); CANARY_AGE=33333; build_fixtures
run_case "row 1: resolved 4 h minus 1 s ago -> not_yet" 2
verdict_is not_yet; field_is "resolved_age_s=$((H4 - 1))"; field_is "prod_incident=resolved"
reset_defaults; ANCHOR_ID=1047829999; A_START=$((NOW - 41111)); A_RES=$((NOW - H4)); CANARY_AGE=25000; build_fixtures
run_case "resolved exactly 4 h ago (different ids and timestamps) -> PASS" 0
verdict_is pass; field_is "resolved_age_s=$H4"
reset_defaults; ANCHOR_ID=1047828888; A_START=$((NOW - 29999)); A_RES=$((NOW - H4 - 1)); CANARY_AGE=27777; build_fixtures
run_case "resolved 4 h plus 1 s ago (different ids and timestamps) -> PASS" 0
verdict_is pass; field_is "resolved_age_s=$((H4 + 1))"
reset_defaults; A_RES=$((NOW - 10)); CANARY_AGE=20000; build_fixtures
run_case "resolved 10 s ago -> not_yet" 2
reset_defaults; A_RES=$((NOW - 7200)); DECLARED=1; build_fixtures
run_case "inside the 4 h window with the canary still declared -> not_yet (the window is not over)" 2
verdict_is not_yet

# ── prod incident still open ─────────────────────────────────────────────────────────────────
reset_defaults; A_RES=open; CANARY_AGE=3000; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"},{"host":"soleur-web-2","n":"39"}]'; build_fixtures
run_case "incident open, canary fired, not yet stale -> not_yet" 2
verdict_is not_yet; field_is "prod_incident=open"; field_is "resolved_age_s=-1"
field_is "rows_in_window=soleur-web-2:39,soleur-web-platform:41"
expect_calls "open incident -> warehouse read keyed on the emitter tag" "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'"
expect_calls "rows read groups by host_name" "JSONExtractString(raw, 'host_name') AS host"
expect_calls "rows read spans hot window UNION archive" "s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1"
expect_calls "rows read is the trailing 15 minutes (the alert's own window)" "dt >= '$(date -u -d "@$((NOW - 900))" '+%Y-%m-%d %H:%M:%S')' AND dt <= '$(date -u -d "@$NOW" '+%Y-%m-%d %H:%M:%S')'"
expect_not_out "rows_in_window prints counts, never row content" 'raw|message'

# row 11: open incident, one roster host has no rows -> the field names it; verdict stays action_required
reset_defaults; A_RES=open; CANARY_AGE=17000; ROSTER_BQ='[{"host":"soleur-web-platform","n":"288"}]'; build_fixtures
run_case "row 11: open past the staleness horizon with web-2 missing from rows -> action_required" 5
verdict_is action_required; field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:288"
expect_out "the ACTION REQUIRED line names the poller (#12190)" 'ACTION REQUIRED:.*12190'
reset_defaults; A_RES=open; CANARY_AGE=$((STALE_S - 1)); ROSTER_BQ='[{"host":"soleur-web-platform","n":"5"},{"host":"soleur-web-2","n":"5"}]'; build_fixtures
run_case "open, one second inside the staleness horizon -> not_yet" 2
reset_defaults; A_RES=open; CANARY_AGE=$((STALE_S + 1)); ROSTER_BQ='[{"host":"soleur-web-platform","n":"5"},{"host":"soleur-web-2","n":"5"}]'; build_fixtures
run_case "open, one second past the staleness horizon -> action_required" 5
field_is "rows_in_window=soleur-web-2:5,soleur-web-platform:5"
# the warehouse read is diagnostic only: its failure must not change the verdict
reset_defaults; A_RES=open; CANARY_AGE=3000; build_fixtures; printf '7' > "$WORK/bq.rc"
run_case "warehouse read fails while the incident is open -> verdict unchanged (not_yet)" 2
field_is "rows_in_window=unknown"; expect_not_out "a failed warehouse read prints no credential" 'dummy-(user|pass|token)'; expect_not_out "a failed warehouse read prints no exception text" 'Authentication'

# ── row 3 / row 10: canary incident absent ───────────────────────────────────────────────────
reset_defaults; CANARY_INC=0; ALERT_LIVE=1; build_fixtures
run_case "row 3: no canary incident, canary alert live -> action_required (evaluator blind)" 5
verdict_is action_required; field_is "canary=absent"; field_is "canary_alert_live=1"
expect_out "blind-evaluator message names the poller" 'ACTION REQUIRED:.*blind.*12190'
reset_defaults; CANARY_INC=0; ALERT_LIVE=0; build_fixtures
run_case "row 10: no canary incident AND no live canary alert -> action_required (apply never created it)" 5
field_is "canary=absent"; field_is "canary_alert_live=0"
expect_out "row 10 names the apply, not an evaluator finding" 'ACTION REQUIRED:.*(apply|create)'
expect_not_out "row 10 does not claim the evaluator is blind" 'blind'
# the canary check does not wait for the 4 h window: prod still open and canary absent -> 5, not 2
reset_defaults; A_RES=open; CANARY_INC=0; ALERT_LIVE=1; build_fixtures
run_case "canary absent while the production incident is still open -> action_required (no waiting)" 5
# exact-name matching: a canary-NAMED cause on a differently named incident is not a canary incident
reset_defaults; CANARY_INC=0; ALERT_LIVE=1; build_fixtures
run_case "an incident whose cause (not name) quotes the canary name is not a canary incident" 5
field_is "canary=absent"

# ── row 4: canary still declared with every other condition true ─────────────────────────────
reset_defaults; DECLARED=1; build_fixtures
run_case "row 4: canary still declared, everything else true -> action_required (delete it)" 5
verdict_is action_required; field_is "canary_declared=1"; field_is "canary=fired"
expect_out "the message says to delete the canary" 'ACTION REQUIRED:.*delete the canary'
reset_defaults; build_fixtures
run_case "the commented-out canary header and a sibling resource do not count as declared" 0
field_is "canary_declared=0"

# ── row 5: recurrence ────────────────────────────────────────────────────────────────────────
reset_defaults; NEWER=1; build_fixtures
run_case "row 5: a second production incident started after the first resolved -> action_required" 5
verdict_is action_required; field_is "newer_prod_incident=1"
expect_out "recurrence message projects id and name only" '9090'
expect_not_out "recurrence message never reprints raw fields" 'SECRETISH_'
expect_calls "a recurrence triggers the rows_in_window read" "BQ "
reset_defaults; NEWER=1; A_RES=open; CANARY_AGE=3000; build_fixtures
run_case "recurrence while the first is open -> action_required" 5
reset_defaults; build_fixtures
run_case "the decoys (name contains prod name; cause quotes it; canary-named incident) are NOT a recurrence" 0
field_is "newer_prod_incident=0"

# ── row 2: truncation / paging ───────────────────────────────────────────────────────────────
reset_defaults; PAGES=2; build_fixtures
run_case "two pages, the walk stops at the page that carries the anchor (page 3 never requested) -> PASS" 0
expect_no_calls "page 3 was never requested" "page=3"
reset_defaults; PAGES=2; build_fixtures; rm -f "$WORK/incidents.p2.json"
run_case "row 2: next page present but unreadable, anchor not reached -> unknown" 3
verdict_is unknown
reset_defaults; build_fixtures
jq -c '.pagination.next = "https://uptime.betterstack.com/api/v2/incidents?page=2"' "$WORK/incidents.json" | jq -c '.data |= map(select(.id != "1047829421" and .id != "1031046761"))' > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
rm -f "$WORK/incidents.p2.json"
run_case "list ends with next present and no anchor on any read page -> unknown" 3
reset_defaults; build_fixtures
jq -c '.data |= map(select(.id != "1047829421"))' "$WORK/incidents.json" > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "list complete (next null) but the anchor is missing from it -> unknown" 3
reset_defaults; build_fixtures
jq -c '.pagination.next = "https://evil.example/api/v2/incidents?page=2"' "$WORK/incidents.json" | jq -c '.data |= map(select(.id != "1047829421" and .id != "1031046761"))' > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "off-host pagination.next is refused -> unknown" 3
expect_no_calls "the off-host URL was never requested" "evil.example"
expect_no_calls "the bearer never rides to the off-host URL" "OFFHOST"
reset_defaults; build_fixtures
jq -c '.pagination.next = "https://uptime.betterstack.com/api/v2/incidents?page=2"' "$WORK/incidents.json" | jq -c '.data |= map(select(.id != "1047829421" and .id != "1031046761"))' > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
cp "$WORK/incidents.json" "$WORK/incidents.p2.json"; cp "$WORK/incidents.json" "$WORK/incidents.p3.json"
run_case "a next chain that never reaches the anchor hits the page cap -> unknown" 3 EGRESS_GW_SILENT_PAGE_CAP=2
rm -f "$WORK/incidents.p3.json"

# ── row 7: transport failures -> 3 ───────────────────────────────────────────────────────────
for ep in single incidents alerts; do
  reset_defaults; build_fixtures; printf '500' > "$WORK/$ep.code"
  run_case "row 7: HTTP 500 on the $ep read -> unknown" 3
  verdict_is unknown
  expect_out "$ep failure prints the HTTP status and a byte length" 'HTTP 500.*bytes=[0-9]+'
  expect_not_out "$ep failure never echoes the response body or credentials (row 9)" 'SECRETISH|dummy-token|server exploded|BETTERSTACK_API_TOKEN='
done
reset_defaults; build_fixtures; printf '' > "$WORK/incidents.json"
run_case "row 7: empty 200 body on the incident list -> unknown" 3
reset_defaults; build_fixtures; printf '' > "$WORK/single.json"
run_case "row 7: empty 200 body on the single-incident read -> unknown" 3
reset_defaults; build_fixtures; printf '{"data":"nope"}' > "$WORK/incidents.json"
run_case "a 200 body whose data is not an array -> unknown" 3
reset_defaults; build_fixtures; printf '{"data":[{"id":"x","attributes":{"name":"%s","started_at":"not-a-time"}}],"pagination":{"next":null}}' "$PROD_NAME" > "$WORK/incidents.json"
run_case "an unparseable started_at -> unknown, never a verdict" 3
reset_defaults; build_fixtures; printf '28' > "$WORK/curl.rc"
run_case "curl timeout (rc 28) -> unknown" 3
expect_not_out "curl failure prints no credential" 'dummy-token'
reset_defaults; build_fixtures; printf '1' > "$WORK/curl.rc"
run_case "row 6: curl itself exits 1 -> remapped to 3, never 1" 3
reset_defaults; build_fixtures
jq -c '.data.attributes.name = "some-other-alert"' "$WORK/single.json" > "$WORK/single.tmp" && mv "$WORK/single.tmp" "$WORK/single.json"
run_case "the anchor id resolves to a differently named incident -> unknown" 3

# ── environment / seam failures -> 3 (never 1) ───────────────────────────────────────────────
reset_defaults; build_fixtures
run_case "BETTERSTACK_API_TOKEN unset -> unknown" 3 BETTERSTACK_API_TOKEN=
verdict_is unknown
run_case "a token with an embedded newline (config injection) -> unknown" 3 "BETTERSTACK_API_TOKEN=abc
header = \"X-Evil: 1\""
expect_not_out "the injected directive is never echoed" 'X-Evil'
run_case "the .tf is absent -> unknown" 3 EGRESS_GW_SILENT_TF="$WORK/nope.tf"
run_case "the .tf path is a directory -> unknown" 3 EGRESS_GW_SILENT_TF="$WORK"
run_case "a non-numeric clock seam is refused -> unknown" 3 EGRESS_GW_SILENT_NOW_EPOCH=yesterday

# ── row 8: xtrace refusal (#7797) ────────────────────────────────────────────────────────────
reset_defaults; build_fixtures
rc=0; out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" BETTERSTACK_API_TOKEN=dummy-token EGRESS_GW_SILENT_TF="$TF" EGRESS_GW_SILENT_NOW_EPOCH="$NOW" bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "row 8: tracing enabled with a bearer set -> exit 78"; else fail "row 8: tracing enabled with a bearer set -> expected 78 got $rc :: ${out:0:300}"; fi
if printf '%s' "$out" | grep -qF -- 'dummy-token'; then fail "xtrace refusal leaks the token"; else pass "xtrace refusal does not leak the token"; fi
rc=0; out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" BETTERSTACK_QUERY_PASSWORD=dummy-pass EGRESS_GW_SILENT_TF="$TF" bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "xtrace with only the query password set -> exit 78"; else fail "xtrace with only the query password set -> expected 78 got $rc"; fi

# ── harness row (a): a suite edit that must RED — the discriminating power of the healthy case ─
# Replace the shimmed incident payload with an empty list for the otherwise-PASSing fixture: the
# verdict MUST change. A probe (or a harness) that stayed green on this would be reading nothing.
reset_defaults; build_fixtures
printf '{"data":[],"pagination":{"next":null}}' > "$WORK/incidents.json"
run_case "harness (a): healthy case with the incident payload replaced by [] -> verdict changes (unknown)" 3
if [[ "$LAST_RC" -ne 0 ]]; then pass "harness (a): the healthy verdict is NOT reproduced on an empty payload"; else fail "harness (a): empty payload still PASSes (vacuous harness or probe)"; fi
# ... and the same property on the alerts side and the single read: neither may be skippable.
reset_defaults; build_fixtures; printf '{"data":[],"pagination":{"next":null}}' > "$WORK/alerts.json"
run_case "harness (a): empty alert listing on an otherwise healthy fixture -> action_required (the production alert is not in it)" 5
field_is "canary_alert_live=0"; field_is "prod_alert=absent"
reset_defaults; CANARY_INC=0; build_fixtures; printf '{"data":[],"pagination":{"next":null}}' > "$WORK/alerts.json"
run_case "harness (a): empty alert listing with the canary incident absent -> action_required, production alert absent" 5
field_is "canary_alert_live=0"; field_is "prod_alert=absent"

# ── production alert state, canary pause/age, resolver, soak-from-apply, EARLIEST, hygiene ──
for st in absent paused shape; do
  reset_defaults; PROD_ALERT=$st; build_fixtures
  run_case "production alert $st -> action_required (never a PASS over an alert that is not running)" 5
  verdict_is action_required; field_is "prod_alert=$st"
done
expect_out "a reverted shape names the old operator problem, not a revert recommendation" "ACTION REQUIRED:.*higher_than 0.*revert"
reset_defaults; PROD_ALERT=ok; ALERT_LIVE=1; CANARY_INC=0; CANARY_PAUSED=true; build_fixtures
run_case "canary alert live but PAUSED, no canary incident -> action_required that is NOT an evaluator finding" 5
field_is "canary_alert_live=1"; expect_out "the paused-canary message says PAUSED" 'PAUSED'; expect_not_out "the paused-canary message does not call the evaluator blind" 'blind'
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=300; build_fixtures
run_case "canary alert created 300 s ago, no incident yet -> not_yet (one evaluation cycle has not passed)" 2
verdict_is not_yet
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=1300; build_fixtures
run_case "canary alert created 1300 s ago, still no incident -> action_required (blind)" 5
expect_out "the aged-canary message names the blind evaluator" 'blind'
reset_defaults; RBY=actor; build_fixtures
run_case "anchor resolved by an actor (not by the alert recovering) -> action_required" 5
field_is "anchor_resolved_by=actor"; expect_not_out "the resolving actor is never printed" 'SECRETISH_RESOLVER'
reset_defaults; A_RES=open; CANARY_AGE=3000; build_fixtures
run_case "SOLEUR_FT_EARLIEST 4 h + 1 s ago and the anchor open -> action_required (the forwarded clock drives staleness)" 5 "SOLEUR_FT_EARLIEST=$(iso $((NOW - H4 - 1)))"
run_case "SOLEUR_FT_EARLIEST 4 h minus 1 s ago and the anchor open -> not_yet" 2 "SOLEUR_FT_EARLIEST=$(iso $((NOW - H4 + 1)))"
reset_defaults; build_fixtures
jq -c '.data |= map(if .id == "7001" then .attributes.started_at = null else . end)' "$WORK/incidents.json" > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "a null started_at on a listed incident -> unknown (never read as epoch 0)" 3
reset_defaults; build_fixtures
jq -c '.data |= map(if .id == "1047829421" then .attributes.started_at = "2026-01-01T00:00:00.000Z" else . end)' "$WORK/incidents.json" > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "the listed anchor disagrees with the single read on its start time -> unknown" 3
# off-host decoys: userinfo and suffix tricks, a relative next, and what the refusal may print
for nxt in "https://uptime.betterstack.com@evil.example/api/v2/incidents?page=2" "https://uptime.betterstack.com.evil.example/api/v2/incidents?page=2" "/api/v2/incidents?page=2&x=SECRETISH_Q"; do
  reset_defaults; build_fixtures
  jq -c --arg n "$nxt" '.pagination.next = $n' "$WORK/incidents.json" | jq -c '.data |= map(select(.id != "1047829421" and .id != "1031046761"))' > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
  run_case "off-host next [$nxt] is refused -> unknown" 3
  expect_no_calls "the bearer never rides to [$nxt]" "evil.example"
  expect_no_calls "no unexpected URL was requested for [$nxt]" "OFFHOST"
  expect_not_out "the refusal never prints a query string or path for [$nxt]" 'page=2|SECRETISH_Q|/api/v2'
done
# rows_in_window: untrusted host names are folded, credentials missing is said out loud
reset_defaults; A_RES=open; CANARY_AGE=3000; ROSTER_BQ='[{"host":"soleur-web-platform","n":"4"},{"host":"evil <b>@mention</b>","n":"2"},{"host":"","n":"3"}]'; build_fixtures
run_case "an untrusted host_name in the warehouse rows -> folded into other, never printed" 2
field_is "rows_in_window=other:5,soleur-web-2:0,soleur-web-platform:4"; expect_not_out "the hostile host_name is not printed" 'evil|mention|<b>'
reset_defaults; A_RES=open; CANARY_AGE=3000; build_fixtures
run_case "warehouse credentials unbound while the incident is open -> verdict unchanged, skip is said out loud" 2 BETTERSTACK_QUERY_PASSWORD=
field_is "rows_in_window=unknown"; expect_out "the skipped read is announced on stderr" 'rows_in_window skipped'
# the EXIT trap and the signal trap: a stray abort and a SIGTERM both end in a verdict line and exit 3, never 1
reset_defaults; build_fixtures; : > "$WORK/curl.term"
run_case "SIGTERM mid-run (signal trap) -> exit 3 with an unknown verdict line" 3
# (the stderr TRANSIENT line is lost here: the signal lands inside http_get, whose stderr is redirected to a scratch
# file; the verdict line on stdout is the contract)
verdict_is unknown; field_is "prod_alert=unknown"
reset_defaults; build_fixtures
# BASH_ENV reaches EVERY bash the probe starts (the curl stub is one): gate the DEBUG trap on being the probe itself.
printf '%s\n' "if [[ \$0 == *egress-gw-probe-silent-12180.sh ]]; then n=0; trap 'n=\$((n+1)); [[ \$n -eq 90 ]] && exit 1' DEBUG; fi" > "$WORK/abort.env"
run_case "a stray exit 1 in the main shell (EXIT trap) -> exit 3 with an unknown verdict line, never 1" 3 BASH_ENV="$WORK/abort.env"
verdict_is unknown; expect_out "the stray-abort path reports the probe ended without a verdict" 'ended without a verdict'

# ── source-level pins on the SUT (cheap, and they catch a refactor that drops a safeguard) ───
sut_code="$(grep -vE '^[[:space:]]*#' "$SUT")"
if grep -qE '^[[:space:]]*exit[[:space:]]+1([[:space:]]|$)' <<<"$sut_code"; then fail "the SUT contains a literal 'exit 1'"; else pass "the SUT contains no literal 'exit 1'"; fi
if grep -qE '^# RETIREMENT:' "$SUT"; then pass "the SUT header carries a RETIREMENT: line"; else fail "the SUT header lacks a RETIREMENT: line"; fi
retire_block="$(sed -n '/^# RETIREMENT:/,/^[^#]/p' "$SUT")"
for site in egress_gw_probe_silent_canary betterstack-logs-alerts.tf apply-web-platform-infra.yml EXPECT_BLOCKS MIN_PASSES betterstack-send-failed-alert-mutation.test.sh egress-gw-alert.test.sh cron-egress-blocked.md ADR-218 INTENDED_DESTROYS ack-destroy CENSUS_FLOOR_ALERTS betterstack-log-query.md infra-validation.yml; do
  if grep -qF -- "$site" <<<"$retire_block"; then pass "RETIREMENT header lists: $site"; else fail "RETIREMENT header lacks: $site"; fi
done
if grep -qE 'attributes\.name[[:space:]]*==' <<<"$sut_code"; then pass "incident matching is exact .attributes.name equality"; else fail "incident matching is not exact .attributes.name equality"; fi
if grep -qE 'startswith|test\(|contains\(|ascii_downcase' <<<"$sut_code"; then fail "the SUT uses a fuzzy string match (startswith/test/contains)"; else pass "the SUT uses no fuzzy string match"; fi

# ── floor ────────────────────────────────────────────────────────────────────────────────────
# Exact baseline, reported via printf+exit: a block of rows that stopped executing must not read as green.
# Re-pin deliberately when rows are added; never lower it to fit a deletion.
MIN_ASSERTIONS=203
if [[ "$total" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: only %s assertions ran (floor %s) -- a block of rows stopped executing\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [[ "$total" -ne "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: %s assertions ran, expected exactly %s (re-pin MIN_ASSERTIONS after a deliberate change)\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf '\n%s assertions, %s failed (floor %s)\n' "$total" "$fails" "$MIN_ASSERTIONS"
[[ "$fails" -eq 0 ]]
