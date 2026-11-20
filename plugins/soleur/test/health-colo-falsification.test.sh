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
#   * thirteen recipe mutation rows (edit_once style: exactly one anchor match, the mutant differs and still compiles), each named
#     with the case that must turn RED, plus a comment-only control that must turn no case RED;
#   * an executed-row floor and a mutation-row floor, reported by printf + exit 1, never through the helpers they backstop;
#   * a child run with one failed row and every floor met must exit 1 (the exit status is what the runner grades).
#
# Pure jq, no network, no git. Inputs reach jq on a pipe and the recipe through process substitution; the two run-block rows
# write one mktemp file each (the block reads its file twice) and remove it.
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
# The documented run block (CTO Q6, Q7): a preflight on the file, the extraction, a sha256 check of the recipe, then the run.
# Each of its four lines must appear in the runbook exactly once, as a whole line.
RECIPE_SHA256=e30242b23618c50cf7c0629bc16e55155d239d1117f08ffae6018086664a7641
check "runbook: the recipe's sha256 is the pre-registered value (change it only with a CTO ruling row)" "$RECIPE_SHA256" \
  "$(printf '%s\n' "$RECIPE" | sha256sum | cut -d' ' -f1)"
PREFLIGHT='.zone == "5af02a2f394e9ba6e0ea23c381a26b67" and .subcommand == "analytics-health-colo" and .window_end == "2026-11-12T12:00:00Z" and .window_hours == 216 and (.series | type == "array" and all(.hour | type == "string" and . >= "2026-11-03T12:00:00Z" and . < "2026-11-12T12:00:00Z"))'
RUN_LINES=()
RUN_LINES+=("/usr/bin/env -i /usr/bin/jq -e '$PREFLIGHT' \"\$file\" >/dev/null || { echo \"refused: \$file is not the pre-registered read (zone, subcommand or R1 window)\"; false; } &&")
RUN_LINES+=("R=\$(awk '$EXTRACT' knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md) &&")
RUN_LINES+=("{ [ \"\$(printf '%s\\n' \"\$R\" | sha256sum | cut -d' ' -f1)\" = \"$RECIPE_SHA256\" ] || { echo \"other: recipe-drift\"; false; }; } &&")
RUN_LINES+=("/usr/bin/env -i /usr/bin/jq -r -f <(printf '%s\\n' \"\$R\") \"\$file\"")
for i in "${!RUN_LINES[@]}"; do
  check "runbook: run-block line $((i + 1)) of ${#RUN_LINES[@]} appears exactly once, as a whole line" "1" "$(grep -cxF -- "${RUN_LINES[$i]}" "$RUNBOOK")"
done
# The whole block, line for line: the fenced block right after the sentence that introduces it holds these four lines and
# nothing else, in this order (a per-line pin alone is satisfied by lines split across blocks or reordered).
RUN_BLOCK=$(awk '/with this four-line block \(the falsification suite pins it line for line\):$/ { f = 1; next } f && /^```bash$/ { g = 1; next } g && /^```$/ { exit } g { print }' "$RUNBOOK")
check "runbook: the run block under 'with this four-line block' is exactly the four pinned lines, in order" \
  "$(printf '%s\n' "${RUN_LINES[@]}")" "$RUN_BLOCK"
# The preflight refuses the synthetic fixture (its zone is not the old zone) and accepts it once zone and R1 window match.
pf() { /usr/bin/env -i "$JQ" -e "$PREFLIGHT" >/dev/null 2>&1; echo $?; }
R1_PATCH='.zone = "5af02a2f394e9ba6e0ea23c381a26b67" | .window_end = "2026-11-12T12:00:00Z" | .window_hours = 216'
check "preflight: refuses the fixture as it is (another zone)" "1" "$(pf < "$FIXTURE")"
check "preflight: accepts the fixture with the old zone and the R1 window" "0" "$(/usr/bin/env -i "$JQ" -c "$R1_PATCH" "$FIXTURE" | pf)"
check "preflight: refuses a row stamped at the R1 window end (half-open)" "1" \
  "$(/usr/bin/env -i "$JQ" -c "$R1_PATCH | .series[0].hour = \"2026-11-12T12:00:00Z\"" "$FIXTURE" | pf)"
# One cause each, on the accepted file: every clause of the preflight is needed.
for brk in '.zone = "0123456789abcdef0123456789abcdef"' '.subcommand = "analytics-health"' '.window_end = "2026-11-12T13:00:00Z"' \
  '.window_hours = 215' '.series[0].hour = "2026-11-03T11:00:00Z"' '.series = {}'; do
  check "preflight: refuses the accepted file with only $brk changed" "1" \
    "$(/usr/bin/env -i "$JQ" -c "$R1_PATCH | $brk" "$FIXTURE" | pf)"
done
# The loop and the preflight name the same old zone and the same R1 window (two copies of one fact; CLO item 4 may change it).
OLD_ZONE=$(printf '%s\n' "$PREFLIGHT" | sed -n 's/^\.zone == "\([0-9a-f]*\)".*/\1/p')
check "runbook: the handoff loop keeps the preflight's zone ($OLD_ZONE) and reads the preflight's R1 window end" "1 1" \
  "$(grep -cF -- "and .zone == \"$OLD_ZONE\" and" "$RUNBOOK") $(grep -cxF -- 'h_read 216 2026-11-12T12:00:00Z; r=$?' "$RUNBOOK")"

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
add_case bad-input-series-not-an-array '.series = {}' "inconclusive: bad-input"
add_case bad-input-negative-count '.series[0].count = -1' "inconclusive: bad-input"
add_case bad-input-hour-off-the-hour '.series[0].hour = "2026-11-06T21:30:00Z"' "inconclusive: bad-input"
add_case bad-input-colo-not-three-capitals '.series[0].colo = "aaa"' "inconclusive: bad-input"
add_case order-unsorted-series '.series |= reverse' "inconclusive: positive-colo$Z"
add_case x-null-p90-unjudged-colo 'gone("BBB") | .series += [{hour: "2026-11-08T05:00:00Z", colo: "CCC", count: 12, avg_ms: null, p50_ms: null, p90_ms: null}]' "inconclusive: positive-colo$Z"
add_case x-null-p90-in-run-breaks 'at("AAA"; 5; 5; .p90_ms = null)' "not supported$Z"
add_case x-null-p90-baseline-not-counted 'at("AAA"; -26; -24; .p90_ms = null)' "not supported$Z"
add_case bad-input-p90-key-absent '.series[0] |= del(.p90_ms)' "inconclusive: bad-input"
add_case ix-null-colo-null-p90-at-10 'nul(5; 10) | .series[-1].p90_ms = null' "inconclusive: invalid-colo; null_colo_rows=1 null_colo_qualifying=1"
add_case ix-two-null-colos-one-hour 'nul(5; 1) | nul(5; 2)' "inconclusive: positive-colo; null_colo_rows=2 null_colo_qualifying=0"

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
# An unjudged colo prints no change point (CTO Q4): the verdict never uses one, so none is shown.
for i in "${!CASE_NAME[@]}"; do [[ "${CASE_NAME[$i]}" == class-no-judged-colo ]] && NJ="$i"; done
WANT_NJ="inconclusive: no-judged-colo$Z
colo=AAA judged=false before=26 after=9 baseline_max=400 change_point=null positive=false late_run=null
colo=BBB judged=false before=26 after=9 baseline_max=400 change_point=null positive=false late_run=null"
check "class-no-judged-colo: the whole output (an unjudged colo shows change_point=null)" "$WANT_NJ" \
  "$(printf '%s\n' "${CASE_INPUT[${NJ:-0}]}" | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") 2>&1)"
# A null-colo row is never a table line (D2): the whole output of ix-null-colo-at-10 has exactly the two real colos.
for i in "${!CASE_NAME[@]}"; do [[ "${CASE_NAME[$i]}" == ix-null-colo-at-10 ]] && NC="$i"; done
WANT_NC="inconclusive: invalid-colo; null_colo_rows=3 null_colo_qualifying=1
colo=AAA judged=true before=26 after=60 baseline_max=400 change_point=2026-11-07T23:00:00Z positive=true late_run=null
colo=BBB judged=true before=26 after=60 baseline_max=400 change_point=null positive=false late_run=null"
check "ix-null-colo-at-10: the whole output (no colo=null table line)" "$WANT_NC" \
  "$(printf '%s\n' "${CASE_INPUT[${NC:-0}]}" | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") 2>&1)"

# --- the recorded-outputs block equals the case list, in order ---------------------------------------------------------------
WANT_OUT=$(for i in "${!CASE_NAME[@]}"; do printf '%s: %s\n' "${CASE_NAME[$i]}" "${CASE_WANT[$i]}"; done)
GOT_OUT=$(region health-colo-r2-outputs | grep -v '^```')
check "runbook: the recorded-outputs block equals this suite's case names and expected lines, in order" "$WANT_OUT" "$GOT_OUT"

# --- a split main read (two H=108 files, split at 2026-11-08T00Z) joins to the same verdict -----------------------------------
JOIN='if (try ((map(.zone) | unique | length) == 1 and all(.[]; .subcommand == "analytics-health-colo") and ([range(1; length) as $i | ((.[$i - 1].window_end | fromdateiso8601) - .[$i - 1].window_hours * 3600) == (.[$i].window_end | fromdateiso8601)] | all)) catch false) then .[0] + {window_hours: (map(.window_hours) | add), rows: (map(.rows) | add), truncated: (map(.truncated) | any), series: (map(.series) | add | sort_by(.hour, .colo))} else {subcommand: "join-refused"} end'
check "runbook: the split-read join command appears exactly once, as a whole line" "1" \
  "$(grep -cxF -- "/usr/bin/env -i /usr/bin/jq -s '$JOIN' \"\$newer\" \"\$older\" > \"\$joined\"" "$RUNBOOK")"
LATER="$PRELUDE .series |= map(select(k >= 1)) | .window_hours = 60 | .rows = (.series | length)"
EARLIER="$PRELUDE .series |= map(select(k <= 0)) | .window_end = \"2026-11-08T00:00:00Z\" | .window_hours = 27 | .rows = (.series | length)"
JOINED=$(/usr/bin/env -i "$JQ" -c -s "$JOIN" <(/usr/bin/env -i "$JQ" -c "$LATER" "$FIXTURE") <(/usr/bin/env -i "$JQ" -c "$EARLIER" "$FIXTURE") 2>&1)
check "split: the joined pair carries the later file's window_end and the summed window" "2026-11-10T12:00:00Z 87 174 false" \
  "$(printf '%s\n' "$JOINED" | /usr/bin/env -i "$JQ" -r '"\(.window_end) \(.window_hours) \(.rows) \(.truncated)"' 2>&1)"
check "split: the joined pair gives the base's whole output" "$WANT_BASE" \
  "$(printf '%s\n' "$JOINED" | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") 2>&1)"
# A join refuses (and the recipe then prints bad-input) for another zone, another subcommand, or a gap between the windows.
for bad in '.zone = "fedcba9876543210fedcba9876543210"' '.subcommand = "analytics-health"' '.window_end = "2026-11-07T23:00:00Z"' '.truncated = true'; do
  check "split: a join whose older half has $bad is refused or flagged (bad-input)" "inconclusive: bad-input" \
    "$(/usr/bin/env -i "$JQ" -c -s "$JOIN" <(/usr/bin/env -i "$JQ" -c "$LATER" "$FIXTURE") <(/usr/bin/env -i "$JQ" -c "$EARLIER | $bad" "$FIXTURE") 2>&1 \
       | /usr/bin/env -i "$JQ" -r -f <(printf '%s\n' "$RECIPE") 2>&1)"
done

# The documented path, end to end: the joined file goes through the pinned four-line run block, from the repository root.
# A correct R1 split (two H=108 halves of the old zone) gives the base output; a refused join stops at the preflight line.
runblock() { # $1 = joined JSON -> the run block's output and its status
  local f rc out
  f=$(mktemp) || { echo "mktemp failed"; return; }
  trap 'rm -f "$f"; trap - RETURN' RETURN
  printf '%s\n' "$1" > "$f"
  out=$(cd "$REPO_ROOT" && /usr/bin/env -i PATH=/usr/bin:/bin file="$f" /bin/bash -c "$(printf '%s\n' "${RUN_LINES[@]}")" 2>&1); rc=$?
  printf '%s\nrc=%s' "$out" "$rc"
}
R1Z='.zone = "5af02a2f394e9ba6e0ea23c381a26b67"'
NEWER="$LATER | $R1Z | .window_end = \"2026-11-12T12:00:00Z\" | .window_hours = 108"
OLDER="$EARLIER | $R1Z | .window_hours = 108"
check "run block: a correct R1 split, joined, gives the base's whole output (rc 0)" "$WANT_BASE
rc=0" "$(runblock "$(/usr/bin/env -i "$JQ" -c -s "$JOIN" <(/usr/bin/env -i "$JQ" -c "$NEWER" "$FIXTURE") <(/usr/bin/env -i "$JQ" -c "$OLDER" "$FIXTURE"))")"
check "run block: a join with a gap stops at the preflight (refused line, rc 1, the recipe never runs)" "refused: <file> is not the pre-registered read (zone, subcommand or R1 window)
rc=1" "$(runblock "$(/usr/bin/env -i "$JQ" -c -s "$JOIN" <(/usr/bin/env -i "$JQ" -c "$NEWER" "$FIXTURE") <(/usr/bin/env -i "$JQ" -c "$OLDER | .window_end = \"2026-11-07T23:00:00Z\"" "$FIXTURE"))" | sed -E 's#refused: [^ ]+ is#refused: <file> is#')"

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
mutate "M11 a null p90 counts as qualifying" x-null-p90-baseline-not-counted 'def q: .count >= 10 and .p90_ms != null;' 'def q: .count >= 10;'
mutate "M12 uniqueness over every row, null colos included" ix-two-null-colos-one-hour '  and (.series | map(select(.colo != null)) | (map([.hour, .colo]) | unique | length) == length);' '  and ((.series | map([.hour, .colo]) | unique | length) == (.series | length));'
mutate "M13 a missing p90_ms key read as null" bad-input-p90-key-absent 'and has("p90_ms") and ' 'and '
mutate "control: comment-only edit" "" '# health-colo R2 recipe:' '# (control) health-colo R2 recipe:'

# --- the exit-status check, accounting and floors (printf + exit 1, never through check/no) -------------------------------
# The exit status is what the runner grades: a child run with one failed row and every floor met must exit 1. The child is
# selected by argv, never by an environment flag, so an inherited variable cannot select it; it sets counters above every
# floor and falls through to the same trailer below, so the child exercises these very lines.
if [[ "${1:-}" == --forced-fail-child ]]; then
  rows_run=100000 mut_run=100000 pass=99999 fail=1
else
  bash "${BASH_SOURCE[0]}" --forced-fail-child >/dev/null 2>&1
  frc=$?
  if [[ "$frc" -ne 1 ]]; then
    printf 'FAIL: exit status: a run with one failed row exited %s, not 1 - the runner would read a failure as green\n' "$frc" >&2
    exit 1
  fi
fi
if [[ "$((pass + fail))" != "$rows_run" ]]; then
  printf 'FAIL: accounting: passes + fails (%s) != rows executed (%s) - a verdict was dropped\n' "$((pass + fail))" "$rows_run" >&2
  exit 1
fi
summary
MUT_FLOOR=13
if [[ "$mut_run" -lt "$MUT_FLOOR" ]]; then
  printf 'FAIL: mutation-row floor: only %s recipe mutation rows ran, need %s (vacuity)\n' "$mut_run" "$MUT_FLOOR" >&2
  exit 1
fi
ROW_FLOOR=96
if [[ "$rows_run" -lt "$ROW_FLOOR" ]]; then
  printf 'FAIL: executed-row floor: only %s rows ran, need at least %s (the exact current count; vacuity)\n' "$rows_run" "$ROW_FLOOR" >&2
  exit 1
fi
if [[ "$fail" -gt 0 ]]; then exit 1; fi
exit 0
