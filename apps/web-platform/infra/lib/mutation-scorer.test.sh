#!/usr/bin/env bash
# Self-test for mutation-scorer.sh (#8855) — the shared row-verdict scorer every web-platform infra
# mutation battery routes through.
#
# The contract under test: mutation_scorer_failed_on returns 0 exactly when every needle is a
# substring of some failure-prefixed line of the log, 1 when one is not, and EXITS 2 on anything
# it cannot score — independent of how the kernel schedules the processes involved.
#
# `pipefail` is load-bearing: without it the old piped-early-exit shape returns 0 on S1 and the
# row that exists to catch it survives. Every call runs in a subshell that prints RAN only if the
# lib RETURNED, and is asserted in THIS shell: an unexpected abort is a row failure rather than
# the end of the suite, an abort row proves the lib EXITED (a `return 2` would reach RAN and
# continue a battery's own shell), and a call that never ran (a failed redirect) cannot pass.
#
# Row ids S3, S4, S12 and S13 were cut at plan review; the gaps are deliberate.
#
# Exit: 0 green; 1 any row failed or the assertion count moved; 2 set-up fault (HARNESS ABORT).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "HARNESS ABORT: could not resolve this suite's directory" >&2; exit 2; }
# shellcheck source=apps/web-platform/infra/lib/mutation-scorer.sh
source "$HERE/mutation-scorer.sh" || { echo "HARNESS ABORT: could not source $HERE/mutation-scorer.sh" >&2; exit 2; }

T="$(mktemp -d -t mutation-scorer-test.XXXXXXXX)" || { echo "HARNESS ABORT: cannot create a scratch dir" >&2; exit 2; }
[[ "$T" == /* && -d "$T" && ! -L "$T" ]] || { echo "HARNESS ABORT: bad scratch dir '$T'" >&2; exit 2; }
trap 'rm -rf -- "$T"' EXIT INT TERM

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# The ERE ssl-full-mitigation and www-apex-canonicalizer pass. A bare `|` is alternation here.
ERE_ALT='^  FAIL|^\[FATAL\]'

# --- fixtures -------------------------------------------------------------------
# S1: the needle is the FIRST failure line and ~1.2 MiB of failure output follows it — the shape
# an early-exit reader on a pipe cannot survive. The PASS line carries `  FAIL` mid-line, so a
# scorer that loses its `^` anchor or its failure-line scope is caught. The last line is the
# only `[FATAL]` line, so a scorer that keeps only the first failure line, or drops `-E` (a
# bare `|` is a literal in a basic regex), cannot see it.
FX="$T/s1.log"
awk 'BEGIN {
  print "  PASS: SELFTEST-ONLY-ON-PASS would  FAIL if unscoped"
  print "  FAIL: SELFTEST-TARGET"
  pad = sprintf("%040d", 0); gsub(/0/, "y", pad)
  for (i = 0; i < 20000; i++) printf "  FAIL: filler %06d %s\n", i, pad
  print "[FATAL] SELFTEST-LAST-FATAL"
}' > "$FX" || { echo "HARNESS ABORT: could not write the S1 fixture" >&2; exit 2; }
line1="$(sed -n 1p "$FX")"; line2="$(sed -n 2p "$FX")"
[[ "$line2" == "  FAIL: SELFTEST-TARGET" ]] \
  || { echo "HARNESS ABORT: S1's needle is not line 2 of its fixture, so S1 tests nothing" >&2; exit 2; }
# Pin the CAUSE, not the file size: the bytes still to be written AFTER the needle line are what
# an early-exit reader loses on. A needle moved to the end keeps the size and disarms the row.
total_bytes="$(wc -c < "$FX")"
after_needle=$(( total_bytes - ${#line1} - ${#line2} - 2 ))
(( after_needle >= 1048576 )) \
  || { echo "HARNESS ABORT: S1 has only $after_needle bytes after its needle (need >= 1048576), so S1 tests nothing" >&2; exit 2; }

fixture() { # <name> <content, backslash escapes expanded> — a small fixture, or a set-up abort
  printf '%b' "$2" > "$T/$1" || { echo "HARNESS ABORT: could not write the $1 fixture" >&2; exit 2; }
}
fixture pass-only.log     '  PASS: one\n  PASS: two SELFTEST-TARGET\n'
fixture glob-absent.log   '  FAIL: saw a bare letter a here\n'
fixture glob-present.log  '  FAIL: literal [ab]* token\n'
fixture option.log        '  FAIL: deploy --branch main was not pinned\n'
fixture bracket-ok.log    '[ok] SELFTEST-BRACKET only on a pass line\n'
fixture bracket-fail.log  '[FAIL] SELFTEST-BRACKET\n'
fixture nul.log           '  FAIL: a\000b SELFTEST-NUL\n'

# --- row helpers ------------------------------------------------------------------
# run_scorer <scorer-args...> — sets RC, and RAN=1 iff the lib RETURNED (never set by an exit).
run_scorer() {
  RC=0
  ( mutation_scorer_failed_on "$@"; r=$?; printf 'RAN\n'; exit "$r" ) >"$T/out" 2>"$T/err" || RC=$?
  RAN=0; [[ "$(cat "$T/out" 2>/dev/null)" == "RAN" ]] && RAN=1
}
# want_rc <id> <want-rc> <description> <scorer-args...>
want_rc() {
  local id="$1" want="$2" desc="$3"; shift 3
  run_scorer "$@"
  if [[ "$RC" == "$want" && "$RAN" == 1 ]]; then
    pass "$id $desc (rc=$RC)"
  else
    fail "$id $desc — want rc=$want from a RETURN, got rc=$RC ran=$RAN: $(head -c 300 "$T/err")"
  fi
}
# want_abort <id> <description> <scorer-args...> — rc 2, the lib's own abort text, and no RAN (it
# exited). A bare rc 2 could be bash misuse, which is not the lib refusing the input.
want_abort() {
  local id="$1" desc="$2"; shift 2
  run_scorer "$@"
  if [[ "$RC" == 2 && "$RAN" == 0 ]] && grep -qF 'HARNESS ABORT: mutation_scorer:' "$T/err"; then
    pass "$id $desc aborts (rc=2)"
  else
    fail "$id $desc — want an EXIT 2 with 'HARNESS ABORT: mutation_scorer:', got rc=$RC ran=$RAN: $(head -c 300 "$T/err")"
  fi
}

# --- instrument self-test -----------------------------------------------------
# Drive every verdict-owning helper once with an input that MUST fail, and refuse to continue
# unless each failure was counted. pass()/fail() alone prove dispatch; want_rc/want_abort own the
# verdicts, and a helper that always said yes would pass every row below. Output is discarded so
# the expected FAILs never reach a runner's failure-marker scan.
{
  pass "instrument (pass)"
  fail "instrument (fail)"
  want_rc    I1 0 "want_rc must reject rc 1"            "$T/pass-only.log" "$ERE_ALT" SELFTEST-TARGET
  want_abort I2   "want_abort must reject a clean return" "$FX" "$ERE_ALT" SELFTEST-TARGET
  want_abort I3   "want_abort must reject rc 1"          "$FX" "$ERE_ALT" SELFTEST-NOT-IN-LOG
} >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 4 ]]; then
  printf 'INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/4.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
PASS=0; FAIL=0

# --- rows ---------------------------------------------------------------------------
want_rc    S1   0 "needle first, ~1.2 MiB of failure lines after it" "$FX" "$ERE_ALT" SELFTEST-TARGET
want_rc    S1b  0 "needles on different failure lines (first and last)" "$FX" "$ERE_ALT" SELFTEST-TARGET SELFTEST-LAST-FATAL
want_rc    S2   1 "needle present only on a PASS line" "$FX" "$ERE_ALT" SELFTEST-ONLY-ON-PASS
want_rc    S5   1 "second needle missing" "$FX" "$ERE_ALT" SELFTEST-TARGET SELFTEST-NOT-IN-LOG
want_rc    S5b  1 "first needle missing" "$FX" "$ERE_ALT" SELFTEST-NOT-IN-LOG SELFTEST-TARGET
want_rc    S6   1 "log with no failure lines (grep rc 1 is a miss, not an abort)" "$T/pass-only.log" "$ERE_ALT" SELFTEST-TARGET
want_abort S7     "an empty needle" "$FX" "$ERE_ALT" ""
want_abort S8     "an empty second needle" "$FX" "$ERE_ALT" SELFTEST-TARGET ""
want_abort S9     "zero needles" "$FX" "$ERE_ALT"
want_abort S10    "an unreadable log" "$T/no-such.log" "$ERE_ALT" SELFTEST-TARGET
want_abort S11    "an ERE that does not compile" "$FX" '(' SELFTEST-TARGET
want_rc    S14a 1 "glob metacharacters in a needle are literal (absent literally)" "$T/glob-absent.log" '^  FAIL' '[ab]*'
want_rc    S14b 0 "glob metacharacters in a needle are literal (present literally)" "$T/glob-present.log" '^  FAIL' '[ab]*'
want_rc    S15  0 "an option-shaped needle is literal" "$T/option.log" '^  FAIL' '--branch'
want_rc    S16a 1 "the escaped [FAIL] ERE does not match a pass line" "$T/bracket-ok.log" '\[FAIL\]' SELFTEST-BRACKET
want_rc    S16b 0 "the escaped [FAIL] ERE matches a [FAIL] line" "$T/bracket-fail.log" '\[FAIL\]' SELFTEST-BRACKET
want_abort S17    "a needle containing a newline" "$FX" "$ERE_ALT" $'SELFTEST-TARGET\n  FAIL: filler'
want_rc    S18  0 "a NUL byte on the failure line does not hide it" "$T/nul.log" '^  FAIL' SELFTEST-NUL

# --- assertion-count pin ----------------------------------------------------------------
# Counts assertion CALLS. Reported with printf + exit, never through pass()/fail().
EXPECTED=18
if (( PASS != EXPECTED || FAIL != 0 )); then
  printf 'mutation-scorer self-test: %d passed, %d failed, %d expected passes\n' "$PASS" "$FAIL" "$EXPECTED"
  exit 1
fi
echo "mutation-scorer self-test: ALL PASS"
