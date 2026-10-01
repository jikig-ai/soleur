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

# Canonical fixture-dir refusal (byte-equal to test-helpers.sh — the
# fixture-relative-assert ratchet keys on this body). NOTE: it is NOT applied
# to $WORK itself — the pre-existing fixtures' unguarded sites are recorded in
# the relative-assert baseline, which is an exact-equality ratchet; new
# fixtures guard their OWN derived roots ($FQ/$FR/$FS/$FU) so this suite adds
# zero new findings without rewriting baseline history.
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
  | grep -oE 'shard: \["1/[0123456789]+' | grep -oE '[0123456789]+$' | head -1)" || true
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
# D3: all timed labels unregistered → the measured set empties, the registered
# label is tabled at the floor, and a count-balanced all-floor manifest is
# still written (WARN-degrade, not a die — #9232).
FF="$WORK/F"; mkdir -p "$FF"
printf 'real-suite\n' > "$FF/registered.txt"
printf 'fake-suite\t100\n' > "$FF/timings.tsv"
if gen "$FF" "$FF/registered.txt" "$FF/m.tsv" --durations-out "$WORK/F-dur.tsv" --write > /dev/null 2> "$WORK/F-err.txt"; then
  check pass "D3: zero-registered timings degrade to an all-floor manifest"
else
  check fail "D3: all-floor degrade refused: $(tail -2 "$WORK/F-err.txt")"
fi
if grep -qF $'real-suite\t60000\tfloor' "$WORK/F-dur.tsv" 2>/dev/null; then
  check pass "D3: the registered label is tabled at DEFAULT_SUITE_MS with src=floor"
else
  check fail "D3: registered label not floored: $(cat "$WORK/F-dur.tsv" 2>/dev/null)"
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

# === Fixture H: --group heavy binds the heavy job's N and the heavy registered set ==========
#
# The two manifests share one generator but disjoint inputs: heavy N comes from
# the test-scripts-heavy job block, the registered set from --enumerate
# scripts-heavy, and light-group labels in a heavy timing stream must be DROPPED
# (warned) — a light label in the heavy table would red the ⊆ lint while
# consuming leg weight for nothing.
CI_N_H="$(awk -v j='^  test-scripts-heavy:' '$0 ~ j {f=1} f&&/^  [a-z][a-z0-9-]*:$/&&$0 !~ j {exit} f' "$CI_YML" \
  | grep -oE 'shard: \["1/[0123456789]+' | grep -oE '[0123456789]+$' | head -1)" || true
if [[ "$CI_N_H" =~ ^[0123456789]+$ ]] && (( 10#$CI_N_H >= 1 )); then
  check pass "ci.yml test-scripts-heavy matrix declares N=$CI_N_H"
else
  check fail "could not derive the test-scripts-heavy matrix N — heavy fixtures cannot be sized"
fi

FH="$WORK/H"; mkdir -p "$FH"
printf 'heavy-a\nheavy-b\nheavy-c\n' > "$FH/registered.txt"
{
  printf 'heavy-a\t800\nheavy-b\t600\nheavy-c\t400\n'
  printf 'light-suite-1\t100\nlight-suite-2\t100\n'
} > "$FH/timings.tsv"
if gen "$FH" "$FH/registered.txt" "$WORK/H-manifest.tsv" --group heavy --write \
     > "$WORK/H-out.txt" 2> "$WORK/H-err.txt"; then
  check pass "fixture H: --group heavy generator exits 0 on valid input"
else
  check fail "fixture H: --group heavy refused valid input: $(tail -2 "$WORK/H-err.txt")"
fi
if grep -q "^# n=$(( 10#${CI_N_H:-0} ))\$" "$WORK/H-manifest.tsv" 2>/dev/null; then
  check pass "fixture H: heavy manifest header carries the HEAVY job's n, not the light N"
else
  check fail "fixture H: heavy manifest n header missing or wrong (want n=${CI_N_H}): $(grep '^# n=' "$WORK/H-manifest.tsv" 2>/dev/null)"
fi
if [[ "$(grep -cv '^#' "$WORK/H-manifest.tsv" 2>/dev/null || true)" == "3" ]] \
   && ! grep -q 'light-suite' "$WORK/H-manifest.tsv" 2>/dev/null; then
  check pass "fixture H: exactly the 3 heavy labels — light-group timings dropped"
else
  check fail "fixture H: wrong-group labels leaked into the heavy manifest"
fi
if grep -q 'dropping timed-but-unregistered' "$WORK/H-err.txt"; then
  check pass "fixture H: wrong-group drop is warned, not silent"
else
  check fail "fixture H: light-group labels dropped WITHOUT a WARN"
fi

# === Fixture I: wrong-group registration set degrades to all-floor ==========================
# A registered file containing only LIGHT labels against HEAVY timings drops
# every measured row — but registered labels still carry weight: the labels
# floor-table and the manifest is produced with a WARN (the all-floor degrade
# replaced this die site in #9232 — a count-balanced table beats an abort).
FI="$WORK/I"; mkdir -p "$FI"
printf 'light-only-1\nlight-only-2\n' > "$FI/registered.txt"
printf 'heavy-a\t800\nheavy-b\t600\n' > "$FI/timings.tsv"
if gen "$FI" "$FI/registered.txt" "$WORK/I-m.tsv" --group heavy \
     --durations-out "$WORK/I-dur.tsv" --write > /dev/null 2> "$WORK/I-err.txt"; then
  check pass "fixture I: wrong-group registration degrades to all-floor, not a die"
else
  check fail "fixture I: all-floor degrade refused: $(tail -2 "$WORK/I-err.txt")"
fi
if grep -qF $'light-only-1\t60000\tfloor' "$WORK/I-dur.tsv" 2>/dev/null \
   && grep -q 'dropping timed-but-unregistered' "$WORK/I-err.txt"; then
  check pass "fixture I: untimed registered labels floor-table; dropped timings still warn"
else
  check fail "fixture I: floor tabling or the unregistered-drop WARN is missing"
fi

# === Fixture J: multi-run aggregation by MEDIAN =============================================
# Three timing dirs — each repeatable --timings-dir is one run's artifact set.
# suite-mid measures 100/300/900 across them: the weight must be the median
# (300) — a max-merge pins the 900 spike, a mean drags to ~433 (ADR-240 amd.).
FJ1="$WORK/J1"; FJ2="$WORK/J2"; FJ3="$WORK/J3"; mkdir -p "$FJ1" "$FJ2" "$FJ3"
printf 'suite-mid\nsuite-lo\n' > "$WORK/J-registered.txt"
printf 'suite-mid\t100\nsuite-lo\t10\n' > "$FJ1/timings.tsv"
printf 'suite-mid\t300\nsuite-lo\t10\n' > "$FJ2/timings.tsv"
printf 'suite-mid\t900\nsuite-lo\t10\n' > "$FJ3/timings.tsv"
if gen "$FJ1" "$WORK/J-registered.txt" "$WORK/J-manifest.tsv" \
     --timings-dir "$FJ2" --timings-dir "$FJ3" \
     --durations-out "$WORK/J-durations.tsv" --write \
     > "$WORK/J-out.txt" 2> "$WORK/J-err.txt"; then
  check pass "fixture J: repeated --timings-dir aggregates one run per dir"
else
  check fail "fixture J: multi-run input refused: $(tail -2 "$WORK/J-err.txt")"
fi
if grep -qF $'suite-mid\t300\tmeasured' "$WORK/J-durations.tsv" 2>/dev/null; then
  check pass "fixture J: suite-mid aggregates to the MEDIAN 300ms across runs"
else
  check fail "fixture J: suite-mid is not the median: $(grep 'suite-mid' "$WORK/J-durations.tsv" 2>/dev/null)"
fi

# === Fixture K: registered-but-untimed labels table at the floor ============================
FK="$WORK/K"; mkdir -p "$FK"
printf 'timed-a\nnever-timed-b\nnever-timed-c\n' > "$FK/registered.txt"
printf 'timed-a\t400\n' > "$FK/timings.tsv"
if gen "$FK" "$FK/registered.txt" "$WORK/K-manifest.tsv" \
     --durations-out "$WORK/K-durations.tsv" --write \
     > "$WORK/K-out.txt" 2> "$WORK/K-err.txt"; then
  check pass "fixture K: generator exits 0 with untimed registered labels"
else
  check fail "fixture K: refused untimed labels: $(tail -2 "$WORK/K-err.txt")"
fi
# floor_ms = median of the measured set (only timed-a at 400) → both untimed
# labels table at 400 with src=floor; the measured row keeps src=measured.
if grep -q '^never-timed-b' "$WORK/K-manifest.tsv" \
   && grep -qF $'never-timed-b\t400\tfloor' "$WORK/K-durations.tsv" 2>/dev/null; then
  check pass "fixture K: untimed label tables in the manifest at floor_ms with src=floor"
else
  check fail "fixture K: untimed label not floored into the manifest/durations table"
fi
if grep -qF $'timed-a\t400\tmeasured' "$WORK/K-durations.tsv" 2>/dev/null; then
  check pass "fixture K: measured rows carry src=measured"
else
  check fail "fixture K: measured row lost its src=measured provenance"
fi
if grep -qi 'floor' "$WORK/K-err.txt"; then
  check pass "fixture K: floor tabling is warned, not silent"
else
  check fail "fixture K: floor tabling produced no WARN"
fi
# Two untimed labels must flow through assign() — not collapse onto one leg by
# construction (equal weights over N>=2 legs deal to distinct least-loaded legs).
LEGS_K="$(awk -F'\t' '$1 ~ /^never-timed-/ {print $2}' "$WORK/K-manifest.tsv" 2>/dev/null | sort -u | wc -l || true)"
if [[ "$LEGS_K" == "2" ]]; then
  check pass "fixture K: floor labels flow through assign() (distinct legs)"
else
  check fail "fixture K: two floor labels collapsed onto $LEGS_K leg(s) — bypassed assign()"
fi

# === Fixture L: --write to the default manifest with K != workflow N refuses ================
# The refusal must fire BEFORE any write: snapshot the committed file, attempt
# the mismatched emission, verify the bytes are untouched. No --manifest arg —
# the default path is the group's committed table.
FL="$WORK/L"; mkdir -p "$FL"
printf 'l-a\nl-b\n' > "$FL/registered.txt"
printf 'l-a\t100\nl-b\t100\n' > "$FL/timings.tsv"
SUM_BEFORE="$(cksum "$REPO_ROOT/scripts/suite-shard-legs.tsv")"
if python3 "$GEN" --timings-dir "$FL" --registered-file "$FL/registered.txt" \
     --legs "$(( N + 1 ))" --write > /dev/null 2> "$WORK/L-err.txt"; then
  check fail "fixture L: --legs $(( N + 1 )) --write at the DEFAULT path succeeded — a committed n-mismatch must refuse"
else
  check pass "fixture L: default-path --write with K != workflow N exits non-zero"
fi
if [[ "$(cksum "$REPO_ROOT/scripts/suite-shard-legs.tsv")" == "$SUM_BEFORE" ]]; then
  check pass "fixture L: refusal fired before the write — committed manifest untouched"
else
  check fail "fixture L: the refusal left the committed manifest rewritten"
fi
if grep -qiE 'mismatch|--legs|declares' "$WORK/L-err.txt"; then
  check pass "fixture L: the refusal names the n-mismatch"
else
  check fail "fixture L: refusal stderr does not explain the mismatch: $(tail -2 "$WORK/L-err.txt")"
fi

# === Fixture M: --durations input wins over --timings-dir ===================================
# The durations file says m-a is heavy (1000); the timings dir says it is light
# (100). Precedence --durations > --timings-dir pins the emitted weight to the
# file's value — and the report's provenance names the source that fed.
FM="$WORK/M"; mkdir -p "$FM"
printf 'm-a\nm-b\n' > "$FM/registered.txt"
printf 'm-a\t100\nm-b\t1000\n' > "$FM/timings.tsv"
printf 'm-a\t1000\tmeasured\nm-b\t100\tmeasured\n' > "$FM/in-durations.tsv"
if gen "$FM" "$FM/registered.txt" "$WORK/M-manifest.tsv" \
     --durations "$FM/in-durations.tsv" --durations-out "$WORK/M-durations.tsv" --write \
     > "$WORK/M-out.txt" 2> "$WORK/M-err.txt"; then
  check pass "fixture M: --durations input exits 0"
else
  check fail "fixture M: --durations input refused: $(tail -2 "$WORK/M-err.txt")"
fi
if grep -qF $'m-a\t1000\tmeasured' "$WORK/M-durations.tsv" 2>/dev/null; then
  check pass "fixture M: the durations file's weights drive the packing, not the dir's"
else
  check fail "fixture M: --durations ignored — $(grep 'm-a' "$WORK/M-durations.tsv" 2>/dev/null)"
fi
if grep -q 'source: durations:' "$WORK/M-out.txt"; then
  check pass "fixture M: provenance names the durations source that actually fed"
else
  check fail "fixture M: report provenance does not name the --durations source"
fi

# === Fixture N: an all-floor durations file still packs (must-pass) ==========================
# src=floor rows in an input file are estimates, not measurements: they re-derive
# as floor on re-pack (floor never launders into measured) and a file of ONLY
# floor rows still produces a valid manifest.
FN="$WORK/N"; mkdir -p "$FN"
printf 'n-a\nn-b\n' > "$FN/registered.txt"
printf 'n-a\t60000\tfloor\nn-b\t60000\tfloor\n' > "$FN/in-durations.tsv"
if python3 "$GEN" --durations "$FN/in-durations.tsv" --registered-file "$FN/registered.txt" \
     --manifest "$WORK/N-manifest.tsv" --durations-out "$WORK/N-durations.tsv" --write \
     > "$WORK/N-out.txt" 2> "$WORK/N-err.txt"; then
  check pass "fixture N: all-floor durations input still packs (exit 0)"
else
  check fail "fixture N: all-floor durations input refused: $(tail -2 "$WORK/N-err.txt")"
fi
if grep -qF $'n-a\t60000\tfloor' "$WORK/N-durations.tsv" 2>/dev/null \
   && ! grep -qF $'\tmeasured' "$WORK/N-durations.tsv" 2>/dev/null; then
  check pass "fixture N: floor rows re-derive as floor — never re-read as measured"
else
  check fail "fixture N: a src=floor row laundered into measured: $(cat "$WORK/N-durations.tsv" 2>/dev/null)"
fi

# === Fixture O: zero usable timing rows → all-floor WARN-degrade =============================
# Files exist but every row is excluded → the measured set is empty. The
# generator warns and still writes a count-balanced all-floor manifest at
# DEFAULT_SUITE_MS (the die this replaces is fixture D3's original contract).
FO="$WORK/O"; mkdir -p "$FO"
printf 'o-a\no-b\n' > "$FO/registered.txt"
printf '__run_boundary_start__\t0\n' > "$FO/timings.tsv"
if gen "$FO" "$FO/registered.txt" "$WORK/O-manifest.tsv" \
     --durations-out "$WORK/O-durations.tsv" --write \
     > /dev/null 2> "$WORK/O-err.txt"; then
  check pass "fixture O: timings-empty input produces an all-floor manifest"
else
  check fail "fixture O: all-floor degrade refused: $(tail -2 "$WORK/O-err.txt")"
fi
if grep -qi 'floor' "$WORK/O-err.txt" \
   && [[ "$(grep -c '^o-[ab]' "$WORK/O-manifest.tsv" 2>/dev/null)" == "2" ]]; then
  check pass "fixture O: all-floor degrade warns and tables every registered label"
else
  check fail "fixture O: all-floor manifest/WARN missing: $(tail -2 "$WORK/O-err.txt")"
fi
if grep -qF $'o-a\t60000\tfloor' "$WORK/O-durations.tsv" 2>/dev/null; then
  check pass "fixture O: nothing measured → floor falls back to DEFAULT_SUITE_MS"
else
  check fail "fixture O: DEFAULT_SUITE_MS fallback missing from durations table"
fi

# === Fixture P: --run paginates the artifacts listing =======================================
# A run with more than one page of artifacts must not silently drop the tail:
# page 1 carries 99 fillers + one timing artifact, page 2 carries the ONLY copy
# of page2-only-suite. A single-page fetch merges the page-1 leg and quietly
# loses page 2 — indistinguishable from a leg that died before its feed write.
# The stub also answers the unpaginated `?per_page=100` shape (returns page 1)
# so the mutation "revert to a single fetch" is expressible and goes RED.
FP="$WORK/P"; mkdir -p "$FP/bin"
printf 'page1-suite\npage2-only-suite\n' > "$FP/registered.txt"
: > "$FP/calls.log"
# Artifact zips: each matching artifact is a zip holding suite-timings.tsv.
python3 - "$FP" <<'PYEOF'
import sys, zipfile
fp = sys.argv[1]
zipfile.ZipFile(f"{fp}/art-9001.zip", "w").writestr(
    "suite-timings.tsv", "page1-suite\t111\n")
zipfile.ZipFile(f"{fp}/art-9002.zip", "w").writestr(
    "suite-timings.tsv", "page2-only-suite\t222\n")
PYEOF
{
  printf '{"total_count":101,"artifacts":['
  for i in $(seq 1 99); do printf '{"id":%d,"name":"filler-art-%d"},' "$i" "$i"; done
  printf '{"id":9001,"name":"suite-timings-scripts-1"}]}'
} > "$FP/arts-p1.json"
printf '{"total_count":101,"artifacts":[{"id":9002,"name":"suite-timings-scripts-2"}]}' \
  > "$FP/arts-p2.json"
cat > "$FP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FIXTURE_DIR/calls.log"
url="${2:-}"   # argv shape: gh api <url>
# `&page=N` is anchored on the '&' (a bare 'page=N' substring matches the
# 'per_page=100' in EVERY request) AND end-anchored — '&page=1' as a non-final
# pattern would also match '&page=10'/'&page=100' and silently re-serve page 1.
case "$url" in
  *'/artifacts?'*'&page=2')
    cat "$FIXTURE_DIR/arts-p2.json" ;;
  *'/artifacts?'*'&page=1'|*'/artifacts?per_page=100')
    cat "$FIXTURE_DIR/arts-p1.json" ;;
  *'/artifacts/'*'/zip')
    aid="$(printf '%s' "$url" | sed -nE 's#.*/artifacts/([0-9]+)/zip#\1#p')"
    cat "$FIXTURE_DIR/art-$aid.zip" ;;
  *) echo "STUB-UNEXPECTED: $*" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
STUB
chmod +x "$FP/bin/gh"

if FIXTURE_DIR="$FP" PATH="$FP/bin:$PATH" python3 "$GEN" --run 4242 --group light \
     --registered-file "$FP/registered.txt" --manifest "$WORK/P-manifest.tsv" \
     --durations-out "$WORK/P-durations.tsv" --write \
     > "$WORK/P-out.txt" 2> "$WORK/P-err.txt"; then
  check pass "fixture P: --run against a two-page artifact set exits 0"
else
  check fail "fixture P: --run fetch refused: $(tail -2 "$WORK/P-err.txt")"
fi
if grep -qF $'page1-suite\t111\tmeasured' "$WORK/P-durations.tsv" 2>/dev/null \
   && grep -qF $'page2-only-suite\t222\tmeasured' "$WORK/P-durations.tsv" 2>/dev/null; then
  check pass "fixture P: timing artifacts on BOTH pages merged (listing paginated)"
else
  check fail "fixture P: a page-2-only artifact was dropped — the artifacts listing truncated at page 1"
fi
if grep -qF '&page=2' "$FP/calls.log"; then
  check pass "fixture P: the artifacts call actually fetched page 2 (call-shape, not just output)"
else
  check fail "fixture P: no page=2 call in the stub's argv log — pagination never ran"
fi

# === Fixture Q: --incremental pins incumbents, tables only new labels =========
# The add/remove regen path (P3, #9402, ADR-240 amd.): incumbent rows pin
# byte-verbatim, unregistered rows drop, and registered-but-untabled labels
# deal onto least-loaded legs priced by the committed durations table — no
# timing fetch, and the durations table takes only the parity delta (dropped
# rows out, new labels in at floor; measured rows byte-identical).
# inc <registered-file> <manifest> <durations> [extra args...]
inc() {
  local rf=$1 mf=$2 df=$3; shift 3
  python3 "$GEN" --incremental --registered-file "$rf" \
    --manifest "$mf" --durations "$df" "$@"
}
FQ="$WORK/Q"; mkdir -p "$FQ"; assert_fixture_dir "$FQ"
: > "$FQ/registered.txt"
printf '# fixture incumbent\n# n=%s\n' "$N" > "$FQ/manifest.tsv"
# The durations fixture is written label-sorted (q-ghost sorts before
# q-inc-*) so the delta's kept-rows check is a pure byte/order comparison.
printf 'q-ghost\t50\tmeasured\n' > "$FQ/durations.tsv"
for i in $(seq 1 "$N"); do
  printf 'q-inc-%02d\n' "$i" >> "$FQ/registered.txt"
  printf 'q-inc-%02d\t%d\n' "$i" "$i" >> "$FQ/manifest.tsv"
  printf 'q-inc-%02d\t%d\tmeasured\n' "$i" "$(( i * 100 ))" >> "$FQ/durations.tsv"
done
printf 'q-ghost\t%d\n' "$N" >> "$FQ/manifest.tsv"   # unregistered — must drop
printf 'q-new-1\nq-new-2\n' >> "$FQ/registered.txt" # untabled — must place
# Snapshot the durations rows that must survive the delta byte-identical.
grep -v 'q-ghost' "$FQ/durations.tsv" > "$FQ/kept-durations.before"
if inc "$FQ/registered.txt" "$FQ/manifest.tsv" "$FQ/durations.tsv" --write \
     > "$FQ/out.txt" 2> "$FQ/err.txt"; then
  check pass "fixture Q: --incremental --write exits 0"
else
  check fail "fixture Q: --incremental refused: $(tail -2 "$FQ/err.txt")"
fi
# Every kept incumbent row pins byte-verbatim — legs identical, zero moved.
PIN_OK=1
for i in $(seq 1 "$N"); do
  grep -qxF "$(printf 'q-inc-%02d\t%d' "$i" "$i")" "$FQ/manifest.tsv" || PIN_OK=0
done
if (( PIN_OK )); then
  check pass "fixture Q: all $N incumbent rows pin verbatim"
else
  check fail "fixture Q: an incumbent row moved — incremental must never rebalance"
fi
if grep -q ' 0 moved' "$FQ/out.txt"; then
  check pass "fixture Q: the report confirms 0 moved"
else
  check fail "fixture Q: report does not confirm zero movement: $(grep 'moved' "$FQ/out.txt")"
fi
if grep -q 'q-ghost' "$FQ/manifest.tsv"; then
  check fail "fixture Q: unregistered incumbent row retained — stale rows must drop"
else
  check pass "fixture Q: unregistered incumbent row dropped"
fi
if grep -qi 'unregistered\|dropping' "$FQ/err.txt"; then
  check pass "fixture Q: the stale-row drop is warned, not silent"
else
  check fail "fixture Q: stale incumbent row dropped WITHOUT a WARN"
fi
# Load-aware placement: leg i is priced i*100 → leg 1 is the lightest.
NEW1="$(awk -F'\t' '$1=="q-new-1" {print $2}' "$FQ/manifest.tsv")"
if [[ "$NEW1" == "1" ]]; then
  check pass "fixture Q: new label lands on the least-loaded incumbent leg"
else
  check fail "fixture Q: q-new-1 landed on leg $NEW1 — expected leg 1 (lightest incumbent load)"
fi
# Dealt by load, not parked: once q-new-1 joins leg 1 at floor_ms the next
# least-loaded leg is leg 2 (200ms < 100ms+floor for N>=3) — q-new-2 must go
# there. Two new labels piling onto leg 1 is the Guard-2 mutation.
NEW2="$(awk -F'\t' '$1=="q-new-2" {print $2}' "$FQ/manifest.tsv")"
if (( N >= 3 )); then
  if [[ "$NEW2" == "2" ]]; then
    check pass "fixture Q: second new label deals to the NEXT least-loaded leg (load-aware)"
  else
    check fail "fixture Q: q-new-2 landed on leg $NEW2 — new labels must spread by load, not pile on one leg"
  fi
fi
# The durations table takes ONLY the parity delta: the dropped label's row
# leaves, each new label merges in at floor_ms (median of measured
# {50,100..700} = (300+400)/2 = 350) with src=floor, and every retained row
# is byte-identical — incremental never recomputes a measurement.
if diff "$FQ/kept-durations.before" <(grep -v 'q-new-' "$FQ/durations.tsv") > /dev/null; then
  check pass "fixture Q: every retained durations row is byte-identical after the delta"
else
  check fail "fixture Q: the delta recomputed a measured row: $(diff "$FQ/kept-durations.before" <(grep -v 'q-new-' "$FQ/durations.tsv") | head -4)"
fi
if ! grep -q 'q-ghost' "$FQ/durations.tsv"; then
  check pass "fixture Q: dropped label's durations row removed (manifest/durations parity)"
else
  check fail "fixture Q: durations still tables the dropped label — check_durations parity would red"
fi
if grep -qF $'q-new-1\t350\tfloor' "$FQ/durations.tsv" \
   && grep -qF $'q-new-2\t350\tfloor' "$FQ/durations.tsv"; then
  check pass "fixture Q: new labels merge into durations as floor rows (350ms, src=floor)"
else
  check fail "fixture Q: new labels missing their floor durations rows"
fi
MLABELS_Q="$(grep -v '^#' "$FQ/manifest.tsv" | cut -f1 | sort -u || true)"
DLABELS_Q="$(grep -vE '^[[:space:]]*(#|$)' "$FQ/durations.tsv" | cut -f1 | sort -u || true)"
if [[ "$MLABELS_Q" == "$DLABELS_Q" ]]; then
  check pass "fixture Q: manifest and durations label sets stay equal after the delta"
else
  check fail "fixture Q: label sets diverge — manifest=[$(printf '%s ' $MLABELS_Q)] durations=[$(printf '%s ' $DLABELS_Q)]"
fi
if grep -vE '^[[:space:]]*(#|$)' "$FQ/durations.tsv" | cut -f1 | LC_ALL=C sort -c 2>/dev/null; then
  check pass "fixture Q: durations rows stay label-sorted after the delta"
else
  check fail "fixture Q: the delta left durations rows unsorted — the lint's sort check would red"
fi
# The emitted header's regen: hint must route operators to --incremental for
# add/remove regens — the plan's Dependencies & Risks flag.
if grep -q '^# regen:.*--incremental' "$FQ/manifest.tsv"; then
  check pass "fixture Q: emitted header's regen: hint names --incremental"
else
  check fail "fixture Q: regen: hint does not name --incremental: $(grep '^# regen:' "$FQ/manifest.tsv")"
fi

# === Fixture R: add-one-suite incremental diff is exactly +1 row ==============
FR="$WORK/R"; mkdir -p "$FR"; assert_fixture_dir "$FR"
printf 'r-a\nr-b\nr-new\n' > "$FR/registered.txt"
{ printf '# fixture incumbent\n# n=%s\n' "$N"
  printf 'r-a\t1\nr-b\t2\n'; } > "$FR/manifest.tsv"
printf 'r-a\t100\tmeasured\nr-b\t100\tmeasured\n' > "$FR/durations.tsv"
cp "$FR/manifest.tsv" "$FR/manifest.before"
cp "$FR/durations.tsv" "$FR/durations.before"
if inc "$FR/registered.txt" "$FR/manifest.tsv" "$FR/durations.tsv" --write \
     > /dev/null 2> "$FR/err.txt"; then
  check pass "fixture R: add-one --incremental --write exits 0"
else
  check fail "fixture R: add-one regen refused: $(tail -2 "$FR/err.txt")"
fi
# <(...) inside $(...) trips bash's paren matcher — extract rows to files first.
grep -v '^#' "$FR/manifest.before" > "$FR/before.rows"
grep -v '^#' "$FR/manifest.tsv" > "$FR/after.rows"
DIFF_R="$(diff "$FR/before.rows" "$FR/after.rows" || true)"
ADDED_R="$(printf '%s\n' "$DIFF_R" | grep -c '^> ' || true)"
REMOVED_R="$(printf '%s\n' "$DIFF_R" | grep -c '^< ' || true)"
if [[ "$ADDED_R" == "1" && "$REMOVED_R" == "0" ]] \
   && printf '%s\n' "$DIFF_R" | grep -qE $'^> r-new\t[0-9]+$'; then
  check pass "fixture R: add-one regen diffs exactly +1 row (r-new); zero moved/removed"
else
  check fail "fixture R: add-one diff is not the single new row: $DIFF_R"
fi
# The durations delta mirrors it: exactly +1 floor row (median of
# {100,100} = 100), the measured rows byte-identical.
grep -v '^#' "$FR/durations.before" > "$FR/dur-before.rows"
grep -v '^#' "$FR/durations.tsv" > "$FR/dur-after.rows"
DIFF_RD="$(diff "$FR/dur-before.rows" "$FR/dur-after.rows" || true)"
if [[ "$(printf '%s\n' "$DIFF_RD" | grep -c '^> ' || true)" == "1" \
   && "$(printf '%s\n' "$DIFF_RD" | grep -c '^< ' || true)" == "0" ]] \
   && printf '%s\n' "$DIFF_RD" | grep -qF $'> r-new\t100\tfloor'; then
  check pass "fixture R: durations delta is exactly +1 floor row (r-new at 100ms)"
else
  check fail "fixture R: durations delta is not the single floor row: $DIFF_RD"
fi

# === Fixture S: empty incumbent → WARN + full-assignment fallback =============
# The first-ever manifest has no incumbent rows — incremental degenerates to
# full floor assignment with a WARN rather than dying.
FS="$WORK/S"; mkdir -p "$FS"; assert_fixture_dir "$FS"
printf 's-a\ns-b\ns-c\n' > "$FS/registered.txt"
printf '# header only — no data rows\n' > "$FS/manifest.tsv"
printf 's-a\t100\tmeasured\n' > "$FS/durations.tsv"
if inc "$FS/registered.txt" "$FS/manifest.tsv" "$FS/durations.tsv" --write \
     > /dev/null 2> "$FS/err.txt"; then
  check pass "fixture S: empty incumbent exits 0 (first-ever-manifest fallback)"
else
  check fail "fixture S: empty incumbent refused: $(tail -2 "$FS/err.txt")"
fi
if grep -qiE 'incumbent|falling back|fallback' "$FS/err.txt"; then
  check pass "fixture S: the empty-incumbent fallback is warned, not silent"
else
  check fail "fixture S: empty-incumbent fallback produced no WARN"
fi
# The fallback tables every registered label as "new" — the durations delta
# adds the two unpriced labels at floor (median of measured {100} = 100) while
# the measured row keeps src=measured.
if grep -qF $'s-a\t100\tmeasured' "$FS/durations.tsv" \
   && grep -qF $'s-b\t100\tfloor' "$FS/durations.tsv" \
   && grep -qF $'s-c\t100\tfloor' "$FS/durations.tsv"; then
  check pass "fixture S: fallback's durations delta tables new labels at floor"
else
  check fail "fixture S: fallback durations delta wrong: $(cat "$FS/durations.tsv")"
fi
ROWS_S="$(grep -cv '^#' "$FS/manifest.tsv" || true)"
LEGS_BAD_S="$(awk -F'\t' -v n="$N" '!/^#/ && ($2 < 1 || $2 > n)' "$FS/manifest.tsv" | wc -l)"
if [[ "$ROWS_S" == "3" && "$LEGS_BAD_S" == "0" ]]; then
  check pass "fixture S: all 3 registered labels tabled on in-range legs"
else
  check fail "fixture S: fallback tabled $ROWS_S rows with $LEGS_BAD_S out-of-range leg(s)"
fi

# === Fixture T: --incremental refuses timing-source flags =====================
# --run/--runs/--timings-dir all request a timing fetch incremental mode never
# performs — accepting one silently re-enters the rebalance path.
for targs in "--run 4242" "--runs 3" "--timings-dir $FQ"; do
  if python3 "$GEN" --incremental --registered-file "$FQ/registered.txt" \
       --manifest "$FQ/T-m.tsv" $targs > /dev/null 2> "$FQ/T-err.txt"; then
    check fail "fixture T: --incremental $targs accepted — contradictory inputs must refuse"
  elif grep -qi 'incremental' "$FQ/T-err.txt"; then
    check pass "fixture T: --incremental $targs refuses and names the mode"
  else
    check fail "fixture T: --incremental $targs refused but stderr does not explain: $(tail -1 "$FQ/T-err.txt")"
  fi
done

# === Fixture U: an out-of-range incumbent pin refuses ==========================
# Committing a leg > n exit-2s the runner at parse — incremental must not
# launder a corrupt incumbent row into a fresh manifest (Guard-2 harness row).
FU="$WORK/U"; mkdir -p "$FU"; assert_fixture_dir "$FU"
printf 'u-a\nu-b\n' > "$FU/registered.txt"
{ printf '# fixture incumbent\n# n=%s\n' "$N"
  printf 'u-a\t1\nu-b\t%d\n' "$(( N + 1 ))"; } > "$FU/manifest.tsv"
printf 'u-a\t100\tmeasured\nu-b\t100\tmeasured\n' > "$FU/durations.tsv"
if inc "$FU/registered.txt" "$FU/manifest.tsv" "$FU/durations.tsv" --write \
     > /dev/null 2> "$FU/err.txt"; then
  check fail "fixture U: incumbent leg $(( N + 1 )) with n=$N accepted — out-of-range pins must refuse"
elif grep -qiE 'out-of-range|range|leg' "$FU/err.txt"; then
  check pass "fixture U: out-of-range incumbent leg refuses and names it"
else
  check fail "fixture U: refused but stderr does not explain: $(tail -1 "$FU/err.txt")"
fi

# === Fixture V: --incremental keeps the committed-write K != N refusal ========
SUM_V_BEFORE="$(cksum "$REPO_ROOT/scripts/suite-shard-legs.tsv")"
if python3 "$GEN" --incremental --registered-file "$FQ/registered.txt" \
     --legs "$(( N + 1 ))" --write > /dev/null 2> "$FQ/V-err.txt"; then
  check fail "fixture V: --incremental --legs $(( N + 1 )) --write at the DEFAULT path succeeded — a committed n-mismatch must refuse"
else
  check pass "fixture V: incremental committed write with K != workflow N exits non-zero"
fi
if [[ "$(cksum "$REPO_ROOT/scripts/suite-shard-legs.tsv")" == "$SUM_V_BEFORE" ]]; then
  check pass "fixture V: refusal fired before the write — committed manifest untouched"
else
  check fail "fixture V: the refusal left the committed manifest rewritten"
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
MIN_CASES=40
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
