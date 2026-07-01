#!/usr/bin/env bash
# 2026-07-01 reproducer: worktree-manager.sh must self-heal a stale git lock
# file left when a git process is killed mid-write (the 2026-07-01 seccomp
# outage class — a residual .git/config.lock wedges every later `git config`
# write with EEXIST forever). Age-guarded sweep: aged locks removed, fresh and
# future-dated locks preserved.
#
# Plan: knowledge-base/project/plans/2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Stand up upstream + local bare clone (mirrors the soleur bare-repo layout,
# same pattern as create-from-origin-main.test.sh) ---
UPSTREAM="$TMP/upstream.git"
git init --bare -b main "$UPSTREAM" >/dev/null
SEED="$TMP/seed"
git clone "$UPSTREAM" "$SEED" >/dev/null 2>&1
( cd "$SEED" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED"

LOCAL="$TMP/local.git"
git init --bare -b main "$LOCAL" >/dev/null
( cd "$LOCAL" && git remote add origin "$UPSTREAM" && git fetch origin main:main >/dev/null 2>&1 )

# For a bare repo, `ensure_bare_config` resolves git_dir == GIT_ROOT (the bare
# dir itself), so the config locks live directly under $LOCAL.
GIT_DIR="$LOCAL"

# --- Source the script to unit-test sweep_stale_git_locks() directly. The
# script's BASH_SOURCE guard (worktree-manager.sh:1490) suppresses main() when
# sourced. The script sets `set -euo pipefail`; disable errexit afterward so the
# harness's && / || assertion style behaves like the sibling tests. ---
cd "$LOCAL"
# shellcheck source=/dev/null
source "$WM"
set +e

# Plant a lock file with a specific mtime. $2 = seconds in the PAST
# (a negative value via the caller means the future — used for the skew guard).
plant() { : > "$GIT_DIR/$1"; touch -d "$2 seconds ago" "$GIT_DIR/$1"; }
present() { [[ -f "$GIT_DIR/$1" ]]; }

# --- AC1: aged config.lock removed ---
plant config.lock 120
sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null
present config.lock \
  && fail "AC1: aged config.lock was NOT removed" \
  || pass "AC1: aged config.lock removed"

# --- AC2: fresh config.worktree.lock preserved ---
: > "$GIT_DIR/config.worktree.lock"   # mtime = now
sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null
present config.worktree.lock \
  && pass "AC2: fresh config.worktree.lock preserved (age < threshold)" \
  || fail "AC2: fresh config.worktree.lock was WRONGLY removed"
rm -f "$GIT_DIR/config.worktree.lock"

# --- AC3: multiple patterns in one run — aged HEAD.lock removed, fresh index.lock kept ---
plant HEAD.lock 120
: > "$GIT_DIR/index.lock"
sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null
if ! present HEAD.lock && present index.lock; then
  pass "AC3: aged HEAD.lock removed AND fresh index.lock preserved"
else
  fail "AC3: mixed-age sweep wrong (HEAD.lock present=$(present HEAD.lock && echo y || echo n), index.lock present=$(present index.lock && echo y || echo n))"
fi
rm -f "$GIT_DIR/index.lock"

# --- AC4: clock-skew guard — future-dated lock preserved (negative age = fresh) ---
: > "$GIT_DIR/config.lock"
touch -d "+120 seconds" "$GIT_DIR/config.lock"
sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null
present config.lock \
  && pass "AC4: future-dated lock preserved (clock-skew guard)" \
  || fail "AC4: future-dated lock was WRONGLY removed"
rm -f "$GIT_DIR/config.lock"

# --- AC6: sweep does not corrupt config — a real git config write still works ---
rm -f "$GIT_DIR"/*.lock 2>/dev/null
sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null
if git config --file "$GIT_DIR/config" test.key val >/dev/null 2>&1 \
   && [[ "$(git config --file "$GIT_DIR/config" test.key 2>/dev/null)" == "val" ]]; then
  pass "AC6: git config write succeeds after sweep (config uncorrupted)"
else
  fail "AC6: git config write FAILED after sweep"
fi
git config --file "$GIT_DIR/config" --unset test.key 2>/dev/null

# --- AC7: no-op is safe under `set -e` (empty lock set + missing dir) ---
rm -f "$GIT_DIR"/*.lock 2>/dev/null
( set -e; sweep_stale_git_locks "$GIT_DIR" 60 >/dev/null ) \
  && pass "AC7a: no-op sweep exits 0 under set -e (empty lock set)" \
  || fail "AC7a: no-op sweep aborted under set -e"
( set -e; sweep_stale_git_locks "$TMP/does-not-exist" 60 >/dev/null ) \
  && pass "AC7b: sweep on missing dir exits 0 under set -e" \
  || fail "AC7b: sweep on missing dir aborted under set -e"

# --- AC5: black-box self-heal wiring — an aged config.lock is swept when
# cleanup-merged (the session-start preamble path) runs through ensure_bare_config ---
: > "$GIT_DIR/config.lock"; touch -d "120 seconds ago" "$GIT_DIR/config.lock"
( cd "$LOCAL" && bash "$WM" --yes cleanup-merged >"$TMP/cm.log" 2>&1 ) || true
present config.lock \
  && fail "AC5: config.lock survived cleanup-merged (ensure_bare_config wiring; log: $(cat "$TMP/cm.log"))" \
  || pass "AC5: aged config.lock swept via cleanup-merged (ensure_bare_config wiring)"

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
