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

# ---------------------------------------------------------------------------
# SCENARIO 2 (#7278, 2026-08-06): the acquirer has EXITED.
#
# The scenario above holds a live `sleep 300` as the lease pid. That is the one
# shape real usage never has — and it is why this suite was green for months
# while the guard protected nothing.
#
# `acquire_lease` records `pid=$$`, and every documented entry point is a
# short-lived process that exits within milliseconds of writing the file:
#
#     bash .claude/hooks/lib/session-state.sh acquire_lease <worktree>
#     bash .../worktree-manager.sh --yes create <branch>
#
# So in production the lease pid is ALWAYS dead moments after acquisition.
# `is_lease_active` gated on `kill -0`, `sweep_orphan_leases` deleted the file
# on a dead pid, and cleanup-merged consequently reaped the worktree, deleted
# the branch locally AND on origin, and closed the PR — twice in one afternoon,
# mid-run, on a leased worktree with hours of duration remaining.
#
# A fixture that instantiates only the passing member of a set is a sample, not
# a proof. This arm instantiates the member that actually occurs.
# ---------------------------------------------------------------------------
git -C "$BARE" worktree add -b feat-victim2 "$WT_PARENT/.worktrees/feat-victim2" main >/dev/null 2>&1
WT_VICTIM2="$WT_PARENT/.worktrees/feat-victim2"
( cd "$WT_VICTIM2"
  echo hi2 > b.txt
  git -c user.email=t@t -c user.name=t add b.txt
  # Older than the 10-minute recent-commit grace, so the LEASE is the only
  # thing that can protect it — otherwise this passes via the grace window and
  # proves nothing about the lease.
  GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t commit \
      --date "2025-01-01T00:00:00Z" -m "victim2 change" >/dev/null
)
VICTIM2_SHA=$(git -C "$BARE" rev-parse refs/heads/feat-victim2)
git -C "$BARE" update-ref refs/heads/main "$VICTIM2_SHA"

# Acquire through the REAL entry point in a child process, then let it exit —
# reproducing production rather than simulating it.
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$LEASE_ROOT'
  # shellcheck source=/dev/null
  source '$SS'
  acquire_lease feat-victim2 one-shot 240
" >/dev/null 2>&1

DEAD_PID=$(grep '^pid=' "$LEASE_ROOT/leases/feat-victim2.lease" 2>/dev/null | cut -d= -f2)
if [[ -z "$DEAD_PID" ]]; then
  fail "scenario 2 setup: no lease file written for feat-victim2"
elif kill -0 "$DEAD_PID" 2>/dev/null; then
  # Asserted, not assumed: a live pid here would exercise scenario 1 again and
  # pass vacuously against the very defect this arm exists to pin.
  fail "scenario 2 precondition: recorded pid $DEAD_PID is still alive — cannot reach the dead-acquirer path"
else
  pass "scenario 2 precondition: the acquiring process has exited (pid $DEAD_PID is dead)"
  (
    cd "$WT_ACTOR"
    SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT" \
      bash "$WM" cleanup-merged >/tmp/cleanup2-out.$$ 2>&1 || true
  )
  if [[ -d "$WT_VICTIM2" ]]; then
    pass "a lease whose acquirer exited STILL protects the worktree from a sibling reap"
  else
    fail "worktree reaped despite a valid in-window lease whose acquirer had exited — this is #7278 (output: $(cat /tmp/cleanup2-out.$$ 2>/dev/null))"
  fi
  rm -f /tmp/cleanup2-out.$$
fi

# ---------------------------------------------------------------------------
# SCENARIO 3 (#7278 second half): `create` must ACQUIRE a lease.
#
# Scenarios 1-2 prove a lease PROTECTS a worktree. Neither proves one is ever
# WRITTEN by the entry point the autonomous pipeline actually calls. It was not:
# `create_worktree` (dispatched from `create`) had zero acquire_lease calls,
# while `create_for_feature` (dispatched from `feature|feat`) had one. one-shot
# Step 0b and work Phase 1 both invoke `--yes create`, so every worktree the
# pipeline made carried no lease at all — and the documented SOLEUR_SKILL_NAME /
# SOLEUR_EXPECTED_DURATION_MIN env vars were read by nobody on that path.
#
# A lease layer that protects but is never acquired protects nothing. The header
# on scenario 2 ("a fixture that instantiates only the passing member of a set is
# a sample, not a proof") applied to this file itself until this arm landed.
#
# Fixture note: `create_worktree` resolves its base through `resolve_base_ref`,
# which needs origin/<from> — so this arm needs a local bare repo WITH an origin
# remote, not the bare-repo-only shape scenarios 1 and 2 use.
# ---------------------------------------------------------------------------
UP3="$TMP/up3.git"; git init --bare -b main "$UP3" >/dev/null
S3="$TMP/s3"; git clone "$UP3" "$S3" >/dev/null 2>&1
( cd "$S3" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null \
    && git push origin main >/dev/null 2>&1 )
rm -rf "$S3"
LOCAL3="$TMP/local3.git"; git init --bare -b main "$LOCAL3" >/dev/null
( cd "$LOCAL3" && git remote add origin "$UP3" && git fetch origin main:main >/dev/null 2>&1 )

LEASE_ROOT3="$LOCAL3/soleur-session-state"
# `if ( cd … && … )` rather than `&& pass || fail` (SC2015) or a bare `cd`
# (SC2164). The guarded cd is load-bearing, not style: this suite runs
# `set -uo pipefail` WITHOUT -e, so an unguarded `cd "$LOCAL3"` that fails would
# let the subshell continue and run `--yes create` against the DEVELOPER'S REAL
# REPO, creating a real worktree, branch and lease.
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes create feat-probe >"$TMP/create3.log" 2>&1 ); then
  pass "scenario 3: --yes create exited 0"
else
  fail "scenario 3: --yes create failed (output: $(cat "$TMP/create3.log"))"
fi

LEASE3="$LEASE_ROOT3/leases/feat-probe.lease"
# Assert the FILE, never the directory: session-state.sh mkdir -p's leases/ at
# source time regardless of whether anything is written, so a `[[ -d ]]` check
# false-passes against the bug (measured during plan deepening).
if [[ -f "$LEASE3" ]]; then
  pass "scenario 3: --yes create wrote $LEASE3"
  # The no-op stubs worktree-manager.sh installs when session-state.sh is absent
  # return 0 and write nothing, which would satisfy an exit-0 check; a `pid=`
  # line can only come from a real acquire_lease.
  if grep -q '^pid=' "$LEASE3"; then
    pass "scenario 3: lease carries a pid= line (real acquire_lease, not a stub)"
  else
    fail "scenario 3: lease file exists but has no pid= line"
  fi
  # The env vars must be READ, not merely set by this test. Half the point of
  # #7278 is that SOLEUR_SKILL_NAME / SOLEUR_EXPECTED_DURATION_MIN were
  # documented on this path and consumed by nobody — so asserting the file
  # exists proves the fix only halfway. Measured: replacing both reads with the
  # literals "unknown"/"240" left the suite fully GREEN without these two.
  if grep -q '^skill=one-shot$' "$LEASE3"; then
    pass "scenario 3: SOLEUR_SKILL_NAME reached the lease (skill=one-shot)"
  else
    fail "scenario 3: lease does not carry skill=one-shot — the env var is not being read \
(got: $(grep '^skill=' "$LEASE3" 2>/dev/null || echo NONE))"
  fi
  if grep -q '^expected_duration_min=240$' "$LEASE3"; then
    pass "scenario 3: SOLEUR_EXPECTED_DURATION_MIN reached the lease (240)"
  else
    fail "scenario 3: lease does not carry expected_duration_min=240 — the env var is not being read \
(got: $(grep '^expected_duration_min=' "$LEASE3" 2>/dev/null || echo NONE))"
  fi
else
  fail "scenario 3: NO lease written by --yes create — this is the #7278 second half \
(dir: $(ls -A "$LEASE_ROOT3/leases" 2>/dev/null || echo MISSING))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 4 (#7278, re-entry arm): `create` on an EXISTING worktree must also
# acquire.
#
# Scenario 3 covers fresh creation. But both creating functions have an early
# return for "worktree already exists" that skips the whole tail of the
# function — including the lease block. `--yes create` sets response=y there,
# so a RESUMED one-shot/work run takes exactly this path and, without the fix,
# holds no lease for its entire duration while a sibling cleanup-merged is free
# to reap it.
#
# The lease belongs to "worked in", not to "created". This arm pins that.
# ---------------------------------------------------------------------------
rm -f "$LEASE3"
# ASSERT the setup landed. This `rm` carries the entire discriminating power of
# scenario 4 — it reuses scenario 3's repo, lease root AND branch name, so if the
# removal silently stops happening the arm reads scenario 3's lease and reports
# "re-entry re-acquired" while the re-entry acquire is absent. Measured: with the
# rm neutered and the re-entry block deleted, the suite went fully GREEN.
if [[ ! -f "$LEASE3" ]]; then
  pass "scenario 4 fixture: scenario 3's lease was removed before the re-entry run"
else
  fail "scenario 4 fixture: lease still present after rm — the arm cannot discriminate"
fi

if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes create feat-probe >"$TMP/create4.log" 2>&1 ); then
  pass "scenario 4: --yes create on an existing worktree exited 0"
else
  fail "scenario 4: re-entry create failed (output: $(cat "$TMP/create4.log"))"
fi

# Prove we actually took the early-return path rather than re-creating, else
# this arm silently duplicates scenario 3 and pins nothing new.
#
# Anchored on create_worktree's OWN literal, not the bare token 'already exists'
# (cq-assert-anchor-not-bare-token). git itself prints "fatal: a branch named
# 'feat-probe' already exists" when the fresh-create path runs, and copy_env_files
# prints "$env_file already exists, backing up" — so the bare token passes on the
# exact path this assertion exists to exclude. Measured: forcing the fresh-create
# path made the bare-token form emit a false `pass:`.
# The negative half is what pins the direction: the fresh-create banner must be ABSENT.
if grep -q 'Worktree already exists at:' "$TMP/create4.log" \
   && ! grep -q 'Creating worktree from' "$TMP/create4.log"; then
  pass "scenario 4 precondition: took the worktree-already-exists early return"
else
  fail "scenario 4 precondition: did NOT take the early return (output: $(cat "$TMP/create4.log"))"
fi

if [[ -f "$LEASE3" ]] && grep -q '^pid=' "$LEASE3"; then
  pass "scenario 4: re-entry re-acquired the lease — a resumed session is protected"
else
  fail "scenario 4: NO lease written on re-entry — a resumed session runs unleased and reapable \
(dir: $(ls -A "$LEASE_ROOT3/leases" 2>/dev/null || echo MISSING))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 5 (#7278): the `feature` verb's arms too — BOTH of them.
#
# Parity with create_for_feature is this fix's whole thesis, and half of it was
# unpinned: deleting create_for_feature's early-return acquire left the suite
# fully GREEN, because no fixture exercised `feature|feat` at all.
# ---------------------------------------------------------------------------
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes feature probe5 >"$TMP/feature5.log" 2>&1 ); then
  : # exit status is asserted via the lease below; a push to the fixture origin
    # can legitimately warn without meaning the lease failed
fi
LEASE5="$LEASE_ROOT3/leases/feat-probe5.lease"
if [[ -f "$LEASE5" ]] && grep -q '^pid=' "$LEASE5"; then
  pass "scenario 5: feature (fresh) acquired a lease"
else
  fail "scenario 5: feature (fresh) wrote NO lease \
(dir: $(ls -A "$LEASE_ROOT3/leases" 2>/dev/null || echo MISSING))"
fi

rm -f "$LEASE5"
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes feature probe5 >"$TMP/feature5b.log" 2>&1 ); then
  :
fi
if [[ -f "$LEASE5" ]] && grep -q '^pid=' "$LEASE5"; then
  pass "scenario 5: feature (re-entry) re-acquired a lease"
else
  fail "scenario 5: feature (re-entry) wrote NO lease — a resumed feature session is reapable \
(output: $(cat "$TMP/feature5b.log"))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 6 (#7278): a name the lease layer cannot key on must SAY SO.
#
# _validate_worktree_name rejects anything outside [A-Za-z0-9._-], so a
# slash-bearing branch makes acquire_lease fail. Measured before this arm:
# `--yes create feat/probe` exited 0, wrote ZERO leases, and emitted nothing an
# orchestrating agent could see — #7278's exact signature, on the path this fix
# exists to protect. The lease cannot be made to work for that shape here (the
# key/reader mismatch is a separate design decision), so what is pinned is that
# the failure is no longer SILENT.
# ---------------------------------------------------------------------------
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes create feat/probe6 >"$TMP/create6.log" 2>&1 ); then
  :
fi
if grep -q 'SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED' "$TMP/create6.log"; then
  pass "scenario 6: an unleasable branch name emits the ACQUIRE_FAILED marker"
else
  fail "scenario 6: unleasable name ran UNLEASED and SILENT — no marker on stdout \
(output: $(cat "$TMP/create6.log"))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 7 (#7278): `switch|go` must lease too.
#
# The last entry point that took an EXISTING worktree and leased nothing. A
# session that switches in and works for hours held no lease for any of them,
# which is the same hole the two early-return arms had — `switch_worktree` just
# lives in a different function, so fixing the arms did not reach it.
#
# Reuses scenario 3's worktree: delete the lease, switch in, assert it returns.
# ---------------------------------------------------------------------------
rm -f "$LEASE3"
if [[ ! -f "$LEASE3" ]]; then
  pass "scenario 7 fixture: lease removed before the switch"
else
  fail "scenario 7 fixture: lease still present after rm — the arm cannot discriminate"
fi

if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
        bash "$WM" --yes switch feat-probe >"$TMP/switch7.log" 2>&1 ); then
  :
fi
if [[ -f "$LEASE3" ]] && grep -q '^pid=' "$LEASE3"; then
  pass "scenario 7: switch acquired a lease — entering a worktree is working in it"
else
  fail "scenario 7: switch wrote NO lease — a switched-into session runs unleased and reapable \
(output: $(cat "$TMP/switch7.log"))"
fi

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

# ANTI-VACUITY FLOOR — same reasoning as session-state.test.sh. `FAIL -eq 0` is
# a pure zero-check, so a run that asserts NOTHING exits 0. That is not
# hypothetical here: both scenarios assert worktree SURVIVAL, which is satisfied
# whenever cleanup-merged does nothing for any reason at all — an early `return`
# on the fetch-prune path, a non-zero sweep aborting under `set -e`, a lock it
# could not take. A floor cannot detect a no-op reap loop by itself, but it does
# catch the case where the assertions were never reached.
MIN_ASSERTIONS=17  # 3 -> 6 -> 9 -> 15 -> 17 (#7278 scenarios 3-7)
# Count DISPATCHES (PASS + FAIL), not wins. Counting PASS alone conflates two
# different things: "the suite did not run" and "the suite ran and found bugs".
# It printed "only N assertions ran — the suite did not execute what it claims
# to cover" on every genuine regression, which is false and misdirects whoever
# reads the failure. It also let a miswired `fail()` (one that increments PASS)
# slip through whenever the defect happened to produce the expected dispatch
# count. Matches scripts/lint-diagnosis-claims.test.sh and
# scripts/lint-workflow-step-env-refs.test.sh, which both count PASS + FAIL.
if [[ $(( PASS + FAIL )) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $(( PASS + FAIL )) assertions ran, expected >= $MIN_ASSERTIONS — the suite did not execute what it claims to cover."
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
