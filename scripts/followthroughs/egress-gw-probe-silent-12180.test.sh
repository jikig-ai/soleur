#!/usr/bin/env bash
# Exit-code harness for egress-gw-probe-silent-12180.sh (#12180 soak follow-through; floor and soak clock: #12189).
#
# The follow-through's exit code IS its authorization artifact: sweep-followthroughs.sh CLOSES the
# tracker on 0, comments ACTION REQUIRED on 5, retries on 2/3/78, and reads a 1 as FAIL (reopening
# a human-closed tracker). The cardinal sins this suite pins: a vacuous 0 (a PASS on an unanswered
# read, a truncated incident list, a soak that has not run its 4 h, a missing canary incident, a
# canary still declared, a roster host with no rows, or a recurrence), an exit 1, and a public comment
# that echoes a response body or a credential.
#
# Guard 2 of knowledge-base/project/plans/archive/20261106-090533-2026-11-05-fix-egress-gw-probe-silent-invert-metric-plan.md
# (verdict matrix, 11 rows + harness rows), amended by the 2026-11-06 floor plan: the recurrence floor
# is the PINNED apply time (APPLY_FLOOR_EPOCH, test seam EGRESS_GW_SILENT_FLOOR_EPOCH), one soak clock
# (quiet_since) replaces the three age gates, the anchor's resolve actor is informational, and the
# pass path requires rows on both roster hosts. The SUT runs under `env -i` exactly as the sweeper runs
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
QUIET_STALE=15300         # the SUT's open-incident horizon past the quiet origin (4 h + 15 min grace)
SLACK=300                 # the SUT's recurrence slack before the floor

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
# curl.term: signal the PROBE's main shell, then keep it waiting. The target is the pid the runner recorded for the
# probe (run_case execs the SUT behind a pid-recording shell), never an ancestor walk or a $PPID hop.
if [[ -f "$cfg/curl.term" && -s "$cfg/probe.pid" ]]; then
  kill -TERM "$(<"$cfg/probe.pid")" 2>/dev/null
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
alert() { # <name> <paused> [operator] [value] [created_epoch]   (updated_at is vendor churn: ALERT_UPDATED, default NOW)
  jq -nc --arg n "$1" --argjson p "${2:-false}" --arg op "${3:-higher_than}" --argjson v "${4:-0}" --arg ca "$(iso "${5:-$((NOW - 100000))}")" --arg ua "$(iso "${ALERT_UPDATED:-$NOW}")" \
    '{id:"1",type:"alert",attributes:{name:$n,paused:$p,operator:$op,value:$v,created_at:$ca,updated_at:$ua}}'
}
patch() { # <file> <jq filter> [jq args...]  -- a fixture edit that fails to apply is a failure, never a silent no-op
  local f="$1" flt="$2" before; shift 2
  before="$(cat "$f" 2>/dev/null)"
  if jq -c "$@" "$flt" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; then
    [[ "$(cat "$f")" != "$before" ]] || fail "fixture patch changed nothing: ${flt:0:70}"
  else fail "fixture patch did not apply: ${flt:0:70}"; fi
}
make_mutant() { # <out> <old> <new> -- a copy of the probe with exactly ONE occurrence replaced; a mutant that does not land is a failure
  local out="$1" old="$2" new="$3"
  if OLD="$old" NEW="$new" python3 - "$SUT" "$out" <<'PYEOF'
import os, sys
s = open(sys.argv[1]).read()
o, n = os.environ["OLD"], os.environ["NEW"]
assert s.count(o) == 1, "anchor count %d" % s.count(o)
open(sys.argv[2], "w").write(s.replace(o, n))
PYEOF
  then chmod 0755 "$out"; else fail "probe mutant did not land: ${old:0:60}"; fi
}

# The default fixture is the REAL exit-0 shape: the apply (the floor) was FLOOR_AGE seconds ago, the anchor was resolved
# through the API before it, a pre-floor resolved decoy shaped like incident 1048111600 sits in the list, the canary
# incident started 64 s before the floor, the canary alert is deleted and no longer declared, both roster hosts emit.
reset_defaults() {
  ANCHOR_ID=1047829421
  FLOOR_AGE=20000                # the floor is NOW minus this
  A_START=$((NOW - 30017))       # before the floor in every row that keeps FLOOR_AGE <= 30017
  A_RES=$((NOW - 25000))         # resolved BEFORE the floor (or `open`)
  CANARY_INC=1                   # a canary incident exists
  CANARY_INC2=0                  # a second, older canary incident (predates the floor bound)
  CANARY_BEFORE=64               # ... that started this many seconds before the floor
  NEWER=0                        # a production incident near/after the floor
  NEWER_OFF=1000                 # ... started this many seconds after the floor (negative = before)
  NEWER_RES_OFF=open             # ... and resolved this many seconds after the floor (`open` = still open)
  PREOPEN=0                      # an extra production incident that started BEFORE the floor
  PREOPEN_RES_OFF=open           # ... `open`, or resolved this many seconds after the floor
  ALERT_LIVE=0                   # canary alert is NOT in the live listing (the real end state: deleted after it fired)
  CANARY_PAUSED=false            # when the canary alert is listed, is it paused
  CANARY_ALERT_AGE=""            # ... and how old is it (empty = created 100 s after the floor)
  PROD_ALERT=ok                  # ok | absent | paused | shape (operator/value reverted)
  RBY=actor                      # who resolved the anchor: actor (the API, as observed) | none (the alert)
  DECLARED=0                     # canary no longer declared in the .tf
  ALERT_UPDATED=$NOW             # vendor churn: the SUT must never read it
  ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"},{"host":"soleur-web-2","n":"39"}]'
  PAGES=1
}

write_tf() { # <declared 0|1>
  {
    printf 'locals {\n  egress_gw_probe_silent_sql = "x"\n}\n'
    printf '# resource "logtail_exploration_alert" "egress_gw_probe_silent_canary" {   <- a comment, not a declaration\n'
    printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent" {\n  name = "%s"\n}\n' "$PROD_NAME"
    printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent_canary_old" {\n  name = "decoy"\n}\n'
    case "$1" in
      1) printf 'resource "logtail_exploration_alert" "egress_gw_probe_silent_canary" {\n  name = "%s"\n}\n' "$CANARY_NAME" ;;
      2) printf 'resource "logtail_exploration" "egress_gw_probe_silent_canary" {\n  name = "x"\n}\n' ;;      # alert gone, exploration left
      3) printf 'locals {\n  egress_gw_probe_silent_canary_sql = replace("a", "b", "c")\n}\n' ;;            # alert and exploration gone, SQL local left
      4) printf '// resource "logtail_exploration_alert" "egress_gw_probe_silent_canary" {   <- a // comment, not a declaration\n' ;;
    esac
  } > "$TF"
}

build_fixtures() {
  local objs=() old_id=1031046761 decoy_id=1048111600 ca pre_res new_res
  FLOOR=$((NOW - FLOOR_AGE))
  objs+=("$(inc "$ANCHOR_ID" "$PROD_NAME" "$A_START" "$([[ "$A_RES" == open ]] && echo '' || echo "$A_RES")" "HTTP 503 SECRETISH_CAUSE" "$RBY")")
  objs+=("$(inc "$old_id" "$PROD_NAME" $((A_START - 1728000)) $((A_START - 600)))")
  # the 1048111600 shape: the OLD alert shape flapping, production name, started and resolved BEFORE the floor, resolved_by null.
  objs+=("$(inc "$decoy_id" "$PROD_NAME" $((FLOOR - 5000)) $((FLOOR - 1000)))")
  objs+=("$(inc 7001 "soleur apex" $((NOW - 13000)) "" "HTTP 503")")
  # exact-name decoys: a name that merely CONTAINS the prod name, and a cause that quotes it.
  objs+=("$(inc 7002 "${PROD_NAME}-copy" $((NOW - 12000)) "" "x")")
  objs+=("$(inc 7003 "Some other alert" $((NOW - 11000)) "" "quotes ${PROD_NAME} and ${CANARY_NAME} in its cause")")
  [[ "$CANARY_INC" == 1 ]] && objs+=("$(inc 5555 "$CANARY_NAME" $((FLOOR - CANARY_BEFORE)) "" "THROWAWAY CANARY (#12180)")")
  [[ "$CANARY_INC2" == 1 ]] && objs+=("$(inc 5556 "$CANARY_NAME" $((FLOOR - 5000)) "" "THROWAWAY CANARY (#12180)")")
  if [[ "$NEWER" == 1 ]]; then
    new_res=""; [[ "$NEWER_RES_OFF" != open ]] && new_res=$((FLOOR + NEWER_RES_OFF))
    objs+=("$(inc 9090 "$PROD_NAME" $((FLOOR + NEWER_OFF)) "$new_res" "recurrence")")
  fi
  if [[ "$PREOPEN" == 1 ]]; then
    pre_res=""; [[ "$PREOPEN_RES_OFF" != open ]] && pre_res=$((FLOOR + PREOPEN_RES_OFF))
    objs+=("$(inc 9191 "$PROD_NAME" $((FLOOR - 7000)) "$pre_res" "older than the apply")")
  fi
  local all; all="$(printf '%s\n' "${objs[@]}" | jq -sc 'sort_by(.attributes.started_at) | reverse')"
  if [[ "$PAGES" == 1 ]]; then
    jq -nc --argjson d "$all" '{data:$d,pagination:{next:null}}' > "$WORK/incidents.json"
  else
    # page 1 = the newest 3, page 2 = the rest (carries the anchor); page 2 points at a page 3 that
    # does NOT exist: a probe that does not stop at the anchor would request it and read a 500.
    jq -nc --argjson d "$all" '{data:$d[:3],pagination:{next:"https://uptime.betterstack.com/api/v2/incidents?page=2"}}' > "$WORK/incidents.json"
    jq -nc --argjson d "$all" '{data:$d[3:],pagination:{next:"https://uptime.betterstack.com/api/v2/incidents?page=3"}}' > "$WORK/incidents.p2.json"
    # the anchor must stay on page 2: the decoy and the extra fixtures above must not push it onto page 1
    if ! jq -e '.data | any(.id == "'"$ANCHOR_ID"'")' "$WORK/incidents.p2.json" >/dev/null 2>&1; then fail "fixture: the anchor is not on page 2 of the PAGES=2 split"; fi
  fi
  jq -nc --argjson d "$(inc "$ANCHOR_ID" "$PROD_NAME" "$A_START" "$([[ "$A_RES" == open ]] && echo '' || echo "$A_RES")" "HTTP 503 SECRETISH_CAUSE" "$RBY")" '{data:$d}' > "$WORK/single.json"
  ca=$((FLOOR + 100)); [[ -n "$CANARY_ALERT_AGE" ]] && ca=$((NOW - CANARY_ALERT_AGE))
  {
    alert "Output utilization high" true
    case "$PROD_ALERT" in
      ok) alert "$PROD_NAME" false ;;
      paused) alert "$PROD_NAME" true ;;
      shape) alert "$PROD_NAME" false lower_than 2 ;;
      shape_gt1) alert "$PROD_NAME" false higher_than 1 ;;
      shape_lt0) alert "$PROD_NAME" false lower_than 0 ;;
      absent) : ;;
    esac
    alert "${CANARY_NAME}-old" false
    [[ "$ALERT_LIVE" == 1 ]] && alert "$CANARY_NAME" "$CANARY_PAUSED" higher_than 0 "$ca"
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
      EGRESS_GW_SILENT_NOW_EPOCH="$NOW" EGRESS_GW_SILENT_ANCHOR_ID="$ANCHOR_ID" EGRESS_GW_SILENT_FLOOR_EPOCH="$FLOOR" \
      EGRESS_GW_SILENT_ROSTER="soleur-web-platform soleur-web-2" "$@" \
      bash -c 'printf "%s" "$$" > "$1"; shift; if [[ -n "${EGS_DROP_STDERR:-}" ]]; then exec "$@" 2>/dev/null; fi; exec "$@"' _ "$WORK/probe.pid" "${RUN_SUT:-$SUT}" 2>&1)" || rc=$?
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

ROWS_BOTH='rows_in_window=soleur-web-2:39,soleur-web-platform:41'

# ── 0. The canonical PASS and the full verdict-line format ───────────────────────────────────
reset_defaults; build_fixtures
run_case "compliant fixture (the real exit-0 shape: floor 20000 s ago, anchor resolved by the API before it, canary alert deleted) -> PASS" 0
verdict_is pass
expect_out "PASS verdict line has all twelve fields in the pinned order, the two appended ones digits or a fixed token" \
  '^SOLEUR_EGRESS_GW_SILENT_SOAK verdict=pass prod_incident=resolved resolved_age_s=[0-9]+ newer_prod_incident=0 canary=fired canary_alert_live=0 canary_declared=0 prod_alert=ok anchor_resolved_by=(none|actor|unknown) rows_in_window=[A-Za-z0-9._:,-]+ quiet_age_s=([0-9]+|-1) pre_floor_open_prod_incident=(0|1|unknown)$'
field_is "prod_incident=resolved"; field_is "resolved_age_s=25000"; field_is "newer_prod_incident=0"
field_is "canary=fired"; field_is "canary_alert_live=0"; field_is "canary_declared=0"; field_is "prod_alert=ok"
field_is "anchor_resolved_by=actor"; field_is "$ROWS_BOTH"; field_is "quiet_age_s=20000"; field_is "pre_floor_open_prod_incident=0"
expect_not_out "output never reprints raw incident fields (public comment)" 'SECRETISH_'
expect_not_out "output never carries the credentials" 'dummy-(token|user|pass)'
expect_calls "the pass path reads the warehouse (rows on both roster hosts are verdict-bearing)" "BQ "
if grep -qF -- 'header = "Authorization: Bearer dummy-token"' "$WORK/stdin.log"; then pass "the bearer header arrives on curl stdin"; else fail "the bearer header arrives on curl stdin"; fi
expect_no_calls "the token is absent from every curl argv" "dummy-token"
expect_calls "the single-incident read targets the anchor id" "/api/v2/incidents/1047829421"
expect_calls "the live alert listing is read from the telemetry host" "telemetry.betterstack.com/api/v2/alerts"
expect_no_calls "no request leaves the two pinned hosts" "OFFHOST"
# the same twelve-field order holds on a verdict the probe never got past setup on (an unset credential)
run_case "BETTERSTACK_API_TOKEN unset -> unknown (field-order probe)" 3 BETTERSTACK_API_TOKEN=
expect_out "an unknown verdict line keeps the twelve-field order and only fixed tokens" \
  '^SOLEUR_EGRESS_GW_SILENT_SOAK verdict=unknown prod_incident=unknown resolved_age_s=-1 newer_prod_incident=unknown canary=unknown canary_alert_live=unknown canary_declared=unknown prod_alert=unknown anchor_resolved_by=unknown rows_in_window=na quiet_age_s=-1 pre_floor_open_prod_incident=unknown$'
# fixture precondition: the 1048111600-shaped decoy (production name, before the floor, resolved, resolved_by null) is in the list
reset_defaults; build_fixtures
if jq -e '.data | any(.id == "1048111600" and .attributes.name == "'"$PROD_NAME"'" and .attributes.resolved_at != null and .attributes.resolved_by == null)' "$WORK/incidents.json" >/dev/null; then
  pass "fixture: the default list carries a resolved, pre-floor, resolved_by-null production incident shaped like 1048111600"
else fail "fixture: the 1048111600-shaped decoy is missing from the default list"; fi

# The canary alert still LIVE after its incident was seen and the declaration is gone: the deletion did not apply -> action_required.
reset_defaults; ALERT_LIVE=1; build_fixtures
run_case "canary incident seen, declaration gone, but the canary alert is still live -> action_required (the deletion did not apply)" 5
field_is "canary_alert_live=1"; expect_out "the message says to delete the canary" 'ACTION REQUIRED:.*delete the canary'

# ── the soak clock: quiet_since = max(floor, latest production resolve); the 4 h gate on non-collinear points ───────────
reset_defaults; FLOOR_AGE=$((H4 - 1000)); build_fixtures
run_case "floor 4 h minus 1000 s ago (everything else true) -> not_yet" 2
reset_defaults; FLOOR_AGE=$((H4 - 1)); A_START=$((NOW - 55555)); A_RES=$((NOW - 33333)); CANARY_BEFORE=120; build_fixtures
run_case "row 1: floor 4 h minus 1 s ago -> not_yet" 2
verdict_is not_yet; field_is "quiet_age_s=$((H4 - 1))"; field_is "prod_incident=resolved"
expect_out "the not_yet message names the soak" 'TRANSIENT:.*soak'
reset_defaults; ANCHOR_ID=1047829999; FLOOR_AGE=$H4; A_START=$((NOW - 41111)); A_RES=$((NOW - 36000)); CANARY_BEFORE=200; PAGES=2; build_fixtures
run_case "floor exactly 4 h ago (different ids and timestamps) -> PASS" 0
verdict_is pass; field_is "quiet_age_s=$H4"
reset_defaults; ANCHOR_ID=1047828888; FLOOR_AGE=$((H4 + 1)); A_START=$((NOW - 29999)); A_RES=$((NOW - 22222)); CANARY_BEFORE=10; build_fixtures
run_case "floor 4 h plus 1 s ago (different ids and timestamps) -> PASS" 0
verdict_is pass; field_is "quiet_age_s=$((H4 + 1))"
reset_defaults; FLOOR_AGE=100; build_fixtures
run_case "floor 100 s ago -> not_yet" 2
field_is "quiet_age_s=100"
# the anchor resolved AFTER the floor moves the origin: quiet_since is its resolve (boundary pair, non-collinear)
reset_defaults; A_RES=$((NOW - H4 + 1)); build_fixtures
run_case "anchor resolved after the floor, 4 h minus 1 s ago -> not_yet (quiet_since is the resolve)" 2
field_is "quiet_age_s=$((H4 - 1))"; field_is "resolved_age_s=$((H4 - 1))"
reset_defaults; ANCHOR_ID=1047829999; FLOOR_AGE=18000; A_START=$((NOW - 41111)); A_RES=$((NOW - H4)); build_fixtures
run_case "anchor resolved after the floor, exactly 4 h ago (other fixture) -> PASS" 0
field_is "quiet_age_s=$H4"
reset_defaults; ANCHOR_ID=1047828888; FLOOR_AGE=17000; A_START=$((NOW - 29999)); A_RES=$((NOW - H4 - 1)); build_fixtures
run_case "anchor resolved after the floor, 4 h plus 1 s ago (third fixture) -> PASS" 0
field_is "quiet_age_s=$((H4 + 1))"
reset_defaults; A_RES=$((NOW - 10)); build_fixtures
run_case "anchor resolved 10 s ago, after the floor -> not_yet" 2
reset_defaults; A_RES=$((NOW - 7200)); DECLARED=1; build_fixtures
run_case "inside the 4 h window with the canary still declared -> not_yet (the window is not over)" 2
verdict_is not_yet
# the not_yet is decided BEFORE the warehouse is read: a dead warehouse must not turn a held soak into an unknown
reset_defaults; FLOOR_AGE=100; build_fixtures; printf '7' > "$WORK/bq.rc"
run_case "soak not complete AND the warehouse read fails -> not_yet, the rows step comes after the soak gate" 2
reset_defaults; ANCHOR_ID=1047829999; FLOOR_AGE=5000; A_START=$((NOW - 41111)); build_fixtures; printf '28' > "$WORK/bq.rc"
run_case "soak not complete (other fixture) AND the warehouse read fails -> not_yet" 2

# ── anchor resolve actor is informational: it never changes a verdict ───────────────────────
reset_defaults; RBY=none; build_fixtures
run_case "anchor resolved by the alert (resolved_by null) -> PASS" 0
field_is "anchor_resolved_by=none"
reset_defaults; build_fixtures
run_case "anchor resolved by an actor -> PASS, the field says actor" 0
field_is "anchor_resolved_by=actor"; expect_not_out "the resolving actor is never printed" 'SECRETISH_RESOLVER'
reset_defaults; build_fixtures
patch "$WORK/single.json" '.data.attributes |= del(.resolved_by)'
run_case "the anchor response carries no resolved_by key -> PASS, the field says unknown" 0
field_is "anchor_resolved_by=unknown"
# vendor churn: alert updated_at is never read (a far-future and an ancient value leave the verdict unchanged)
reset_defaults; ALERT_UPDATED=$((NOW + 9999999)); build_fixtures
run_case "every alert carries an updated_at far in the future -> PASS, updated_at is never read" 0
reset_defaults; ALERT_UPDATED=1; build_fixtures
run_case "every alert carries an updated_at of 1970 -> PASS, updated_at is never read" 0
# SOLEUR_FT_EARLIEST is no longer an input
reset_defaults; build_fixtures
run_case "a FRESH SOLEUR_FT_EARLIEST on a compliant fixture -> PASS (the sweeper date is ignored)" 0 "SOLEUR_FT_EARLIEST=$(iso $((NOW - 100)))"
run_case "an ANCIENT SOLEUR_FT_EARLIEST on a compliant fixture -> PASS" 0 "SOLEUR_FT_EARLIEST=2020-01-01"
reset_defaults; PREOPEN=1; FLOOR_AGE=3000; build_fixtures
run_case "a pre-floor open incident with an ANCIENT SOLEUR_FT_EARLIEST -> not_yet (the old clock would have said stale)" 2 "SOLEUR_FT_EARLIEST=2020-01-01"
run_case "the same with SOLEUR_FT_EARLIEST=now -> not_yet" 2 "SOLEUR_FT_EARLIEST=now"

# ── a production incident that started BEFORE the floor ────────────────────────────────────────
# open: blocks a pass; exit 2 inside quiet_since + 15300, exit 5 past it
reset_defaults; A_RES=open; FLOOR_AGE=3000; build_fixtures
run_case "anchor open (it started before the floor), not yet stale -> not_yet" 2
verdict_is not_yet; field_is "prod_incident=open"; field_is "resolved_age_s=-1"; field_is "pre_floor_open_prod_incident=1"; field_is "quiet_age_s=3000"
field_is "$ROWS_BOTH"
expect_calls "an open pre-floor incident -> warehouse read keyed on the emitter tag" "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'"
expect_calls "rows read groups by host_name" "JSONExtractString(raw, 'host_name') AS host"
expect_calls "rows read spans hot window UNION archive" "s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1"
expect_calls "rows read is the trailing 15 minutes (the alert's own window)" "dt >= '$(date -u -d "@$((NOW - 900))" '+%Y-%m-%d %H:%M:%S')' AND dt <= '$(date -u -d "@$NOW" '+%Y-%m-%d %H:%M:%S')'"
expect_not_out "rows_in_window prints counts, never row content" 'raw|message'
# row 11: open past the horizon, one roster host has no rows -> the field names it; verdict is action_required
reset_defaults; A_RES=open; FLOOR_AGE=17000; ROSTER_BQ='[{"host":"soleur-web-platform","n":"288"}]'; build_fixtures
run_case "row 11: open past the horizon with web-2 missing from rows -> action_required" 5
verdict_is action_required; field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:288"
expect_out "the ACTION REQUIRED line names the poller (#12190)" 'ACTION REQUIRED:.*12190'
reset_defaults; A_RES=open; FLOOR_AGE=$QUIET_STALE; build_fixtures
run_case "anchor open, quiet origin exactly 15300 s ago -> not_yet (the horizon is exclusive)" 2
reset_defaults; A_RES=open; FLOOR_AGE=$((QUIET_STALE + 1)); build_fixtures
run_case "anchor open, quiet origin 15301 s ago -> action_required" 5
field_is "$ROWS_BOTH"
reset_defaults; ANCHOR_ID=1047827777; A_START=$((NOW - 70000)); A_RES=open; FLOOR_AGE=$QUIET_STALE; ROSTER_BQ='[{"host":"soleur-web-platform","n":"5"}]'; build_fixtures
run_case "anchor open, other fixture, exactly at the horizon -> not_yet" 2
# a NON-anchor open production incident that started before the floor blocks the same way (the anchor is resolved)
reset_defaults; PREOPEN=1; FLOOR_AGE=3000; build_fixtures
run_case "a non-anchor pre-floor incident is open -> not_yet" 2
field_is "pre_floor_open_prod_incident=1"; field_is "prod_incident=resolved"
reset_defaults; PREOPEN=1; FLOOR_AGE=$QUIET_STALE; build_fixtures
run_case "non-anchor pre-floor open incident, quiet origin exactly 15300 s ago -> not_yet" 2
reset_defaults; PREOPEN=1; FLOOR_AGE=$((QUIET_STALE + 1)); build_fixtures
run_case "non-anchor pre-floor open incident, quiet origin 15301 s ago -> action_required" 5
expect_out "the stale message names the poller (#12190)" 'ACTION REQUIRED:.*12190'
# the warehouse read is diagnostic only here: its failure must not change the verdict
reset_defaults; A_RES=open; FLOOR_AGE=3000; build_fixtures; printf '7' > "$WORK/bq.rc"
run_case "warehouse read fails while an incident is open -> verdict unchanged (not_yet)" 2
field_is "rows_in_window=unknown"; expect_not_out "a failed warehouse read prints no credential" 'dummy-(user|pass|token)'; expect_not_out "a failed warehouse read prints no exception text" 'Authentication'
# a pre-floor incident that resolved AFTER the floor moves quiet_since (boundary pair on non-collinear fixtures)
reset_defaults; PREOPEN=1; PREOPEN_RES_OFF=100; FLOOR_AGE=14499; build_fixtures
run_case "pre-floor incident resolved 100 s after the floor, quiet 14399 s -> not_yet" 2
field_is "quiet_age_s=14399"; field_is "pre_floor_open_prod_incident=0"
reset_defaults; ANCHOR_ID=1047829999; A_START=$((NOW - 41111)); PREOPEN=1; PREOPEN_RES_OFF=700; FLOOR_AGE=15100; build_fixtures
run_case "pre-floor incident resolved 700 s after the floor, quiet exactly 14400 s (other fixture) -> PASS" 0
field_is "quiet_age_s=$H4"

# ── the recurrence floor: a pinned apply time minus 300 s of slack ───────────────────────────
reset_defaults; build_fixtures
run_case "the pre-floor resolved decoy (shaped like 1048111600) never counts -> PASS" 0
field_is "newer_prod_incident=0"
reset_defaults; NEWER=1; build_fixtures
run_case "row 5: a production incident started after the floor, listed beside the compliant pre-floor decoy -> action_required" 5
verdict_is action_required; field_is "newer_prod_incident=1"
expect_out "recurrence message projects id and name only" '9090'
expect_not_out "recurrence message never reprints raw fields" 'SECRETISH_'
expect_calls "a recurrence triggers the rows_in_window read" "BQ "
reset_defaults; NEWER=1; A_RES=open; FLOOR_AGE=3000; build_fixtures
run_case "recurrence while the anchor is open -> action_required" 5
# slack boundary pair, non-collinear: floor minus 300 counts, floor minus 301 does not
reset_defaults; NEWER=1; NEWER_OFF=-300; NEWER_RES_OFF=-100; build_fixtures
run_case "incident started exactly floor minus 300 s (resolved before the floor) -> action_required (it counts)" 5
field_is "newer_prod_incident=1"
reset_defaults; ANCHOR_ID=1047829999; A_START=$((NOW - 41111)); FLOOR_AGE=21000; NEWER=1; NEWER_OFF=-301; NEWER_RES_OFF=-250; build_fixtures
run_case "incident started floor minus 301 s (resolved before the floor, other fixture) -> PASS (it does not count)" 0
field_is "newer_prod_incident=0"
reset_defaults; ANCHOR_ID=1047828888; A_START=$((NOW - 33333)); FLOOR_AGE=22000; NEWER=1; NEWER_OFF=-299; NEWER_RES_OFF=-10; build_fixtures
run_case "incident started floor minus 299 s (third fixture) -> action_required" 5
# a second incident in the anchor's own second is pre-floor now: it is judged by the floor, not by the anchor's start
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data += [{id:"9191",type:"incident",attributes:{name:"soleur-egress-gw-probe-silent-prd",started_at:$s,resolved_at:$r,cause:"x"}}]' --arg s "$(iso "$A_START")" --arg r "$(iso $((A_START + 60)))"
run_case "a second RESOLVED production incident in the anchor's own second (before the floor) -> PASS, not a recurrence" 0
field_is "newer_prod_incident=0"
reset_defaults; build_fixtures
run_case "the decoys (name contains prod name; cause quotes it; canary-named incident) are NOT a recurrence" 0
field_is "newer_prod_incident=0"

# ── row 3 / row 10: canary incident absent ───────────────────────────────────────────────────
reset_defaults; CANARY_INC=0; ALERT_LIVE=1; build_fixtures
run_case "row 3: no canary incident, canary alert live -> action_required (evaluator blind)" 5
verdict_is action_required; field_is "canary=absent"; field_is "canary_alert_live=1"
expect_out "blind-evaluator message names the poller" 'ACTION REQUIRED:.*blind.*12190'
reset_defaults; CANARY_INC=0; ALERT_LIVE=0; DECLARED=1; build_fixtures
run_case "row 10: no canary incident, no live canary alert, still declared -> action_required (the apply never created it)" 5
field_is "canary=absent"; field_is "canary_alert_live=0"; field_is "canary_declared=1"
expect_out "row 10 names the apply, not an evaluator finding" 'ACTION REQUIRED:.*(apply|create)'
expect_not_out "row 10 does not claim the evaluator is blind" 'blind'
expect_out "the declared message says deleted or never created" 'DELETED or NEVER CREATED'
# the retired canary: alert absent, not declared, incident no longer listed -> a DISTINCT exit 5, never a pass
reset_defaults; CANARY_INC=0; ALERT_LIVE=0; DECLARED=0; build_fixtures
run_case "retired canary (alert absent, not declared, incident not listed) -> action_required, never a pass" 5
verdict_is action_required; field_is "canary=absent"; field_is "canary_declared=0"
expect_out "the retired message says retired and asks for a hand close" 'ACTION REQUIRED:.*retired.*by hand'
expect_not_out "the retired message is not the apply-never-created text" 'DELETED or NEVER CREATED|apply|create'
expect_not_out "the retired message does not call the evaluator blind" 'blind'
# the canary check does not wait for the soak: a held pre-floor incident and an absent canary -> 5, not 2
reset_defaults; A_RES=open; FLOOR_AGE=3000; CANARY_INC=0; ALERT_LIVE=1; build_fixtures
run_case "canary absent while the anchor is still open -> action_required (no waiting)" 5
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

# ── rows on both roster hosts are verdict-bearing on the pass path ───────────────────────────
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"}]'; build_fixtures
run_case "one roster host (web-2) has no rows in the window -> action_required, never a pass" 5
verdict_is action_required; field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:41"
expect_out "the message says a roster host has no rows" 'ACTION REQUIRED:.*no rows'
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"},{"host":"soleur-web-2","n":"0"}]'; build_fixtures
run_case "a roster host reported with an explicit zero count -> action_required" 5
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"5"},{"host":"soleur-extra-host","n":"50"}]'; build_fixtures
run_case "an extra non-roster host cannot cover a missing roster host -> action_required" 5
field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:5,soleur-extra-host:50"
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"},{"host":"soleur-web-2","n":"39"},{"host":"soleur-extra-host","n":"7"}]'; build_fixtures
run_case "an extra non-roster host beside both roster hosts is permitted -> PASS" 0
reset_defaults; ROSTER_BQ='[]'; build_fixtures
run_case "harness (a): the compliant fixture with the warehouse mock answering no rows at all -> action_required (the verdict changes)" 5
if [[ "$LAST_RC" -ne 0 ]]; then pass "harness (a): the healthy verdict is NOT reproduced on an empty warehouse answer"; else fail "harness (a): an empty warehouse answer still PASSes (vacuous rows step)"; fi
# every unreadable-warehouse mode on the pass path is unknown (3), one loop over the mock modes
for mode in rc nonrow nocred noroster; do
  reset_defaults; build_fixtures
  extra=()
  case "$mode" in
    rc) printf '7' > "$WORK/bq.rc" ;;
    nonrow) printf '%s\n' 'DB::Exception: Code 62. a bare mid-stream error line' > "$WORK/bq.json" ;;
    nocred) extra=(BETTERSTACK_QUERY_PASSWORD=) ;;
    noroster) extra=("EGRESS_GW_SILENT_ROSTER= ") ;;
  esac
  run_case "pass path, warehouse mode $mode -> unknown (a pass is never granted over an unproven roster)" 3 "${extra[@]}"
  verdict_is unknown; field_is "rows_in_window=unknown"
  expect_not_out "warehouse mode $mode prints no credential or exception text" 'dummy-(user|pass|token)|Authentication|Code 62'
done

# ── the floor and the setup checks (all unknown, exit 3) ─────────────────────────────────────
reset_defaults; build_fixtures
run_case "floor one second after the clock -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=$((NOW + 1))"
run_case "floor far after the clock (other value) -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=$((NOW + 100000))"
run_case "floor one second before the anchor's start -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=$((A_START - 1))"
run_case "floor 1000 s before the anchor's start (other value) -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=$((A_START - 1000))"
run_case "a non-numeric floor -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=yesterday"
run_case "a thirteen-digit floor is refused (digit cap) -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH=1793816817000"
run_case "a leading-zero floor is canonicalised, not read as octal -> PASS" 0 "EGRESS_GW_SILENT_FLOOR_EPOCH=0${FLOOR}"
run_case "the floor seam unset: the PINNED apply time applies and lies after this suite's clock -> unknown" 3 "EGRESS_GW_SILENT_FLOOR_EPOCH="
# the floor equal to the anchor's start is allowed (start <= floor)
reset_defaults; FLOOR_AGE=30017; A_RES=$((NOW - 35000)); build_fixtures
run_case "floor equal to the anchor's start -> PASS" 0
# a LISTED canary alert: created_at must be a time at or after floor minus slack (checked while the alert is listed)
for mode in missing unparseable early; do
  reset_defaults; ALERT_LIVE=1
  [[ "$mode" == early ]] && CANARY_ALERT_AGE=$((FLOOR_AGE + SLACK + 1))
  build_fixtures
  case "$mode" in
    missing) patch "$WORK/alerts.json" '.data |= map(if .attributes.name == $n then .attributes |= del(.created_at) else . end)' --arg n "$CANARY_NAME" ;;
    unparseable) patch "$WORK/alerts.json" '.data |= map(if .attributes.name == $n then .attributes.created_at = "not-a-time" else . end)' --arg n "$CANARY_NAME" ;;
  esac
  run_case "listed canary alert, created_at $mode -> unknown" 3
  verdict_is unknown
done
reset_defaults; ALERT_LIVE=1; CANARY_ALERT_AGE=$((FLOOR_AGE + SLACK)); build_fixtures
run_case "listed canary alert created exactly floor minus slack -> accepted (action_required: delete it)" 5
expect_out "an accepted young-enough canary alert still asks for the deletion" 'ACTION REQUIRED:.*delete the canary'
reset_defaults; ALERT_LIVE=1; build_fixtures
patch "$WORK/alerts.json" '.data += [.data[] | select(.attributes.name == $n)]' --arg n "$CANARY_NAME"
run_case "two canary alerts are listed -> unknown" 3
# the canary incident bounds the pin from above: floor <= canary start + slack
reset_defaults; CANARY_BEFORE=$((SLACK + 1)); build_fixtures
run_case "canary incident started floor minus 301 s -> unknown (the pin sits after the canary by more than the slack)" 3
reset_defaults; ANCHOR_ID=1047829999; A_START=$((NOW - 41111)); CANARY_BEFORE=$SLACK; build_fixtures
run_case "canary incident started exactly floor minus 300 s (other fixture) -> PASS" 0
reset_defaults; CANARY_INC2=1; build_fixtures
run_case "two canary incidents, the earlier one predates the bound (a re-created canary needs a re-pin) -> unknown" 3
# the single anchor read and the list must agree on whether the anchor is resolved
reset_defaults; build_fixtures
patch "$WORK/single.json" '.data.attributes.resolved_at = null'
run_case "single read says the anchor is open, the list says resolved -> unknown" 3
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "1047829421" then .attributes.resolved_at = null else . end)'
run_case "single read says the anchor is resolved, the list says open -> unknown" 3
# an unparseable (or future) resolved_at on a listed production incident is never read as open or as quiet
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "1048111600" then .attributes.resolved_at = "garbage" else . end)'
run_case "an unparseable resolved_at on a listed production incident -> unknown, never read as open" 3
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "1048111600" then .attributes.resolved_at = $f else . end)' --arg f "$(iso $((NOW + 500)))"
run_case "a production incident resolved in the future -> unknown" 3

# ── row 2: truncation / paging ───────────────────────────────────────────────────────────────
reset_defaults; PAGES=2; build_fixtures
run_case "two pages, the walk stops at the page that carries the anchor (page 3 never requested) -> PASS" 0
expect_no_calls "page 3 was never requested" "page=3"
reset_defaults; PAGES=2; NEWER=1; build_fixtures
run_case "two pages with a post-floor incident on page 2 -> action_required (the walk reached it)" 5
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
if grep -qF -- 'dummy-token' < <(printf '%s' "$out"); then fail "xtrace refusal leaks the token"; else pass "xtrace refusal does not leak the token"; fi
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

# ── production alert state, canary pause/age, hygiene ────────────────────────────────────────
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
# rows_in_window: untrusted host names are folded, credentials missing is said out loud (diagnostic read: an open incident)
reset_defaults; A_RES=open; FLOOR_AGE=3000; ROSTER_BQ='[{"host":"soleur-web-platform","n":"4"},{"host":"evil <b>@mention</b>","n":"2"},{"host":"","n":"3"}]'; build_fixtures
run_case "an untrusted host_name in the warehouse rows -> folded into other, never printed" 2
field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:4,other:5"; expect_not_out "the hostile host_name is not printed" 'evil|mention|<b>'
reset_defaults; A_RES=open; FLOOR_AGE=3000; build_fixtures
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

# ── round-2 rows: shape conjuncts, schema gaps, folding, declaration shapes ──────────────────
# The production alert's operator and value are each load-bearing: a single wrong conjunct must read as `shape`.
for st in shape_gt1 shape_lt0; do
  reset_defaults; PROD_ALERT=$st; build_fixtures
  run_case "production alert $st (one conjunct wrong) -> action_required" 5
  field_is "prod_alert=shape"
done
# `paused` must be a boolean on every alert read: a missing key is a schema gap (unknown), never "not paused".
reset_defaults; build_fixtures
jq -c --arg n "$PROD_NAME" '.data |= map(if .attributes.name == $n then .attributes |= del(.paused) else . end)' "$WORK/alerts.json" > "$WORK/alerts.tmp" && mv "$WORK/alerts.tmp" "$WORK/alerts.json"
run_case "the production alert carries no paused key -> unknown, never a PASS" 3
verdict_is unknown
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; build_fixtures
jq -c --arg n "$CANARY_NAME" '.data |= map(if .attributes.name == $n then .attributes |= del(.paused) else . end)' "$WORK/alerts.json" > "$WORK/alerts.tmp" && mv "$WORK/alerts.tmp" "$WORK/alerts.json"
run_case "the canary alert carries no paused key -> unknown" 3
# canary-alert minimum age: exactly one evaluation cycle (1200 s), on two different alert ages
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=1199; build_fixtures
run_case "canary alert 1199 s old, no incident -> not_yet" 2
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=1200; build_fixtures
run_case "canary alert exactly 1200 s old, no incident -> action_required (blind)" 5
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=1201; build_fixtures
run_case "canary alert 1201 s old, no incident -> action_required (blind)" 5
# a recurrence is never delayed by a young canary alert
reset_defaults; ALERT_LIVE=1; CANARY_INC=0; CANARY_ALERT_AGE=300; NEWER=1; build_fixtures
run_case "recurrence while the canary alert is only 300 s old -> action_required, not not_yet" 5
field_is "newer_prod_incident=1"
# host folding in rows_in_window (diagnostic read: an open incident)
reset_defaults; A_RES=open; FLOOR_AGE=3000
ROSTER_BQ='[{"host":"soleur-web-platform","n":"4"},{"host":"ok\n","n":"2"},{"host":"has space","n":"1"},{"host":"a@b.example","n":"1"}]'; build_fixtures
run_case "a host_name with a trailing newline, a space or an @ is folded into other" 2
field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:4,other:4"
if [[ "$(grep -c '^' <<<"$LAST_OUT")" -eq "$(grep -cE '^(SOLEUR_EGRESS_GW_SILENT_SOAK|TRANSIENT|ACTION REQUIRED)' <<<"$LAST_OUT")" ]]; then pass "no output line starts with smuggled host text (every line is a verdict or a message)"; else fail "a host name smuggled a line break into the public output :: ${LAST_OUT:0:400}"; fi
reset_defaults; A_RES=open; FLOOR_AGE=3000
ROSTER_BQ="$(jq -nc '[{host:"soleur-web-platform",n:"4"},{host:"soleur-web-2",n:"3"}] + [range(0;13) | {host:("10.0.0." + (. | tostring)), n:"1"}]')"; build_fixtures
run_case "13 other hosts plus the roster: the roster is kept, ten others follow, the rest fold into other" 2
field_is "rows_in_window=soleur-web-2:3,soleur-web-platform:4,10.0.0.0:1,10.0.0.1:1,10.0.0.10:1,10.0.0.11:1,10.0.0.12:1,10.0.0.2:1,10.0.0.3:1,10.0.0.4:1,10.0.0.5:1,10.0.0.6:1,other:3"
reset_defaults; A_RES=open; FLOOR_AGE=3000
ROSTER_BQ="$(jq -nc --arg h "$(printf 'h%.0s' $(seq 1 64))" '[{host:"soleur-web-platform",n:"4"},{host:$h,n:"2"}]')"; build_fixtures
run_case "a 64-character host_name is folded into other" 2
field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:4,other:2"
# an incident id that is not numeric is a transport fault, and a pagination path never reaches a public line
reset_defaults; build_fixtures
jq -c '.data |= map(if .id == "7001" then .id = "12 @everyone" else . end)' "$WORK/incidents.json" > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "a listed incident with a non-numeric id -> unknown" 3
reset_defaults; PAGES=2; build_fixtures; rm -f "$WORK/incidents.p2.json"
run_case "page 2 answers 500 -> unknown, and the error line names the host only" 3
expect_not_out "the error line carries no path or query" '/api/v2|page=2'
expect_out "the error line names the pinned host" 'HTTP 500 on GET https://uptime\.betterstack\.com'
# the recurrence line is rebuilt from validated values: trailing text on a timestamp never reaches the comment
reset_defaults; NEWER=1; build_fixtures
jq -c '.data |= map(if .id == "9090" then .attributes.started_at += " @everyone x" else . end)' "$WORK/incidents.json" > "$WORK/incidents.tmp" && mv "$WORK/incidents.tmp" "$WORK/incidents.json"
run_case "a recurrence whose started_at carries trailing text -> never echoed" any
expect_not_out "no vendor text rides into the public line" '@everyone'
# canary declaration: a half-deleted canary still counts as declared; a // comment never does
for d in 2 3; do
  reset_defaults; DECLARED=$d; build_fixtures
  run_case "canary declaration shape $d (alert gone, a piece left) -> action_required (delete it)" 5
  field_is "canary_declared=1"
done
reset_defaults; DECLARED=4; build_fixtures
run_case "a // comment naming the canary header is not a declaration -> PASS" 0
field_is "canary_declared=0"

# ── review round 1: rows aimed at the survivors the panel found (defaults, scoping, ordering, shapes, wiring) ─────────────
# The PINNED floor, the default anchor id and the default roster are what the sweeper actually runs with; every other row passes a
# seam. Run once with all three seams empty on a clock set so that the fixture floor IS the pin.
PIN="$(sed -nE 's/^APPLY_FLOOR_EPOCH=([0-9]+).*/\1/p' "$SUT")"
if [[ "$(date -u -d "@${PIN:-0}" '+%Y-%m-%dT%H:%M:%SZ')" == "2026-11-06T12:16:03Z" ]]; then pass "APPLY_FLOOR_EPOCH is the vetted apply time 2026-11-06T12:16:03Z"; else fail "APPLY_FLOOR_EPOCH is not 2026-11-06T12:16:03Z (${PIN:-unset})"; fi
RUNBOOK="$HERE/../../knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"
if [[ -f "$RUNBOOK" ]] && grep -qF -- '2026-11-06T12:16:03Z' "$RUNBOOK"; then pass "the runbook names the same pinned instant"; else fail "the runbook does not name the pinned instant 2026-11-06T12:16:03Z"; fi
NOW_SAVED=$NOW; NOW=$((PIN + 20000))
reset_defaults; build_fixtures
run_case "the pinned floor, default anchor id and default roster (all three seams empty) on a clock 20000 s after the pin -> PASS" 0 EGRESS_GW_SILENT_FLOOR_EPOCH= EGRESS_GW_SILENT_ANCHOR_ID= EGRESS_GW_SILENT_ROSTER=
field_is "quiet_age_s=20000"
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"}]'; build_fixtures
run_case "the default roster with web-2 silent (roster seam empty) -> action_required" 5 EGRESS_GW_SILENT_FLOOR_EPOCH= EGRESS_GW_SILENT_ANCHOR_ID= EGRESS_GW_SILENT_ROSTER=
field_is "rows_in_window=soleur-web-2:0,soleur-web-platform:41"
NOW=$NOW_SAVED
# quiet_since and the open-incident set are PRODUCTION-only: unrelated and canary incidents never move either
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "7001" or .id == "5555" then .attributes.resolved_at = $r else . end) | .data += [{id:"7004",type:"incident",attributes:{name:"Unrelated monitor",started_at:$s,resolved_at:null,cause:"x"}}]' --arg r "$(iso $((NOW - 100)))" --arg s "$(iso $((FLOOR - 4000)))"
if jq -e '[.data[] | select(.id == "7001" or .id == "5555") | .attributes.resolved_at] | length == 2 and all(. != null)' "$WORK/incidents.json" >/dev/null; then pass "fixture: the unrelated and canary incidents really carry a resolved_at near NOW"; else fail "fixture: the unrelated/canary resolved_at patch did not land"; fi
run_case "unrelated and canary incidents resolved 100 s ago plus an unrelated open pre-floor incident -> PASS, quiet_since is production-only" 0
field_is "quiet_age_s=20000"; field_is "pre_floor_open_prod_incident=0"
# an open anchor that started INSIDE the slack window is still an open pre-floor incident (the anchor is excluded from the recurrence set by id)
reset_defaults; A_RES=open; A_START=$((NOW - 20000 - 100)); build_fixtures
run_case "anchor open and started 100 s before the floor, quiet 20000 s -> action_required (an open anchor always blocks)" 5
field_is "pre_floor_open_prod_incident=1"; field_is "anchor_resolved_by=unknown"
# the production-alert findings do not wait for the soak
for st in paused absent shape; do
  reset_defaults; PROD_ALERT=$st; FLOOR_AGE=100; build_fixtures
  run_case "production alert $st while the soak is still running -> action_required, not not_yet" 5
  field_is "prod_alert=$st"
done
# ordering (CTO ruling 2026-11-06): a canary/pin disagreement is raised AFTER the production findings, so it never masks them
reset_defaults; ALERT_LIVE=1; CANARY_ALERT_AGE=$((FLOOR_AGE + SLACK + 1)); PROD_ALERT=paused; build_fixtures
run_case "canary alert too early AND the production alert paused -> action_required (the production finding wins)" 5
field_is "prod_alert=paused"
reset_defaults; CANARY_BEFORE=$((SLACK + 1)); PROD_ALERT=absent; build_fixtures
run_case "canary incident too early AND the production alert absent -> action_required" 5
reset_defaults; CANARY_BEFORE=$((SLACK + 1)); NEWER=1; build_fixtures
run_case "canary incident too early AND a recurrence -> action_required (the recurrence wins)" 5
field_is "newer_prod_incident=1"
# timestamp shapes the real vendor emits: non-zero millis and a +00:00 offset
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "7001" then .attributes.started_at = "2026-11-04T21:00:03.768+00:00" else . end)'
run_case "a listed incident with .768 millis and a +00:00 offset -> PASS (it parses)" 0
# cardinality and agreement
reset_defaults; build_fixtures
patch "$WORK/alerts.json" '.data += [.data[] | select(.attributes.name == $n)]' --arg n "$PROD_NAME"
run_case "the production alert is listed twice -> unknown" 3
reset_defaults; build_fixtures
patch "$WORK/incidents.json" '.data |= map(if .id == "1047829421" then .attributes.name = "Some other alert" else . end)'
run_case "the listed anchor carries a different name than the single read -> unknown" 3
# the .tf must be the file that declares the production alert (an empty or unrelated file is not 'canary retired')
reset_defaults; build_fixtures; : > "$TF"
run_case "a zero-byte .tf -> unknown, never 'canary retired'" 3
reset_defaults; build_fixtures; printf 'locals {\n  unrelated = 1\n}\n' > "$TF"
run_case "a .tf that does not declare the production alert -> unknown" 3
# the roster: a malformed entry is not silently dropped, and a glob cannot expand
reset_defaults; build_fixtures
run_case "a roster entry outside the host-name shape -> unknown (a shrunken roster never reads as a complete one)" 3 "EGRESS_GW_SILENT_ROSTER=soleur-web-platform soleur-web-2 bad!host"
field_is "rows_in_window=unknown"
run_case "a glob in the roster is refused, not expanded -> unknown" 3 "EGRESS_GW_SILENT_ROSTER=*"
# malformed pagination must not read as 'end of list'
for ep in alerts incidents; do
  reset_defaults; build_fixtures
  # (the incident walk stops at the anchor's page before it reads pagination, so the anchor is removed to make it keep walking)
  if [[ "$ep" == incidents ]]; then patch "$WORK/$ep.json" '.data |= map(select(.id != "1047829421" and .id != "1031046761")) | .pagination = "not-an-object"'; else patch "$WORK/$ep.json" '.pagination = "not-an-object"'; fi
  run_case "a $ep body whose pagination is a string -> unknown (not an end-of-list)" 3
  expect_out "the pagination refusal names the host only" 'unreadable pagination in GET https://[a-z.]+ \(bytes='
done
# a leading-zero clock seam is canonicalised, not read as octal
reset_defaults; build_fixtures
run_case "a leading-zero clock seam is canonical -> PASS" 0 "EGRESS_GW_SILENT_NOW_EPOCH=0${NOW}"
# the retired message tells the operator to drop the label
reset_defaults; CANARY_INC=0; ALERT_LIVE=0; DECLARED=0; build_fixtures
run_case "retired canary (second look) -> action_required" 5
expect_out "the retired message tells the operator to remove the follow-through label" 'follow-through label'
# the rows read: both union branches carry the window, and the aggregation and format are present
reset_defaults; A_RES=open; FLOOR_AGE=3000; build_fixtures
run_case "sql shape probe (open anchor, diagnostic read)" 2
if [[ "$(grep '^BQ ' "$CALLS" | grep -o "dt >= '" | wc -l | tr -d ' ')" == 2 ]]; then pass "the window predicate is on BOTH union branches"; else fail "the window predicate is not on both union branches"; fi
expect_calls "the rows read aggregates per host in the pinned order and format" "GROUP BY host ORDER BY host FORMAT JSONEachRow"
expect_calls "the rows read counts rows" "count() AS n"
# transport flags the stub records
reset_defaults; build_fixtures
run_case "transport-flag probe (compliant fixture)" 0
expect_calls "every GET pins the scheme" "--proto =https"
expect_calls "every GET refuses redirects" "--max-redirs 0"
expect_calls "every GET carries a 20 s cap" "-m 20"
expect_calls "the incident listing asks for 50 per page" "per_page=50"
# the verdict line: exactly one per run, and on STDOUT
if [[ "$(printf '%s\n' "$LAST_OUT" | grep -c '^SOLEUR_EGRESS_GW_SILENT_SOAK ')" == 1 ]]; then pass "exactly one verdict line per run"; else fail "the verdict line is not printed exactly once"; fi
run_case "stdout-only probe (stderr dropped)" 0 EGS_DROP_STDERR=1
expect_out "the verdict line is on stdout, not stderr" '^SOLEUR_EGRESS_GW_SILENT_SOAK verdict=pass '
# the two internal backstops no input can reach are DRIVEN, not source-grepped: a copy of the probe is handed a bad state
# (a word/exit pairing that would close the tracker; a pass whose preconditions are not all established)
reset_defaults; build_fixtures
make_mutant "$WORK/sut-ctl.sh" "# Defense in depth: the ladder above tests the BAD value" "# Defense in depth: the ladder above tests the BAD value"
RUN_SUT="$WORK/sut-ctl.sh"; run_case "control: an identity-mutated copy of the probe still passes the compliant fixture" 0; RUN_SUT=""
make_mutant "$WORK/sut-pair.sh" $'\nverdict pass 0\n' $'\nverdict action_required 0\n'
RUN_SUT="$WORK/sut-pair.sh"; run_case "a call site pairing action_required with exit 0 is refused -> unknown (3), never a tracker-closing 0" 3; RUN_SUT=""
verdict_is unknown; expect_out "the refusal names the pairing" 'internal: verdict action_required paired with exit 0'
make_mutant "$WORK/sut-precond.sh" "# Defense in depth: the ladder above tests the BAD value" $'PRE_OPEN=1\n# Defense in depth: the ladder above tests the BAD value'
RUN_SUT="$WORK/sut-precond.sh"; run_case "a pass whose preconditions are not all established is refused -> unknown (3)" 3; RUN_SUT=""
verdict_is unknown; expect_out "the refusal names the pass preconditions" 'pass preconditions were not all established'
make_mutant "$WORK/sut-xcheck.sh" "# Defense in depth: the ladder above tests the BAD value" $'XCHECK_MSG=leftover\n# Defense in depth: the ladder above tests the BAD value'
RUN_SUT="$WORK/sut-xcheck.sh"; run_case "a leftover canary cross-check message at the pass is refused -> unknown (3)" 3; RUN_SUT=""
# the default roster is the canonical set behind var.web_hosts (in the manner of the #6608 allowlist parity)
VARTF="$HERE/../../apps/web-platform/infra/variables.tf"
CANON_ROSTER="$(awk '/^variable "web_hosts"/,/^}/' "$VARTF" 2>/dev/null | sed 's/#.*//' | grep -oE '^[[:space:]]*"web-[0-9]+"[[:space:]]*=[[:space:]]*\{' | grep -oE 'web-[0-9]+' | while read -r k; do if [[ "$k" == web-1 ]]; then echo soleur-web-platform; else echo "soleur-$k"; fi; done | sort | paste -sd' ')"
PROBE_ROSTER="$(sed -nE 's/^ROSTER_RAW="\$\{EGRESS_GW_SILENT_ROSTER:-([^}]*)\}"$/\1/p' "$SUT" | tr ' ' '\n' | sort | paste -sd' ')"
if [[ -n "$CANON_ROSTER" && "$CANON_ROSTER" == *" "* && "$CANON_ROSTER" == "$PROBE_ROSTER" ]]; then pass "the probe's default roster equals the host names derived from var.web_hosts"; else fail "the probe's default roster ('${PROBE_ROSTER}') differs from the names derived from var.web_hosts ('${CANON_ROSTER}')"; fi
# a non-string pagination.next, a 20-digit clock and a negative row count
reset_defaults; build_fixtures
patch "$WORK/alerts.json" '.pagination = {next: false}'
run_case "an alerts body whose pagination.next is false -> unknown (not an end-of-list)" 3
reset_defaults; build_fixtures
run_case "a 20-digit clock seam is refused (it would wrap in bash arithmetic) -> unknown" 3 "EGRESS_GW_SILENT_NOW_EPOCH=99999999999999999999"
reset_defaults; ROSTER_BQ='[{"host":"soleur-web-platform","n":"41"},{"host":"soleur-web-2","n":"-5"},{"host":"soleur-web-2","n":"7"}]'; build_fixtures
run_case "a negative row count is clamped to zero, not netted against a real count -> PASS" 0
field_is "rows_in_window=soleur-web-2:7,soleur-web-platform:41"

# ── negative controls: every assertion helper must RED on a deliberately wrong input ─────────
# The floor counts assertions; it cannot tell a helper that stopped asserting from one that works. Each control runs a
# helper against known state, expects exactly one failure, then restores the counters.
neg_control() { # <desc> <helper...>
  local desc="$1" t0=$total f0=$fails nf; shift
  "$@" >/dev/null 2>&1
  nf=$((fails - f0)); total=$t0; fails=$f0
  if [[ "$nf" -eq 1 ]]; then pass "negative control: $desc"; else fail "negative control: $desc (helper recorded $nf failures, expected 1)"; fi
}
reset_defaults; build_fixtures
run_case "negative-control fixture (healthy) -> PASS" 0
neg_control "expect_out REDs on an absent pattern" expect_out "x" 'THIS-PATTERN-IS-ABSENT'
neg_control "expect_not_out REDs on a present pattern" expect_not_out "x" 'SOLEUR_EGRESS_GW_SILENT_SOAK'
neg_control "expect_calls REDs on an absent string" expect_calls "x" 'THIS-IS-NEVER-CALLED'
neg_control "expect_no_calls REDs on a present string" expect_no_calls "x" '/api/v2/incidents/'
neg_control "field_is REDs on a wrong value" field_is "prod_alert=paused"
neg_control "verdict_is REDs on a wrong verdict" verdict_is action_required
neg_control "run_case REDs on a wrong expected exit" run_case "x" 5
neg_control "run_case REDs on a forbidden exit 1" run_case "x" 0 BETTERSTACK_API_TOKEN=
neg_control "patch REDs when the jq filter cannot apply" patch "$WORK/no-such-fixture.json" '.'
neg_control "patch REDs when the filter changes nothing" patch "$WORK/err500.json" '.'
neg_control "make_mutant REDs when its anchor is absent" make_mutant "$WORK/never.sh" "THIS-ANCHOR-IS-ABSENT-FROM-THE-PROBE" "x"
if grep -qxF '[[ "$fails" -eq 0 ]]' "$0"; then pass "the suite's last line is its exit status"; else fail "the suite's last line is not the failure check"; fi

# ── source-level pins on the SUT (cheap, and they catch a refactor that drops a safeguard) ───
sut_code="$(grep -vE '^[[:space:]]*#' "$SUT")"
if grep -qE '^[[:space:]]*exit[[:space:]]+1([[:space:]]|$)' <<<"$sut_code"; then fail "the SUT contains a literal 'exit 1'"; else pass "the SUT contains no literal 'exit 1'"; fi
if [[ "$(grep -cE '^APPLY_FLOOR_EPOCH=[0-9]+([[:space:]]|$)' "$SUT")" -eq 1 && "$(grep -cE 'APPLY_FLOOR_EPOCH=' <<<"$sut_code")" -eq 1 ]]; then pass "APPLY_FLOOR_EPOCH is assigned exactly once, at column 0, as digits"; else fail "APPLY_FLOOR_EPOCH is not assigned exactly once at column 0 as digits"; fi
if grep -qE '^# RETIREMENT:' "$SUT"; then pass "the SUT header carries a RETIREMENT: line"; else fail "the SUT header lacks a RETIREMENT: line"; fi
retire_block="$(sed -n '/^# RETIREMENT:/,/^[^#]/p' "$SUT")"
for site in egress_gw_probe_silent_canary betterstack-logs-alerts.tf apply-web-platform-infra.yml EXPECT_BLOCKS MIN_PASSES betterstack-send-failed-alert-mutation.test.sh egress-gw-alert.test.sh cron-egress-blocked.md ADR-218 INTENDED_DESTROYS ack-destroy CENSUS_FLOOR_ALERTS betterstack-log-query.md infra-validation.yml APPLY_FLOOR_EPOCH; do
  if grep -qF -- "$site" <<<"$retire_block"; then pass "RETIREMENT header lists: $site"; else fail "RETIREMENT header lacks: $site"; fi
done
# DERIVED, not a literal list: every tracked file that names the canary (outside the plan/spec history and this probe) must
# be named in the RETIREMENT header, so a suite added later that hardcodes the canary cannot be missed by the deletion PR.
ref_n=0
in_git=0; git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  ref_n=$((ref_n + 1))
  key="${ref##*/}"; [[ "$key" =~ ^(ADR-[0-9]+)- ]] && key="${BASH_REMATCH[1]}"   # an ADR is named by its number
  if grep -qF -- "$key" <<<"$retire_block"; then pass "RETIREMENT header names the referrer ${key}"; else fail "RETIREMENT header lacks the referrer ${ref}"; fi
done < <(git -C "$HERE" grep -lE 'silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project' ':(top,exclude)scripts/followthroughs' 2>/dev/null)
# Anti-vacuity: the derivation must have found the files that are known to carry the canary.
if [[ "$in_git" -eq 0 ]]; then pass "the referrer derivation is skipped outside a git checkout (nothing to enumerate)"; elif [[ "$ref_n" -ge 6 ]]; then pass "the referrer derivation found $ref_n files (>= 6)"; else fail "the referrer derivation found only $ref_n files; git grep did not run or the tree moved"; fi
if grep -qE 'attributes\.name[[:space:]]*==' <<<"$sut_code"; then pass "incident matching is exact .attributes.name equality"; else fail "incident matching is not exact .attributes.name equality"; fi
if grep -qE 'startswith|test\(|contains\(|ascii_downcase' <<<"$sut_code"; then fail "the SUT uses a fuzzy string match (startswith/test/contains)"; else pass "the SUT uses no fuzzy string match"; fi

# ── floor ────────────────────────────────────────────────────────────────────────────────────
# Exact baseline, reported via printf+exit: a block of rows that stopped executing must not read as green.
# Re-pin deliberately when rows are added; never lower it to fit a deletion.
MIN_ASSERTIONS=430
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
