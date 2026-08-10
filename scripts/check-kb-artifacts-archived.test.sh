#!/usr/bin/env bash
# Tests for scripts/check-kb-artifacts-archived.sh.
#
# Run via: bash scripts/check-kb-artifacts-archived.test.sh
#
# Fixture DIRECTION matters here (the #7373 lesson): a suite whose every fixture expects
# "flag it" cannot see the gate becoming too aggressive. Both directions are instantiated
# — must-flag AND must-pass — and T7 pins the carve-out that is the likeliest over-reach.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-kb-artifacts-archived.sh"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A throwaway repo per case: the gate resolves its root via `git rev-parse --show-toplevel`,
# so it must run inside a real work tree, never against the developer's checkout.
mk_repo() {
  local d="$TMP/$1"; local branch="$2"
  mkdir -p "$d" && git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  # -B, not -b: the repo is already on `main`, and T5 deliberately uses that name.
  # `-b main` would print a stray `fatal: a branch named 'main' already exists` into an
  # otherwise-green run, which is how a reader learns to skim past real fatals.
  git -C "$d" checkout -q -B "$branch"
  printf '%s' "$d"
}
run_gate() { ( cd "$1" && bash "$GATE" "${2:-}" >"$TMP/out" 2>&1; echo $? ); }

echo "T1: a live spec dir is flagged"
R=$(mk_repo t1 feat-alpha)
mkdir -p "$R/knowledge-base/project/specs/feat-alpha"; echo x > "$R/knowledge-base/project/specs/feat-alpha/tasks.md"
rc=$(run_gate "$R")
if [[ "$rc" == "1" ]] && grep -q 'tasks.md' "$TMP/out"; then pass "T1 (rc=1, names the file)"
else fail "T1 expected rc=1 naming the file, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T2: a live plan carrying the slug is flagged"
R=$(mk_repo t2 feat-beta)
mkdir -p "$R/knowledge-base/project/plans"; echo x > "$R/knowledge-base/project/plans/2026-01-01-beta-plan.md"
rc=$(run_gate "$R")
if [[ "$rc" == "1" ]] && grep -q 'beta-plan.md' "$TMP/out"; then pass "T2"
else fail "T2 expected rc=1, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T3: ARCHIVED artifacts pass (the must-pass direction)"
R=$(mk_repo t3 feat-gamma)
mkdir -p "$R/knowledge-base/project/specs/archive/20260101-000000-feat-gamma" "$R/knowledge-base/project/plans/archive"
echo x > "$R/knowledge-base/project/specs/archive/20260101-000000-feat-gamma/tasks.md"
echo x > "$R/knowledge-base/project/plans/archive/20260101-000000-gamma-plan.md"
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]]; then pass "T3 (archived => clean)"
else fail "T3 expected rc=0, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T4: a branch with no artifacts at all passes"
R=$(mk_repo t4 feat-delta)
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]]; then pass "T4"; else fail "T4 expected rc=0, got rc=$rc"; fi

echo "T5: non-feature branch fails OPEN"
R=$(mk_repo t5 main)
mkdir -p "$R/knowledge-base/project/specs/main"; echo x > "$R/knowledge-base/project/specs/main/tasks.md"
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]] && grep -q 'not a feature branch' "$TMP/out"; then pass "T5 (fails open off feature branches)"
else fail "T5 expected rc=0 + skip message, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T6: another feature's plan is NOT flagged (slug scoping)"
R=$(mk_repo t6 feat-epsilon)
mkdir -p "$R/knowledge-base/project/plans"; echo x > "$R/knowledge-base/project/plans/2026-01-01-unrelated-zeta-plan.md"
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]]; then pass "T6 (does not flag a sibling feature's plan)"
else fail "T6 expected rc=0, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T7: decision-challenges.md ALONE is carved out (over-reach guard)"
R=$(mk_repo t7 feat-eta)
mkdir -p "$R/knowledge-base/project/specs/feat-eta"
echo x > "$R/knowledge-base/project/specs/feat-eta/decision-challenges.md"
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]] && grep -q 'carve-out' "$TMP/out"; then pass "T7 (Phase-6 carve-out honoured)"
else fail "T7 expected rc=0 + carve-out note, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T8: carve-out does NOT mask a sibling live file"
R=$(mk_repo t8 feat-theta)
mkdir -p "$R/knowledge-base/project/specs/feat-theta"
echo x > "$R/knowledge-base/project/specs/feat-theta/decision-challenges.md"
echo x > "$R/knowledge-base/project/specs/feat-theta/tasks.md"
rc=$(run_gate "$R")
if [[ "$rc" == "1" ]] && grep -q 'tasks.md' "$TMP/out"; then pass "T8 (carve-out is per-file, not per-directory)"
else fail "T8 expected rc=1 naming tasks.md, got rc=$rc: $(cat "$TMP/out")"; fi

echo "T9: a plan this branch ADDED is flagged even when its name shares no slug substring"
# The #7373 shape exactly: branch slug `one-shot-worktree-create-lease`, plan named
# `2026-08-09-fix-worktree-create-acquires-lease-plan.md`. A slug-glob check passes this;
# the diff-derived check must not.
R=$(mk_repo t9 main)
git -C "$R" remote add origin "$R" 2>/dev/null || true
git -C "$R" checkout -q -B feat-one-shot-worktree-create-lease
mkdir -p "$R/knowledge-base/project/plans"
echo x > "$R/knowledge-base/project/plans/2026-08-09-fix-worktree-create-acquires-lease-plan.md"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m "add plan"
git -C "$R" update-ref refs/remotes/origin/main refs/heads/main
rc=$(run_gate "$R")
if [[ "$rc" == "1" ]] && grep -q 'acquires-lease-plan.md' "$TMP/out"; then
  pass "T9 (diff-derived detection catches a non-slug-matching plan)"
else
  fail "T9 expected rc=1 naming the plan, got rc=$rc: $(cat "$TMP/out")"
fi

echo "T10: an ALREADY-ARCHIVED plan added by this branch is not double-flagged"
R=$(mk_repo t10 main)
git -C "$R" remote add origin "$R" 2>/dev/null || true
git -C "$R" checkout -q -B feat-iota
mkdir -p "$R/knowledge-base/project/plans/archive"
echo x > "$R/knowledge-base/project/plans/archive/20260101-000000-iota-plan.md"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m "add archived plan"
git -C "$R" update-ref refs/remotes/origin/main refs/heads/main
rc=$(run_gate "$R")
if [[ "$rc" == "0" ]]; then pass "T10 (archive/ path excluded from the diff-derived set)"
else fail "T10 expected rc=0, got rc=$rc: $(cat "$TMP/out")"; fi

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

# Count DISPATCHES, not wins — a floor over PASS alone cannot tell "did not run" from
# "ran and found failures", and prints a false diagnostic on every genuine regression.
MIN_ASSERTIONS=10
if [[ $(( PASS + FAIL )) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $(( PASS + FAIL )) assertions ran, expected >= $MIN_ASSERTIONS — the suite did not execute what it claims to cover."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
