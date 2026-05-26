#!/usr/bin/env bash
# 2026-04-21 reproducer: cleanup_merged_worktrees must NOT reap a worktree
# whose `session-state.sh` lease is still active.
#
# Plan: knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md
# Seed: knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
SS="$REPO_ROOT/.claude/hooks/lib/session-state.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Stand up a fake bare repo with two branches: main + feat-victim. Merge
# feat-victim into main so it qualifies as "merged" for cleanup_merged_worktrees.
# ---------------------------------------------------------------------------
BARE="$TMP/repo.git"
git init --bare -b main "$BARE" >/dev/null

# Seed a commit on main via a temporary clone
SEED="$TMP/seed"
git clone "$BARE" "$SEED" >/dev/null 2>&1
( cd "$SEED"
  git -c user.email=t@t -c user.name=t commit --allow-empty -m "seed" >/dev/null
  git push origin main >/dev/null 2>&1
)
rm -rf "$SEED"

# Create a worktree directory simulating the layout worktree-manager.sh expects.
# We deliberately do NOT call `worktree-manager.sh feature` because that path
# performs network operations (git push -u origin) once Phase 4 wiring lands —
# and we want this test to exercise cleanup independently. Build the worktree
# state manually.
WT_PARENT="$TMP/wt-parent"
mkdir -p "$WT_PARENT/.worktrees"

# Anchor a fake "victim" checkout — the worktree that holds an active lease
# and which a sibling cleanup-merged invocation must NOT reap.
git -C "$BARE" worktree add -b feat-victim "$WT_PARENT/.worktrees/feat-victim" main >/dev/null 2>&1
( cd "$WT_PARENT/.worktrees/feat-victim"
  echo hi > a.txt
  git -c user.email=t@t -c user.name=t add a.txt
  # Date the commit older than the 10-min recent-commit grace so the lease
  # is the ONLY protection — guarantees the test fails if the lease guard
  # is removed (avoids vacuous green via the recent-commit code path).
  GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t commit \
      --date "2025-01-01T00:00:00Z" -m "victim change" >/dev/null
)
# Fast-forward main to the victim commit so `git branch --merged main` lists it.
VICTIM_SHA=$(git -C "$BARE" rev-parse refs/heads/feat-victim)
git -C "$BARE" update-ref refs/heads/main "$VICTIM_SHA"

# Anchor a sibling "actor" worktree — the session that runs cleanup-merged
# concurrently. This is what reproduces 2026-04-21: cleanup runs from
# session A while session B holds the lease on the victim.
git -C "$BARE" worktree add -b feat-actor "$WT_PARENT/.worktrees/feat-actor" main >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Acquire a lease for feat-victim. The lease lives under git-common-dir,
# which for our fake bare repo is $BARE itself.
# ---------------------------------------------------------------------------
LEASE_ROOT="$BARE/soleur-session-state"
mkdir -p "$LEASE_ROOT/leases" "$LEASE_ROOT/locks" "$LEASE_ROOT/logs"

# Hold a real, alive PID for the lease. Background a long sleep.
sleep 300 &
HOLDER_PID=$!
trap 'kill "$HOLDER_PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT

cat > "$LEASE_ROOT/leases/feat-victim.lease" <<EOF
pid=$HOLDER_PID
ppid=$$
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=240
hostname=$HOSTNAME
EOF

# ---------------------------------------------------------------------------
# Invoke worktree-manager.sh cleanup-merged from inside one of the fake
# worktrees. The worktree-manager.sh sources from $REPO_ROOT — that's the
# session-state.sh under test, even though GIT_ROOT will resolve to our
# fake bare repo via git rev-parse.
# ---------------------------------------------------------------------------
WT_VICTIM="$WT_PARENT/.worktrees/feat-victim"
WT_ACTOR="$WT_PARENT/.worktrees/feat-actor"

# Run cleanup-merged from the ACTOR worktree (a sibling). The existing
# "currently active" guard at worktree-manager.sh:795 only skips when PWD
# matches the worktree being considered — so feat-victim is NOT protected
# by that guard from a sibling session. Only the new lease guard protects it.
(
  cd "$WT_ACTOR"
  SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT" \
    bash "$WM" cleanup-merged >/tmp/cleanup-out.$$ 2>&1 || true
)

if [[ -d "$WT_VICTIM" ]]; then
  pass "lease protected feat-victim worktree from sibling reap"
else
  fail "feat-victim worktree was reaped by sibling despite active lease (output: $(cat /tmp/cleanup-out.$$ 2>/dev/null))"
fi
rm -f /tmp/cleanup-out.$$

kill "$HOLDER_PID" 2>/dev/null || true
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
