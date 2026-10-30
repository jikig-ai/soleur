# shellcheck shell=bash
# Shared mutation harness for the follow-through probe suites (scripts/followthroughs/*.test.sh). SOURCED, never executed:
# it defines functions only, with no assignment, `set` or `trap` at source time. A suite sources it after its helpers and
# before calling `instrument_selftest`, by `$REPO` (never a BASH_SOURCE path: a mutant copy of a suite runs from a scratch
# directory, and `FT_REPO` is exported before any mutant runs).
#
# Caller contract, all supplied by the suite:
#   variables  SELF SUT MUT LEDGER PASS FAIL FIX_N LEDGER_N   (read at call time; `set -u` makes a missing one abort)
#              FT_INNER is optional (read as ${FT_INNER:-}): set by the battery itself on a mutant's inner run
#   helpers    ok bad check has hasnt  (stay IN each suite: `mutate_helper` neuters them by awk over $SELF, so a
#              definition moved out of the suite would make the h1..h5 rows report "did not land")
#   protocol   a mutant run is `FT_INNER=1 FT_SUT=<mutant> bash $SELF`, so the suite MUST take its probe from
#              `SUT="${FT_SUT:-<default>}"`, derive REPO from an exported `FT_REPO`, and `export FT_REPO` before the
#              battery; a suite that ignores FT_SUT re-runs the pristine probe and every mutant reports SURVIVED.
# The function names below are unprefixed on purpose (the suites' call sites were left unchanged by the extraction);
# only the pure scorer and the floor carry the `mh_` prefix.
#
# MUTATION CREDIT. A mutant is credited as caught only when its inner run exits 1 AND prints its own named
# `FAIL: <fragment>` line (`mh_caught`, the single place that match lives). rc 0 = SURVIVED; any other rc, or a mutant that
# does not parse or did not land, means the instrument itself broke.

# shellcheck disable=SC2154  # the caller-supplied names above

# The repo-wide path guard (byte-identical to every tracked copy): fixture roots are absolute or we stop.
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

# mh_caught <fragment> <inner-run log> [exact]: 0 only when a log line STARTS with `  FAIL: <fragment>` (exactly how `bad` prints
# a row label, so a `FAIL:` quoted mid-line or inside a detail line never counts). Literal match, prefix semantics (a
# fragment is the leading words of a row label), and an empty fragment is never caught. With `exact` (what `mutate_run` passes
# when `mh_frag_unique` says `exact`) the line must EQUAL `  FAIL: <fragment>`, so a longer sibling row cannot credit the shorter
# row's mutant. Prints nothing; the scorer's controls call it directly.
mh_caught() {
  [ -n "${1:-}" ] || return 1
  FRAG="$1" MODE="${3:-}" awk 'BEGIN { p = "  FAIL: " ENVIRON["FRAG"] } (ENVIRON["MODE"] == "exact" ? $0 == p : index($0, p) == 1) { found = 1 } END { exit !found }' "$2"
}

# mh_frag_unique <fragment> <ledger> [fix_n]: pure. Scans the first <fix_n> ledger lines (`ok|bad<TAB>label`; all lines when
# <fix_n> is empty) on the label field only, by literal prefix match. PRINTS one token and keeps the rc binary:
#   unique     zero or exactly one distinct label starts with the fragment (zero: it may name a battery row)
#   exact      the fragment EQUALS one label and two or more labels share the prefix (`...: exit 5` vs `...: exit 5 (30 days or older)`)
#   ambiguous  two or more distinct labels start with it and none equals it
#   empty      no fragment
# rc 0 for unique/exact, 1 otherwise.
mh_frag_unique() {
  local r
  r="$(FRAG="${1:-}" N="${3:-}" awk -F'\t' '
    BEGIN { f = ENVIRON["FRAG"]; n = ENVIRON["N"] }
    f == "" { print "empty"; done = 1; exit }
    n != "" && NR > n + 0 { exit }
    index($2, f) == 1 && !($2 in seen) { seen[$2] = 1; d++; if ($2 == f) e = 1 }
    END { if (!done) print (d <= 1 ? "unique" : (e ? "exact" : "ambiguous")) }' "$2")"
  printf '%s\n' "$r"
  [ "$r" = unique ] || [ "$r" = exact ]
}

# mh_selftest_caught <rc> <log>: 0 only when the mutant suite exited 4 AND a log line STARTS with the self-test banner.
mh_selftest_caught() {
  [ "${1:-}" = 4 ] || return 1
  awk 'index($0, "INSTRUMENT SELF-TEST FAILED") == 1 { found = 1 } END { exit !found }' "$2"
}

instrument_selftest() {
  local p0=$PASS f0=$FAIL n0 p1 f1 p2 f2
  assert_fixture_dir "$LEDGER"
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
  local name="$1" tag="$2" rep="$3" frag="$4" f="$MUT/$1.sh" o="$MUT/$1.out" rc=0 fu ex=""
  assert_fixture_dir "$f"; assert_fixture_dir "$o"
  fu="$(mh_frag_unique "$frag" "$LEDGER" "$FIX_N")" || true
  case "$fu" in
    ambiguous|empty) bad "mutation $name: fragment [$frag] is ambiguous (instrument)"; return ;;
    exact) ex=exact ;;
  esac
  if ! grep -qF -- "$tag" "$SUT"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
  REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
  if cmp -s "$SUT" "$f"; then bad "mutation $name: the mutation did not land (instrument)"; return; fi
  if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant does not parse (instrument)"; return; fi
  FT_INNER=1 FT_SUT="$f" bash "$SELF" > "$o" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
  elif [ "$rc" != 1 ]; then bad "mutation $name: unresolved instrument rc=$rc"
  elif mh_caught "$frag" "$o" "$ex"; then ok "mutation $name: caught by its own FAIL line [$frag]"
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
  assert_fixture_dir "$f"; assert_fixture_dir "$o"
  HELPER="$helper" REP="$rep" awk 'index($0, ENVIRON["HELPER"] "()") == 1 { print ENVIRON["REP"]; next } { print }' "$SELF" > "$f"
  if cmp -s "$SELF" "$f"; then bad "mutation $name: the helper mutation did not land (instrument)"; return; fi
  if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant suite does not parse (instrument)"; return; fi
  FT_INNER=1 FT_SUT="$SUT" bash "$f" > "$o" 2>&1 || rc=$?
  if mh_selftest_caught "$rc" "$o"; then ok "mutation $name: caught by the instrument self-test (rc 4)"
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
