#!/usr/bin/env bash
# Tests for scripts/lint-skill-body-budget.py.
#
# THE PROPERTY: no lifecycle SKILL.md exceeds its pinned ceiling, and a ceiling
# can only be lowered.
#
# THE ANCHOR IS THE MERGE BASE, and that is the whole design. A ceiling read from
# the working tree lets one diff raise both the file and its limit and satisfy
# itself -- which is exactly what SKILL_DESCRIPTION_WORD_BUDGET has done fourteen
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

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

TMP_ROOT=$(mktemp -d -t skillbudget.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

assert_fixture_dir() {
  local d="${1-}"
  [[ -n "$d" && "$d" == /* && -d "$d" && ! -L "$d" ]] || {
    echo "FATAL: refusing to operate on non-fixture dir '${d-}'" >&2; exit 2; }
  case "$d" in "$TMP_ROOT"|"$TMP_ROOT"/*) : ;; *)
    echo "FATAL: '$d' is outside the fixture root" >&2; exit 2 ;;
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
  rm -rf "$REPO"; mkdir -p "$REPO/plugins/soleur/skills/plan" "$REPO/plugins/soleur/test" "$REPO/.claude"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
  # Two nodes only: enough to show a per-file report AND a second offender.
  cat > "$REPO/.claude/workflow-transitions.json" <<'EOF'
{ "transitions": { "plan": ["work"], "work": ["review"] } }
EOF
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
if [[ "$RC" -ne 0 && "$OUT" == *plan* && "$OUT" =~ 1[0-9]{3} ]]; then
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

# --- 5. a lifecycle skill with NO row fails (unclassified bucket) -------------
mk_repo
cat > "$REPO/plugins/soleur/test/skill-body-budget.json" <<'EOF'
{ "_comment": "fixture", "ceilings": { "plan": 1100 } }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *work* ]]; then
  pass "a lifecycle skill with no ceiling row fails, naming it"
else
  fail "unclassified bucket did not fire — rc=$RC out=$OUT"
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

# --- 10. the guard's own discovery cannot match zero files -------------------
# MIN_CASES equivalent: a glob or node list that resolves to nothing must fail
# rather than report a clean sweep over an empty set.
mk_repo
cat > "$REPO/.claude/workflow-transitions.json" <<'EOF'
{ "transitions": {} }
EOF
OUT=$(run_sut); RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "an empty node set fails rather than reporting a clean sweep"
else
  fail "empty node set reported clean — out=$OUT"
fi

REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=10
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
