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
SS="$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh"

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
# SCENARIO 2 (#5454, 2026-08-06): the acquirer has EXITED.
#
# The scenario above holds a live `sleep 300` as the lease pid. That is the one
# shape real usage never has — and it is why this suite was green for months
# while the guard protected nothing.
#
# `acquire_lease` records `pid=$$`, and every documented entry point is a
# short-lived process that exits within milliseconds of writing the file:
#
#     bash <plugin-root>/scripts/lib/session-state.sh acquire_lease <worktree>
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
    fail "worktree reaped despite a valid in-window lease whose acquirer had exited — this is #5454 (output: $(cat /tmp/cleanup2-out.$$ 2>/dev/null))"
  fi
  rm -f /tmp/cleanup2-out.$$
fi

# ---------------------------------------------------------------------------
# SCENARIO 3 (PR #7373, second half): `create` must ACQUIRE a lease.
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
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
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
  # #5454 is that SOLEUR_SKILL_NAME / SOLEUR_EXPECTED_DURATION_MIN were
  # documented on this path and consumed by nobody — so asserting the file
  # exists proves the fix only halfway. Measured: replacing both reads with the
  # literals "unknown"/"240" left the suite fully GREEN without these two.
  if grep -q '^skill=one-shot$' "$LEASE3"; then
    pass "scenario 3: SOLEUR_SKILL_NAME reached the lease (skill=one-shot)"
  else
    fail "scenario 3: lease does not carry skill=one-shot — the env var is not being read \
(got: $(grep '^skill=' "$LEASE3" 2>/dev/null || echo NONE))"
  fi
  if grep -q '^expected_duration_min=137$' "$LEASE3"; then
    pass "scenario 3: SOLEUR_EXPECTED_DURATION_MIN reached the lease (137, a NON-default value)"
  else
    fail "scenario 3: lease does not carry expected_duration_min=137 — the env var is not being read \
(got: $(grep '^expected_duration_min=' "$LEASE3" 2>/dev/null || echo NONE))"
  fi
else
  fail "scenario 3: NO lease written by --yes create — this is the second half (PR #7373) \
(dir: $(ls -A "$LEASE_ROOT3/leases" 2>/dev/null || echo MISSING))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 4 (PR #7373, re-entry arm): `create` on an EXISTING worktree must also
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
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
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
# SCENARIO 5 (PR #7373): the `feature` verb's arms too — BOTH of them.
#
# Parity with create_for_feature is this fix's whole thesis, and half of it was
# unpinned: deleting create_for_feature's early-return acquire left the suite
# fully GREEN, because no fixture exercised `feature|feat` at all.
# ---------------------------------------------------------------------------
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
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
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
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
# SCENARIO 6 (PR #7373, re-pointed by #7408): a name the lease layer cannot key
# on must SAY SO.
#
# _validate_worktree_name rejects anything outside [A-Za-z0-9._-]. Measured
# before this arm: `--yes create feat/probe` exited 0, wrote ZERO leases, and
# emitted nothing an orchestrating agent could see — #5454's exact signature.
#
# RE-POINTED by #7408. This arm used `feat/probe6`, and the premise it rested on
# — "the lease cannot be made to work for that shape here" — is now FALSE:
# #7408 derives the lease key through `_safe_worktree_name`, so `feat/probe6`
# keys as `feat-probe6` and leases cleanly. Left as written, this arm asserted
# that a FIXED bug was still broken, and it went red the moment the fix landed.
#
# The scenario's real subject is the RESIDUAL class: a legal git refname that is
# still unkeyable AFTER slugification. `+` is legal in a refname (`git
# check-ref-format` accepts `feat+probe6`) and is outside the validator's
# character set, so it survives the transform unkeyable — which is exactly the
# class #7408's new `reason=name-not-keyable` discriminator exists to report.
# Asserting the reason= value here also gives that discriminator its only test.
# ---------------------------------------------------------------------------
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
        bash "$WM" --yes create feat+probe6 >"$TMP/create6.log" 2>&1 ); then
  :
fi
if grep -q 'SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED' "$TMP/create6.log"; then
  pass "scenario 6: an unleasable branch name emits the ACQUIRE_FAILED marker"
else
  fail "scenario 6: unleasable name ran UNLEASED and SILENT — no marker on stdout \
(output: $(cat "$TMP/create6.log"))"
fi
if grep -q 'reason=name-not-keyable' "$TMP/create6.log"; then
  pass "scenario 6b: the marker discriminates the residual class (reason=name-not-keyable)"
else
  fail "scenario 6b: marker did not carry reason=name-not-keyable — the #7408 discriminator \
is unreported for a name that survives slugification unkeyable \
(output: $(cat "$TMP/create6.log"))"
fi
# A slash-bearing name, by contrast, must now lease CLEANLY — the #7408 fix.
# Without this the arm above could be satisfied by a transform that does nothing.
if ( cd "$LOCAL3" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT3" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
        bash "$WM" --yes create feat/probe6 >"$TMP/create6c.log" 2>&1 ); then
  :
fi
if grep -q 'SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED' "$TMP/create6c.log"; then
  fail "scenario 6c: a SLASH-bearing branch still failed to lease — #7408's fix is not in effect \
(output: $(cat "$TMP/create6c.log"))"
else
  pass "scenario 6c: a slash-bearing branch leases cleanly under its slug"
fi

# ---------------------------------------------------------------------------
# SCENARIO 7 (PR #7373): `switch|go` must lease too.
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
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
        bash "$WM" --yes switch feat-probe >"$TMP/switch7.log" 2>&1 ); then
  :
fi
if [[ -f "$LEASE3" ]] && grep -q '^pid=' "$LEASE3"; then
  pass "scenario 7: switch acquired a lease — entering a worktree is working in it"
else
  fail "scenario 7: switch wrote NO lease — a switched-into session runs unleased and reapable \
(output: $(cat "$TMP/switch7.log"))"
fi

# ---------------------------------------------------------------------------
# SCENARIO 8 (#7409): the MARKETPLACE-INSTALL layout.
#
# Every scenario above runs `worktree-manager.sh` out of THIS repo, where
# `../../../../..` reaches a tree that happens to contain the lease library. A
# marketplace user has no such tree: the plugin is copied alone into
# ~/.claude/plugins/cache/<mkt>/soleur/<ver>/, so a path walk that leaves the
# plugin root resolves to nothing, the no-op stubs load, and the entire lock and
# lease layer is silently absent for that entire population (#7409).
#
# FIXTURE DISCIPLINE: copy ONLY plugins/soleur. Copying the repo makes this
# vacuous, because the bug *is* the absence of everything outside that
# directory — asserted below as a precondition, not assumed.
# ---------------------------------------------------------------------------
CACHE_ROOT="$TMP/cache/soleur-mkt/soleur/9.9.9"
mkdir -p "$CACHE_ROOT"
cp -r "$REPO_ROOT/plugins/soleur/." "$CACHE_ROOT/" 2>/dev/null
CACHE_WM="$CACHE_ROOT/skills/git-worktree/scripts/worktree-manager.sh"

if [[ -z "$(find "$CACHE_ROOT" -name '.claude' -type d -print -quit 2>/dev/null)" ]]; then
  pass "scenario 8 fixture: the cache tree contains no .claude/ — a real marketplace layout"
else
  fail "scenario 8 fixture: cache tree contains a .claude/ directory — the fixture cannot \
reproduce #7409 and every assertion below would pass vacuously"
fi

# A throwaway repo with an origin remote (create_worktree resolves its base
# through resolve_base_ref, which needs origin/<from>).
UP8="$TMP/up8.git"; git init --bare -b main "$UP8" >/dev/null
S8="$TMP/s8"; git clone "$UP8" "$S8" >/dev/null 2>&1
( cd "$S8" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null \
    && git push origin main >/dev/null 2>&1 )
rm -rf "$S8"
LOCAL8="$TMP/local8.git"; git init --bare -b main "$LOCAL8" >/dev/null
( cd "$LOCAL8" && git remote add origin "$UP8" && git fetch origin main:main >/dev/null 2>&1 )
LEASE_ROOT8="$LOCAL8/soleur-session-state"

# Guarded cd — this suite runs `set -uo pipefail` WITHOUT -e, so an unguarded
# `cd` failure would run `--yes create` against the developer's real repo.
if ( cd "$LOCAL8" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT8" \
        SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
        bash "$CACHE_WM" --yes create feat-cacheprobe >"$TMP/create8.log" 2>&1 ); then
  : # Deliberately NO exit-code assertion: `--yes create` exits 0 in BOTH the
    # broken and the fixed state (_acquire_worktree_lease early-returns 0 when the
    # library is missing, and every call site is `|| true`). The exit code carries
    # no information here; the lease FILE is the only discriminator.
fi

LEASE8="$LEASE_ROOT8/leases/feat-cacheprobe.lease"
if [[ -f "$LEASE8" ]] && grep -q '^pid=' "$LEASE8"; then
  pass "scenario 8: a cache-install worktree-manager.sh resolved the lease library and wrote a lease"
else
  fail "scenario 8: NO lease written from a marketplace-install layout — this is #7409; every \
installed user runs with no lock/lease layer (output: $(cat "$TMP/create8.log" 2>/dev/null))"
fi
# 137, never 240: 240 is the default at BOTH worktree-manager.sh's
# ${SOLEUR_EXPECTED_DURATION_MIN:-240} and session-state.sh's ${3:-240}, so
# asserting it passes whether the env var is read or ignored (the #5454 vacuity
# class). skill=one-shot is discriminating too — the default is `unknown`.
if grep -q '^skill=one-shot$' "$LEASE8" 2>/dev/null; then
  pass "scenario 8: SOLEUR_SKILL_NAME reached the lease from a cache install"
else
  fail "scenario 8: lease does not carry skill=one-shot \
(got: $(grep '^skill=' "$LEASE8" 2>/dev/null || echo NONE))"
fi
if grep -q '^expected_duration_min=137$' "$LEASE8" 2>/dev/null; then
  pass "scenario 8: SOLEUR_EXPECTED_DURATION_MIN reached the lease (137, a NON-default value)"
else
  fail "scenario 8: lease does not carry expected_duration_min=137 \
(got: $(grep '^expected_duration_min=' "$LEASE8" 2>/dev/null || echo NONE))"
fi

# --- Scenario 8b (T2): the mutation arm -----------------------------------
# Delete the library from the cache fixture. Scenario 8 must become
# unsatisfiable — otherwise scenario 8 is passing for some reason other than
# the library resolving, and pins nothing.
CACHE_LIB="$(find "$CACHE_ROOT" -name 'session-state.sh' -print -quit 2>/dev/null)"
if [[ -n "$CACHE_LIB" ]]; then
  mv "$CACHE_LIB" "$CACHE_LIB.disabled"
  if ( cd "$LOCAL8" \
       && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT8" \
          SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=137 \
          bash "$CACHE_WM" --yes create feat-cachemutant >"$TMP/create8b.log" 2>&1 ); then
    :
  fi
  if [[ -f "$LEASE_ROOT8/leases/feat-cachemutant.lease" ]]; then
    fail "scenario 8b (mutation): a lease was written with the library REMOVED — scenario 8 is \
vacuous, it is not measuring library resolution"
  else
    pass "scenario 8b (mutation): removing the library from the cache fixture stops the lease \
being written — scenario 8 is non-vacuous"
  fi
  if grep -q 'SOLEUR_WORKTREE_LEASE_LIB_MISSING' "$TMP/create8b.log"; then
    pass "scenario 8b (mutation): the absence is reported on stdout, not silent"
  else
    fail "scenario 8b (mutation): library absent but NO marker on stdout \
(output: $(cat "$TMP/create8b.log" 2>/dev/null))"
  fi
  mv "$CACHE_LIB.disabled" "$CACHE_LIB"
else
  fail "scenario 8b (mutation): no session-state.sh found anywhere under the cache fixture — \
the library does not ship in the plugin, which is the #7409 defect itself"
fi

# ---------------------------------------------------------------------------
# SCENARIO 9 (#7409, T3): the DESTRUCTIVE direction, in a cache layout.
#
# This PR ARMS THE REAPER for the marketplace population. Pre-fix their library
# is missing, so `is_lease_active(){ return 0; }` makes cleanup-merged refuse to
# reap anything, ever. Post-fix the library resolves and an unrecoverable
# operation — delete the worktree, the local branch, the remote branch, close
# the PR — goes live for them for the first time. Scenarios 8/8b cover
# ACQUISITION; nothing covers REFUSAL from a cache layout. That asymmetry is the
# whole risk profile of this change.
# ---------------------------------------------------------------------------
BARE9="$TMP/repo9.git"; git init --bare -b main "$BARE9" >/dev/null
SEED9="$TMP/seed9"; git clone "$BARE9" "$SEED9" >/dev/null 2>&1
( cd "$SEED9" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null \
    && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED9"
WT9="$TMP/wt9"; mkdir -p "$WT9/.worktrees"
git -C "$BARE9" worktree add -b feat-v9 "$WT9/.worktrees/feat-v9" main >/dev/null 2>&1
( cd "$WT9/.worktrees/feat-v9"
  echo hi9 > c.txt
  git -c user.email=t@t -c user.name=t add c.txt
  # Older than the 10-minute recent-commit grace, so the LEASE is the only thing
  # that can protect it — otherwise this passes via the grace window and proves
  # nothing about lease resolution from a cache install.
  GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t commit \
      --date "2025-01-01T00:00:00Z" -m "v9 change" >/dev/null
)
git -C "$BARE9" update-ref refs/heads/main "$(git -C "$BARE9" rev-parse refs/heads/feat-v9)"
git -C "$BARE9" worktree add -b feat-a9 "$WT9/.worktrees/feat-a9" main >/dev/null 2>&1

LEASE_ROOT9="$BARE9/soleur-session-state"
mkdir -p "$LEASE_ROOT9/leases"
cat > "$LEASE_ROOT9/leases/feat-v9.lease" <<EOF
pid=$$
ppid=$$
skill=one-shot
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expected_duration_min=137
hostname=$HOSTNAME
EOF

if ( cd "$WT9/.worktrees/feat-a9" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT9" \
        bash "$CACHE_WM" cleanup-merged >"$TMP/cleanup9.log" 2>&1 ); then
  :
fi
if [[ -d "$WT9/.worktrees/feat-v9" ]]; then
  pass "scenario 9: from a CACHE install, the reaper refused to reap a leased worktree"
else
  fail "scenario 9: a cache-install cleanup-merged REAPED a leased worktree — this PR arms an \
unrecoverable operation for every marketplace user (output: $(cat "$TMP/cleanup9.log" 2>/dev/null))"
fi

# Mutation arm: clear the lease and the SAME victim must now be reaped. Without
# this, scenario 9 is satisfied by cleanup-merged doing nothing for any reason at
# all — an early return, a lock it could not take, a fail-closed stub.
rm -f "$LEASE_ROOT9/leases/feat-v9.lease"
if ( cd "$WT9/.worktrees/feat-a9" \
     && SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT9" \
        bash "$CACHE_WM" cleanup-merged >"$TMP/cleanup9b.log" 2>&1 ); then
  :
fi
if [[ -d "$WT9/.worktrees/feat-v9" ]]; then
  fail "scenario 9b (mutation): the victim survived with NO lease — scenario 9 is vacuous, the \
reaper is not reaping for some unrelated reason (output: $(cat "$TMP/cleanup9b.log" 2>/dev/null))"
else
  pass "scenario 9b (mutation): with the lease cleared the victim IS reaped — scenario 9's \
refusal is attributable to the lease, not to an inert reaper"
fi

# ---------------------------------------------------------------------------
# SCENARIO 10 (#7409, T3b): the SKILL.md anchor hop.
#
# Every other scenario in this file invokes worktree-manager.sh by absolute path
# inside a fixture. A marketplace user never does that — their agent executes the
# `${CLAUDE_PLUGIN_ROOT:-…}` form written in SKILL.md. That hop is the link the
# whole fix has to traverse, and nothing tested it: the suite could be fully
# green while delivering nothing to the population #7409 is about.
# ---------------------------------------------------------------------------
NONSOLEUR="$TMP/not-soleur"; mkdir -p "$NONSOLEUR"
git init -b main "$NONSOLEUR" >/dev/null 2>&1
( cd "$NONSOLEUR" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null 2>&1 )
if [[ ! -e "$NONSOLEUR/plugins/soleur" ]]; then
  pass "scenario 10 fixture: cwd is a non-Soleur repo (no ./plugins/soleur to fall back to)"
else
  fail "scenario 10 fixture: cwd contains ./plugins/soleur — the anchor's default arm would \
resolve and the hop under test is bypassed"
fi
# `export` on its own line, NOT a `CLAUDE_PLUGIN_ROOT=… bash "${CLAUDE_PLUGIN_ROOT:-…}"`
# prefix assignment: a command-prefix assignment populates the COMMAND's
# environment, but every expansion on that same command line is performed first,
# against the current shell — so the anchor would take its DEFAULT arm and this
# scenario would silently test `./plugins/soleur` from a directory that has none.
# Measured: written that way, the run failed with `bash: ./plugins/…: No such
# file or directory`, and the negative assertion below still reported `pass`.
if ( cd "$NONSOLEUR" \
     && export CLAUDE_PLUGIN_ROOT="$CACHE_ROOT" \
     && bash "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh" \
        list >"$TMP/anchor10.log" 2>&1 ); then
  :
fi
# The anchor must have resolved to a REAL script. Without this, every assertion
# below is satisfied by the interpreter failing to find the file at all — which
# is precisely how the fixture bug above stayed invisible.
if grep -q 'No such file or directory' "$TMP/anchor10.log"; then
  fail "scenario 10 precondition: the anchor did not resolve to a script — assertions below \
cannot discriminate (output: $(cat "$TMP/anchor10.log" 2>/dev/null))"
else
  pass "scenario 10 precondition: the anchor resolved to a real script"
fi
if grep -q 'SOLEUR_WORKTREE_LEASE_LIB_OK' "$TMP/anchor10.log"; then
  pass "scenario 10: reached through the SKILL.md anchor form, the library resolves (\
..._LIB_OK on stdout)"
else
  fail "scenario 10: through the SKILL.md anchor form from a non-Soleur cwd the library did NOT \
resolve — the hop a marketplace user actually traverses is broken \
(output: $(cat "$TMP/anchor10.log" 2>/dev/null))"
fi
if grep -q 'SOLEUR_WORKTREE_LEASE_LIB_MISSING' "$TMP/anchor10.log"; then
  fail "scenario 10: the MISSING marker was emitted through the anchor hop"
else
  pass "scenario 10: no MISSING marker through the anchor hop"
fi

# ---------------------------------------------------------------------------
# SCENARIO 11 (#7409, T6): OLD-tree / NEW-tree interoperation.
#
# During rollout, one worktree on disk predates the move and sources the library
# from .claude/hooks/lib/, while a sibling sources it from the plugin. Both
# anchor their lease store to `git rev-parse --git-common-dir`, so they share one
# set of lease files. If the two copies disagreed about the lease FORMAT, a new
# worktree would read an old worktree's lease as absent and reap it.
#
# AC10's byte-identity check proves the file is unchanged; it does NOT prove
# interop, which is the property the rollout actually depends on. This arm runs
# the ORIGIN/MAIN copy (genuinely old code) against the post-move copy.
# ---------------------------------------------------------------------------
# The pre-move path is DERIVED from origin/main's tree, never hard-coded. Two
# reasons, both load-bearing: (a) AC6 asserts no `.claude/hooks/lib/
# session-state.sh` literal survives anywhere under plugins/soleur/skills/, and a
# fixture that spelled it out would turn that AC red for a correct tree; (b) a
# derived path cannot silently rot into testing nothing once the old file is gone
# from main — the lookup returns empty and the assertion below fails loudly.
# `ls-tree` is exact, unlike rename detection, which is a diff-renderer heuristic.
OLD_REL="$(git -C "$REPO_ROOT" ls-tree -r --name-only origin/main 2>/dev/null \
  | grep -E 'hooks/lib/session-state\.sh$' | head -1)"
OLD_LIB="$TMP/oldtree/legacy-session-state.sh"
mkdir -p "$(dirname "$OLD_LIB")"
if [[ -n "$OLD_REL" ]] \
   && git -C "$REPO_ROOT" show "origin/main:$OLD_REL" > "$OLD_LIB" 2>/dev/null \
   && [[ -s "$OLD_LIB" ]]; then
  pass "scenario 11 fixture: recovered the pre-move library from origin/main ($OLD_REL)"
else
  fail "scenario 11 fixture: could not recover the pre-move session-state library from \
origin/main (resolved path: ${OLD_REL:-NONE}) — cannot test old/new interop"
fi
NEW_LIB="$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh"
SHARED11="$TMP/shared11"; mkdir -p "$SHARED11/leases"
# OLD code acquires...
bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$SHARED11'
  # shellcheck source=/dev/null
  source '$OLD_LIB'
  acquire_lease feat-interop one-shot 137
" >/dev/null 2>&1
if [[ -f "$SHARED11/leases/feat-interop.lease" ]]; then
  pass "scenario 11: the pre-move library wrote a lease into the shared store"
else
  fail "scenario 11: the pre-move library wrote no lease — fixture cannot discriminate"
fi
# ...and NEW code must honour it. `is_lease_active` is only trustworthy here
# because NEW_LIB genuinely exists: when it does not, worktree-manager.sh's
# fail-closed STUB also returns 0, so this would pass vacuously against the exact
# bug. Guard on the file, then call the real function.
if [[ -f "$NEW_LIB" ]] && bash -c "
  export SOLEUR_SESSION_STATE_ROOT='$SHARED11'
  # shellcheck source=/dev/null
  source '$NEW_LIB'
  is_lease_active feat-interop
" >/dev/null 2>&1; then
  pass "scenario 11: the post-move library honours a lease written by the pre-move library"
else
  fail "scenario 11: the post-move library does NOT honour a pre-move lease — a mid-rollout \
worktree would be reaped by a sibling (new lib present: $([[ -f "$NEW_LIB" ]] && echo yes || echo NO))"
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
MIN_ASSERTIONS=32  # 3 -> 6 -> 9 -> 15 -> 17 (PR #7373 sc. 3-7) -> 32 (#7409 sc. 8-11)
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
