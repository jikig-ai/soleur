# shellcheck shell=bash
# Shared mutation harness for the follow-through probe suites (scripts/followthroughs/*.test.sh). SOURCED, never executed:
# it defines functions only, with no assignment, `set` or `trap` at source time. A suite sources it after its helpers and
# before calling `instrument_selftest`, by `$REPO` (never a BASH_SOURCE path: a mutant copy of a suite runs from a scratch
# directory, and `FT_REPO` is exported before any mutant runs).
#
# Caller contract, all supplied by the suite:
#   variables  SELF SUT MUT REPO LEDGER PASS FAIL FIX_N LEDGER_N FT_INNER
#   helpers    ok bad check has hasnt  (stay IN each suite: `mutate_helper` neuters them by awk over $SELF, so a
#              definition moved out of the suite would make the h1..h5 rows report "did not land")
# The suites run `set -uo pipefail`, so nothing here reads an unset variable unguarded.
#
# MUTATION CREDIT. A mutant is credited as caught only when its inner run exits 1 AND prints its own named
# `FAIL: <fragment>` line (`mh_caught`, the single place that match lives). rc 0 = SURVIVED; any other rc, or a mutant that
# does not parse or did not land, means the instrument itself broke.

# shellcheck disable=SC2154  # the caller-supplied names above

# mh_caught <fragment> <inner-run log>: 0 only when the log holds a line containing `FAIL: <fragment>` (that is how `bad`
# prints a row label). Prints nothing; the scorer's controls call it directly.
mh_caught() { grep -qF -- "FAIL: $1" "$2"; }

instrument_selftest() {
  local p0=$PASS f0=$FAIL n0 p1 f1 p2 f2
  n0="$(wc -l < "$LEDGER")"
  { check st 1 2; has st abc z; hasnt st abc b; } >/dev/null
  p1=$((PASS - p0)); f1=$((FAIL - f0))
  { check st 1 1; has st abc b; hasnt st abc z; } >/dev/null
  p2=$((PASS - p0 - p1)); f2=$((FAIL - f0 - f1))
  PASS=$p0; FAIL=$f0
  head -n "$n0" "$LEDGER" > "$LEDGER.t" && mv "$LEDGER.t" "$LEDGER"
  if [ "$p1/$f1/$p2/$f2" != "0/3/3/0" ]; then
    echo "INSTRUMENT SELF-TEST FAILED: check/has/hasnt cannot tell true from false (false-block pass/fail $p1/$f1, true-block pass/fail $p2/$f2)"
    exit 4
  fi
}

run_battery() { [ -z "${FT_INNER:-}" ] && [ "${1:-}" != "--no-battery" ]; }

# mutate_run <name> <tag-or-unique-text> <replacement line> <expected FAIL fragment>
mutate_run() {
  local name="$1" tag="$2" rep="$3" frag="$4" f="$MUT/$1.sh" o="$MUT/$1.out" rc=0
  if ! grep -qF -- "$tag" "$SUT"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
  REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
  if cmp -s "$SUT" "$f"; then bad "mutation $name: the mutation did not land (instrument)"; return; fi
  if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant does not parse (instrument)"; return; fi
  FT_INNER=1 FT_SUT="$f" bash "$SELF" > "$o" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
  elif [ "$rc" != 1 ]; then bad "mutation $name: unresolved instrument rc=$rc"
  elif mh_caught "$frag" "$o"; then ok "mutation $name: caught by its own FAIL line [$frag]"
  else bad "mutation $name: rc=1 but no FAIL line [$frag] (killed by something else)"; fi
}

# mutate_sub <name> <unique text> <from> <to> <expected FAIL fragment>: replace <from> by <to> inside the ONE line holding <unique text>
mutate_sub() {
  local line new
  line="$(grep -F -- "$2" "$SUT" || true)"
  if [ -z "$line" ] || [ "$(printf '%s\n' "$line" | wc -l)" != 1 ]; then bad "mutation $1: the text [$2] matches exactly one line (instrument)"; return; fi
  new="${line/"$3"/"$4"}"
  if [ "$new" = "$line" ]; then bad "mutation $1: [$3] is present in the line (instrument)"; return; fi
  mutate_run "$1" "$2" "$new" "$5"
}

# mutate_helper <name> <helper> <neutered definition>: the self-test must abort the run (rc 4) on a copy of THIS file
mutate_helper() {
  local name="$1" helper="$2" rep="$3" f="$MUT/$1.test.sh" o="$MUT/$1.out" rc=0
  HELPER="$helper" REP="$rep" awk 'index($0, ENVIRON["HELPER"] "()") == 1 { print ENVIRON["REP"]; next } { print }' "$SELF" > "$f"
  if cmp -s "$SELF" "$f"; then bad "mutation $name: the helper mutation did not land (instrument)"; return; fi
  if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant suite does not parse (instrument)"; return; fi
  FT_INNER=1 FT_SUT="$SUT" bash "$f" > "$o" 2>&1 || rc=$?
  if [ "$rc" = 4 ] && grep -qF -- "INSTRUMENT SELF-TEST FAILED" "$o"; then ok "mutation $name: caught by the instrument self-test (rc 4)"
  else bad "mutation $name: the neutered helper went undetected (rc=$rc)"; fi
}

# mh_floor <MIN_FIXTURE> <MIN_BATTERY> <suite-arg>: the anti-vacuity floor tail. <suite-arg> is the SUITE's own "${1:-}",
# because inside a function $1 is MIN_FIXTURE and `run_battery` needs the `--no-battery` argument.
mh_floor() {
  if [ -z "${FT_INNER:-}" ]; then
    if [ "$FIX_N" -lt "$1" ]; then printf 'FLOOR: only %s fixture assertions ran, expected at least %s\n' "$FIX_N" "$1"; exit 1; fi
    if run_battery "${3:-}" && [ $((LEDGER_N - FIX_N)) -lt "$2" ]; then printf 'FLOOR: only %s battery assertions ran, expected at least %s\n' "$((LEDGER_N - FIX_N))" "$2"; exit 1; fi
  fi
}
