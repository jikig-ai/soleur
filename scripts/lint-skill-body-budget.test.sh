#!/usr/bin/env bash
# Tests for scripts/lint-skill-body-budget.py.
#
# THE PROPERTY: no lifecycle SKILL.md exceeds its pinned ceiling, and a ceiling
# can only be lowered.
#
# THE ANCHOR IS THE MERGE BASE, and that is the whole design. A ceiling read from
# the working tree lets one diff raise both the file and its limit and satisfy
# itself -- which is exactly what SKILL_DESCRIPTION_WORD_BUDGET has done fifteen
# times, each bump recorded "against an N/N zero-headroom baseline". Reading the
# ceiling from the base makes a same-diff raise impossible, so raising one
# requires its own reviewed PR.
#
# WHERE IT RUNS IS PART OF THE CONTRACT. A merge-base read needs a fetched
# origin/main. plugins/soleur/test/components.test.ts runs in a CI job with NO
# fetch-depth, where at depth 1 origin/main is not a ref at all -- the read fails
# on every run, and any working-tree fallback is then permanently fail-open,
# degrading the guard to the changelog it exists to replace. So base-unavailable
# is a HARD FAILURE here, never a skip, and case 7 pins that.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-skill-body-budget.py"

# A missing tool is a FAIL, not a SKIP: the scripts shard requires both, and an
# exit-0 skip is counted as a pass by run_suite -- a suite that never ran its SUT
# would read as green (review coverage consult).
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing — this suite cannot run its SUT"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git missing — this suite cannot run its SUT"; exit 1; }

TMP_ROOT=$(mktemp -d -t skillbudget.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

fails=0; passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0; SELFTEST_PASSES=$passes

[[ -f "$SUT" ]] || { echo "  FAIL: $SUT missing (RED expected before implementation)"; echo "0 passed, 1 failed"; exit 1; }

echo "lint-skill-body-budget.test.sh"

# --- fixture repo -------------------------------------------------------------
# A REAL git repo with a real main branch, because the property under test is a
# merge-base comparison and a fake one cannot exercise it.
REPO="$TMP_ROOT/repo"
mk_repo() {
  assert_fixture_dir "$TMP_ROOT"
  rm -rf "$REPO"; mkdir -p "$REPO/plugins/soleur/skills/plan" "$REPO/plugins/soleur/test"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
  # Two rows only: enough to show a per-file report AND a second offender. The
  # lint reads no transition view -- the row set IS the ceiling file (base ∪
  # working tree); which rows exist is pinned in workflow-fidelity.test.ts.
  mkdir -p "$REPO/plugins/soleur/skills/work"
  printf 'x%.0s' $(seq 1 1000) > "$REPO/plugins/soleur/skills/plan/SKILL.md"
  printf 'y%.0s' $(seq 1 2000) > "$REPO/plugins/soleur/skills/work/SKILL.md"
  cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1100, "work": 2200 } }
EOF
  git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm base
}
run_sut() { ( cd "$REPO" && python3 "$SUT" --base main 2>&1 ); }

# --- 1. in-budget tree passes -------------------------------------------------
mk_repo
OUT=$(run_sut); RC=$?
if [[ "$RC" -eq 0 ]]; then pass "an in-budget tree exits 0"; else fail "in-budget rc=$RC out=$OUT"; fi

# --- 2. a file over its ceiling fails, naming THAT file and a number ----------
mk_repo
printf 'x%.0s' $(seq 1 500) >> "$REPO/plugins/soleur/skills/plan/SKILL.md"
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"plan: plugins/soleur/skills/plan/SKILL.md is 1500 bytes, ceiling is 1100 (400 over)"* ]]; then
  pass "an oversized file fails, naming the file and its number"
else
  fail "oversize not caught — rc=$RC out=$OUT"
fi

# --- 3. raising a ceiling IN THE SAME DIFF does not satisfy it ----------------
# The whole point of the merge-base anchor. A working-tree read passes here.
mk_repo
printf 'x%.0s' $(seq 1 500) >> "$REPO/plugins/soleur/skills/plan/SKILL.md"
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 9000, "work": 2200 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "raising a ceiling in the same diff does NOT satisfy the guard"
else
  fail "same-diff ceiling raise was accepted — out=$OUT"
fi

# --- 4. lowering a ceiling is allowed ----------------------------------------
# One-sided by design: driving a number DOWN must never red, or the guard
# punishes the behaviour it exists to encourage.
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1050, "work": 2200 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -eq 0 ]]; then pass "lowering a ceiling is allowed"; else fail "lowering rejected — out=$OUT"; fi

# --- 5. retiring a row in a BUDGET-ONLY diff is legal (must-PASS) -------------
# Which rows exist is pinned in workflow-fidelity.test.ts (a required check);
# this lint only refuses a removal that rides with another change (case 12).
# Same trust level as a raise: the diff changes nothing but the ceiling file.
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1100 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "a row retired in a budget-only diff passes (the TS pin owns the row set)"
else
  fail "budget-only row retirement rejected — rc=$RC out=$OUT"
fi

# --- 6. deleting the ceiling file entirely fails ------------------------------
# Case 5 covers a missing ROW; this covers the missing FILE, which would
# otherwise be a permanent escape hatch through the bootstrap arm.
mk_repo
rm -f "$REPO/plugins/soleur/test/skill-body-budget.json"
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 ]]; then pass "deleting the ceiling file fails"; else fail "deleted ceiling file accepted"; fi

# --- 7. an UNAVAILABLE base is a hard failure, never a skip -------------------
# The defect this guard would otherwise ship: in a shallow checkout the base read
# fails on every run, and a fallback to the working tree is fail-open forever.
mk_repo
OUT=$( ( cd "$REPO" && python3 "$SUT" --base does-not-exist 2>&1 ) ); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *base* ]]; then
  pass "an unavailable base fails hard rather than skipping"
else
  fail "missing base did not fail hard — rc=$RC out=$OUT"
fi

# --- 8. a SECOND offender is reported, not just the first ---------------------
mk_repo
printf 'x%.0s' $(seq 1 500) >> "$REPO/plugins/soleur/skills/plan/SKILL.md"
printf 'y%.0s' $(seq 1 500) >> "$REPO/plugins/soleur/skills/work/SKILL.md"
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *plan* && "$OUT" == *work* ]]; then
  pass "both offenders are reported, not only the first"
else
  fail "second offender missed — out=$OUT"
fi

# --- 9. a file exactly 1 byte under its ceiling passes (non-canonical PASS) ---
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1001, "work": 2200 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -eq 0 ]]; then pass "a file 1 byte under its ceiling passes"; else fail "off-by-one rejected — out=$OUT"; fi

# --- 10. an EMPTY row set fails rather than reporting a clean sweep ---------
# MIN_CASES equivalent. Base and working tree both empty (the fixture commits
# the empty file as base). Anchored on the sentinel, not on a bare non-zero rc.
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": {} }
EOF
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm empty-rows
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"declares NO rows"* ]]; then
  pass "an empty row set fails rather than reporting a clean sweep"
else
  fail "empty row set reported clean or failed for another reason — rc=$RC out=$OUT"
fi

# --- 11. every row is measured, whatever the FSM says about it ---------------
# The lifecycle includes sub-skills the FSM does not model (qa, deepen-plan);
# which rows exist is pinned on the TS side; here every row is enforced.
mk_repo
mkdir -p "$REPO/plugins/soleur/skills/qa"; printf 'q%.0s' $(seq 1 3000) > "$REPO/plugins/soleur/skills/qa/SKILL.md"
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1100, "work": 2200, "qa": 2500 } }
EOF
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm qa-row
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"qa: plugins/soleur/skills/qa/SKILL.md is 3000 bytes"* ]]; then
  pass "a row for a sub-skill the FSM does not model is measured like any other"
else
  fail "non-node row skipped — rc=$RC out=$OUT"
fi

# --- 12. a row REMOVED in the same diff is still measured against the base ---
# The escape test-design found in the view-based version (bloat the file AND
# drop its node -> OK over the survivors), re-expressed on the row set: bloat
# work/SKILL.md AND delete the `work` row. The base still names it.
mk_repo
printf 'y%.0s' $(seq 1 3000) >> "$REPO/plugins/soleur/skills/work/SKILL.md"
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1100 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"work: ceiling row REMOVED"* && "$OUT" == *"work: plugins/soleur/skills/work/SKILL.md is 5000 bytes"* ]]; then
  pass "a row removed in the same diff is refused AND its file is still measured against the base"
else
  fail "same-diff row removal unmeasured the file — rc=$RC out=$OUT"
fi

# --- 14. bootstrap is NOT reachable by renaming the ceiling file --------------
# The rename escape: `git mv` the ceiling file + edit BUDGET_REL in one diff, and
# every ceiling re-seeds with the monotonic check skipped. Bootstrap is legal
# only when the LINT is also absent at the base; here it is committed there.
mk_repo
mkdir -p "$REPO/scripts"; cp "$SUT" "$REPO/scripts/lint-skill-body-budget.py"
git -C "$REPO" rm -q plugins/soleur/test/skill-body-budget.json
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm lint-present-budget-absent
# Base now: lint PRESENT, ceiling file ABSENT. The working tree re-introduces the
# file with re-seeded ceilings -- the shape a rename-in-one-diff produces.
# (`git rm` also removed the now-empty directory; recreate it.)
mkdir -p "$REPO/plugins/soleur/test"
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 9000, "work": 9000 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"RENAME or deletion"* ]]; then
  pass "a missing base ceiling file under a present base lint is refused, not bootstrapped"
else
  fail "rename re-entered bootstrap — rc=$RC out=$OUT"
fi

# --- 15. a raise in a diff that touches ONLY the ceiling file is LEGAL --------
# The documented remedy for an over-ceiling file used to be "raise it in a
# separate PR" -- which reddened identically, because that PR was compared
# against the same base. A gate with no passable remedy trains bypass. The
# legal raise: base..HEAD changes nothing but the ceiling file.
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 5000, "work": 2200 } }
EOF
git -C "$REPO" checkout -q -b feature-raise-only
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm raise-only
OUT=$(run_sut); RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "a raise in a diff that changes only the ceiling file passes"
else
  fail "raise-only diff rejected — rc=$RC out=$OUT"
fi

# --- 16. a raise beside ANY other change is still refused -------------------
# The same raise plus one byte of growth in the file it licenses: RED, naming
# the co-travelling file. Also pins that an UNCOMMITTED growth beside a committed
# raise is seen (the working-tree diff is part of the changed set).
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 5000, "work": 2200 } }
EOF
git -C "$REPO" checkout -q -b feature-raise
git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm raise
printf 'x' >> "$REPO/plugins/soleur/skills/plan/SKILL.md"
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *"ceiling RAISED"* && "$OUT" == *"plugins/soleur/skills/plan/SKILL.md"* ]]; then
  pass "a raise beside an uncommitted growth is refused and names the co-travelling file"
else
  fail "raise-plus-growth accepted — rc=$RC out=$OUT"
fi

# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments into
# a mutant, and a binding 130 lines up is unbound there (measured: CONSTRUCTION, not
# FIRES). The self-test above asserts passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=15
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
