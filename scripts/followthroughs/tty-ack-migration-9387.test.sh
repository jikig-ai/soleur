#!/usr/bin/env bash
# Suite for tty-ack-migration-9387.sh. The probe is NOTIFY-ONLY, so the contract under test is
# negative: no input and no source edit may make it exit 0 (the sweeper would CLOSE the tracker)
# or 1 (read as FAIL). Drives every exit arm through a fixed-clock seam, pins the probe's source,
# and mutates a copy of it to prove the checks can go red.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/tty-ack-migration-9387.sh"
# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh. plugins/soleur/test/fixture-dir-operand-assert.test.sh
# compares every copy in the tree against that one with comments stripped — edit there, then
# re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

if [ ! -f "$PROBE" ]; then
  printf 'FATAL: probe missing: %s\n' "$PROBE" >&2
  exit 2
fi

SUITE_TMP=$(mktemp -d "${TMPDIR:-/var/tmp}/ft-9387.XXXXXX")
assert_fixture_dir "$SUITE_TMP"
trap 'rm -rf "$SUITE_TMP"' EXIT

pass=0; failc=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { failc=$((failc + 1)); printf 'FAIL %s\n' "$1"; }

# Reporter self-test: each helper must move its own counter, or the verdict below means nothing.
ok "selftest-ok" >/dev/null; no "selftest-no" >/dev/null
if [ "$pass" -ne 1 ] || [ "$failc" -ne 1 ]; then
  printf 'INSTRUMENT FAIL: pass/fail=%s/%s after one call each\n' "$pass" "$failc" >&2
  exit 2
fi
pass=0; failc=0

BASH_ABS="$(command -v bash)"

# Stub gh and curl: log every call and refuse. The probe must never reach either.
BIN="$SUITE_TMP/bin"
mkdir -p "$BIN"
assert_fixture_dir "$BIN"
CALLS="$SUITE_TMP/calls.log"
assert_fixture_dir "$CALLS"
for t in gh curl; do
  assert_fixture_dir "$BIN/$t"
  cat > "$BIN/$t" <<'STUBEOF'
#!/usr/bin/env bash
[ -n "${STUB_CALLS:-}" ] && printf '%s %s\n' "${0##*/}" "$*" >> "$STUB_CALLS"
exit 99
STUBEOF
  chmod +x "$BIN/$t"
done

# A `date` that is present but prints garbage, and a PATH directory holding no `date` at all.
GARB="$SUITE_TMP/garb"
mkdir -p "$GARB"
assert_fixture_dir "$GARB"
assert_fixture_dir "$GARB/date"
printf '#!/bin/sh\necho garbage\n' > "$GARB/date"
chmod +x "$GARB/date"
EMPTYDIR="$SUITE_TMP/empty"
mkdir -p "$EMPTYDIR"
assert_fixture_dir "$EMPTYDIR"

# The deadline, computed here with a different date spelling than the probe's, then cross-checked.
DEADLINE=$(date -u -d '2026-10-16T00:00:00Z' +%s)
DEADLINE_ALT=$(date -u -d '2026-10-16 00:00:00 UTC' +%s)
if [ "$DEADLINE" != "$DEADLINE_ALT" ]; then
  printf 'INSTRUMENT FAIL: two date spellings of the deadline disagree (%s vs %s)\n' "$DEADLINE" "$DEADLINE_ALT" >&2
  exit 2
fi
BEFORE=$(date -u -d '2026-10-05T12:00:00Z' +%s)
AFTER=$((DEADLINE + 3600))

# run_probe <probe> [VAR=val ...] -> sets OUT (stdout+stderr) and RC. LC_ALL=C.UTF-8 is forced in so the
# probe's own `export LC_ALL=C` is what is under test; bash is invoked by absolute path so a caller's PATH
# override cannot hide the interpreter.
OUT=""; RC=0
run_probe() {
  local probe=$1; shift
  OUT=$(env LC_ALL=C.UTF-8 STUB_CALLS="$CALLS" "$@" "$BASH_ABS" "$probe" 2>&1); RC=$?
}

# case_ <name> <want-rc> <want-substring> [VAR=val ...]
case_() {
  local name=$1 want=$2 sub=$3; shift 3
  run_probe "$PROBE" "$@"
  if [ "$RC" -eq "$want" ] && [[ "$OUT" == *"$sub"* ]] && [ "$RC" -ne 0 ] && [ "$RC" -ne 1 ]; then ok "$name"
  else no "$name (rc=$RC want=$want out=${OUT:0:160})"; fi
}

# Control: case_ must be able to FAIL. A case_ that always said yes would make every row below vacuous.
case_ control-must-fail 99 "x" NOW_EPOCH="$AFTER" >/dev/null
if [ "$pass" -ne 0 ] || [ "$failc" -ne 1 ]; then
  printf 'INSTRUMENT FAIL: case_ did not reject a wrong expectation (pass/fail=%s/%s)\n' "$pass" "$failc" >&2
  exit 2
fi
pass=0; failc=0

# --- the clock table: one copy, used for the real probe (report) and for every mutant (quiet)
T_NAME=(); T_RC=(); T_SUB=(); T_VAL=()
row() { T_NAME+=("$1"); T_RC+=("$2"); T_SUB+=("$3"); T_VAL+=("$4"); }
row epoch-zero                 2 "NOT YET"          0
row today                      2 "NOT YET"          "$BEFORE"
row deadline-minus-1s          2 "NOT YET"          "$((DEADLINE - 1))"
row deadline-exactly           5 "ACTION REQUIRED"  "$DEADLINE"
row deadline-plus-1s           5 "ACTION REQUIRED"  "$((DEADLINE + 1))"
row year-2100                  5 "ACTION REQUIRED"  4102444800
row zero-padded-before         2 "NOT YET"          0000000009
row zero-padded-above-deadline 5 "ACTION REQUIRED"  "00$((DEADLINE + 3600))"
row clock-letters              3 "CANNOT ESTABLISH" abc
row clock-negative             3 "CANNOT ESTABLISH" -5
row clock-fractional           3 "CANNOT ESTABLISH" 1.5
row clock-13-digits            3 "CANNOT ESTABLISH" 1234567890123
row clock-trailing-newline     3 "CANNOT ESTABLISH" $'1792108800\n'
row clock-fullwidth-digits     3 "CANNOT ESTABLISH" $'\xef\xbc\x91\xef\xbc\x97\xef\xbc\x99'
row clock-arabic-indic-digits  3 "CANNOT ESTABLISH" $'\xd9\xa1\xd9\xa7\xd9\xa9'

SAW_01=0; TABLE_BAD=0
# run_table <probe> <report|quiet>: rc and verdict word must both match, and rc must never be 0 or 1.
run_table() {
  local probe=$1 mode=$2 i
  TABLE_BAD=0
  for i in "${!T_NAME[@]}"; do
    run_probe "$probe" NOW_EPOCH="${T_VAL[$i]}"
    if [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; then SAW_01=1; fi
    if [ "$RC" -eq "${T_RC[$i]}" ] && [[ "$OUT" == *"${T_SUB[$i]}"* ]] && [ "$RC" -ne 0 ] && [ "$RC" -ne 1 ]; then
      if [ "$mode" = report ]; then ok "${T_NAME[$i]}"; fi
    else
      TABLE_BAD=$((TABLE_BAD + 1))
      if [ "$mode" = report ]; then no "${T_NAME[$i]} (rc=$RC want=${T_RC[$i]} out=${OUT:0:120})"; fi
    fi
  done
}

# exit_ops <file>: the operand of every `exit` on an executable (non-comment) line; a bare exit prints nothing.
exit_ops() {
  grep -vE '^[[:space:]]*#' "$1" | grep -oE '\bexit\b([[:space:]]+[^[:space:];&|)]+)?' | sed -E 's/^exit[[:space:]]*//'
}

# pins <file>: the source-level half of the contract. Prints the first reason and returns 1 on any breach.
pins() {
  local f=$1 n bad
  n=$(grep -vE '^[[:space:]]*#' "$f" | grep -cE '\bexit\b')
  if [ "$n" -lt 3 ]; then echo "only $n exit sites (floor 3)"; return 1; fi
  bad=$(exit_ops "$f" | grep -vxE '2|3|5' | head -n 1)
  if [ -n "$bad" ] || [ "$(exit_ops "$f" | wc -l)" -ne "$n" ]; then echo "exit operand outside {2,3,5}: '${bad:-bare exit}'"; return 1; fi
  if grep -vE '^[[:space:]]*#' "$f" | grep -qE '(^|[[:space:];])set[[:space:]]+(-[a-zA-Z]*[eu]|-o[[:space:]]+(errexit|nounset))'; then
    echo "set -e / set -u present"; return 1
  fi
  if grep -vE '^[[:space:]]*#' "$f" | grep -qE '\btrap\b'; then echo "trap present"; return 1; fi
  if grep -vE '^[[:space:]]*#' "$f" | grep -qE '\b(gh|curl|wget)\b'; then echo "gh/curl/wget on an executable line"; return 1; fi
  return 0
}

# nogh_clean <probe>: neither verdict arm may reach the stub gh/curl on PATH.
nogh_clean() {
  local probe=$1 v
  assert_fixture_dir "$CALLS"
  : > "$CALLS"
  for v in "$BEFORE" "$AFTER"; do run_probe "$probe" PATH="$BIN:/usr/bin:/bin" NOW_EPOCH="$v"; done
  [ ! -s "$CALLS" ]
}

# check_all <probe>: pins + clock table + no-gh. 0 only when every one of them is clean.
check_all() {
  local probe=$1 bad=0
  pins "$probe" >/dev/null || bad=1
  run_table "$probe" quiet
  [ "$TABLE_BAD" -eq 0 ] || bad=1
  nogh_clean "$probe" || bad=1
  return "$bad"
}

# --- the real probe
run_table "$PROBE" report
if [ "$SAW_01" -eq 0 ]; then ok "table-never-rc-0-or-1"; else no "table-never-rc-0-or-1 (a clock row produced rc 0 or 1)"; fi

run_probe "$PROBE" NOW_EPOCH=""
if { [ "$RC" -eq 2 ] || [ "$RC" -eq 5 ]; } && [[ "$OUT" == *"2026-10-16"* ]]; then ok "empty-seam-falls-through-to-real-clock"
else no "empty-seam-falls-through-to-real-clock (rc=$RC)"; fi

# date unusable: absent (empty PATH dir) and garbage-printing, each with and without the clock seam.
run_probe "$PROBE" PATH="$EMPTYDIR"
if [ "$RC" -eq 3 ]; then ok "date-absent-no-seam"; else no "date-absent-no-seam (rc=$RC)"; fi
run_probe "$PROBE" PATH="$EMPTYDIR" NOW_EPOCH="$AFTER"
if [ "$RC" -eq 3 ]; then ok "date-absent-with-seam"; else no "date-absent-with-seam (rc=$RC)"; fi
run_probe "$PROBE" PATH="$GARB:/usr/bin:/bin"
if [ "$RC" -eq 3 ] && [[ "$OUT" == *"CANNOT ESTABLISH"* ]]; then ok "date-garbage-no-seam"; else no "date-garbage-no-seam (rc=$RC)"; fi
run_probe "$PROBE" PATH="$GARB:/usr/bin:/bin" NOW_EPOCH="$AFTER"
if [ "$RC" -eq 3 ] && [[ "$OUT" == *"CANNOT ESTABLISH"* ]]; then ok "date-garbage-with-seam"; else no "date-garbage-with-seam (rc=$RC)"; fi

# The production shape: the sweeper's env -i, no seams. Clock-independent outcomes only, so the suite does
# not rot on the deadline. Credential canaries are set in the environment and must never be printed.
OUT=$(env -i PATH=/usr/bin:/bin HOME="$SUITE_TMP" GH_TOKEN=canary-gh-9387 SENTRY_ACTIONS_RO_TOKEN=canary-sentry-9387 "$BASH_ABS" "$PROBE" 2>&1); RC=$?
if [ "$RC" -eq 2 ] || [ "$RC" -eq 5 ]; then ok "prod-shape-rc-in-2-or-5"; else no "prod-shape-rc-in-2-or-5 (rc=$RC out=${OUT:0:120})"; fi
if [[ "$OUT" != *canary-gh-9387* && "$OUT" != *canary-sentry-9387* ]]; then ok "prod-shape-prints-no-credential"
else no "prod-shape-prints-no-credential"; fi

# No gh / curl on either verdict arm.
if nogh_clean "$PROBE"; then ok "no-gh-or-curl-call-on-either-arm"; else no "no-gh-or-curl-call-on-either-arm ($(head -n 1 "$CALLS"))"; fi

# Both verdict messages go to stdout and name the date; exit-5 carries the two-step instruction in order.
run_probe "$PROBE" NOW_EPOCH="$BEFORE"
if [[ "$OUT" == *"2026-10-16"* ]]; then ok "not-yet-names-the-date"; else no "not-yet-names-the-date"; fi
OUT_STDOUT=$(env LC_ALL=C.UTF-8 NOW_EPOCH="$AFTER" "$BASH_ABS" "$PROBE" 2>/dev/null)
if [[ "$OUT_STDOUT" == *"2026-10-16"* && "$OUT_STDOUT" == *"ACTION REQUIRED"* ]]; then ok "action-required-on-stdout-names-the-date"
else no "action-required-on-stdout-names-the-date"; fi
IA=${OUT_STDOUT%%"(a)"*}; IB=${OUT_STDOUT%%"(b)"*}
if [[ "$OUT_STDOUT" == *"(a)"* && "$OUT_STDOUT" == *"(b)"* && ${#IA} -lt ${#IB} ]]; then ok "step-a-precedes-step-b"
else no "step-a-precedes-step-b"; fi
A_PART=${OUT_STDOUT#*"(a)"}; A_PART=${A_PART%%"(b)"*}
if [[ "$A_PART" == *"bootstrap-runs.jsonl"* && "$A_PART" == *"founder"* && "$A_PART" == *"ADR-264"* ]]; then ok "step-a-names-ledger-founder-adr"
else no "step-a-names-ledger-founder-adr"; fi
if [[ "$A_PART" == *"ledger line is not evidence of approval"* && "$A_PART" == *"approved by YOU at the prompt"* ]]; then ok "step-a-asks-for-the-operators-own-approval"
else no "step-a-asks-for-the-operators-own-approval"; fi
B_PART=${OUT_STDOUT#*"(b)"}
if [[ "$B_PART" == *"start the migration"* ]]; then ok "step-b-says-start-the-migration"; else no "step-b-says-start-the-migration"; fi

# Direct source pins on the real probe.
if why=$(pins "$PROBE"); then ok "source-pins-exit-set-no-errexit-no-trap-no-gh"; else no "source-pins ($why)"; fi
if grep -qE '^export LC_ALL=C$' "$PROBE"; then ok "pin-lc-all-c"; else no "pin-lc-all-c"; fi
if grep -q 'NOTIFY-ONLY' "$PROBE" && grep -qE '^# RETIREMENT:' "$PROBE"; then ok "header-has-notify-only-and-retirement"
else no "header-has-notify-only-and-retirement"; fi

# --- mutation arms: one edit to a copy of the probe; the checks above, run against the copy, must go red.
# The edit is asserted to have LANDED (a mutant identical to the probe would report the baseline), and the
# unmutated copy goes through the identical check_all and must come out clean.
assert_fixture_dir "$SUITE_TMP/pristine.sh"
cp "$PROBE" "$SUITE_TMP/pristine.sh"
if check_all "$SUITE_TMP/pristine.sh"; then ok "mutation-control-pristine-copy-is-clean"; else no "mutation-control-pristine-copy-is-clean"; fi

# mutant <name> <old> <new> [all]
mutant() {
  local name=$1 old=$2 new=$3 all=${4:-} dest="$SUITE_TMP/mutant-$1.sh" src
  src=$(<"$PROBE")
  if [ -n "$all" ]; then src=${src//"$old"/"$new"}; else src=${src/"$old"/"$new"}; fi
  assert_fixture_dir "$dest"
  printf '%s\n' "$src" > "$dest"
  if cmp -s "$PROBE" "$dest"; then no "$name (the mutation did not land)"; return; fi
  if check_all "$dest"; then no "$name (mutant NOT caught)"; else ok "$name"; fi
}
mutant M1-exit-5-becomes-exit-0       $'\n  exit 5'              $'\n  exit 0'
mutant M2a-dead-exit-1-after-last     $'\nexit 2'               $'\nexit 2\nexit 1'
mutant M2b-variable-exit-operand      $'\n  exit 5'              $'\n  rc5=5\n  exit $rc5'
mutant M3-ge-becomes-gt               '$NOW >= 10#'              '$NOW > 10#'
mutant M4-octal-hazard-no-base-prefix '10#'                      ''                        all
mutant M5-verdict-falls-off-the-end   $'\nexit 2'               $'\ntrue'
mutant M6-adds-a-gh-call              $'export LC_ALL=C\n'     $'export LC_ALL=C\ngh issue view 9387 >/dev/null 2>&1\n'

printf '\n%s passed, %s failed\n' "$pass" "$failc"
if [ "$pass" -lt 41 ]; then
  printf 'FAIL: ran only %s passing assertions (<41)\n' "$pass" >&2
  exit 1
fi
[ "$failc" -eq 0 ]
