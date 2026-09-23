#!/usr/bin/env bash
# regenerate-shard-manifest.test.sh — the offline sticky-LPT generator must
# produce deterministic, filtered, provenance-stamped manifests (#8006, ADR-240).
#
# WHY THIS EXISTS. `scripts/regenerate-shard-manifest.py` is the ONLY place shard
# assignment is computed; the runner is a pure lookup. If the generator silently
# mis-parses timings (keeps a boundary row, a skipped suite, a partial FAIL
# timing, or a fixture-leak label), the committed manifest encodes that error and
# no runtime check notices — the table is still well-formed, just wrong. Every
# exclusion rule and the sticky guarantee therefore gets its own fixture here.
#
# Fixtures are synthesized under $WORK (cq-test-fixtures-synthesized-only); no
# gh calls, no network — --timings-dir + --registered-file + --manifest seams.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GEN="$REPO_ROOT/scripts/regenerate-shard-manifest.py"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/regen-shard-manifest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
cases=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }
# Every verdict routes through check(): the case counter moves at the CALL
# site (a wrapper is the sanctioned home), never inside a terminal verdict
# helper — so PASS+FAIL vs cases can diverge and conservation is a real
# constraint, not a tautology (ADR-193; guard-vacuity-floor ARM 10d).
check() { cases=$(( cases + 1 )); "$@"; }

echo "=== regenerate-shard-manifest unit test ==="
echo ""

# --- Instrument self-test (ADR-193) -------------------------------------------------------
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)"
fail "instrument self-test (expected — subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  echo "FATAL: instrument self-test did not move both counters." >&2
  exit 2
fi
PASS=$(( PASS - 1 )); FAIL=$(( FAIL - 1 ))
echo "  (instrument self-test OK — both counters move; counters reset)"
echo ""

[[ -f "$GEN" ]] || { echo "FATAL: generator missing: $GEN" >&2; exit 2; }

# The declared N — same job-block scoping as scripts-shard-manifest.test.sh.
CI_N="$(awk -v j='^  test-scripts:' '$0 ~ j {f=1} f&&/^  [a-z][a-z0-9-]*:$/&&$0 !~ j {exit} f' "$CI_YML" \
  | grep -oE 'shard: \["1/[0123456789]+' | grep -oE '[0123456789]+$' | head -1)"
if [[ "$CI_N" =~ ^[0123456789]+$ ]] && (( 10#$CI_N >= 2 )); then
  check pass "ci.yml test-scripts matrix declares N=$CI_N"
else
  check fail "could not derive the test-scripts matrix N — fixtures cannot be sized"
  echo "FATAL: cannot continue without N." >&2
  exit 2
fi
N=$(( 10#$CI_N ))

gen() { # gen <timings-dir> <registered-file> <manifest-path> [extra args...]
  local td=$1 rf=$2 mf=$3; shift 3
  python3 "$GEN" --timings-dir "$td" --registered-file "$rf" --manifest "$mf" "$@"
}

# === Fixture A: exclusion rules + balanced LPT =============================================
# N*2 registered labels at 100ms each → perfect balance is 2 rows/leg, 200ms/leg.
FA="$WORK/A"; mkdir -p "$FA"
: > "$FA/registered.txt"
for i in $(seq 1 $(( N * 2 ))); do
  printf 'suite-a%02d\n' "$i" >> "$FA/registered.txt"
  printf 'suite-a%02d\t100\n' "$i" >> "$FA/timings.tsv"
done
# Rows that must be excluded: boundary, skip, partial verdicts, unregistered.
{
  printf '__run_boundary_start__\t0\n'
  printf '__run_boundary_end__\t0\n'
  printf 'declined-suite\t0\tskip=not relevant\n'
  printf 'failed-suite\t5000\tFAIL\n'
  printf 'killed-suite\t5000\tKILLED\n'
  printf 'tripped-suite\t5000\tTRIPWIRE\n'
  printf 'ghost-unregistered\t99999\n'
} >> "$FA/timings.tsv"

if gen "$FA" "$FA/registered.txt" "$WORK/A-manifest.tsv" --write > "$WORK/A-out.txt" 2> "$WORK/A-err.txt"; then
  check pass "fixture A: generator exits 0 on valid input"
else
  check fail "fixture A: generator refused valid input: $(tail -2 "$WORK/A-err.txt")"
fi

ROWS="$(grep -cv '^#' "$WORK/A-manifest.tsv" || true)"
if (( ROWS == N * 2 )); then
  check pass "fixture A: exactly $(( N * 2 )) rows — exclusions left only registered timed labels"
else
  check fail "fixture A: manifest has $ROWS rows, expected $(( N * 2 )) — an exclusion rule leaked"
fi

for banned in __run_boundary declined-suite failed-suite killed-suite tripped-suite ghost-unregistered; do
  if grep -q "$banned" "$WORK/A-manifest.tsv"; then
    check fail "excluded row '$banned' landed in the manifest"
  fi
done
check pass "boundary/skip/FAIL/KILLED/TRIPWIRE/unregistered rows all excluded"

if grep -q 'dropping timed-but-unregistered' "$WORK/A-err.txt"; then
  check pass "unregistered label drop is warned, not silent"
else
  check fail "unregistered label was dropped WITHOUT a WARN — silent filtering hides fixture leaks"
fi

# Per-leg sums must be exactly 200ms — LPT on equal items deals evenly.
SUMS="$(awk -F'\t' '!/^#/ {s[$2]+=100} END {for (l in s) print s[l]}' "$WORK/A-manifest.tsv" | sort -u)"
if [[ "$SUMS" == "200" ]]; then
  check pass "fixture A: every leg sums to exactly 200ms (LPT deals equal items evenly)"
else
  check fail "fixture A: per-leg sums diverge: $(printf '%s ' $SUMS)"
fi

# Every leg 1..N present.
LEGS="$(awk -F'\t' '!/^#/ {print $2}' "$WORK/A-manifest.tsv" | sort -un | tr '\n' ' ')"
if [[ "$LEGS" == "$(seq -s' ' 1 "$N") " || "$LEGS" == "$(seq -s' ' 1 "$N")" ]]; then
  check pass "fixture A: legs 1..$N all populated"
else
  check fail "fixture A: legs present = '$LEGS', expected 1..$N"
fi

# Determinism: regenerate, compare data rows byte-for-byte.
cp "$WORK/A-manifest.tsv" "$WORK/A-manifest-1.tsv"
gen "$FA" "$FA/registered.txt" "$WORK/A-manifest-2.tsv" --write > /dev/null 2>&1
if diff <(grep -v '^#' "$WORK/A-manifest-1.tsv") <(grep -v '^#' "$WORK/A-manifest-2.tsv") > /dev/null; then
  check pass "fixture A: regeneration is deterministic (data rows byte-identical)"
else
  check fail "fixture A: regeneration is NON-deterministic — assignment must not depend on wall state"
fi

# Header provenance.
if grep -q "^# n=$N\$" "$WORK/A-manifest.tsv" && grep -q '^# generator=' "$WORK/A-manifest.tsv" \
   && grep -q '^# generated-at=' "$WORK/A-manifest.tsv"; then
  check pass "manifest header carries n + provenance"
else
  check fail "manifest header missing n=/generator=/generated-at="
fi

# === Fixture B: sticky-LPT bounds churn ====================================================
# Imbalanced incumbent (everything on leg 1) + skewed timings: LPT MUST move rows —
# but regenerating against its OWN output must move zero (fixpoint).
FB="$WORK/B"; mkdir -p "$FB"
cp "$FA/registered.txt" "$FB/registered.txt"
cp "$FA/timings.tsv" "$FB/timings.tsv"
# Incumbent: every label on leg 1.
awk -F'\t' '!/^#/ {print $1 "\t1"}' "$WORK/A-manifest.tsv" > "$WORK/B-incumbent.tsv"
gen "$FB" "$FB/registered.txt" "$WORK/B-incumbent.tsv" --write > "$WORK/B-out1.txt" 2>/dev/null
if grep -q 'moved' "$WORK/B-out1.txt"; then
  check pass "fixture B: rebalancing an all-leg-1 incumbent reports movement"
else
  check fail "fixture B: all-leg-1 incumbent produced no 'moved' report — LPT may not be running"
fi
# Fixpoint: incumbent == own output → 0 moved.
gen "$FB" "$FB/registered.txt" "$WORK/B-incumbent.tsv" --write > "$WORK/B-out2.txt" 2>/dev/null
if grep -q ' 0 moved' "$WORK/B-out2.txt"; then
  check pass "fixture B: regenerating against own output is a fixpoint (0 moved — sticky guarantee)"
else
  check fail "fixture B: self-regeneration moved rows — sticky-LPT is churning: $(grep 'moved' "$WORK/B-out2.txt")"
fi

# === Fixture C: cross-leg duplicate warns and keeps max =====================================
FC="$WORK/C"; mkdir -p "$FC/leg1" "$FC/leg2"
printf 'dup-suite\nsolo-suite\n' > "$FC/registered.txt"
printf 'dup-suite\t100\n' > "$FC/leg1/suite-timings.tsv"
printf 'dup-suite\t900\nsolo-suite\t50\n' > "$FC/leg2/suite-timings.tsv"
gen "$FC" "$FC/registered.txt" "$WORK/C-manifest.tsv" --write > /dev/null 2> "$WORK/C-err.txt"
if grep -q 'timed on multiple legs' "$WORK/C-err.txt"; then
  check pass "fixture C: cross-leg duplicate label warns"
else
  check fail "fixture C: duplicate label across timing files produced no WARN"
fi
# max kept: with only 2 labels the 900ms dominates its leg; a 100ms dup would not.
if grep -q 'keeping max' "$WORK/C-err.txt"; then
  check pass "fixture C: duplicate merge keeps max explicitly"
else
  check fail "fixture C: WARN does not document the max-merge policy"
fi

# === Fixture D: failure modes ==============================================================
# D1: bad ms field → exit 2.
FD="$WORK/D"; mkdir -p "$FD"
printf 'x\n' > "$FD/registered.txt"
printf 'x\tnotanumber\n' > "$FD/timings.tsv"
if gen "$FD" "$FD/registered.txt" "$WORK/D-m.tsv" > /dev/null 2>&1; then
  check fail "D1: non-numeric ms field accepted — corrupt timings must refuse"
else
  check pass "D1: non-numeric ms field refuses (exit 2)"
fi
# D2: no timings at all → exit 2.
FE="$WORK/E"; mkdir -p "$FE/empty"
printf 'x\n' > "$FE/registered.txt"
if gen "$FE/empty" "$FE/registered.txt" "$WORK/E-m.tsv" > /dev/null 2>&1; then
  check fail "D2: empty timings dir accepted"
else
  check pass "D2: empty timings dir refuses (exit 2)"
fi
# D3: all timed labels unregistered → exit 2 (the table would be empty-but-valid).
FF="$WORK/F"; mkdir -p "$FF"
printf 'real-suite\n' > "$FF/registered.txt"
printf 'fake-suite\t100\n' > "$FF/timings.tsv"
if gen "$FF" "$FF/registered.txt" "$FF/m.tsv" > /dev/null 2>&1; then
  check fail "D3: zero-registered timings produced a manifest"
else
  check pass "D3: timings with zero registered labels refuse (exit 2)"
fi
# D4: dry-run must NOT write the manifest.
FG="$WORK/G"; mkdir -p "$FG"
cp "$FA/registered.txt" "$FG/registered.txt"; cp "$FA/timings.tsv" "$FG/timings.tsv"
gen "$FG" "$FG/registered.txt" "$WORK/G-m.tsv" > /dev/null 2>&1
if [[ ! -f "$WORK/G-m.tsv" ]]; then
  check pass "D4: dry-run writes nothing"
else
  check fail "D4: dry-run wrote the manifest — --write must gate all writes"
fi

# --- Accounting conservation (ADR-193) -----------------------------------------------------
# Ordered BEFORE the floor — a neutered helper deflates the verdict counters, and this
# reports "a verdict was discarded" rather than the misleading "rows were deleted".
# Reported directly, never through fail(). The literal `[FATAL] accounting` is
# load-bearing: guard-vacuity-floor's ARM 10 builds its population by grepping it.
if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '[FATAL] accounting: PASS+FAIL=%d but cases=%d — a verdict was counted or discarded without its pair.\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi

# --- ASSERTION FLOOR (ADR-193) -------------------------------------------------------------
# printf + exit, NEVER through fail(). MIN_CASES sits on the line directly above its
# `if` so guard-vacuity-floor's backward slice-widening binds it.
MIN_CASES=16
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d check(s) ran, expected >= %d. The suite did not run to completion.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "regenerate-shard-manifest.test.sh: $cases checks, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'VERDICT: %d of %d checks FAILED — this suite is RED.\n' "$FAIL" "$cases" >&2
  exit 1
fi
echo "All tests passed"
