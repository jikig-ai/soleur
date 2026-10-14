#!/usr/bin/env bash
# Wall-clock parsing for suites that bound a step with `timeout` and then assert
# the bound actually fired.
#
# EXTRACTED because both notice-frontmatter suites carried a byte-identical copy
# of these two functions plus their four contract rows (~45 lines). Those two
# files have a documented drift history: the same `assert_eq` pin had to be fixed
# in two separate PRs (#8251 and a follow-up on #8166's head), and the lag
# red-lit a GDPR freshness attestation twice. A helper that must be re-derived
# per file eventually gets re-derived wrongly, so there is now one copy.
#
# A read that is not `digits.digits` makes the CASE FAIL, never pass: under a
# comma-radix locale or an old bash (unset EPOCHREALTIME) a lenient parse would
# compute a zero or garbage elapsed time and `< 6 s` would pass vacuously.

# _epoch_to_us <value> -> integer microseconds on stdout; rc 1 and no output
# when <value> is not digits.digits.
_epoch_to_us() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
  echo $(( ${1%.*} * 1000000 + 10#${1#*.} ))
}

# _wall_verdict <start> <end> <limit_us> -> "PASS" when both reads parse and
# end - start < limit_us; otherwise "FAIL (<why>)". Always exits 0 so a caller
# under `set -e` records the verdict instead of aborting.
_wall_verdict() {
  local s_us e_us
  if ! s_us=$(_epoch_to_us "$1") || ! e_us=$(_epoch_to_us "$2"); then
    printf 'FAIL (unparseable EPOCHREALTIME: start=%q end=%q)' "$1" "$2"
    return 0
  fi
  if (( e_us - s_us < $3 )); then
    echo "PASS"
  else
    echo "FAIL (elapsed $(( e_us - s_us ))us >= $3us)"
  fi
}

# The parser's own contract, before it is trusted with the real measurement.
# Row 3 is the one that matters: a comma radix must FAIL the case.
# Call with the suite's own assert_eq available.
_wall_clock_self_test() {
  echo "TS-cron-5-parser: elapsed-time parser rejects what it cannot read"
  assert_eq "PASS" "$(_wall_verdict "100.000000" "101.500000" 6000000)" \
    "parser: 1.5s elapsed under a 6s limit passes (positive control)"
  assert_eq "FAIL (elapsed 7000000us >= 6000000us)" "$(_wall_verdict "100.000000" "107.000000" 6000000)" \
    "parser: 7s elapsed over a 6s limit fails"
  # Expected value is COMPUTED, not written out: `%q`'s escaping set differs
  # across bash releases (5.3 renders `12,5` as `12\,5`; 3.2 — stock macOS, the
  # host class this work exists to support — does not escape the comma). A
  # hand-written literal here pinned the suite to one bash.
  assert_eq "FAIL (unparseable EPOCHREALTIME: start=$(printf '%q' '12,5') end=$(printf '%q' '13,5'))" \
    "$(_wall_verdict "12,5" "13,5" 6000000)" \
    "parser: comma-radix reads FAIL the case, never pass it"
  assert_eq "FAIL (unparseable EPOCHREALTIME: start=$(printf '%q' '') end=101.000000)" \
    "$(_wall_verdict "" "101.000000" 6000000)" \
    "parser: an empty read (EPOCHREALTIME unset, bash < 5) fails the case"
  echo ""
}
