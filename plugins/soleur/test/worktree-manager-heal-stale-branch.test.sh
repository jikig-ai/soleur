#!/usr/bin/env bash

# Tests for worktree-manager.sh heal_stale_branch() auto-healing.
# Regression test for the 2026-07-05 #4826 session: a prior aborted one-shot run
# left `feat-one-shot-4826-*` pushed to origin with ZERO commits and no PR, and
# the next attempt had to be rescued by a manual `git push origin --delete`.
# `create`/`feature` now auto-heal that stale EMPTY orphan branch (exact-name +
# 0 commits ahead of base + no live PR) so the run proceeds without hand cleanup.
# Run: bash plugins/soleur/test/worktree-manager-heal-stale-branch.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook or worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

# Route session-state.sh's headless_or_stderr to stderr (not a per-PID log file)
# so the SUT's heal warnings land in the captured logs we assert on. The log-file
# branch fires only when CLAUDECODE is set AND stderr is non-TTY (this harness).
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh heal_stale_branch() auto-healing ==="
echo ""

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Seed a non-bare repo (acts as the remote "origin"), then bare-clone it as the
# working repo — mirroring the real bare-repo-with-worktrees layout. The bare
# clone keeps origin pointed at the seed, so `git push origin --delete` and
# `git ls-remote origin` operate on the seed just like they would on GitHub.
git init -q -b main "$TEST_DIR/seed"
git -C "$TEST_DIR/seed" config user.email "test@test.local"
git -C "$TEST_DIR/seed" config user.name "Test"
mkdir -p "$TEST_DIR/seed/knowledge-base/project/specs"
touch "$TEST_DIR/seed/knowledge-base/.gitkeep"
git -C "$TEST_DIR/seed" add .
git -C "$TEST_DIR/seed" commit -q -m "seed"
git clone -q --bare "$TEST_DIR/seed" "$TEST_DIR/bare.git"

BARE="$TEST_DIR/bare.git"

# gh stub factory: `gh pr list ... --jq ...` prints the given live-PR count.
# heal_stale_branch invokes gh with --jq so gh itself emits the filtered scalar;
# the stub just echoes it. All other gh subcommands exit 1 (unhandled).
make_pr_count_stub() {
  local dir="$1" count="$2"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  printf '%s\n' "$count"
  exit 0
fi
echo "gh stub: unhandled '\$*'" >&2
exit 1
EOF
  chmod +x "$dir/gh"
}

# gh stub whose `pr list` FAILS (auth/rate-limit/network class) — exercises the
# fail-safe branch: gh present but errored must NOT delete (unknown PR state).
make_pr_fail_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo "gh: could not connect to api.github.com (stub-forced error)" >&2
  exit 1
fi
exit 1
EOF
  chmod +x "$dir/gh"
}

remote_has_branch() {
  git -C "$BARE" ls-remote --heads origin "$1" 2>/dev/null | grep -q . && echo true || echo false
}

local_has_branch() {
  git -C "$BARE" show-ref --verify --quiet "refs/heads/$1" && echo true || echo false
}

# A bin dir with every PATH binary symlinked EXCEPT gh, so `command -v gh` fails
# inside the SUT (gh genuinely absent) while git/bash/coreutils stay reachable.
# (Simply dropping gh-containing PATH dirs would also remove git — the two share
# /usr/bin on most systems.) First occurrence wins, preserving PATH precedence.
CLEAN_BIN="$TEST_DIR/clean-bin"; mkdir -p "$CLEAN_BIN"
while IFS= read -r d; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "gh" ] && continue
    [ -e "$CLEAN_BIN/$b" ] || ln -s "$f" "$CLEAN_BIN/$b" 2>/dev/null || true
  done
done < <(printf '%s\n' "$PATH" | tr ':' '\n')
PATH_NO_GH="$CLEAN_BIN"

# ---------------------------------------------------------------------------
# Test 1: stale EMPTY remote branch + no live PR -> auto-deleted, worktree made
# ---------------------------------------------------------------------------
echo "Test 1: empty remote orphan with no live PR is auto-healed"
git -C "$TEST_DIR/seed" branch feat-one-shot-stale-empty main   # 0 commits ahead of main
STUB0="$TEST_DIR/stub-nopr"; make_pr_count_stub "$STUB0" 0
assert_eq "true" "$(remote_has_branch feat-one-shot-stale-empty)" "precondition: orphan exists on origin"
cd "$BARE"
PATH="$STUB0:$PATH" bash "$SCRIPT" --yes create feat-one-shot-stale-empty >"$TEST_DIR/t1.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t1.log"; }
assert_eq "false" "$(remote_has_branch feat-one-shot-stale-empty)" "empty orphan deleted from origin"
assert_eq "true" "$([[ -d "$BARE/.worktrees/feat-one-shot-stale-empty" ]] && echo true || echo false)" \
  "worktree created after heal"
assert_contains "$(cat "$TEST_DIR/t1.log")" "auto-healed stale empty remote branch" "heal was logged"
echo ""

# ---------------------------------------------------------------------------
# Test 2: remote branch WITH commits -> NOT deleted (real work is never healed)
# ---------------------------------------------------------------------------
echo "Test 2: remote branch with real commits is preserved"
git -C "$TEST_DIR/seed" checkout -q -b feat-has-work main
echo "change" > "$TEST_DIR/seed/work.txt"
git -C "$TEST_DIR/seed" add work.txt
git -C "$TEST_DIR/seed" commit -q -m "real work"
git -C "$TEST_DIR/seed" checkout -q main
STUB0b="$TEST_DIR/stub-nopr2"; make_pr_count_stub "$STUB0b" 0
cd "$BARE"
PATH="$STUB0b:$PATH" bash "$SCRIPT" --yes create feat-has-work >"$TEST_DIR/t2.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t2.log"; }
assert_eq "true" "$(remote_has_branch feat-has-work)" "branch with commits NOT deleted from origin"
assert_contains "$(cat "$TEST_DIR/t2.log")" "NOT auto-deleting (real work)" "collision (real work) was surfaced"
echo ""

# ---------------------------------------------------------------------------
# Test 3: no remote branch of that name -> heal is a clean no-op
# ---------------------------------------------------------------------------
echo "Test 3: absent branch -> heal is a no-op, create proceeds"
STUB0c="$TEST_DIR/stub-nopr3"; make_pr_count_stub "$STUB0c" 0
cd "$BARE"
PATH="$STUB0c:$PATH" bash "$SCRIPT" --yes create feat-brand-new >"$TEST_DIR/t3.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t3.log"; }
assert_eq "true" "$([[ -d "$BARE/.worktrees/feat-brand-new" ]] && echo true || echo false)" \
  "worktree created for a never-before-seen branch"
echo ""

# ---------------------------------------------------------------------------
# Test 4: empty remote branch BUT a live PR exists -> NOT deleted (collision)
# ---------------------------------------------------------------------------
echo "Test 4: empty remote orphan WITH a live PR is preserved (parallel session)"
git -C "$TEST_DIR/seed" branch feat-empty-with-pr main   # 0 commits ahead of main
STUB1="$TEST_DIR/stub-livepr"; make_pr_count_stub "$STUB1" 1   # gh reports 1 live PR
assert_eq "true" "$(remote_has_branch feat-empty-with-pr)" "precondition: orphan exists on origin"
cd "$BARE"
PATH="$STUB1:$PATH" bash "$SCRIPT" --yes create feat-empty-with-pr >"$TEST_DIR/t4.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t4.log"; }
assert_eq "true" "$(remote_has_branch feat-empty-with-pr)" "empty branch with a live PR NOT deleted"
assert_contains "$(cat "$TEST_DIR/t4.log")" "has a live PR" "live-PR collision was surfaced"
echo ""

# ---------------------------------------------------------------------------
# Test 5: stale EMPTY LOCAL branch (not checked out) -> pruned so worktree adds
# ---------------------------------------------------------------------------
# A pre-existing local `refs/heads/feat-*` at 0 commits ahead would make
# `git worktree add -b` fail ("branch already exists"); heal must prune it first.
echo "Test 5: empty local orphan ref is pruned (unblocks worktree add)"
git -C "$BARE" branch feat-local-orphan main   # local ref, 0 ahead, not checked out
STUB5="$TEST_DIR/stub-nopr5"; make_pr_count_stub "$STUB5" 0
assert_eq "true" "$(local_has_branch feat-local-orphan)" "precondition: local orphan ref exists"
cd "$BARE"
PATH="$STUB5:$PATH" bash "$SCRIPT" --yes create feat-local-orphan >"$TEST_DIR/t5.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t5.log"; }
assert_eq "true" "$([[ -d "$BARE/.worktrees/feat-local-orphan" ]] && echo true || echo false)" \
  "worktree created after local orphan pruned"
assert_contains "$(cat "$TEST_DIR/t5.log")" "auto-healed stale empty local branch" "local prune was logged"
echo ""

# ---------------------------------------------------------------------------
# Test 6: branch checked out in a worktree is NEVER healed (early-return guard)
# ---------------------------------------------------------------------------
# feat-active is checked out at a NON-standard path, so create_worktree's
# standard-path existence check misses it and reaches heal — which must early-
# return on the checked-out guard, leaving both the ref and worktree intact.
echo "Test 6: a checked-out branch is not healed"
git -C "$BARE" worktree add -q "$TEST_DIR/active-elsewhere" -b feat-active main 2>/dev/null
STUB6="$TEST_DIR/stub-nopr6"; make_pr_count_stub "$STUB6" 0
cd "$BARE"
PATH="$STUB6:$PATH" bash "$SCRIPT" --yes create feat-active >"$TEST_DIR/t6.log" 2>&1 || true
assert_eq "true" "$(local_has_branch feat-active)" "checked-out branch ref preserved (not pruned)"
assert_eq "true" "$([[ -d "$TEST_DIR/active-elsewhere" ]] && echo true || echo false)" \
  "checked-out worktree left intact"
echo ""

# ---------------------------------------------------------------------------
# Test 7: gh ABSENT -> empty orphan still healed on exact-name + empty evidence
# ---------------------------------------------------------------------------
echo "Test 7: gh unavailable still heals an empty orphan"
git -C "$TEST_DIR/seed" branch feat-nogh-orphan main
assert_eq "true" "$(remote_has_branch feat-nogh-orphan)" "precondition: orphan exists on origin"
cd "$BARE"
PATH="$PATH_NO_GH" bash "$SCRIPT" --yes create feat-nogh-orphan >"$TEST_DIR/t7.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t7.log"; }
assert_eq "false" "$(remote_has_branch feat-nogh-orphan)" "empty orphan deleted even with gh absent"
echo ""

# ---------------------------------------------------------------------------
# Test 8: gh ERRORS (present but failing) -> fail-safe, do NOT delete
# ---------------------------------------------------------------------------
# The load-bearing asymmetry: a transient gh outage must not yank a branch that
# might have a live PR. Distinct from gh-absent (Test 7), which DOES heal.
echo "Test 8: gh error is fail-safe (empty orphan preserved, not deleted)"
git -C "$TEST_DIR/seed" branch feat-gh-error main
STUB8="$TEST_DIR/stub-ghfail"; make_pr_fail_stub "$STUB8"
assert_eq "true" "$(remote_has_branch feat-gh-error)" "precondition: orphan exists on origin"
cd "$BARE"
PATH="$STUB8:$PATH" bash "$SCRIPT" --yes create feat-gh-error >"$TEST_DIR/t8.log" 2>&1 || {
  echo "  WARN: create exited non-zero:"; sed 's/^/    /' "$TEST_DIR/t8.log"; }
assert_eq "true" "$(remote_has_branch feat-gh-error)" "orphan NOT deleted when gh could not confirm PR state"
assert_contains "$(cat "$TEST_DIR/t8.log")" "could not confirm PR state" "fail-safe was logged"
echo ""

print_results
