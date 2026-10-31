# shellcheck shell=bash
# Scorer controls for scripts/lib/mutation-harness.sh, shared by the follow-through probe suites that source that lib
# (#11572 items 8, 9 and 11). SOURCED, never executed: it defines `mh_lib_controls` only, with no assignment, `set` or `trap`
# at source time. One definition, so the lib's controls cannot drift between the suites.
#
# Caller contract (read at call time, like the lib's):
#   helpers    check  (the suite's own: it stays IN the suite so `mutate_helper` can neuter it by awk over $SELF)
#   variables  MUT    an existing, absolute scratch directory. The suite's own scorer block need not have run first: this
#                     file writes every log it reads under its own `mh-` prefix (no dependency on sc-empty.log or any other
#                     suite-created file).
#   functions  the lib itself, sourced first (mh_caught, mh_frag_unique, mh_selftest_caught, mutate_run, mh_floor,
#              assert_fixture_dir)
# Call it ONCE, after the suite has taken FIX_N, inside the battery block, so that every row counts toward MIN_BATTERY.
# Each row is a capture-only `check` in THIS shell; the two lib functions that `exit` (mh_floor, assert_fixture_dir) run in a
# subshell and their rc is read on its own line. Nothing here writes the suite's own ledger except through `check`.
# A control that never goes RED is worthless: each row is checked against a mutant of the lib before it is added.

# shellcheck disable=SC2154  # MUT is caller-supplied (see above)

mh_lib_controls() {
  assert_fixture_dir "$MUT"   # every file below is written under $MUT
  # --- mh_frag_unique: unique / zero / ambiguous / exact / empty, FIX_N edges, literal and prefix-only matching ----------
  # Ledger lines (n = line number): the ambiguous pair sits at 3 and 4, the solo pair at 7 and 8, and two labels hold
  # `needle` only MID-label at 9 and 10 (a prefix-only matcher sees none).
  printf 'ok\tdemo: exit 5\nok\tdemo: exit 5 (30 days or older)\nok\talpha one\nbad\talpha two\nok\tonly row\nbad\tonly row\nok\tsolo\nok\tsolo too\nok\tpre needle a\nok\tpre needle b\n' > "$MUT/mh-ledger"
  mh_fu() { local o rc; o="$(mh_frag_unique "$@")"; rc=$?; echo "$o/$rc"; }
  check "scorer: a fragment that is the leading words of exactly one label (two ledger lines, one distinct label) is unique" unique/0 "$(mh_fu 'only' "$MUT/mh-ledger" 6)"
  check "scorer: a fragment matching no fixture label (a battery-row name) is unique" unique/0 "$(mh_fu 'nothing here' "$MUT/mh-ledger" 6)"
  check "scorer: a fragment that is the leading words of two distinct labels is ambiguous" ambiguous/1 "$(mh_fu 'alpha' "$MUT/mh-ledger" 6)"
  check "scorer: a fragment equal to one label that prefixes a longer sibling is exact (the tie-break)" exact/0 "$(mh_fu 'demo: exit 5' "$MUT/mh-ledger" 6)"
  check "scorer: the longer sibling label alone is unique" unique/0 "$(mh_fu 'demo: exit 5 (30 days or older)' "$MUT/mh-ledger" 6)"
  check "scorer: an empty fragment is refused" empty/1 "$(mh_fu '' "$MUT/mh-ledger" 6)"
  check "scorer: a sibling past FIX_N is not a fixture label" unique/0 "$(mh_fu 'solo' "$MUT/mh-ledger" 7)"
  check "scorer: a sibling at exactly line FIX_N is a fixture label (a unique fragment becomes exact, solo, FIX_N 8)" exact/0 "$(mh_fu 'solo' "$MUT/mh-ledger" 8)"
  check "scorer: a colliding sibling at exactly line FIX_N is a fixture label (alpha, FIX_N 4)" ambiguous/1 "$(mh_fu 'alpha' "$MUT/mh-ledger" 4)"
  check "scorer: the second colliding sibling one line past FIX_N is not a fixture label (alpha, FIX_N 3)" unique/0 "$(mh_fu 'alpha' "$MUT/mh-ledger" 3)"
  check "scorer: an empty FIX_N scans the whole ledger (the two needle labels at lines 9 and 10 collide)" ambiguous/1 "$(mh_fu 'pre needle' "$MUT/mh-ledger" '')"
  check "scorer: a FIX_N before the second needle label leaves the fragment unique" unique/0 "$(mh_fu 'pre needle' "$MUT/mh-ledger" 9)"
  check "scorer: a fragment is matched literally, never as a regular expression" unique/0 "$(mh_fu 'al.ha' "$MUT/mh-ledger" 6)"
  check "scorer: a fragment found only mid-label (two labels hold it) is unique: the match is prefix-only" unique/0 "$(mh_fu 'needle' "$MUT/mh-ledger" 10)"
  # --- exact-mode mh_caught: a longer sibling's FAIL line must not credit the shorter row's mutant -----------------------
  printf '  FAIL: demo: exit 5 (30 days or older)\n' > "$MUT/mh-sibling.log"
  printf '  FAIL: demo: exit 5\n        expected [5] got [2]\n' > "$MUT/mh-own.log"
  mh_verdict_x() { [ -f "$2" ] || { echo missing; return; }; mh_caught "$1" "$2" "${3:-}" && echo yes || echo no; }
  check "scorer: without exact mode the longer sibling's FAIL line credits the fragment (prefix semantics)" yes "$(mh_verdict_x 'demo: exit 5' "$MUT/mh-sibling.log")"
  check "scorer: in exact mode the longer sibling's FAIL line does NOT credit the fragment" no "$(mh_verdict_x 'demo: exit 5' "$MUT/mh-sibling.log" exact)"
  check "scorer: in exact mode the row's own FAIL line is caught" yes "$(mh_verdict_x 'demo: exit 5' "$MUT/mh-own.log" exact)"
  # --- mutate_run itself ---------------------------------------------------------------------------------------------------
  # Refuses an ambiguous or empty fragment, and a fragment check that returned anything but a known token (fail closed), all
  # BEFORE the inner run; scores an exact fragment in exact mode. The inner run is stubbed (a `bash` function in the
  # subshell), so a mutate_run that skips the check or the pass-through would reach it and credit a mutant.
  printf 'echo hi # [mut:x]\n' > "$MUT/mh-sut.sh"
  mh_mr() { # <fragment> <stub inner-run output> [stub mh_frag_unique token: -, or any word to print; absent = the real one]
    # shellcheck disable=SC2034  # LEDGER, SUT, SELF and FIX_N are consumed dynamically by mutate_run
    ( LEDGER="$MUT/mh-ledger"; SUT="$MUT/mh-sut.sh"; SELF=stub; SC_OUT="$2"
      FIX_N=6
      ok() { echo "ok: $1"; }; bad() { echo "bad: $1"; }
      bash() { if [ "${1:-}" = -n ]; then command bash "$@"; else printf '%s\n' "$SC_OUT"; return 1; fi; }
      if [ $# -ge 3 ]; then SC_FU="$3"; mh_frag_unique() { [ "$SC_FU" = - ] || printf '%s\n' "$SC_FU"; return 0; }; fi
      mutate_run sc-mr '[mut:x]' 'echo changed' "$1" )
  }
  check "scorer: mutate_run refuses an ambiguous fragment before the inner run" "bad: mutation sc-mr: fragment [alpha] is ambiguous (instrument)" "$(mh_mr 'alpha' '  FAIL: alpha one')"
  check "scorer: mutate_run refuses an empty fragment as empty (not ambiguous) before the inner run" "bad: mutation sc-mr: fragment [] is empty (instrument)" "$(mh_mr '' '  FAIL: alpha one')"
  check "scorer: mutate_run fails closed when the fragment check prints nothing" "bad: mutation sc-mr: fragment check failed (instrument)" "$(mh_mr 'only' '  FAIL: only row' -)"
  check "scorer: mutate_run fails closed when the fragment check prints an unknown token" "bad: mutation sc-mr: fragment check failed (instrument)" "$(mh_mr 'only' '  FAIL: only row' bogus)"
  check "scorer: mutate_run credits a unique fragment by its FAIL line" "ok: mutation sc-mr: caught by its own FAIL line [only]" "$(mh_mr 'only' '  FAIL: only row')"
  check "scorer: mutate_run does not credit an exact fragment by a longer sibling's FAIL line" "bad: mutation sc-mr: rc=1 but no FAIL line [demo: exit 5] (killed by something else)" "$(mh_mr 'demo: exit 5' '  FAIL: demo: exit 5 (30 days or older)')"
  check "scorer: mutate_run credits an exact fragment by its own FAIL line" "ok: mutation sc-mr: caught by its own FAIL line [demo: exit 5]" "$(mh_mr 'demo: exit 5' '  FAIL: demo: exit 5')"
  # --- mh_selftest_caught (item 8): only rc 4 AND a line STARTING with the self-test banner --------------------------------
  printf 'INSTRUMENT SELF-TEST FAILED: check/has/hasnt cannot tell true from false\n' > "$MUT/mh-st-ok.log"
  printf 'noise INSTRUMENT SELF-TEST FAILED: quoted mid-line\n' > "$MUT/mh-st-mid.log"
  : > "$MUT/mh-st-empty.log"
  mh_st() { [ -f "$2" ] || { echo missing; return; }; mh_selftest_caught "$1" "$2" && echo yes || echo no; }
  check "scorer: rc 4 with the self-test banner at line start is caught" yes "$(mh_st 4 "$MUT/mh-st-ok.log")"
  check "scorer: the self-test banner with rc 1 is not caught" no "$(mh_st 1 "$MUT/mh-st-ok.log")"
  check "scorer: the self-test banner with rc 5 is not caught (only rc 4 is the self-test abort)" no "$(mh_st 5 "$MUT/mh-st-ok.log")"
  check "scorer: rc 4 with the banner only mid-line is not caught" no "$(mh_st 4 "$MUT/mh-st-mid.log")"
  check "scorer: rc 4 with an empty log is not caught" no "$(mh_st 4 "$MUT/mh-st-empty.log")"
  check "scorer: rc 4 with an unreadable log is not caught" no "$(mh_selftest_caught 4 "$MUT/mh-st-absent.log" 2>/dev/null && echo yes || echo no)"
  # --- item 9: mh_floor and assert_fixture_dir refusal rows. Both `exit`, so each runs in a subshell and its rc is read on its
  # own line. ---------------------------------------------------------------------------------------------------------------
  mh_floor_rc() { # <FIX_N> <LEDGER_N> <MIN_FIXTURE> <MIN_BATTERY> [inner] [suite arg]
    local out rc
    # shellcheck disable=SC2034  # FIX_N, LEDGER_N and FT_INNER are consumed dynamically by mh_floor
    out="$( ( FIX_N="$1"; LEDGER_N="$2"; unset FT_INNER; [ -n "${5:-}" ] && FT_INNER=1; mh_floor "$3" "$4" "${6:-}" ) 2>&1 )"
    rc=$?
    echo "$rc|$out"
  }
  check "mh_floor: a short fixture count exits 1 and names the fixture floor" "1|FLOOR: only 5 fixture assertions ran, expected at least 10" "$(mh_floor_rc 5 30 10 5)"
  check "mh_floor: a short battery count exits 1 and names the battery floor" "1|FLOOR: only 2 battery assertions ran, expected at least 5" "$(mh_floor_rc 10 12 10 5)"
  check "mh_floor: sufficient fixture and battery counts pass silently" "0|" "$(mh_floor_rc 10 20 10 5)"
  check "mh_floor: a battery count exactly at the floor passes" "0|" "$(mh_floor_rc 10 15 10 5)"
  check "mh_floor: a battery count one below the floor exits 1" "1|FLOOR: only 4 battery assertions ran, expected at least 5" "$(mh_floor_rc 10 14 10 5)"
  check "mh_floor: under FT_INNER a short count still passes (the inner run is not floored)" "0|" "$(mh_floor_rc 1 1 10 5 inner)"
  check "mh_floor: the suite's --no-battery argument skips the battery floor (a short battery count passes)" "0|" "$(mh_floor_rc 10 12 10 5 '' --no-battery)"
  mh_afd() { # <dir argument>: rc and the FIRST line of the refusal
    local out rc
    out="$( ( assert_fixture_dir "$1" ) 2>&1 )"
    rc=$?
    echo "$rc|${out%%$'\n'*}"
  }
  check "assert_fixture_dir: an empty dir exits 2 naming the empty dir" "2|FATAL: fixture dir is EMPTY; git -C \"\" would operate on $PWD" "$(mh_afd '')"
  check "assert_fixture_dir: a relative dir exits 2 naming the relative path" "2|FATAL: fixture dir rel/dir is RELATIVE; refusing" "$(mh_afd 'rel/dir')"
  check "assert_fixture_dir: a dir containing .. exits 2 naming the dot-dot" "2|FATAL: fixture dir /tmp/a/../b contains ..; refusing" "$(mh_afd '/tmp/a/../b')"
  check "assert_fixture_dir: a trailing .. exits 2 naming the dot-dot" "2|FATAL: fixture dir /tmp/a/.. contains ..; refusing" "$(mh_afd '/tmp/a/..')"
  check "assert_fixture_dir: a /proc dir exits 2 naming the synthetic fs" "2|FATAL: fixture dir /proc/self/x is a synthetic-fs path; refusing" "$(mh_afd '/proc/self/x')"
  check "assert_fixture_dir: a /sys dir exits 2 naming the synthetic fs" "2|FATAL: fixture dir /sys/x is a synthetic-fs path; refusing" "$(mh_afd '/sys/x')"
  check "assert_fixture_dir: a /dev dir exits 2 naming the synthetic fs" "2|FATAL: fixture dir /dev/x is a synthetic-fs path; refusing" "$(mh_afd '/dev/x')"
  check "assert_fixture_dir: / exits 2 naming the filesystem root" "2|FATAL: fixture dir resolves to the filesystem root; refusing" "$(mh_afd '/')"
  check "assert_fixture_dir: // exits 2 naming the filesystem root" "2|FATAL: fixture dir resolves to the filesystem root; refusing" "$(mh_afd '//')"
  check "assert_fixture_dir: /. exits 2 naming the filesystem root" "2|FATAL: fixture dir resolves to the filesystem root; refusing" "$(mh_afd '/.')"
  check "assert_fixture_dir: an absolute temp path passes silently" "0|" "$(mh_afd "$MUT/mh-fixture")"
}
