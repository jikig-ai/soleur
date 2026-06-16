#!/usr/bin/env bash
# Concierge repo-readiness gate (fix-concierge-repo-readiness-gate):
# worktree-manager.sh must FAIL LOUD when invoked in a workspace that has no git
# repository at all (the Concierge cloud env when a connected repo's clone is
# still in flight, or its self-heal clone failed). Previously the `create` path
# died silently under `set -e` on `git rev-parse --show-toplevel`, so the
# skill (go/one-shot) saw no clear signal and the agent improvised ~40 varied
# exploration commands (evading the narrow cd-&&-pwd-loop runtime detector from
# #5313) before the session hung. The fix emits a distinct `NO_GIT_REPOSITORY`
# marker + non-zero exit so the skill can stop with an honest, no-wait message.
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/no-repo-fail-loud.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A workspace dir that is NOT a git repo (no `.git`) — mirrors a Concierge
# /workspaces/<id> whose clone never landed. GIT_CEILING_DIRECTORIES stops git
# from discovering an ancestor repo (e.g. the soleur checkout hosting this test).
NOREPO="$TMP/workspace"
mkdir -p "$NOREPO"
export GIT_CEILING_DIRECTORIES="$TMP"

# --- AC1: `create` exits non-zero in a repo-less workspace ---
(
  cd "$NOREPO"
  bash "$WM" --yes create feat-x
) >"$TMP/out.log" 2>&1
RC=$?
[[ "$RC" -ne 0 ]] \
  && pass "AC1: create exits non-zero in a repo-less workspace (rc=$RC)" \
  || fail "AC1: create exited 0 in a repo-less workspace (should fail loud)"

# --- AC2: output carries the machine-detectable NO_GIT_REPOSITORY marker ---
grep -q "NO_GIT_REPOSITORY" "$TMP/out.log" \
  && pass "AC2: output contains NO_GIT_REPOSITORY marker" \
  || fail "AC2: output missing NO_GIT_REPOSITORY marker (got: $(cat "$TMP/out.log"))"

# --- AC3: it does NOT die with the raw, opaque git error under set -e ---
grep -qi "not a git repository\|must be run in a work tree" "$TMP/out.log" \
  && fail "AC3: leaked raw git error instead of the honest marker (got: $(cat "$TMP/out.log"))" \
  || pass "AC3: no raw/opaque git error leaked"

# --- AC4: a real bare-repo workspace still works (guard is not over-broad) ---
BARE="$TMP/local.git"
git init --bare -b main "$BARE" >/dev/null
SEED="$TMP/seed"
git clone "$BARE" "$SEED" >/dev/null 2>&1
( cd "$SEED" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED"
(
  cd "$BARE"
  bash "$WM" --yes create feat-ok
) >"$TMP/out.ok.log" 2>&1 \
  && pass "AC4: create still succeeds in a valid bare repo" \
  || fail "AC4: create regressed in a valid bare repo (output: $(cat "$TMP/out.ok.log"))"

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
