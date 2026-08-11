#!/usr/bin/env bash
# Verifies sub-PR 3's two contracts:
# (1) Static: the 4 skills whose SKILL.md invokes `gh pr merge --auto`
#     must wrap that invocation in acquire_lock merge-main / release_lock.
# (2) Smoke: the underlying merge-main lock serializes parallel acquirers.
#
# Run via:  bash plugins/soleur/test/concurrent-ship.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SS="$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh"

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
# T1b (#7409): T1 alone can no longer distinguish "every invocation is wrapped"
# from "one of two is".
#
# Before #7409 each of these files held exactly ONE `gh pr merge --auto`, so a
# file-scoped presence grep for `with_lock merge-main` was a sound proxy for
# "the invocation is wrapped". #7409 added a deliberately-UNLOCKED second
# invocation in a degrade-open else arm — so the bare token now matches whether
# or not the locked arm still exists, and deleting the locked arm would leave
# T1 green. This asserts the STRUCTURE the pair is supposed to have.
# ---------------------------------------------------------------------------
echo "T1b: the locked arm and the degrade-open arm both exist, and nothing else merges"

for f in "${SKILL_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  [[ -f "$path" ]] || { fail "T1b: missing file $f"; continue; }

  # Anchor on the call form, not a bare token: these files also DISCUSS the
  # wrapper in prose, and a bare `with_lock merge-main` is satisfied by that.
  locked=$(grep -cE 'bash "\$SS_LIB" with_lock merge-main' "$path" || true)
  unlocked_marker=$(grep -cE 'reason=running-unlocked' "$path" || true)

  if [[ "$locked" -eq 1 ]]; then
    pass "T1b: $f has exactly one LOCKED merge invocation"
  else
    fail "T1b: $f has $locked locked merge invocations (expected exactly 1) — \
the degrade-open arm makes T1's presence grep unable to catch this"
  fi

  if [[ "$unlocked_marker" -ge 1 ]]; then
    pass "T1b: $f announces the unlocked arm (reason=running-unlocked)"
  else
    fail "T1b: $f runs a merge unlocked without emitting reason=running-unlocked — \
a silent unserialised merge"
  fi

  # NO cardinality leg here. A `grep -c 'gh pr merge'` counts PROSE mentions as
  # well as invocations — measured: 12 in ship/SKILL.md, 4 in merge-pr, 3 in
  # product-roadmap — so "expected 2" fails on a correct file. Catching a third,
  # unaccounted invocation would need a real shell parse; the two assertions
  # above pin what this suite can actually measure.
done

# ---------------------------------------------------------------------------
# T1c (#7409): the seven SKILL.md anchor sites — the actual deliverable.
#
# Nothing pinned these. #7409's whole user-visible effect is that seven
# agent-executed snippets resolve the library through the plugin-root anchor
# instead of a repo-only path; reverting all seven left every suite green,
# because the one scenario that exercises an anchor types the command into the
# test rather than reading it from SKILL.md. AC6 was a manual grep, which is
# not a gate.
# ---------------------------------------------------------------------------
echo "T1c: all seven SKILL.md sites resolve session-state through the plugin-root anchor"

declare -a ANCHOR_SITES=(
  "plugins/soleur/skills/merge-pr/SKILL.md"
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/skills/product-roadmap/SKILL.md"
  "plugins/soleur/skills/schedule/SKILL.md"
  "plugins/soleur/skills/one-shot/SKILL.md"
  "plugins/soleur/skills/work/SKILL.md"
  "plugins/soleur/skills/git-worktree/SKILL.md"
)

for f in "${ANCHOR_SITES[@]}"; do
  path="$REPO_ROOT/$f"
  [[ -f "$path" ]] || { fail "T1c: missing file $f"; continue; }

  # Presence of the new shape, then absence of the old — in that order. An
  # absence-only assertion is satisfied by DELETING the call site.
  if grep -qE '\$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}/scripts/lib/session-state\.sh' "$path"; then
    pass "T1c: $f anchors session-state at \${CLAUDE_PLUGIN_ROOT:-…}/scripts/lib/"
  else
    fail "T1c: $f does not resolve session-state through the plugin-root anchor — \
a marketplace install cannot reach the library from this site (#7409)"
  fi

  if grep -qE '\.claude/hooks/lib/session-state\.sh' "$path"; then
    fail "T1c: $f still references the pre-#7409 repo-only path, which does not \
exist in a marketplace install"
  else
    pass "T1c: $f carries no reference to the pre-#7409 repo-only path"
  fi
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
