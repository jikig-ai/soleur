#!/usr/bin/env bash
# 2026-05-14 reproducer: worktree-manager.sh create must succeed when a
# sibling worktree holds main checked out (issue #3741).
#
# Plan: knowledge-base/project/plans/2026-05-14-fix-worktree-create-from-origin-main-plan.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Stand up upstream + local bare clone (mirrors the soleur bare-repo layout) ---
UPSTREAM="$TMP/upstream.git"
git init --bare -b main "$UPSTREAM" >/dev/null
SEED="$TMP/seed"
git clone "$UPSTREAM" "$SEED" >/dev/null 2>&1
( cd "$SEED" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED"

LOCAL="$TMP/local.git"
git init --bare -b main "$LOCAL" >/dev/null
( cd "$LOCAL" && git remote add origin "$UPSTREAM" && git fetch origin main:main >/dev/null 2>&1 )

# Advance upstream so origin/main is ahead of local main
SEED2="$TMP/seed2"
git clone "$UPSTREAM" "$SEED2" >/dev/null 2>&1
( cd "$SEED2" && git -c user.email=t@t -c user.name=t commit --allow-empty -m "upstream-advance" >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED2"

# --- Setup: sibling worktree A holds main checked out (under $LOCAL/.worktrees to
# match the script's WORKTREE_DIR convention; not strictly required for the lock-
# contention test, but mirrors the production layout faithfully). ---
mkdir -p "$LOCAL/.worktrees"
( cd "$LOCAL" && git worktree add "$LOCAL/.worktrees/feat-a" main >/dev/null 2>&1 )

LOCAL_MAIN_BEFORE=$(git -C "$LOCAL" rev-parse refs/heads/main)

# --- AC1: create succeeds when sibling holds main ---
(
  cd "$LOCAL"
  bash "$WM" --yes create feat-bar >/tmp/wt-out.$$ 2>&1
) && pass "AC1: create succeeds with sibling holding main" || fail "AC1: create FAILED (output: $(cat /tmp/wt-out.$$))"

# --- AC2: local main unchanged ---
LOCAL_MAIN_AFTER=$(git -C "$LOCAL" rev-parse refs/heads/main)
[[ "$LOCAL_MAIN_BEFORE" == "$LOCAL_MAIN_AFTER" ]] \
  && pass "AC2: local main SHA unchanged ($LOCAL_MAIN_BEFORE)" \
  || fail "AC2: local main advanced from $LOCAL_MAIN_BEFORE to $LOCAL_MAIN_AFTER (should be unchanged)"

# --- AC3: worktree HEAD == origin/main HEAD ---
WT_HEAD=$(git -C "$LOCAL/.worktrees/feat-bar" rev-parse HEAD 2>/dev/null || echo "MISSING")
ORIGIN_MAIN=$(git -C "$LOCAL" rev-parse refs/remotes/origin/main)
[[ "$WT_HEAD" == "$ORIGIN_MAIN" ]] \
  && pass "AC3: worktree HEAD == origin/main ($WT_HEAD)" \
  || fail "AC3: worktree HEAD ($WT_HEAD) != origin/main ($ORIGIN_MAIN)"

# --- R1 mitigation: --no-track produces empty upstream (same as pre-fix behavior) ---
WT_REMOTE=$(git -C "$LOCAL/.worktrees/feat-bar" config --get branch.feat-bar.remote 2>/dev/null || true)
WT_MERGE=$(git -C "$LOCAL/.worktrees/feat-bar" config --get branch.feat-bar.merge 2>/dev/null || true)
[[ -z "$WT_REMOTE" && -z "$WT_MERGE" ]] \
  && pass "R1: upstream is unset (matches pre-fix behavior; --no-track is in effect)" \
  || fail "R1: branch tracks $WT_REMOTE/$WT_MERGE — should be unset (downstream git push would regress)"

# --- AC6: --update-local-main advances local main ---
# Add yet another upstream commit
SEED3="$TMP/seed3"
git clone "$UPSTREAM" "$SEED3" >/dev/null 2>&1
( cd "$SEED3" && git -c user.email=t@t -c user.name=t commit --allow-empty -m "upstream-advance-2" >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED3"

# Release main lock by removing the sibling worktree (otherwise refspec fetch fails by design)
( cd "$LOCAL" && git worktree remove --force "$LOCAL/.worktrees/feat-a" >/dev/null 2>&1 )

LOCAL_MAIN_BEFORE_UPDATE=$(git -C "$LOCAL" rev-parse refs/heads/main)
(
  cd "$LOCAL"
  bash "$WM" --yes --update-local-main create feat-baz >/tmp/wt-out2.$$ 2>&1
) && pass "AC6a: --update-local-main create succeeded" || fail "AC6a: --update-local-main create failed (output: $(cat /tmp/wt-out2.$$))"

LOCAL_MAIN_AFTER_UPDATE=$(git -C "$LOCAL" rev-parse refs/heads/main)
[[ "$LOCAL_MAIN_AFTER_UPDATE" != "$LOCAL_MAIN_BEFORE_UPDATE" ]] \
  && pass "AC6b: --update-local-main advanced local main" \
  || fail "AC6b: --update-local-main did NOT advance local main"

rm -f /tmp/wt-out.$$ /tmp/wt-out2.$$
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
