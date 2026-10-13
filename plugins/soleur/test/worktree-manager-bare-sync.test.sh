#!/usr/bin/env bash

# Tests for worktree-manager.sh sync_bare_files() full-mirror reconciliation.
# Regression test for bare-root drift: the legacy populated working tree at the
# bare root drifted from HEAD because the old sync archived only a whitelist of
# trees and pruned deletions only under .claude/hooks/. Stale .github workflows
# (deleted in the Inngest migration #4483) and stale knowledge-base content
# (brand-guide drift, learning 2026-05-21) misled later analysis.
#
# The fix mirrors the FULL HEAD tree (checkout-index) and prunes tracked-deleted
# leftovers, gated on the git-history discriminator so untracked runtime artifacts
# are never removed. These tests pin all four behaviors + idempotency.
# Run: bash plugins/soleur/test/worktree-manager-bare-sync.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook or worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

# ...then re-pin config isolation. These must come AFTER the loop above: the
# loop unsets every GIT_* var, so an override exported by the caller is wiped.
# A host with `commit.gpgsign=true` (+ an ssh agent that declines) fails every
# fixture `git commit` with "failed to write commit object"; `git clone` then
# only warns "you appear to have cloned an empty repository", so the arms go red
# for a missing fixture while reading as genuine SUT failures.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh sync_bare_files() full-mirror ==="
echo ""

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# --- Build a seed repo with two commits so HEAD has an add, a delete, and a change ---
SEED="$TEST_DIR/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email "test@test.local"
git -C "$SEED" config user.name "Test"

# commit 1: baseline (old.yml will be deleted later; doc.md will change)
mkdir -p "$SEED/.github/workflows" "$SEED/plugins" "$SEED/knowledge-base/marketing"
printf 'name: old\n' > "$SEED/.github/workflows/old.yml"
printf 'keep me\n'   > "$SEED/plugins/keep.md"
printf 'v1\n'        > "$SEED/knowledge-base/marketing/doc.md"
git -C "$SEED" add .
git -C "$SEED" commit -q -m "commit1: baseline"

# commit 2 (HEAD): delete old.yml, change doc.md -> v2, add new.md
git -C "$SEED" rm -q .github/workflows/old.yml
printf 'v2\n'      > "$SEED/knowledge-base/marketing/doc.md"
printf 'brand new\n' > "$SEED/plugins/new.md"
git -C "$SEED" add .
git -C "$SEED" commit -q -m "commit2: delete old.yml, change doc, add new"

# --- Bare clone whose HEAD == commit2 ---
BARE="$TEST_DIR/bare.git"
git clone -q --bare "$SEED" "$BARE"

# --- Simulate the drifted populated working tree at the bare root (state of commit1) ---
mkdir -p "$BARE/.github/workflows" "$BARE/plugins" "$BARE/knowledge-base/marketing"
printf 'name: old\n' > "$BARE/.github/workflows/old.yml"   # tracked-deleted in HEAD -> must be pruned
printf 'keep me\n'   > "$BARE/plugins/keep.md"
printf 'v1\n'        > "$BARE/knowledge-base/marketing/doc.md"  # stale content -> must refresh to v2
# new.md intentionally absent -> must appear after sync

# Untracked runtime artifacts that were NEVER tracked: the safety boundary.
mkdir -p "$BARE/node_modules/pkg" "$BARE/_site"
printf 'dep\n'        > "$BARE/node_modules/pkg/index.js"
printf '<html>\n'     > "$BARE/_site/index.html"
printf 'SECRET=1\n'   > "$BARE/.env"

cd "$BARE"
bash "$SCRIPT" --yes sync-bare-files > "$TEST_DIR/sync1.log" 2>&1 || {
  echo "  WARN: sync-bare-files exited non-zero:"; sed 's/^/    /' "$TEST_DIR/sync1.log"; }

echo "Test 1: stale tracked-deleted file pruned"
assert_file_not_exists "$BARE/.github/workflows/old.yml" "old.yml removed from bare root"
echo ""

echo "Test 2: stale content refreshed to HEAD"
assert_eq "v2" "$(cat "$BARE/knowledge-base/marketing/doc.md")" "doc.md refreshed v1 -> v2"
echo ""

echo "Test 3: file added in HEAD now present"
assert_file_exists "$BARE/plugins/new.md" "new.md materialized from HEAD"
assert_file_exists "$BARE/plugins/keep.md" "keep.md still present"
echo ""

echo "Test 4: SAFETY BOUNDARY — never-tracked artifacts preserved"
assert_file_exists "$BARE/node_modules/pkg/index.js" "node_modules preserved"
assert_file_exists "$BARE/_site/index.html" "_site build output preserved"
assert_file_exists "$BARE/.env" "untracked .env preserved"
echo ""

echo "Test 5: idempotency — second run leaves the same state"
bash "$SCRIPT" --yes sync-bare-files > "$TEST_DIR/sync2.log" 2>&1 || {
  echo "  WARN: second sync exited non-zero:"; sed 's/^/    /' "$TEST_DIR/sync2.log"; }
assert_file_not_exists "$BARE/.github/workflows/old.yml" "old.yml still absent after 2nd run"
assert_eq "v2" "$(cat "$BARE/knowledge-base/marketing/doc.md")" "doc.md still v2 after 2nd run"
assert_file_exists "$BARE/.env" ".env still preserved after 2nd run"
echo ""

echo "Test 6: locale-independent prune — tracked dotfiles survive a non-C collation"
# The prune diffs two LC_ALL=C-sorted streams with comm; comm itself must run under
# LC_ALL=C too, or an en_US collation (dotfiles sort differently) makes it report
# "not in sorted order" and the unreliable output deletes TRACKED files that were just
# materialized (measured: .claude-plugin/marketplace.json, .gitignore, .github/ ...).
LOC=""
for cand in en_US.utf8 en_US.UTF-8; do
  if LC_ALL="$cand" bash -c ':' 2>/dev/null && locale -a 2>/dev/null | grep -qix "$cand"; then LOC="$cand"; break; fi
done
if [[ -z "$LOC" ]]; then
  if [[ -n "${CI:-}" ]]; then
    FAIL=$((FAIL + 1)); echo "  FAIL: no en_US UTF-8 locale installed on this CI host: the comm regression row cannot run"
  else
    echo "  SKIP: no en_US UTF-8 locale installed on this host"
  fi
else
  SEED2="$TEST_DIR/seed2"
  git init -q -b main "$SEED2"
  git -C "$SEED2" config user.email "test@test.local"
  git -C "$SEED2" config user.name "Test"
  mkdir -p "$SEED2/.claude-plugin" "$SEED2/apps"
  printf '{}\n'   > "$SEED2/.claude-plugin/marketplace.json"
  printf 'ignore\n' > "$SEED2/.gitignore"
  printf 'a\n'    > "$SEED2/apps/a.md"
  printf 'r\n'    > "$SEED2/README.md"
  git -C "$SEED2" add .
  git -C "$SEED2" commit -q -m "commit1"
  # GNU comm only checks sort order once it has seen an UNPAIRED line, so the fixture
  # needs a tracked-deleted path that sorts FIRST in C order (leading dot) ahead of the
  # kept README.md/apps/a.md pair, whose relative order differs between C and en_US.
  # `.zz-gone.md` sorts second in C order (after `.0-old.md`, before `README.md`) but LAST under en_US,
  # which is what makes GNU comm (without LC_ALL=C) emit the KEPT paths README.md and apps/a.md as deletions.
  printf 'gone\n' > "$SEED2/.0-old.md"
  printf 'gone\n' > "$SEED2/old.md"
  printf 'gone\n' > "$SEED2/.zz-gone.md"
  git -C "$SEED2" add .0-old.md old.md .zz-gone.md
  git -C "$SEED2" commit -q -m "commit2: add old files"
  git -C "$SEED2" rm -q .0-old.md old.md .zz-gone.md
  git -C "$SEED2" commit -q -m "commit3: delete old files"
  BARE2="$TEST_DIR/bare2.git"
  git clone -q --bare "$SEED2" "$BARE2"
  printf 'gone\n' > "$BARE2/old.md"      # tracked-deleted leftovers: must still be pruned
  printf 'gone\n' > "$BARE2/.0-old.md"
  printf 'gone\n' > "$BARE2/.zz-gone.md"
  cd "$BARE2"
  LC_ALL="$LOC" bash "$SCRIPT" --yes sync-bare-files > "$TEST_DIR/sync3.log" 2>&1 || {
    echo "  WARN: locale sync exited non-zero:"; sed 's/^/    /' "$TEST_DIR/sync3.log"; }
  assert_file_exists "$BARE2/.claude-plugin/marketplace.json" "marketplace.json survives under $LOC"
  assert_file_exists "$BARE2/.gitignore" ".gitignore survives under $LOC"
  assert_file_exists "$BARE2/apps/a.md" "apps/a.md survives under $LOC"
  assert_file_exists "$BARE2/README.md" "README.md survives under $LOC"
  assert_file_not_exists "$BARE2/old.md" "tracked-deleted old.md still pruned under $LOC"
  assert_file_not_exists "$BARE2/.0-old.md" "tracked-deleted .0-old.md still pruned under $LOC"
  assert_file_not_exists "$BARE2/.zz-gone.md" "tracked-deleted .zz-gone.md still pruned under $LOC"
  if grep -q 'not in sorted order' "$TEST_DIR/sync3.log"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: comm reported unsorted input under $LOC"
  else
    PASS=$((PASS + 1)); echo "  PASS: no comm sort-order complaint under $LOC"
  fi
fi
echo ""

print_results
