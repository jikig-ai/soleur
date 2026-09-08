#!/usr/bin/env bash
#
# Guard: the await-ci deploy gate's constants must stay in their declared relationships (#7902).
#
# WHY THIS EXISTS. web-platform-release.yml carries a loud comment — "do NOT lower CEILING_S,
# MAX_ATTEMPTS, or timeout-minutes without re-reading ADR-072" — and ADR-072 invariant #7 states
# `timeout-minutes * 60 >= 1.2 * CEILING_S`. Until this suite, BOTH were unenforced prose: an
# instruction addressed to a reader who may not arrive. #7902 is itself the proof that such an
# instruction does not hold. Its plan raised CEILING_S 3000 -> 3600 and did NOT mention
# MAX_ATTEMPTS; left at 300 the loop would have exhausted at (300+6)*10 = 3060s and the raise
# would have bought 60 seconds instead of ten minutes, while every constant still "looked" right.
# That was caught by reading the loop, not by any gate.
#
# The relationships are also EXACTLY TIGHT as shipped (4320 >= 4320, 360*10 == 3600), so there is
# no slack to absorb a one-sided edit: the very next change to either side breaks an invariant
# unless something measures it. Both failure modes are silent at edit time and expensive later —
# a timeout-minutes hard-kill pre-empts the in-bash ceiling, so the deploy dies as an opaque
# cancelled job instead of the diagnostic ::error:: ADR-072 promises.
#
# SCOPE. These are relationships among DECLARED constants, which is all a static guard can hold.
# It deliberately asserts nothing about whether CEILING_S is large enough for real CI — declared
# budgets bound execution only and omit the queue, which is the reasoning that got Guard 2
# rejected (ADR-208). The quantity-measuring counterpart is the 0.7 x CEILING_S ::warning:: inside
# await-ci itself; row I4 asserts that warning still has a consumer, because an output nothing
# reads is the same defect class in a different dress.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REL="$ROOT/.github/workflows/web-platform-release.yml"
[[ -f "$REL" ]] || { echo "FATAL: missing $REL" >&2; exit 2; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }

echo "=== Guard: await-ci ceiling invariants (#7902) ==="

# INSTRUMENT SELF-TEST (ADR-193). A suite whose pass/fail helpers are neutered reports green
# having asserted nothing. Drive both once, upstream of every row, and refuse to continue unless
# both counters moved. Its own effect is subtracted before the real rows begin.
pass "instrument self-test (this row is expected — it is subtracted below)"
fail "instrument self-test (this row is expected — it is subtracted below)"
if (( PASS != 1 || FAIL != 1 )); then
  printf 'FATAL: instrument self-test did not move both counters — assertions here prove nothing.\n' >&2
  exit 9
fi
echo "  (instrument self-test OK — both counters move; counters reset)"
PASS=0; FAIL=0

# Extract one job's block. A naive awk RANGE cannot do this: the end pattern /^  <job>:$/ also
# matches the START line, so the range collapses to a single line and every downstream grep reads
# an empty haystack — which fails OPEN, since "no match" and "no input" are indistinguishable to
# grep. Measured on this very file while building this suite. Hence an explicit flag.
job_block() {  # $1 = workflow path, $2 = job key
  awk -v job="$2" '
    $0 ~ "^  " job ":$" { inb=1; print; next }
    inb && /^  [a-zA-Z0-9_-]+:$/ { exit }
    inb { print }
  ' "$1"
}

# Every reader takes the FILE as an argument so the mutation rows below can point the identical
# assertions at a mutated copy. An assertion that reads a global cannot be driven red.
envval() {  # $1 = file, $2 = env key — matched at its own indent, anchored, first hit
  job_block "$1" await-ci | grep -oE "^[[:space:]]+$2:[[:space:]]*\"?[0-9]+" | grep -oE '[0-9]+$' | head -1
}
timeoutval() {  # $1 = file — await-ci's own job-level timeout-minutes
  job_block "$1" await-ci | grep -oE '^[[:space:]]+timeout-minutes:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | head -1
}

# --- The four invariants, each a predicate over a FILE (0 = holds, 1 = violated) -------------
# Each returns 2 when an input is unreadable, so "could not measure" can never be reported as
# "measured and fine" — the collapse this repo has been bitten by often enough to name.
i1_timeout_over_ceiling() {  # ADR-072 invariant #7
  local f="$1" c t; c=$(envval "$f" CEILING_S); t=$(timeoutval "$f")
  [[ -n "$c" && -n "$t" ]] || return 2
  (( t * 60 * 10 >= 12 * c ))
}
i2_attempts_track_ceiling() {  # the loop's iteration backstop must not bind before the ceiling
  local f="$1" c m i; c=$(envval "$f" CEILING_S); m=$(envval "$f" MAX_ATTEMPTS); i=$(envval "$f" INTERVAL_S)
  [[ -n "$c" && -n "$m" && -n "$i" ]] || return 2
  (( m * i == c ))
}
i3_soft_ceiling_is_derived() {  # derived from CEILING_S, never restated as a literal
  local f="$1"
  job_block "$f" await-ci | grep -qE 'soft_ceiling_s=\$\(\([[:space:]]*CEILING_S[[:space:]]*\*'
}
i4_soft_breach_has_consumer() {  # an output nothing reads is a warning that never arrives
  local f="$1"
  job_block "$f" await-ci | grep -q 'soft_breach=true' \
    && grep -qE '^[[:space:]]+soft_breach:[[:space:]]*\$\{\{[[:space:]]*steps\.' "$f" \
    && grep -qE "needs\.await-ci\.outputs\.soft_breach" "$f"
}

check() {  # $1 = predicate, $2 = file, $3 = description — reports, never exits
  local rc; "$1" "$2"; rc=$?
  case "$rc" in
    0) pass "$3" ;;
    2) fail "$3 — UNMEASURABLE: a constant could not be read from $2 (never scored as holding)" ;;
    *) fail "$3" ;;
  esac
}

# EXTRACTION SANITY, before any invariant is scored. An empty block is not a violated
# invariant: i3/i4 grep the block directly, so an extraction that silently returned nothing
# would report them RED and send the next reader hunting a defect that is not there. Three
# sibling suites in this repo already guard their extraction this way; this row is that guard.
# (Sibling suites deliberately DUPLICATE this extractor rather than source a shared one — see
# terraform-drift-step-order.test.sh, which explains that a cross-file source makes one suite's
# failure look like another's. Keep the copy; keep the sanity row with it.)
_blk_lines=$(job_block "$REL" await-ci | wc -l)
if (( _blk_lines > 1 )) && job_block "$REL" await-ci | grep -q '^  await-ci:$'; then
  pass "EXTRACTION — the await-ci job block is $_blk_lines lines and starts at its own key"
else
  fail "EXTRACTION — job_block returned $_blk_lines line(s); every invariant below would be scored against an empty haystack"
fi

C=$(envval "$REL" CEILING_S); M=$(envval "$REL" MAX_ATTEMPTS)
I=$(envval "$REL" INTERVAL_S); T=$(timeoutval "$REL")
R=$(envval "$REL" RECONCILE_ATTEMPTS)
echo "  read: CEILING_S=$C MAX_ATTEMPTS=$M INTERVAL_S=$I RECONCILE_ATTEMPTS=$R timeout-minutes=$T"

check i1_timeout_over_ceiling      "$REL" "I1 — ADR-072 #7: timeout-minutes*60 ($(( T * 60 ))s) >= 1.2 x CEILING_S ($(( 12 * C / 10 ))s)"
check i2_attempts_track_ceiling    "$REL" "I2 — MAX_ATTEMPTS x INTERVAL_S ($(( M * I ))s) == CEILING_S (${C}s), so the loop backstop never binds before the elapsed ceiling"
check i3_soft_ceiling_is_derived   "$REL" "I3 — the soft ceiling is DERIVED from CEILING_S, not restated as a literal"
check i4_soft_breach_has_consumer  "$REL" "I4 — soft_breach is emitted, exported as a job output, AND read by a consumer job"

# --- MUTATION ROWS ---------------------------------------------------------------------------
# Every row above is satisfiable by an assertion that cannot fail. These drive each one RED on a
# COPY, so a green verdict above is evidence rather than decoration. Control first: the unmutated
# copy must be green, or the rows below score nothing.
if i1_timeout_over_ceiling "$REL" && i2_attempts_track_ceiling "$REL" \
   && i3_soft_ceiling_is_derived "$REL" && i4_soft_breach_has_consumer "$REL"; then
  pass "CONTROL — every invariant holds on the unmutated file, so each mutation below scores a real change"
else
  fail "CONTROL — the unmutated file already violates an invariant; the mutation rows below prove nothing"
fi

mutate_row() {  # $1 = predicate  $2 = sed program  $3 = description
  local pred="$1" prog="$2" desc="$3" cp="$W/mut.yml"
  cp "$REL" "$cp"
  sed -i -E "$prog" "$cp"
  if cmp -s "$REL" "$cp"; then
    fail "MUTATION '$desc' — the edit changed NOTHING; this row tested an unmutated file"
    return
  fi
  if "$pred" "$cp"; then
    fail "SURVIVOR: '$desc' left $pred GREEN. Either the assertion does not read what it claims, or the mutant is equivalent — decide which."
  else
    pass "MUTATION — $pred goes RED under '$desc'"
  fi
}

mutate_row i1_timeout_over_ceiling \
  's/^([[:space:]]+)timeout-minutes: 72$/\1timeout-minutes: 50/' \
  "timeout-minutes lowered below 1.2 x CEILING_S (the hard-kill then pre-empts the diagnostic ::error::)"

mutate_row i2_attempts_track_ceiling \
  's/^([[:space:]]+)MAX_ATTEMPTS: "360"/\1MAX_ATTEMPTS: "300"/' \
  "CEILING_S raised while MAX_ATTEMPTS left behind — the exact omission #7902's plan shipped"

mutate_row i3_soft_ceiling_is_derived \
  's/soft_ceiling_s=\$\(\( CEILING_S \* 7 \/ 10 \)\)/soft_ceiling_s=2520/' \
  "the soft ceiling restated as a literal instead of derived"

mutate_row i4_soft_breach_has_consumer \
  's/needs\.await-ci\.outputs\.soft_breach/needs.await-ci.outputs.absent_key/' \
  "the consumer job stops reading soft_breach — the warning is emitted and never arrives"

# A guard that only ever goes red is as useless as one that only goes green.
mutate_row_muststay() {  # $1 = predicate  $2 = sed program  $3 = description
  local pred="$1" prog="$2" desc="$3" cp="$W/mustpass.yml"
  cp "$REL" "$cp"; sed -i -E "$prog" "$cp"
  if cmp -s "$REL" "$cp"; then fail "MUSTPASS '$desc' — the edit changed nothing"; return; fi
  if "$pred" "$cp"; then pass "MUSTPASS — $pred stays GREEN under '$desc'"
  else fail "MUSTPASS — $pred went RED under '$desc', which changes no invariant. The assertion is over-broad."; fi
}
mutate_row_muststay i1_timeout_over_ceiling \
  's/^([[:space:]]+)RECONCILE_ATTEMPTS: "6"/\1RECONCILE_ATTEMPTS: "7"/' \
  "an unrelated constant edit that changes no I1 term"

# --- ASSERTION FLOOR (ADR-193) ---------------------------------------------------------------
# Reported with printf + exit, NEVER through fail() — a floor that calls the very helper it
# backstops is disarmed by the same one-token edit it exists to catch.
TOTAL=$(( PASS + FAIL ))
MIN_ROWS=11
if (( TOTAL < MIN_ROWS )); then
  printf 'FAIL: assertion floor — %d rows executed, expected at least %d. The suite did not run to completion, so its verdict is not evidence.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "await-ci-ceiling-invariants.test.sh: $TOTAL rows, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then exit 1; fi
echo "All tests passed"
