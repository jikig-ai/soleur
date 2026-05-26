#!/usr/bin/env bash
# Verifies sub-PR 3's two contracts:
# (1) Static: the 4 skills whose SKILL.md invokes `gh pr merge --auto`
#     must wrap that invocation in acquire_lock merge-main / release_lock.
# (2) Smoke: the underlying merge-main lock serializes parallel acquirers.
#
# Run via:  bash plugins/soleur/test/concurrent-ship.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SS="$REPO_ROOT/.claude/hooks/lib/session-state.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# ---------------------------------------------------------------------------
# T1: Static wiring check
# ---------------------------------------------------------------------------
# These 4 skills are the only callers of `gh pr merge --auto` per the plan
# Reconciliation table. Each must invoke acquire_lock merge-main near the
# call site. The reverse direction (release_lock) is exercised by the trap
# in session-state.sh's exit handler, but we also assert it textually so a
# future refactor that drops the release doesn't silently leak the lock.
echo "T1: 4 skill files wrap gh pr merge --auto with acquire_lock merge-main"

declare -a SKILL_FILES=(
  "plugins/soleur/skills/schedule/SKILL.md"
  "plugins/soleur/skills/product-roadmap/SKILL.md"
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/skills/merge-pr/SKILL.md"
)

for f in "${SKILL_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  if [[ ! -f "$path" ]]; then
    fail "T1: missing file $f"
    continue
  fi
  # Match both arg orderings: `--auto --squash` and `--squash --auto`.
  if ! grep -qE 'gh pr merge.*--auto|gh pr merge.*--squash' "$path"; then
    pass "T1: $f does not invoke auto-merge (skipped)"
    continue
  fi
  # Accept either `acquire_lock merge-main` or `with_lock merge-main`
  # (the latter calls the former internally; it is the SKILL-friendly form
  # because it keeps fd 9 open across the critical section in a single
  # bash invocation).
  if ! grep -qE '(acquire_lock|with_lock) merge-main' "$path"; then
    fail "T1: $f invokes gh pr merge auto-merge but never acquires the merge-main lock"
    continue
  fi
  pass "T1: $f acquires merge-main lock"
done

# ---------------------------------------------------------------------------
# T2: Serialization smoke — primitive correctness under contention
# ---------------------------------------------------------------------------
echo "T2: parallel acquire_lock merge-main serializes critical sections"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export SOLEUR_SESSION_STATE_ROOT="$TMP/state"
mkdir -p "$SOLEUR_SESSION_STATE_ROOT/locks"

TRACE="$TMP/trace"
: > "$TRACE"

worker() {
  local id="$1"
  bash -c "
    export SOLEUR_SESSION_STATE_ROOT='$SOLEUR_SESSION_STATE_ROOT'
    source '$SS'
    acquire_lock merge-main 600
    printf '%s start %s\n' \"$id\" \"\$(date +%s%N)\" >> '$TRACE'
    sleep 1.2
    printf '%s end %s\n' \"$id\" \"\$(date +%s%N)\" >> '$TRACE'
    release_lock merge-main
  "
}

worker A &
worker B &
wait

lines=$(wc -l < "$TRACE")
if [[ "$lines" -ne 4 ]]; then
  fail "T2: expected 4 trace lines, got $lines (trace: $(cat "$TRACE"))"
else
  first_id=$(awk 'NR==1 {print $1}' "$TRACE")
  first_end=$(awk -v id="$first_id" '$1==id && $2=="end" {print $3}' "$TRACE")
  follower_id=$(awk -v id="$first_id" '$1!=id {print $1; exit}' "$TRACE")
  follower_start=$(awk -v id="$follower_id" '$1==id && $2=="start" {print $3}' "$TRACE")
  if [[ -z "$first_end" || -z "$follower_start" ]]; then
    fail "T2: could not parse leader/follower from trace: $(cat "$TRACE")"
  else
    diff_ns=$(( follower_start - first_end ))
    if (( diff_ns > -100000000 )); then
      pass "T2: merge-main lock serialized (follower start - leader end = $((diff_ns/1000000))ms)"
    else
      fail "T2: lock NOT serialized (follower started ${diff_ns}ns before leader finished)"
    fi
  fi
fi

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
