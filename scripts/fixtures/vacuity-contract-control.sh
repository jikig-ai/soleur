#!/usr/bin/env bash
# SYNTHESIZED must-PASS control for scripts/guard-vacuity-floor.test.sh.
#
# This file is NOT named `*.test.sh`, deliberately: the guard's population sweep enumerates
# tracked `*.test.sh`, so this fixture sits OUTSIDE the derived population by construction.
# That is the whole point. The guard's earlier "controls" were population members already
# exercised by the main loop, so they asserted nothing beyond it — a control that is also a
# subject is not a control.
#
# It is built to the anti-vacuity contract using counter and helper names that appear nowhere
# else in the repo (`tally` / `good` / `bad_n`, helpers `yay`/`nope`), so a guard that only
# works against the names it was written for will fail here. It must pass every arm unmodified.

set -euo pipefail

good=0
bad_n=0
tally=0

# Verdict helpers touch ONLY the verdict counters. The case counter moves at the call site.
yay() { good=$((good + 1)); printf '  [yay] %s\n' "$1"; }
nope() { bad_n=$((bad_n + 1)); printf '  [nope] %s\n' "$1"; }

check() { # <label> <actual> <expected> -- one wrapper, exactly one verdict per call
  tally=$((tally + 1))
  if [[ "$2" == "$3" ]]; then yay "$1"; else nope "$1 (got '$2', want '$3')"; fi
}

check "arithmetic still works" "$((2 + 2))" "4"
check "string equality" "soleur" "soleur"
check "empty compares equal" "" ""

tally=$((tally + 1))
if [[ -d / ]]; then yay "root directory exists"; else nope "root directory missing"; fi

# --- Anti-vacuity floor: reported DIRECTLY, never through nope() ---
MIN_TALLY=4
if [[ "$tally" -lt "$MIN_TALLY" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$tally" "$MIN_TALLY" >&2
  exit 1
fi

# --- Accounting conservation: reported DIRECTLY ---
if [[ $((good + bad_n)) -ne "$tally" ]]; then
  printf '\n[FATAL] accounting: good+bad_n (%d) != tally (%d).\n' "$((good + bad_n))" "$tally" >&2
  exit 1
fi

printf '=== vacuity-contract-control: %d passed, %d failed (%d assertions) ===\n' \
  "$good" "$bad_n" "$tally"
[[ "$bad_n" -eq 0 ]]
