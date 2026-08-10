#!/usr/bin/env bash

# Tests for worktree-manager.sh safe-branch derivation (#7408).
#
# The defect: create_worktree derived BOTH the worktree directory path and the
# session-lease key from the RAW git branch name, while cleanup_merged_worktrees
# assumed a slugified directory name. For any slash-bearing branch that mismatch
# is unattended destruction of uncommitted work:
#
#   1. `git worktree add -b ci/rule-metrics .worktrees/ci/rule-metrics` nests
#      THREE levels deep instead of two.
#   2. _validate_worktree_name rejects the slash, acquire_lease returns 1, and
#      the `|| true` call site lets creation proceed UNLEASED.
#   3. cleanup_orphan_worktree_dirs globs exactly ONE level, so the intermediate
#      `.worktrees/ci` is unregistered, has no `.git` entry, is not a symlink and
#      is not a bare layout — every guard falls through to `rm -rf`.
#
# Origin carried 29 slash-bearing branches (ci/*, dependabot/*, bot-fix/*,
# gh-readonly-queue/*, chore/*) when this was filed, so it was reachable.
#
# Two arms are MUTANTS, because a single derivation-only mutant is defeated by
# the descendant guard shipped in the same PR (A4 would go green on it):
#   M1 — neuter the helper AND the descendant guard  -> A1 and A4 must FAIL.
#   M2 — neuter ONLY the descendant guard            -> A8 must FAIL.
#
# Reaper arms source the script and call cleanup_orphan_worktree_dirs directly:
# there is no CLI verb for it (its only call site is inside
# cleanup_merged_worktrees, which locks, deletes remote branches and closes PRs).
# Sourcing imports `set -euo pipefail` and the preamble exits 3 outside a git
# repo, so every source happens inside the fixture repo, in a subshell.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

# Sibling suites default this too: /tmp is a machine-global 4 GiB tmpfs shared by
# parallel worktrees, and a fixture that cannot be built yields a CONFIDENT WRONG
# verdict rather than a missing one.
export TMPDIR="${TMPDIR:-/var/tmp}"

echo "=== worktree-manager.sh safe-branch derivation (#7408) ==="
echo ""

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# --- Mutant variants -------------------------------------------------------
# Built by transforming a COPY of the script. Each mutation is asserted to have
# landed (diff against the pristine copy); a silently-missed anchor would make
# the mutant identical to the real script and the arm would pass vacuously —
# certifying a guard that does not exist.
MUT_DIR="$TEST_DIR/mutants"
mkdir -p "$MUT_DIR" || { echo "FATAL: cannot create mutant dir" >&2; exit 2; }

# M1 body: _safe_worktree_name becomes an identity transform. This reverts the
# derivation at EVERY call site in one edit rather than at N individual anchors.
neuter_helper() {
  perl -0pi -e 's/^_safe_worktree_name\(\) \{.*?^\}/_safe_worktree_name() {\n  printf "%s" "\$1"\n}/ms' "$1"
}
# Removes the descendant-guard block, anchored on its sentinel marker.
neuter_descendant_guard() {
  perl -0pi -e 's/^\s*# SOLEUR-GUARD-DESCENDANT-START.*?# SOLEUR-GUARD-DESCENDANT-END\n//ms' "$1"
}

build_mutant() {
  local name="$1"; shift
  local out="$MUT_DIR/$name.sh"
  cp "$SCRIPT" "$out" || { echo "FATAL: cp failed for $name" >&2; exit 2; }
  local fn
  for fn in "$@"; do "$fn" "$out"; done
  # Mutation-landed assertion: a mutant byte-identical to the script is a
  # harness defect, not a passing test.
  if diff -q "$SCRIPT" "$out" >/dev/null 2>&1; then
    echo "FATAL: mutant '$name' is identical to the script — mutation did not land" >&2
    exit 2
  fi
  bash -n "$out" || { echo "FATAL: mutant '$name' is not valid bash" >&2; exit 2; }
  printf '%s' "$out"
}

# --- Fixture ---------------------------------------------------------------
# Each arm gets a PRISTINE bare repo: create/reap are destructive and a shared
# fixture would let one arm's mutation decide the next arm's verdict.
new_fixture() {
  local id="$1"
  local root="$TEST_DIR/$id"
  mkdir -p "$root" || { echo "FATAL: cannot create fixture $id" >&2; exit 2; }
  git init -q -b main "$root/seed" || { echo "FATAL: git init failed" >&2; exit 2; }
  git -C "$root/seed" config user.email "test@test.local"
  git -C "$root/seed" config user.name "Test"
  mkdir -p "$root/seed/knowledge-base/project/specs"
  touch "$root/seed/knowledge-base/.gitkeep"
  git -C "$root/seed" add . >/dev/null 2>&1
  git -C "$root/seed" commit -q -m "seed"
  git clone -q --bare "$root/seed" "$root/bare.git" \
    || { echo "FATAL: bare clone failed" >&2; exit 2; }
  # Mirror the real repo: a stale knowledge-base/ copy at the bare root.
  mkdir -p "$root/bare.git/knowledge-base/project/specs"
  printf '%s' "$root/bare.git"
}

# Run the manager as a subprocess. Surfaces a non-zero exit rather than letting
# it present as "directory missing", which would misdirect diagnosis.
run_mgr() {
  local repo="$1" log="$2"; shift 2
  ( cd "$repo" && bash "$SCRIPT" --yes "$@" ) >"$log" 2>&1 || true
}

# Invoke the reaper directly from a chosen script variant, from OUTSIDE the
# worktrees (cwd = the bare root), which is where session-start runs it.
run_reaper() {
  local repo="$1" variant="${2:-$SCRIPT}"
  ( cd "$repo" && source "$variant" && cleanup_orphan_worktree_dirs true ) \
    >/dev/null 2>&1 || true
}

exists() { [[ -e "$1" ]] && echo true || echo false; }

# ---------------------------------------------------------------------------
# A1 — the slug is the directory name, and no nested intermediate is created.
# ---------------------------------------------------------------------------
echo "A1: create ci/rule-metrics -> .worktrees/ci-rule-metrics (two levels)"
R_A1=$(new_fixture a1)
run_mgr "$R_A1" "$TEST_DIR/a1.log" create ci/rule-metrics main

assert_eq "true" "$(exists "$R_A1/.worktrees/ci-rule-metrics")" \
  "slugified worktree dir exists"
# Deliberately NOT `find -maxdepth 2`: -maxdepth counts from the start path, so
# that command also prints every top-level dir inside a CORRECT worktree and
# discriminates nothing.
assert_eq "false" "$(exists "$R_A1/.worktrees/ci")" \
  "no nested intermediate .worktrees/ci"
echo ""

# ---------------------------------------------------------------------------
# A2 — the BRANCH keeps its slashes. The slug is a path/key concern only.
# ---------------------------------------------------------------------------
echo "A2: created ref is exactly ci/rule-metrics"
assert_eq "ci/rule-metrics" \
  "$(git -C "$R_A1/.worktrees/ci-rule-metrics" rev-parse --abbrev-ref HEAD 2>/dev/null || echo MISSING)" \
  "branch name preserved verbatim"
echo ""

# ---------------------------------------------------------------------------
# A3 — the lease key equals the directory basename and is actually keyable.
#      The marker's ABSENCE is the observable: it is what fires today.
# ---------------------------------------------------------------------------
echo "A3: lease acquired under the slug (no ACQUIRE_FAILED marker)"
assert_eq "false" \
  "$(grep -q 'SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED' "$TEST_DIR/a1.log" && echo true || echo false)" \
  "no lease-acquire failure during create"
assert_eq "true" \
  "$( ( source "$SCRIPT_DIR/../../../.claude/hooks/lib/session-state.sh" 2>/dev/null \
        && _validate_worktree_name "ci-rule-metrics" && echo true ) || echo false )" \
  "slug passes _validate_worktree_name"
echo ""

# ---------------------------------------------------------------------------
# A4 — the core data-loss arm. Uncommitted work in a slash-branch worktree must
#      survive the reaper that runs at session start / work Phase 0 / ship 7.4.
# ---------------------------------------------------------------------------
echo "A4: slash-branch worktree with uncommitted work survives the reaper"
R_A4=$(new_fixture a4)
run_mgr "$R_A4" "$TEST_DIR/a4.log" create ci/rule-metrics main
# Write uncommitted work wherever create actually put the worktree, so the arm
# measures survival rather than accidentally measuring path placement (A1's job).
# maxdepth 3, not 2: on the BUGGY path the worktree nests a level deeper
# (.worktrees/ci/rule-metrics/.git), and a depth-2 probe cannot see the very
# worktree whose survival this arm measures — the precondition would fail for
# the wrong reason and mask the arm.
WT_A4=$(find "$R_A4/.worktrees" -mindepth 1 -maxdepth 3 -name '.git' -printf '%h\n' 2>/dev/null | head -1)
if [[ -n "$WT_A4" ]]; then echo "precious uncommitted work" > "$WT_A4/UNCOMMITTED.txt"; fi
run_reaper "$R_A4"

assert_eq "true" "$([[ -n "$WT_A4" ]] && echo true || echo false)" \
  "a worktree was created (fixture precondition)"
assert_eq "true" "$(exists "${WT_A4:-/nonexistent}/UNCOMMITTED.txt")" \
  "uncommitted work survives the orphan reaper"
echo ""

# ---------------------------------------------------------------------------
# A5 — create_for_feature self-consistency. NOT "agrees with
#      cleanup_merged_worktrees": those two spec_dir paths have different roots
#      ($worktree_path vs $GIT_ROOT) and can never agree (plan R6).
# ---------------------------------------------------------------------------
echo "A5: feature a/b -> basename(spec_dir) == basename(worktree_path)"
R_A5=$(new_fixture a5)
run_mgr "$R_A5" "$TEST_DIR/a5.log" feature a/b

assert_eq "true" "$(exists "$R_A5/.worktrees/feat-a-b")" \
  "feature worktree dir is slugified"
assert_eq "true" \
  "$(exists "$R_A5/.worktrees/feat-a-b/knowledge-base/project/specs/feat-a-b")" \
  "spec dir basename matches worktree basename"
assert_eq "false" "$(exists "$R_A5/.worktrees/feat-a")" \
  "no nested intermediate for the feature path"
echo ""

# ---------------------------------------------------------------------------
# A6 — IDENTITY. tr '/' '-' is a no-op for every non-slash name, so nothing
#      about existing worktrees may change.
# ---------------------------------------------------------------------------
echo "A6: plain branch name behaves exactly as before"
R_A6=$(new_fixture a6)
run_mgr "$R_A6" "$TEST_DIR/a6.log" create feat-plain main

assert_eq "true" "$(exists "$R_A6/.worktrees/feat-plain")" \
  "plain worktree dir unchanged"
assert_eq "feat-plain" \
  "$(git -C "$R_A6/.worktrees/feat-plain" rev-parse --abbrev-ref HEAD 2>/dev/null || echo MISSING)" \
  "plain branch name unchanged"
assert_eq "false" \
  "$(grep -q 'SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED' "$TEST_DIR/a6.log" && echo true || echo false)" \
  "plain branch still leases cleanly"
echo ""

# ---------------------------------------------------------------------------
# A7 / M1 — mutation. Neuter the helper AND the descendant guard: the producer
#           nests again and nothing catches it, so A1 and A4 must both FAIL.
# ---------------------------------------------------------------------------
echo "A7 (M1 mutant): neutered helper + guard -> nesting returns and work is reaped"
M1=$(build_mutant m1 neuter_helper neuter_descendant_guard)
R_M1=$(new_fixture m1)
( cd "$R_M1" && bash "$M1" --yes create ci/rule-metrics main ) >"$TEST_DIR/m1.log" 2>&1 || true

assert_eq "true" "$(exists "$R_M1/.worktrees/ci/rule-metrics")" \
  "M1 reproduces the nested layout (A1 inverted)"

echo "mutant work" > "$R_M1/.worktrees/ci/rule-metrics/UNCOMMITTED.txt" 2>/dev/null || true
run_reaper "$R_M1" "$M1"
assert_eq "false" "$(exists "$R_M1/.worktrees/ci")" \
  "M1 reproduces the rm -rf of the live worktree (A4 inverted)"
echo ""

# ---------------------------------------------------------------------------
# A8 — REMEDIATION. Fixing the producer does nothing for a worktree ALREADY
#      nested on a customer's disk. Built with a direct `git worktree add`,
#      because the fixed manager can no longer produce this shape.
# ---------------------------------------------------------------------------
echo "A8: pre-existing nested worktree survives (descendant guard)"
R_A8=$(new_fixture a8)
mkdir -p "$R_A8/.worktrees"
git -C "$R_A8" worktree add -q -b ci/legacy "$R_A8/.worktrees/ci/legacy" main 2>/dev/null || true
echo "legacy work" > "$R_A8/.worktrees/ci/legacy/UNCOMMITTED.txt" 2>/dev/null || true
run_reaper "$R_A8"

assert_eq "true" "$(exists "$R_A8/.worktrees/ci/legacy/UNCOMMITTED.txt")" \
  "already-nested worktree is skipped, not reaped"
echo ""

# ---------------------------------------------------------------------------
# A8b / M2 — mutation. Keep the producer fix, neuter ONLY the guard: A8 must
#            FAIL. This is what makes A8 a real assertion rather than a
#            restatement of A1.
# ---------------------------------------------------------------------------
echo "A8b (M2 mutant): guard removed -> the pre-existing nested worktree is reaped"
M2=$(build_mutant m2 neuter_descendant_guard)
R_M2=$(new_fixture m2)
mkdir -p "$R_M2/.worktrees"
git -C "$R_M2" worktree add -q -b ci/legacy "$R_M2/.worktrees/ci/legacy" main 2>/dev/null || true
echo "legacy work" > "$R_M2/.worktrees/ci/legacy/UNCOMMITTED.txt" 2>/dev/null || true
run_reaper "$R_M2" "$M2"

assert_eq "false" "$(exists "$R_M2/.worktrees/ci")" \
  "M2 reproduces the reap of the pre-existing nested worktree"
echo ""

# ---------------------------------------------------------------------------
# A9 — the guard must NOT over-trigger. `"$dir"/*` (path boundary), never
#      `"$dir"*` (string prefix): a prefix match would treat .worktrees/ci-foo
#      as a descendant of .worktrees/ci and silently disable orphan reaping for
#      every name-prefix family.
# ---------------------------------------------------------------------------
echo "A9: a genuine orphan sharing a name prefix IS still reaped"
R_A9=$(new_fixture a9)
mkdir -p "$R_A9/.worktrees"
git -C "$R_A9" worktree add -q -b ci-foo "$R_A9/.worktrees/ci-foo" main 2>/dev/null || true
mkdir -p "$R_A9/.worktrees/ci"
echo "junk" > "$R_A9/.worktrees/ci/stale.txt"
run_reaper "$R_A9"

assert_eq "false" "$(exists "$R_A9/.worktrees/ci")" \
  "true orphan .worktrees/ci is reaped despite the ci-foo prefix sibling"
assert_eq "true" "$(exists "$R_A9/.worktrees/ci-foo")" \
  "the registered prefix-sibling is untouched"
echo ""

print_results
