#!/usr/bin/env bash
# scripts-shard-manifest.test.sh — the committed label→leg manifest must be
# well-formed, pinned to the CI matrix's N, and a subset of the registered set.
#
# WHY THIS EXISTS (#8006, ADR-240). `scripts/suite-shard-legs.tsv` is generated data
# the runner consumes by lookup. Two drift shapes matter:
#
#   * STALE-SUBSET — a suite is renamed or removed, its manifest row is now a
#     phantom. The runner tolerates it (the row simply never matches), so nothing
#     runtime-side notices. Without this suite a phantom lives forever and the
#     manifest rots toward decorative.
#   * N-DRIFT — ci.yml's test-scripts matrix changes leg count without a manifest
#     regen. The runner degrades to positional silently (correct fail-safe), and
#     the balance the manifest exists to provide quietly stops applying. That is
#     exactly the "silently does nothing" class this repo gates: the fail-safe is
#     right at runtime, and it still must be LOUD somewhere.
#
# The regeneration path is printed in every failure so the fix is always named:
# `python3 scripts/regenerate-shard-manifest.py --run <green-ci-run> --write`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
MANIFEST="$REPO_ROOT/scripts/suite-shard-legs.tsv"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
REGEN="python3 scripts/regenerate-shard-manifest.py --run <green-ci-run> --write"

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

echo "=== scripts-shard-manifest lint ==="
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

if [[ ! -f "$MANIFEST" ]]; then
  check fail "manifest absent: $MANIFEST — the runner degrades to positional, but the committed file is the feature. Regenerate: $REGEN"
else
  check pass "manifest exists"
fi
if [[ ! -f "$CI_YML" ]]; then
  echo "FATAL: ci.yml missing — cannot derive the declared leg count." >&2
  exit 2
fi

# --- Parse -------------------------------------------------------------------------------
# Data rows: non-comment, non-blank. Header: `# n=<digits>` plus provenance keys.
N_HDR="$(grep -m1 '^# n=' "$MANIFEST" | sed 's/^# n=//' || true)"
DATA="$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" || true)"

# The light job's declared N — same job_block scoping as scripts-shard-runtime-coverage:
# `^  test-scripts:` does NOT match `test-scripts-heavy:`.
CI_N="$(awk -v j='^  test-scripts:' '$0 ~ j {f=1} f&&/^  [a-z][a-z0-9-]*:$/&&$0 !~ j {exit} f' "$CI_YML" \
  | grep -oE 'shard: \["1/[0123456789]+' | grep -oE '[0123456789]+$' | head -1)"

if [[ "$CI_N" =~ ^[0123456789]+$ ]] && (( 10#$CI_N >= 1 )); then
  check pass "ci.yml test-scripts matrix declares N=$CI_N"
else
  check fail "could not derive the test-scripts matrix N from ci.yml — the drift pin has no reference"
fi

if [[ "$N_HDR" =~ ^[0123456789]+$ ]]; then
  check pass "manifest declares n=$N_HDR"
else
  check fail "manifest has no '# n=<int>' header — the runner will degrade it as unversioned. Regenerate: $REGEN"
fi

if [[ "$N_HDR" =~ ^[0123456789]+$ && "$CI_N" =~ ^[0123456789]+$ ]]; then
  if (( 10#$N_HDR == 10#$CI_N )); then
    check pass "manifest n == ci.yml N ($CI_N) — the runtime n-mismatch degrade is not silently active"
  else
    check fail "manifest n=$N_HDR but ci.yml declares $CI_N legs — every leg is running positional while the file pretends to apply. Regenerate: $REGEN"
  fi
fi

for key in generated-from-run generated-at generator; do
  if grep -q "^# ${key}=" "$MANIFEST"; then
    check pass "provenance field '# ${key}=' present"
  else
    check fail "provenance field '# ${key}=' missing — provenance is what makes a stale manifest diagnosable. Regenerate: $REGEN"
  fi
done

if [[ -z "$DATA" ]]; then
  check fail "manifest has zero data rows — an empty table degrades every assignment to hash fallback. Regenerate: $REGEN"
else
  ROWS="$(printf '%s\n' "$DATA" | wc -l)"
  if (( ROWS >= 100 )); then
    check pass "manifest carries $ROWS label rows"
  else
    check fail "manifest carries only $ROWS rows — the light group registers ~480; a mostly-empty table silently reverts to hash for nearly everything. Regenerate: $REGEN"
  fi
fi

# Malformed rows: every data row must be exactly `label<TAB>leg`, leg in 1..n.
BAD=0
while IFS=$'\t' read -r _lbl _leg _rest; do
  [[ -z "$_lbl" ]] && continue
  if [[ -n "$_rest" || ! "$_leg" =~ ^[0123456789]+$ ]]; then
    check fail "malformed row: '$_lbl' — expected 'label<TAB>leg'"
    BAD=$(( BAD + 1 ))
    continue
  fi
  if [[ "$N_HDR" =~ ^[0123456789]+$ ]] && (( 10#$_leg < 1 || 10#$_leg > 10#$N_HDR )); then
    check fail "row '$_lbl' assigns leg $_leg outside 1..$N_HDR"
    BAD=$(( BAD + 1 ))
  fi
done <<< "$DATA"
if (( BAD == 0 )) && [[ -n "$DATA" ]]; then
  check pass "every row is 'label<TAB>leg' with leg inside 1..n"
fi

# Duplicate labels — the runner refuses these outright, but they should never be
# committed in the first place.
DUPS="$(printf '%s\n' "$DATA" | cut -f1 | sort | uniq -d | tr '\n' ' ')"
if [[ -z "$DUPS" ]]; then
  check pass "no duplicate labels"
else
  check fail "duplicate label(s): $DUPS — the runner exit-2s on these. Regenerate: $REGEN"
fi

# Every declared leg must own ≥1 row — a leg with no pins relies entirely on hash
# fallback, and an all-fallback leg is the n-mismatch degrade wearing a disguise.
if [[ "$N_HDR" =~ ^[0123456789]+$ && -n "$DATA" ]]; then
  for leg in $(seq 1 "$(( 10#$N_HDR ))"); do
    if printf '%s\n' "$DATA" | cut -f2 | grep -qx "$leg"; then
      check pass "leg $leg has at least one pinned label"
    else
      check fail "leg $leg has ZERO pinned labels — it would run on hash fallback alone"
    fi
  done
fi

# labels ⊆ registered set — STRICT: a phantom row is the stale-subset drift this
# suite exists to catch. Derive the registered set the way the totality guard does:
# the runner's own enumerate, unsharded.
env -u SCRIPTS_SHARD TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts 2>/dev/null | grep '^SUITE_REGISTRATION' | cut -f2 \
  | sort -u > "${TMPDIR:-/tmp}/ssm-registered.$$"
trap 'rm -f "${TMPDIR:-/tmp}/ssm-registered.$$"' EXIT
printf '%s\n' "$DATA" | cut -f1 | sort -u > "${TMPDIR:-/tmp}/ssm-manifest.$$"
trap 'rm -f "${TMPDIR:-/tmp}/ssm-registered.$$" "${TMPDIR:-/tmp}/ssm-manifest.$$"' EXIT

REF_N="$(wc -l < "${TMPDIR:-/tmp}/ssm-registered.$$")"
if (( REF_N >= 100 )); then
  check pass "registered reference derived ($REF_N labels)"
else
  check fail "registered reference derived only $REF_N labels — the enumerate extraction is broken, every ⊆ assertion below is ungrounded"
fi

PHANTOMS="$(comm -23 "${TMPDIR:-/tmp}/ssm-manifest.$$" "${TMPDIR:-/tmp}/ssm-registered.$$" | tr '\n' ' ')"
if [[ -z "$PHANTOMS" ]]; then
  check pass "every manifest label is a registered scripts suite"
else
  check fail "phantom label(s) not in the registered set: $PHANTOMS — stale rows consume review trust while matching nothing. Regenerate: $REGEN"
fi

# --- Heavy manifest (suite-shard-legs-heavy.tsv, #8006 phase 2) -------------------------------
#
# Same contract as the light table, three deliberate deltas: scoped to the
# test-scripts-heavy job's N, subset-checked against the scripts-heavy
# registered set, and floored at >= 1 row — the group has ~3 registrations, so
# the light table's >=100 density floor would be wrong here.
MANIFEST_HEAVY="$REPO_ROOT/scripts/suite-shard-legs-heavy.tsv"
REGEN_HEAVY="python3 scripts/regenerate-shard-manifest.py --group heavy --run <green-ci-run> --write"

echo ""
echo "--- heavy manifest ---"
if [[ ! -f "$MANIFEST_HEAVY" ]]; then
  check fail "heavy manifest absent: $MANIFEST_HEAVY — the heavy group degrades to positional, but the committed file is the feature. Regenerate: $REGEN_HEAVY"
else
  check pass "heavy manifest exists"

  N_HDR_H="$(grep -m1 '^# n=' "$MANIFEST_HEAVY" | sed 's/^# n=//' || true)"
  DATA_H="$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST_HEAVY" || true)"
  CI_N_H="$(awk -v j='^  test-scripts-heavy:' '$0 ~ j {f=1} f&&/^  [a-z][a-z0-9-]*:$/&&$0 !~ j {exit} f' "$CI_YML" \
    | grep -oE 'shard: \["1/[0123456789]+' | grep -oE '[0123456789]+$' | head -1)"

  if [[ "$CI_N_H" =~ ^[0123456789]+$ ]] && (( 10#$CI_N_H >= 1 )); then
    check pass "ci.yml test-scripts-heavy matrix declares N=$CI_N_H"
  else
    check fail "could not derive the test-scripts-heavy matrix N from ci.yml"
  fi
  if [[ "$N_HDR_H" =~ ^[0123456789]+$ && "$CI_N_H" =~ ^[0123456789]+$ ]]; then
    if (( 10#$N_HDR_H == 10#$CI_N_H )); then
      check pass "heavy manifest n == ci.yml heavy N ($CI_N_H)"
    else
      check fail "heavy manifest n=$N_HDR_H but ci.yml declares $CI_N_H heavy legs — the heavy group is silently positional. Regenerate: $REGEN_HEAVY"
    fi
  elif [[ ! "$N_HDR_H" =~ ^[0123456789]+$ ]]; then
    check fail "heavy manifest has no '# n=<int>' header. Regenerate: $REGEN_HEAVY"
  fi
  for key in generated-from-run generated-at generator; do
    if grep -q "^# ${key}=" "$MANIFEST_HEAVY"; then
      check pass "heavy provenance field '# ${key}=' present"
    else
      check fail "heavy provenance field '# ${key}=' missing. Regenerate: $REGEN_HEAVY"
    fi
  done
  if [[ -z "$DATA_H" ]]; then
    check fail "heavy manifest has zero data rows — an empty table degrades the whole group to hash fallback. Regenerate: $REGEN_HEAVY"
  else
    ROWS_H="$(printf '%s\n' "$DATA_H" | wc -l)"
    if (( ROWS_H >= 1 )); then
      check pass "heavy manifest carries $ROWS_H label row(s)"
    fi
  fi
  BAD_H=0
  while IFS=$'\t' read -r _lbl _leg _rest; do
    [[ -z "$_lbl" ]] && continue
    if [[ -n "$_rest" || ! "$_leg" =~ ^[0123456789]+$ ]]; then
      check fail "heavy malformed row: '$_lbl' — expected 'label<TAB>leg'"
      BAD_H=$(( BAD_H + 1 ))
      continue
    fi
    if [[ "$N_HDR_H" =~ ^[0123456789]+$ ]] && (( 10#$_leg < 1 || 10#$_leg > 10#$N_HDR_H )); then
      check fail "heavy row '$_lbl' assigns leg $_leg outside 1..$N_HDR_H"
      BAD_H=$(( BAD_H + 1 ))
    fi
  done <<< "$DATA_H"
  if (( BAD_H == 0 )) && [[ -n "$DATA_H" ]]; then
    check pass "every heavy row is 'label<TAB>leg' with leg inside 1..n"
  fi
  DUPS_H="$(printf '%s\n' "$DATA_H" | cut -f1 | sort | uniq -d | tr '\n' ' ')"
  if [[ -z "$DUPS_H" ]]; then
    check pass "no duplicate heavy labels"
  else
    check fail "duplicate heavy label(s): $DUPS_H. Regenerate: $REGEN_HEAVY"
  fi
  if [[ "$N_HDR_H" =~ ^[0123456789]+$ && -n "$DATA_H" ]]; then
    for leg in $(seq 1 "$(( 10#$N_HDR_H ))"); do
      if printf '%s\n' "$DATA_H" | cut -f2 | grep -qx "$leg"; then
        check pass "heavy leg $leg has at least one pinned label"
      else
        check fail "heavy leg $leg has ZERO pinned labels — it would run on hash fallback alone"
      fi
    done
  fi
  env -u SCRIPTS_SHARD TEST_GROUP=scripts-heavy SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate scripts-heavy 2>/dev/null | grep '^SUITE_REGISTRATION' | cut -f2 \
    | sort -u > "${TMPDIR:-/tmp}/ssm-registered-heavy.$$"
  printf '%s\n' "$DATA_H" | cut -f1 | sort -u > "${TMPDIR:-/tmp}/ssm-manifest-heavy.$$"
  trap 'rm -f "${TMPDIR:-/tmp}/ssm-registered.$$" "${TMPDIR:-/tmp}/ssm-manifest.$$" "${TMPDIR:-/tmp}/ssm-registered-heavy.$$" "${TMPDIR:-/tmp}/ssm-manifest-heavy.$$"' EXIT
  REF_N_H="$(wc -l < "${TMPDIR:-/tmp}/ssm-registered-heavy.$$")"
  if (( REF_N_H >= 1 )); then
    check pass "heavy registered reference derived ($REF_N_H labels)"
  else
    check fail "heavy registered reference derived 0 labels — every ⊆ assertion below is ungrounded"
  fi
  PHANTOMS_H="$(comm -23 "${TMPDIR:-/tmp}/ssm-manifest-heavy.$$" "${TMPDIR:-/tmp}/ssm-registered-heavy.$$" | tr '\n' ' ')"
  if [[ -z "$PHANTOMS_H" ]]; then
    check pass "every heavy manifest label is a registered scripts-heavy suite"
  else
    check fail "phantom heavy label(s) not in the registered set: $PHANTOMS_H. Regenerate: $REGEN_HEAVY"
  fi
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
# printf + exit, NEVER through fail() — the helper this floor backstops is the thing
# one edit disarms. MIN_CASES sits on the line directly above its `if` so
# guard-vacuity-floor's backward slice-widening binds it.
MIN_CASES=25
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d check(s) ran, expected >= %d. The suite did not run to completion.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "scripts-shard-manifest.test.sh: $cases checks, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'VERDICT: %d of %d checks FAILED — this suite is RED.\n' "$FAIL" "$cases" >&2
  exit 1
fi
echo "All tests passed"
