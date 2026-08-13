#!/usr/bin/env bash
# Meta-guard: the anti-vacuity floors must survive a NEUTERED assertion machinery.
#
# WHY THIS EXISTS. Both delivery-path suites end with an anti-vacuity floor whose
# job is to notice "no assertions ran". Both originally enforced that floor by
# calling `fail`:
#
#     if [[ "$cases" -lt 75 ]]; then fail "vacuity guard: only $cases ..."; fi
#     ...
#     [[ "$fails" -eq 0 ]]
#
# `fail` increments `fails`, and the exit status reads `fails`. So the detector
# ran THROUGH the thing it detects: neuter `fail` — redefine it, break its
# arithmetic, lose its body to an editing slip — and every row goes quiet AND so
# does the floor that exists to notice the quiet. The suite prints a total and
# exits 0. A floor enforced through the suspect cannot witness the suspect.
#
# This meta-suite pins the fix by MUTATION, not by inspection. Reading the source
# for `exit 1` would pass against a floor whose condition can never be true, so
# each arm builds a mutant of the real suite — `fail` stubbed to a no-op and
# `cases` forced to 0 — and asserts the mutant still exits non-zero. Against the
# pre-fix form those arms exit 0, which is the whole point.
#
# NOTHING HERE RUNS THE REAL SUITES TO COMPLETION. Each mutant is truncated to its
# harness plus the floor, so this suite costs milliseconds and cannot be made slow
# or flaky by the batteries it guards.

export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

passes=0
fails=0
cases=0

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
# Deliberately NOT the mechanism this suite's own floor depends on — see the
# bottom of this file.
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

SUITE_TMP="$(mktemp -d "${TMPDIR}/vacuity-floor-meta.XXXXXXXX")" || {
  echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup_suite() { [[ -n "${SUITE_TMP:-}" && -d "$SUITE_TMP" ]] && rm -rf "$SUITE_TMP" || true; return 0; }
trap cleanup_suite EXIT

# Build a mutant: the target suite's floor block, with `fail` stubbed to a no-op,
# `cases` forced to 0, and the counters declared. This reproduces exactly the
# state the floor is supposed to catch (no assertions ran) under exactly the
# fault that used to hide it (a silenced `fail`).
#
# The floor block is extracted from the REAL FILE rather than restated here. A
# restated copy is a second pin, and the copy that drifts is the one that runs —
# the failure mode this whole PR is about.
build_mutant() { # <suite-path> <out-path>
  local src="$1" out="$2" start
  # First line of the floor's `if`, and everything to the closing `fi`.
  start="$(grep -n '^if \[\[ "\$cases" -lt ' "$src" | head -1 | cut -d: -f1)"
  [[ -n "$start" ]] || { echo "FATAL: no floor found in $src" >&2; exit 2; }
  local end
  end="$(awk -v s="$start" 'NR>=s && /^fi$/ {print NR; exit}' "$src")"
  [[ -n "$end" ]] || { echo "FATAL: unterminated floor in $src" >&2; exit 2; }
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' 'passes=0; fails=0; cases=0'
    # THE NEUTERING. This is the fault under test.
    printf '%s\n' 'fail() { :; }'
    sed -n "${start},${end}p" "$src"
    printf '%s\n' 'printf "\nTotal: %d passed, %d failed (%d assertions)\n" "$passes" "$fails" "$cases"'
    printf '%s\n' '[[ "$fails" -eq 0 ]]'
  } > "$out"
}

assert_rc_nonzero() { # <name> <script>
  cases=$((cases + 1))
  local rc=0
  bash "$2" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "$1 (exit $rc)"
  else
    fail "$1 — the floor exited 0 with \`fail\` neutered and zero assertions; it is enforced THROUGH the machinery it guards"
  fi
}

for suite in plugin-delivery-canary plugin-legacy-resolver-probe; do
  src="$REPO_ROOT/scripts/${suite}.test.sh"
  [[ -f "$src" ]] || { echo "FATAL: missing $src" >&2; exit 2; }
  mutant="$SUITE_TMP/${suite}.mutant.sh"
  build_mutant "$src" "$mutant"

  # The mutant must actually carry the neutering, or the arm proves nothing.
  cases=$((cases + 1))
  if grep -q '^fail() { :; }$' "$mutant"; then
    pass "${suite}: the mutant really does neuter fail()"
  else
    fail "${suite}: mutant construction failed — fail() was not stubbed, so the arm below is vacuous"
  fi

  # The extracted floor must be the real one, not an empty slice.
  cases=$((cases + 1))
  if grep -q 'vacuity guard' "$mutant"; then
    pass "${suite}: the mutant carries the suite's real floor block"
  else
    fail "${suite}: mutant carries no floor block — extraction produced an empty slice"
  fi

  assert_rc_nonzero "${suite}: the floor still fails the run with fail() neutered and cases=0" "$mutant"
done

# NEGATIVE CONTROL. The arms above must be capable of failing, or they assert
# nothing. This builds the PRE-FIX shape by hand — a floor that reports through
# `fail` — and asserts it exits 0 under the same neutering. If this control ever
# turns non-zero, the arms above have stopped discriminating and this whole file
# is decorative.
control="$SUITE_TMP/prefix-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'passes=0; fails=0; cases=0'
  printf '%s\n' 'fail() { :; }'
  # `-lt 1` deliberately, not a copy of either suite's real floor: `cases=0` fires
  # any positive threshold, so restating 75/121 here would only go stale when a
  # floor is ratcheted, while testing exactly the same thing.
  printf '%s\n' 'if [[ "$cases" -lt 1 ]]; then'
  printf '%s\n' '  fail "vacuity guard: only $cases assertions ran"'
  printf '%s\n' 'fi'
  printf '%s\n' '[[ "$fails" -eq 0 ]]'
} > "$control"
cases=$((cases + 1))
control_rc=0
bash "$control" >/dev/null 2>&1 || control_rc=$?
if [[ "$control_rc" -eq 0 ]]; then
  pass "negative control: the pre-fix fail()-routed floor DOES exit 0 when neutered (so the arms above discriminate)"
else
  fail "negative control: the pre-fix shape exited $control_rc — this suite can no longer tell the two forms apart"
fi

# This suite's OWN floor. Same rule it enforces on the others: reported directly,
# never through `fail`, so it cannot be silenced by the fault it exists to catch.
# 7 = two suites x three arms (neutering-is-real, floor-block-is-real, mutant-still-
# fails) + the negative control. Ratcheted by hand when arms are added; never derived
# from a variable this file computes, because a floor that descends with the thing it
# guards is not a floor.
if [[ "$cases" -lt 7 ]]; then
  printf '\n[FATAL] meta-guard vacuity: only %d assertions ran; expected >= 7.\n' "$cases" >&2
  printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
  exit 1
fi

# ACCOUNTING CONSERVATION — the arm that actually catches a neutered `fail()`.
# The floor above catches "no assertions RAN". It cannot catch "assertions ran and
# their verdicts were discarded", because `cases` is incremented by the assert
# HELPERS and never by `fail` — so stubbing `fail` to a no-op leaves `cases` at its
# full value, the floor is satisfied, and the suite exits 0 with real failures
# silenced. Measured during review: `fail() { :; }` plus a genuine defect printed
# `45 passed, 0 failed (48 assertions)` and RC=0.
#
# Every assertion must record exactly one verdict, so passes+fails MUST equal cases.
# Reported directly, never through `fail`, for the same reason as the floor.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d) — an assertion was counted but its verdict was not recorded. That is what a neutered pass()/fail() looks like.\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi

printf '\nTotal: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
