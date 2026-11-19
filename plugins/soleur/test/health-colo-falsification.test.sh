#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031  # jq programs are single-quoted on purpose; the self-test subshells change counters on purpose
# The pre-registered falsification recipe for the per-colo /health read (CTO T2 with the D2 null-colo rule; CTO D3; Ref #12846).
#
# WHAT IT PROVES. The runbook knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md holds the ONE jq recipe that
# turns the post-merge analytics-health-colo evidence file into a verdict line (`not supported` or `inconclusive: <reason>`). That
# verdict is decided once, on data that cannot be re-read after the old zone is deleted, so the recipe is pinned here before any
# real data exists:
#   * the recipe is taken from the runbook itself, from exactly one `health-colo-r2-recipe` marker pair, never from a copy;
#   * it runs the way the runbook says it runs (`/usr/bin/env -i /usr/bin/jq -r -f`), so a planted ~/.jq or JQ_LIBRARY_PATH
#     cannot redefine a builtin under it;
#   * each case is a named one-line jq patch on ONE synthetic fixture (fixtures/health-colo-falsification/base.json; invented
#     zone id and colo codes, cq-test-fixtures-synthesized-only), and its FULL verdict line is asserted: the three T2 classes,
#     and both sides of boundaries (i)-(ix) of the plan;
#   * the runbook's recorded-outputs block (`health-colo-r2-outputs` markers) equals this file's case list, in order, so the
#     copy the reader sees cannot drift from what was pre-registered;
#   * ten recipe mutation rows (edit_once style: exactly one anchor match, the mutant differs and still compiles), each named
#     with the case that must turn RED, plus a comment-only control that must turn no case RED;
#   * an executed-row floor and a mutation-row floor, reported by printf + exit 1, never through the helpers they backstop;
#   * a child run with one failed row and every floor met must exit 1 (the exit status is what the runner grades).
#
# Pure jq, no network, no git, no scratch files: inputs reach jq on a pipe and the recipe through process substitution.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

TESTDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$TESTDIR/../../.." && pwd -P)"
RUNBOOK="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md"
FIXTURE="$TESTDIR/fixtures/health-colo-falsification/base.json"
JQ=/usr/bin/jq

pass=0
fail=0
rows_run=0
mut_run=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
# check <label> <expected> <actual>: one executed row. `rows_run` moves at the call, independent of the verdict.
check() {
  rows_run=$((rows_run + 1))
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    no "$1"
    printf '       expected: %s\n       actual:   %s\n' "$2" "$3"
  fi
}
summary() { printf '\n%s passed, %s failed (%s rows executed, %s mutation rows)\n' "$pass" "$fail" "$rows_run" "$mut_run"; }

# --- floors (printf + exit 1, never through check/no) and accounting ---------------------------------------------------------
MUT_FLOOR=10
ROW_FLOOR=63
# finish: the suite's verdict. The real run and the forced-fail child below both call it, so the child exercises these lines.
finish() {
  if [[ "$((pass + fail))" != "$rows_run" ]]; then
    printf 'FAIL: accounting: passes + fails (%s) != rows executed (%s) - a verdict was dropped\n' "$((pass + fail))" "$rows_run" >&2
    exit 1
  fi
  summary
  if [[ "$mut_run" -lt "$MUT_FLOOR" ]]; then
    printf 'FAIL: mutation-row floor: only %s recipe mutation rows ran, need %s (vacuity)\n' "$mut_run" "$MUT_FLOOR" >&2
    exit 1
  fi
  if [[ "$rows_run" -lt "$ROW_FLOOR" ]]; then
    printf 'FAIL: executed-row floor: only %s rows ran, need at least %s (the exact current count; vacuity)\n' "$rows_run" "$ROW_FLOOR" >&2
    exit 1
  fi
  if [[ "$fail" -gt 0 ]]; then exit 1; fi
  exit 0
}
# The exit status is what the runner grades: a run with every floor met and one failed row must exit 1. The child is selected
# by argv, never by an environment flag, so an inherited variable cannot select it.
if [[ "${1:-}" == --forced-fail-child ]]; then
  pass=$((ROW_FLOOR - 1)) fail=1 rows_run=$ROW_FLOOR mut_run=$MUT_FLOOR
  finish >/dev/null 2>&1
fi

# --- instrument self-test: check() must be able to fail AND to pass, or every row below is vacuous ---------------------------
( pass=0; fail=0; check "self-test" "a" "b" >/dev/null; [[ "$fail" -eq 1 && "$pass" -eq 0 ]] ) \
  || { printf 'FATAL: check() cannot fail - the instrument is neutered\n' >&2; exit 2; }
( pass=0; fail=0; check "self-test" "a" "a" >/dev/null; [[ "$pass" -eq 1 && "$fail" -eq 0 ]] ) \
  || { printf 'FATAL: check() cannot pass - the instrument is broken\n' >&2; exit 2; }

[[ -x "$JQ" ]] || { printf 'FATAL: %s is missing; the runbook runs the recipe with it by absolute path\n' "$JQ" >&2; exit 2; }
[[ -s "$RUNBOOK" ]] || { printf 'FATAL: runbook missing or empty: %s\n' "$RUNBOOK" >&2; exit 2; }
[[ -s "$FIXTURE" ]] || { printf 'FATAL: fixture missing or empty: %s\n' "$FIXTURE" >&2; exit 2; }

# --- the marker pairs: exactly one each, in order, each holding exactly one fenced block -------------------------------------
# region <name>: the lines strictly between the <name>:start and <name>:end marker lines (blank lines dropped).
region() { awk -v s="<!-- $1:start -->" -v e="<!-- $1:end -->" '$0 == e { f = 0 } f && NF { print } $0 == s { f = 1 }' "$RUNBOOK"; }
# The one extraction the runbook documents for the operator: the lines inside the fence between the recipe markers (the test
# asserts the runbook carries this command verbatim, below).
EXTRACT='/^<!-- health-colo-r2-recipe:start -->$/ { f = 1; next } /^<!-- health-colo-r2-recipe:end -->$/ { f = 0 } f && /^```/ { g = !g; next } f && g { print }'
STRUCT_OK=1
for m in health-colo-r2-recipe health-colo-r2-outputs; do
  ns=$(grep -cxF "<!-- $m:start -->" "$RUNBOOK")
  ne=$(grep -cxF "<!-- $m:end -->" "$RUNBOOK")
  check "runbook: exactly one $m marker pair (start lines $ns, end lines $ne)" "1 1" "$ns $ne"
  if [[ "$ns $ne" != "1 1" ]]; then STRUCT_OK=0; continue; fi
  ls_=$(grep -nxF "<!-- $m:start -->" "$RUNBOOK" | cut -d: -f1)
  le_=$(grep -nxF "<!-- $m:end -->" "$RUNBOOK" | cut -d: -f1)
  check "runbook: the $m start marker comes before its end marker" "1" "$([[ "$ls_" -lt "$le_" ]] && echo 1 || echo 0)"
  r=$(region "$m")
  case "$m" in health-colo-r2-recipe) lang=jq ;; *) lang=text ;; esac
  fences="$(printf '%s\n' "$r" | grep -c '^```')|$(printf '%s\n' "$r" | head -n 1)|$(printf '%s\n' "$r" | tail -n 1)"
  check "runbook: the $m pair holds exactly one fenced $lang block and nothing outside it" "2|\`\`\`$lang|\`\`\`" "$fences"
  [[ "$fences" == "2|\`\`\`$lang|\`\`\`" ]] || STRUCT_OK=0
done
if [[ "$STRUCT_OK" != 1 ]]; then
  no "runbook: the recipe and outputs blocks are not in place - nothing below can run (RED until the addendum is written)"
  summary
  exit 1
fi
RECIPE=$(awk "$EXTRACT" "$RUNBOOK")
check "runbook: the extracted recipe is non-empty and starts with its title comment" "# health-colo R2 recipe" "${RECIPE:0:23}"
check "runbook: the extracted recipe compiles (jq -n on it prints bad-input)" "inconclusive: bad-input" \
  "$(/usr/bin/env -i "$JQ" -r -n -f <(printf '%s\n' "$RECIPE") 2>&1)"
RUN_CMD="/usr/bin/env -i /usr/bin/jq -r -f <(awk '$EXTRACT' knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md)"
check "runbook: the documented run command (env -i, absolute jq, this extraction) appears exactly once" "1" "$(grep -cF -- "$RUN_CMD" "$RUNBOOK")"

# --- cases: name | one-line jq patch on the base fixture | full expected verdict line ----------------------------------------
# Patch helpers (test side only). k is the clock-hour offset from 2026-11-07T23Z, as in the recipe. The base: colo AAA has
# p90 400 ms on every hour to 22Z and 900 ms from 23Z on (count 20 everywhere: positive); colo BBB is 400 ms throughout; hours
# k = -26..60 for both; no null-colo row.
PRELUDE='def F: "2026-11-07T23:00:00Z" | fromdateiso8601;
def k: ((.hour | fromdateiso8601) - F) / 3600;
def at($c; $a; $b; f): .series |= map(if .colo == $c and k >= $a and k <= $b then f else . end);
def drop($c; $a; $b): .series |= map(select((.colo == $c and k >= $a and k <= $b) | not));
def gone($c): .series |= map(select(.colo != $c));
def nul($h; $n): .series += [{hour: (F + $h * 3600 | todate), colo: null, count: $n, avg_ms: 2000, p50_ms: 2000, p90_ms: 5000}];'
Z='; null_colo_rows=0 null_colo_qualifying=0'
CASE_NAME=() CASE_PATCH=() CASE_WANT=()
add_case() { CASE_NAME+=("$1"); CASE_PATCH+=("$2"); CASE_WANT+=("$3"); }
add_case base-positive-23Z           '.'                                                            "inconclusive: positive-colo$Z"
add_case class-none-positive         'at("AAA"; 0; 60; .p90_ms = 400)'                              "not supported$Z"
add_case class-no-judged-colo        'at("AAA"; 10; 60; .count = 5) | at("BBB"; 10; 60; .count = 5)' "inconclusive: no-judged-colo$Z"
add_case i-cp-00Z-positive           'at("AAA"; 0; 0; .p90_ms = 400)'                               "inconclusive: positive-colo$Z"
add_case i-cp-01Z-not-positive       'at("AAA"; 0; 1; .p90_ms = 400)'                               "not supported$Z"
add_case ii-before-23-not-judged     'gone("AAA") | at("BBB"; -26; -24; .count = 5)'                "inconclusive: no-judged-colo$Z"
add_case ii-before-24-judged         'gone("AAA") | at("BBB"; -26; -25; .count = 5)'                "not supported$Z"
add_case ii-after-23-not-judged      'gone("AAA") | at("BBB"; 24; 60; .count = 5)'                  "inconclusive: no-judged-colo$Z"
add_case ii-after-24-judged          'gone("AAA") | at("BBB"; 25; 60; .count = 5)'                  "not supported$Z"
add_case iii-6-qualifying-positive   'at("AAA"; 1; 24; .count = 5) | at("AAA"; 1; 6; .count = 20)'  "inconclusive: positive-colo$Z"
add_case iii-5-qualifying-not-positive 'at("AAA"; 1; 24; .count = 5) | at("AAA"; 1; 5; .count = 20)' "not supported$Z"
add_case iv-dip-at-cp24-breaks       'at("AAA"; 24; 24; .p90_ms = 400)'                             "not supported$Z"
add_case iv-dip-at-cp25-holds        'at("AAA"; 25; 25; .p90_ms = 400)'                             "inconclusive: positive-colo$Z"
add_case v-missing-hour-in-run       'drop("AAA"; 10; 10)'                                          "not supported$Z"
add_case v-missing-hour-after-run    'drop("AAA"; 25; 25)'                                          "inconclusive: positive-colo$Z"
add_case vi-count-9-in-run           'at("AAA"; 1; 24; .count = 5) | at("AAA"; 1; 6; .count = 20) | at("AAA"; 6; 6; .count = 9)'  "not supported$Z"
add_case vi-count-10-in-run          'at("AAA"; 1; 24; .count = 5) | at("AAA"; 1; 6; .count = 20) | at("AAA"; 6; 6; .count = 10)' "inconclusive: positive-colo$Z"
add_case vi-p90-equal-baseline-max   'at("AAA"; 12; 12; .p90_ms = 400)'                             "not supported$Z"
add_case vi-p90-above-baseline-max   'at("AAA"; 12; 12; .p90_ms = 401)'                             "inconclusive: positive-colo$Z"
add_case vii-late-run-from-06Z       'at("AAA"; 0; 60; .p90_ms = 400) | at("AAA"; 2; 2; .p90_ms = 900) | at("AAA"; 7; 60; .p90_ms = 900) | at("BBB"; 0; 60; .p90_ms = 900)' "not supported$Z"
add_case vii-exceedance-01Z-only     'at("AAA"; 0; 60; .p90_ms = 400) | at("AAA"; 2; 2; .p90_ms = 900) | at("BBB"; 0; 60; .p90_ms = 900)' "inconclusive: positive-colo$Z"
add_case viii-late-run-from-01Z      'at("BBB"; 2; 60; .p90_ms = 900)'                              "not supported$Z"
add_case viii-run-from-00Z-positive  'at("BBB"; 1; 60; .p90_ms = 900)'                              "inconclusive: positive-colo$Z"
add_case ix-null-colo-under-10       'nul(-5; 9) | nul(0; 9) | nul(5; 9)'                           "inconclusive: positive-colo; null_colo_rows=3 null_colo_qualifying=0"
add_case ix-null-colo-at-10          'nul(-5; 9) | nul(0; 10) | nul(5; 9)'                          "inconclusive: invalid-colo; null_colo_rows=3 null_colo_qualifying=1"
add_case ix-null-colo-overrides-not-supported 'at("AAA"; 0; 60; .p90_ms = 400) | nul(0; 10)'        "inconclusive: invalid-colo; null_colo_rows=1 null_colo_qualifying=1"
add_case bad-input-truncated         '.truncated = true'                                            "inconclusive: bad-input"
add_case bad-input-other-subcommand  '.subcommand = "analytics-health"'                             "inconclusive: bad-input"
add_case bad-input-duplicate-row     '.series += [.series[0]]'                                      "inconclusive: bad-input"
add_case bad-input-truncated-absent 'del(.truncated)' "inconclusive: bad-input"
add_case bad-input-not-an-object '[.]' "inconclusive: bad-input"
add_case bad-input-negative-count '.series[0].count = -1' "inconclusive: bad-input"
add_case bad-input-hour-off-the-hour '.series[0].hour = "2026-11-06T21:30:00Z"' "inconclusive: bad-input"
add_case bad-input-colo-not-three-capitals '.series[0].colo = "aaa"' "inconclusive: bad-input"
add_case order-unsorted-series '.series |= reverse' "inconclusive: positive-colo$Z"

# All case inputs in ONE jq call (one compact line per case, in case order): jq start-up, not the recipe, dominates the time.
PROG="$PRELUDE"
for i in "${!CASE_NAME[@]}"; do PROG+=$'\n'"$([[ "$i" -gt 0 ]] && printf ', ')(${CASE_PATCH[$i]})"; done
if ! INPUTS=$(/usr/bin/env -i "$JQ" -c "$PROG" "$FIXTURE"); then INPUTS=""; fi
mapfile -t CASE_INPUT < <(printf '%s\n' "$INPUTS" | grep .)
check "cases: every patch applied (one input per case)" "${#CASE_NAME[@]}" "${#CASE_INPUT[@]}"
check "cases: every patch changed the base except the base case itself (distinct inputs)" "${#CASE_NAME[@]}" \
  "$(printf '%s\n' "${CASE_INPUT[@]}" | sort -u | grep -c .)"

# verdicts <recipe> [case index...]: the verdict line of every case input (or of the named ones), in that order (table lines
# start with `colo=`).
verdicts() {
  local prog="$1" j
  shift
  if [[ $# -gt 0 ]]; then for j in "$@"; do printf '%s\n' "${CASE_INPUT[$j]}"; done; else printf '%s\n' "${CASE_INPUT[@]}"; fi \
    | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$prog") 2>&1 | grep -v '^colo='
}
mapfile -t GOT < <(verdicts "$RECIPE")
check "cases: one verdict line per case" "${#CASE_NAME[@]}" "${#GOT[@]}"
for i in "${!CASE_NAME[@]}"; do
  check "case[${CASE_NAME[$i]}]: full verdict line" "${CASE_WANT[$i]}" "${GOT[$i]:-<no line>}"
done

# The base case's whole output, table included (a table line is the reader's only view of why a colo was or was not judged).
WANT_BASE="inconclusive: positive-colo$Z
colo=AAA judged=true before=26 after=60 baseline_max=400 change_point=2026-11-07T23:00:00Z positive=true late_run=null
colo=BBB judged=true before=26 after=60 baseline_max=400 change_point=null positive=false late_run=null"
GOT_BASE=$(/usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") "$FIXTURE" 2>&1)
check "base: the whole output (verdict line plus one table line per colo, sorted by colo)" "$WANT_BASE" "$GOT_BASE"

# --- the recorded-outputs block equals the case list, in order ---------------------------------------------------------------
WANT_OUT=$(for i in "${!CASE_NAME[@]}"; do printf '%s: %s\n' "${CASE_NAME[$i]}" "${CASE_WANT[$i]}"; done)
GOT_OUT=$(region health-colo-r2-outputs | grep -v '^```')
check "runbook: the recorded-outputs block equals this suite's case names and expected lines, in order" "$WANT_OUT" "$GOT_OUT"

# --- a split main read (two H=108 files, split at 2026-11-08T00Z) joins to the same verdict -----------------------------------
JOIN='.[0] + {window_hours: (map(.window_hours) | add), rows: (map(.rows) | add), truncated: (map(.truncated) | any), series: (map(.series) | add | sort_by(.hour, .colo))}'
check "runbook: the split-read join program appears exactly once" "1" "$(grep -cF -- "$JOIN" "$RUNBOOK")"
LATER="$PRELUDE .series |= map(select(k >= 1)) | .window_hours = 60 | .rows = (.series | length)"
EARLIER="$PRELUDE .series |= map(select(k <= 0)) | .window_end = \"2026-11-08T00:00:00Z\" | .window_hours = 27 | .rows = (.series | length)"
JOINED=$(/usr/bin/env -i "$JQ" -c -s "$JOIN" <(/usr/bin/env -i "$JQ" -c "$LATER" "$FIXTURE") <(/usr/bin/env -i "$JQ" -c "$EARLIER" "$FIXTURE") 2>&1)
check "split: the joined pair carries the later file's window_end and the summed window" "2026-11-10T12:00:00Z 87 174 false" \
  "$(printf '%s\n' "$JOINED" | /usr/bin/env -i "$JQ" -r '"\(.window_end) \(.window_hours) \(.rows) \(.truncated)"' 2>&1)"
check "split: the joined pair gives the base's whole output" "$WANT_BASE" \
  "$(printf '%s\n' "$JOINED" | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") 2>&1)"

# --- recipe mutation rows ----------------------------------------------------------------------------------------------------
# mutate <label> <case that must turn RED> <from> <to>: ONE literal edit of the extracted recipe. The row measures something
# only when the anchor matched exactly once, the mutant differs, and the mutant still compiles (a mutant that does not compile
# reds every case and proves nothing about the case set). A named mutation runs its named case only. The comment-only control
# runs last, on every case the named mutations name, and must turn none of them RED (the runner does not red every edit).
NAMED_IDX=()
mutate() {
  local label="$1" want_case="$2" from="$3" to="$4" tmp cnt mut i red=0 hit=""
  if [[ -n "$want_case" ]]; then mut_run=$((mut_run + 1)); fi
  tmp="${RECIPE//"$from"/}"
  cnt=$(((${#RECIPE} - ${#tmp}) / ${#from}))
  if [[ "$cnt" != 1 ]]; then check "mutation[$label]: anchor matched exactly once" "1" "$cnt"; return; fi
  mut="${RECIPE/"$from"/"$to"}"
  if ! /usr/bin/env -i "$JQ" -r -n -f <(printf '%s\n' "$mut") >/dev/null 2>&1; then
    check "mutation[$label]: the mutant compiles" "compiles" "does not compile"; return
  fi
  if [[ -z "$want_case" ]]; then
    mapfile -t MGOT < <(verdicts "$mut" "${NAMED_IDX[@]}")
    for i in "${!NAMED_IDX[@]}"; do [[ "${MGOT[$i]:-}" == "${CASE_WANT[${NAMED_IDX[$i]}]}" ]] || red=$((red + 1)); done
    check "mutation[$label]: leaves all ${#NAMED_IDX[@]} named cases GREEN (${#MGOT[@]} lines)" "0 ${#NAMED_IDX[@]}" "$red ${#MGOT[@]}"
    return
  fi
  for i in "${!CASE_NAME[@]}"; do [[ "${CASE_NAME[$i]}" == "$want_case" ]] && hit="$i"; done
  if [[ -z "$hit" ]]; then check "mutation[$label]: names a case of this suite" "a case" "$want_case"; return; fi
  NAMED_IDX+=("$hit")
  mapfile -t MGOT < <(verdicts "$mut" "$hit")
  check "mutation[$label]: caught - case $want_case turns RED (now: ${MGOT[0]:-<no line>})" "1" \
    "$([[ "${MGOT[0]:-}" != "${CASE_WANT[$hit]}" ]] && echo 1 || echo 0)"
}
mutate "M1 the 23Z hour counted as baseline" ii-before-23-not-judged '.k <= -1' '.k <= 0'
mutate "M2 sustained window cp..cp+23 instead of cp+1..cp+24" iv-dip-at-cp24-breaks 'range($s + 1; $s + 25)' 'range($s; $s + 24)'
mutate "M3 five qualifying hours suffice" iii-5-qualifying-not-positive 'length >= 6' 'length >= 5'
mutate "M4 step by row position, not by clock hour" v-missing-hour-in-run '[range($s + 1; $s + 25) | $by[tostring]]' '([$rows[] | select(.k > $s)] | .[0:24])'
mutate "M5 only the first exceedance from 01Z on is tried" vii-late-run-from-06Z '[$qr[] | select(.k >= 2 and .p90_ms > $m) | .k | select(sustained)]' '[[$qr[] | select(.k >= 2 and .p90_ms > $m) | .k][0:1][] | select(sustained)]'
mutate "M6 the second not-supported path dropped" viii-late-run-from-01Z ' or ($j | any(.late_run != null))' ''
mutate "M7 the D2 null-colo rule dropped" ix-null-colo-at-10 'if $nq > 0 then "inconclusive: invalid-colo"' 'if false then "inconclusive: invalid-colo"'
mutate "M8 the count check dropped from okrow" bad-input-negative-count '  and (.count | type == "number" and . >= 0)' ''
mutate "M9 a missing truncated key read as not truncated" bad-input-truncated-absent '.truncated == false' '.truncated != true'
mutate "M10 the object check dropped from okinput" bad-input-not-an-object 'def okinput: type == "object" and ' 'def okinput: '
mutate "control: comment-only edit" "" '# health-colo R2 recipe:' '# (control) health-colo R2 recipe:'

# --- the exit-status check and the verdict --------------------------------------------------------------------------------
bash "${BASH_SOURCE[0]}" --forced-fail-child >/dev/null 2>&1
frc=$?
if [[ "$frc" -ne 1 ]]; then
  printf 'FAIL: exit status: a run with one failed row exited %s, not 1 - the runner would read a failure as green\n' "$frc" >&2
  exit 1
fi
finish
