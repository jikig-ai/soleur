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

remote_has_branch() {
  git -C "$BARE" ls-remote --heads origin "$1" 2>/dev/null | grep -q . && echo true || echo false
}

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

print_results
