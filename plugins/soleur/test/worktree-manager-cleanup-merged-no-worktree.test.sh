#!/usr/bin/env bash
# #8400 — `cleanup_merged_worktrees` must evaluate the session-lease decision and the
# commit-age decision for EVERY stale branch, whether or not that branch has a worktree;
# and the main-checkout `reset --hard HEAD` must run only after the checkout has been
# established to be on `main`/`master`.
#
# The defect this characterizes, reproduced live on 2026-09-20 before any fix: a branch
# merged into `main` with NO worktree reaches `git push origin --delete` AND `git branch -D`
# with `reaper-armed` already stamped, because all five per-branch guards downstream of
# `all_stale_branches` are gated on a non-empty worktree path.
#
# HARNESS ATTRIBUTION (plan review B6 requires saying which harness contributes what, since
# this is a separate file rather than scenarios appended to lease-protects-active.test.sh):
#   * the reap fixture, the `SOLEUR_SESSION_STATE_ROOT` scratch root and the `reaper-armed`
#     PRE-STAMP come from plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh;
#   * the `diff`-confirmed mutant-copy technique (`build_mutant`, per-mutation landing
#     assertions, `bash -n` on the mutant) comes from
#     plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh.
# It is a separate file because the mutant arms need a pristine per-arm fixture and adding
# ~500 lines to a 1015-line suite would make neither legible.
#
# WHY THE PRE-STAMP IS LOAD-BEARING, not hygiene: `cleanup_merged_worktrees` holds EVERY
# branch on the first armed run per session-state root. Without `: > "$ROOT/reaper-armed"`
# the arms below pass because nothing is ever reaped — including the must-PASS arms, whose
# whole job is to prove the fix did not degrade into a blanket refusal — and mutants M1/M2
# could not go RED. A fixture that cannot fail is the defect class this suite exists for.
#
# The destructive calls are observed by their EFFECTS on a synthesized repo rather than by
# PATH-stubbing `git`: the effect is what #8400 asks about ("which of the three destructive
# calls does it reach"), and a `git` stub broad enough to record them would also have to
# reimplement every read the reaper makes before reaching them.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh

set -uo pipefail

# Git-location tripwire (#7833), same reasoning as lease-protects-active.test.sh: this suite
# drives worktree-manager.sh, which runs `git worktree remove`, `git branch -D`,
# `git push origin --delete` and `git reset --hard`. An inherited GIT_DIR aims all of them at
# the developer's real repository.
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
          GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH; do
  if [[ -n "${!_v:-}" && "${SOLEUR_GIT_TRIPWIRE_ALLOW:-0}" != "1" ]]; then
    printf 'FATAL: %s started with an inherited git-location environment (%s=%s).\n' \
      "${BASH_SOURCE[0]}" "$_v" "${!_v}" >&2
    printf 'Fix the ENTRY POINT: unset %s && <runner>\n' "$_v" >&2
    exit 97
  fi
done
unset _v

# A DIRECT invocation of this suite inherits the bare /tmp, which is a machine-global
# 4 GiB tmpfs shared by every parallel worktree; test-all.sh and run-registered-suites.sh
# default this to /var/tmp and a direct run is the documented inner loop while editing the
# thing under test.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
[[ -f "$SCRIPT" ]] || { printf 'FATAL: worktree-manager.sh not found at %s\n' "$SCRIPT" >&2; exit 2; }

PASS=0; FAIL=0
ASSERTED=0
declare -a FAILURES=()
# The case counter increments at the CALL SITE, never inside `$( )` — a command substitution
# is a subshell and the increment would never reach the parent (AP-023 mechanics, plan L1).
pass() { ASSERTED=$((ASSERTED+1)); PASS=$((PASS+1)); printf '  pass: %s\n' "$1"; }
fail() { ASSERTED=$((ASSERTED+1)); FAIL=$((FAIL+1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)" || {
  printf 'FATAL: mktemp -d failed — refusing to run with an empty $TMP, every fixture path would resolve against /\n' >&2
  exit 2
}
trap 'rm -rf "$TMP"' EXIT

# Canonical guard, copied byte-for-byte (plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts every inline copy is byte-equal to this body; an inline `case` of my own is NOT
# recognised by fixture-scan.py's `_rel_guarded`).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMP"

# --- mutant construction (safe-branch-sanitization.test.sh's technique) ---------------------
MUT_DIR="$TMP/mutants"
mkdir -p "$MUT_DIR" || { printf 'FATAL: cannot create mutant dir\n' >&2; exit 2; }

# M1 — restore the `[[ -n "$worktree_path" ]] &&` conjunct on the lease check, i.e. revert
# exactly the Phase 1 step 2 edit.
restore_lease_path_conjunct() {
  perl -0pi -e 's/# SOLEUR-GUARD-LEASE-START.*?# SOLEUR-GUARD-LEASE-END/if [[ -n "\$worktree_path" ]] \&\& is_lease_active "\$(basename "\$worktree_path")"; then/ms' "$1"
}
# M2 — the pre-#5454 fail-open: no lease is ever active.
#
# `is_lease_active` is defined in session-state.sh, which worktree-manager.sh SOURCES, so
# there is no definition in the SUT to rewrite (the only inline one is the _SS_LIB_MISSING
# stub, which this fixture never reaches — its lease library resolves). The override is
# therefore INSERTED into the copy immediately above `cleanup_merged_worktrees()`, after the
# source has run: the last definition in effect at call time wins.
neuter_is_lease_active() {
  perl -0pi -e 's/^cleanup_merged_worktrees\(\) \{/is_lease_active() {\n  return 1\n}\ncleanup_merged_worktrees() {/ms' "$1"
}
# M3 — restore the PRE-#8400 ORDERING: an unconditional dirty-check + `reset --hard`, with
# the `current_branch` read moved back BELOW it.
#
# This REORDERS rather than deletes, and the distinction is the whole point. Deleting the
# reset would make the uncommitted file survive trivially — the arm would report the mutant
# killed while proving nothing about ordering, which is exactly the vacuity Guard 1 row 5
# names. The replacement below is the shape that shipped before this PR.
unhoist_main_branch_check() {
  perl -0pi -e 's/# SOLEUR-GUARD-MAINRESET-START.*?# SOLEUR-GUARD-MAINRESET-END/if ! git -C "\$GIT_ROOT" diff --quiet HEAD 2>\/dev\/null || ! git -C "\$GIT_ROOT" diff --cached --quiet 2>\/dev\/null; then\n        git -C "\$GIT_ROOT" reset --hard HEAD >\/dev\/null 2>\&1\n      fi\n      local current_branch\n      current_branch=\$(git -C "\$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>\/dev\/null || true)/ms' "$1"
}

# The mutant must sit at the SAME DEPTH as the shipped script, with a resolvable
# `scripts/lib/` beside it. `worktree-manager.sh` computes
# `_SS_LIB="$SCRIPT_DIR/../../../scripts/lib/session-state.sh"`, so a mutant dropped in a
# flat directory cannot find the lease library, `_SS_LIB_MISSING` goes true, and the
# fail-closed `is_lease_active() { return 0; }` stub holds EVERY branch. Measured: every
# mutant then reaps nothing. M1 and M2 still reported "killed" — for the wrong reason, via
# the stub rather than via the mutation — and M3 could not be killed at all, because its
# assertion depends on the post-loop summary block, which is reached only when something
# was actually cleaned. A harness that silently disables the SUT's lease layer is measuring
# a different program than the one it names.
mutant_root() {
  local name="$1"
  printf '%s' "$MUT_DIR/$name/skills/git-worktree/scripts"
}
build_mutant() {
  local name="$1"; shift
  local dir; dir="$(mutant_root "$name")"
  local out="$dir/worktree-manager.sh"
  assert_fixture_dir "$dir"
  mkdir -p "$dir" "$MUT_DIR/$name/scripts" || { printf 'FATAL: mkdir failed for %s\n' "$name" >&2; exit 2; }
  # Symlink, not a copy: the lease library is NOT under mutation here, and a stale copy
  # would make these arms measure a different session-state.sh from the one that ships.
  ln -sfn "$REPO_ROOT/plugins/soleur/scripts/lib" "$MUT_DIR/$name/scripts/lib" \
    || { printf 'FATAL: could not link the lease library for %s\n' "$name" >&2; exit 2; }
  cp "$SCRIPT" "$out" || { printf 'FATAL: cp failed for %s\n' "$name" >&2; exit 2; }
  local fn
  # PER-MUTATION landing assertion, not one `diff -q` at the end: for a composite mutant a
  # single final diff cannot distinguish "both landed" from "one of two landed", and a
  # half-landed mutant still differs from the script so it clears the final gate while
  # testing something other than what its name claims.
  for fn in "$@"; do
    cp "$out" "$out.before" || { printf 'FATAL: snapshot failed for %s/%s\n' "$name" "$fn" >&2; exit 2; }
    "$fn" "$out"
    if diff -q "$out.before" "$out" >/dev/null 2>&1; then
      printf 'FATAL: mutation %s did not land in mutant %s (anchor drifted?)\n' "$fn" "$name" >&2
      exit 2
    fi
    rm -f "$out.before"
  done
  if diff -q "$SCRIPT" "$out" >/dev/null 2>&1; then
    printf 'FATAL: mutant %s is identical to the script — mutation did not land\n' "$name" >&2
    exit 2
  fi
  bash -n "$out" || { printf 'FATAL: mutant %s is not valid bash\n' "$name" >&2; exit 2; }
  # The mutant must see a RESOLVABLE lease library, or it runs the fail-closed stub and the
  # arm measures that instead of the mutation. Asserted, not assumed.
  if [[ ! -e "$dir/../../../scripts/lib/session-state.sh" ]]; then
    printf 'FATAL: mutant %s cannot resolve session-state.sh — it would run the fail-closed stub\n' "$name" >&2
    exit 2
  fi
  printf '%s' "$out"
}

# --- fixture ------------------------------------------------------------------------------
# Each arm gets a PRISTINE origin+clone pair: the reaper is destructive and a shared fixture
# would make arm N's verdict a function of arm N-1's writes.
#
# `git` is configured through GIT_CONFIG_GLOBAL=/dev/null rather than by writing a fixture
# config: the suite must not read the developer's ~/.gitconfig (a global `init.defaultBranch`
# or a commit hook would change what these arms measure).
# The shared builder, not a hand-rolled env array: it sets a ceiling
# (`GIT_CEILING_DIRECTORIES`) so a fixture git command cannot walk UP into a live repository,
# which a bare `GIT_CONFIG_GLOBAL=/dev/null` array does not. `fixture-env-adoption.test.sh` is
# the ratchet that derives this; adopting is its prescribed remedy, and a ceiling bump is
# documented there as being for suites that arrive from main rather than one in the bumping
# PR's own diff.
# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
FIXTURE_GIT_ENV=(
  GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_SYSTEM=/dev/null
  GIT_AUTHOR_NAME=soleur-fixture
  GIT_AUTHOR_EMAIL=fixture@soleur.invalid
  GIT_COMMITTER_NAME=soleur-fixture
  GIT_COMMITTER_EMAIL=fixture@soleur.invalid
)
fgit() { env "${FIXTURE_GIT_ENV[@]}" git "$@"; }

# mk_repo <dir> — an origin bare repo plus a clone on `main` with one commit.
# Prints nothing; the caller uses "$dir/origin.git" and "$dir/clone".
mk_repo() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir" || { printf 'FATAL: mkdir failed for %s\n' "$dir" >&2; exit 2; }
  git_fixture_env "$dir" || {
    printf 'FATAL: git_fixture_env refused to build an environment for %s\n' "$dir" >&2
    exit 2
  }
  fgit init -q --bare "$dir/origin.git" || { printf 'FATAL: bare init failed\n' >&2; exit 2; }
  fgit clone -q "$dir/origin.git" "$dir/clone" || { printf 'FATAL: clone failed\n' >&2; exit 2; }
  # Every setup command carries its own `|| exit 2`. This file is `set -uo pipefail`, NOT
  # `set -e` (an assertion failure must not abort the run), so nothing catches a failing
  # setup command implicitly — a silently failed clone would leave the fixture absent and the
  # arm would then report a confident wrong CAUSE rather than a missing fixture.
  fgit -C "$dir/clone" commit -q --allow-empty -m init || { printf 'FATAL: seed commit failed\n' >&2; exit 2; }
  fgit -C "$dir/clone" branch -M main || { printf 'FATAL: branch -M main failed\n' >&2; exit 2; }
  fgit -C "$dir/clone" push -q -u origin main || { printf 'FATAL: seed push failed\n' >&2; exit 2; }
}

# mk_merged_branch <clone> <branch> [age-seconds] — a branch merged into main, pushed to
# origin, with NO worktree. `age-seconds` backdates the COMMITTER date, which is the field
# `git log -1 --format=%ct` reads and therefore the one the commit-age grace measures.
mk_merged_branch() {
  local clone="$1" branch="$2" age="${3:-100000}"
  assert_fixture_dir "$clone"
  local when; when="$(( $(date +%s) - age ))"
  fgit -C "$clone" checkout -q -b "$branch"
  env "${FIXTURE_GIT_ENV[@]}" GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$clone" commit -q --allow-empty -m "work on $branch"
  fgit -C "$clone" push -q -u origin "$branch"
  fgit -C "$clone" checkout -q main
  # --no-ff so the branch is an ancestor of main (`git branch --merged main` sees it) while
  # main's own tip is NOT the branch tip.
  fgit -C "$clone" merge -q --no-ff "$branch" -m "merge $branch"
  fgit -C "$clone" push -q origin main
}

# mk_squash_merged_branch <clone> <branch> — the cohort THIS REPO produces for every PR.
# A squash merge puts the content on main under a NEW sha, so the branch is NOT an ancestor of
# `refs/heads/main`. Every other fixture here uses `--no-ff` and is therefore always an
# ancestor, which is exactly why the `-D`/`-d` downgrade shipped untested: no fixture
# instantiated the shape the producer actually emits.
mk_squash_merged_branch() {
  local clone="$1" branch="$2" age="${3:-100000}"
  assert_fixture_dir "$clone"
  # Backdated for the same reason `mk_merged_branch` is, but the arm it clears is a
  # DIFFERENT one. This fixture's branch carries a worktree (that is the only shape
  # `gh_merged_branches` is built from), so the guard that measures it is the WORKTREE
  # commit-age arm, not the worktree-less one — and that arm's skip line is `verbose`-gated,
  # i.e. `[[ -t 1 ]]`, i.e. silent under a redirected test run. A fresh commit here produced
  # a reaper that printed NOTHING AT ALL and an A9a failure reading as "the merge-evidence
  # block is broken". It was not; the loop never reached it.
  local when; when="$(( $(date +%s) - age ))"
  fgit -C "$clone" checkout -q -b "$branch"
  printf 'squashed work\n' > "$clone/$branch.txt"
  fgit -C "$clone" add "$branch.txt"
  env "${FIXTURE_GIT_ENV[@]}" GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$clone" commit -q -m "work on $branch"
  fgit -C "$clone" push -q -u origin "$branch"
  fgit -C "$clone" checkout -q main
  fgit -C "$clone" merge -q --squash "$branch"
  fgit -C "$clone" commit -q -m "squash: $branch"
  fgit -C "$clone" push -q origin main
}

# hold_lease <state-root> <key> — take a real lease through session-state.sh's own CLI, so
# the arm exercises the production lease format rather than a hand-written file that could
# drift from it.
hold_lease() {
  local root="$1" key="$2"
  assert_fixture_dir "$root"
  SOLEUR_SESSION_STATE_ROOT="$root" \
    bash "$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh" acquire_lease "$key" soleur-fixture 240 >/dev/null 2>&1 \
    || { printf 'FATAL: acquire_lease failed for key %s\n' "$key" >&2; exit 2; }
  # LANDING ASSERTION. Without it M1/M2 report "killed" vacuously: their assertion is that the
  # leased branch IS reaped, which is also what happens when no lease was ever taken.
  SOLEUR_SESSION_STATE_ROOT="$root" \
    bash "$REPO_ROOT/plugins/soleur/scripts/lib/session-state.sh" is_lease_active "$key" >/dev/null 2>&1 \
    || { printf 'FATAL: lease for key %s is not active after acquire\n' "$key" >&2; exit 2; }
}

# arm_reaper <state-root> — the PRE-STAMP. See the header: without this every arm below is
# satisfied by the one-time arming hold rather than by the guard under test.
arm_reaper() {
  local root="$1"
  assert_fixture_dir "$root"
  mkdir -p "$root"
  : > "$root/reaper-armed"
}

# run_reaper <script> <cwd> <state-root> <logfile> — drive cleanup-merged and capture rc.
# `rc=$?` on its own line immediately after the command whose status matters, never through
# a pipe: `cmd | tail` takes the pipe's status and destroys the evidence in the same stroke.
RC=0
run_reaper() {
  local script="$1" cwd="$2" root="$3" log="$4"
  assert_fixture_dir "$cwd"
  # The redirect target is bound OUTSIDE this function, so its writing window is unguarded
  # from here — an empty or relative `$log` would retarget the write. Guard the directory it
  # lands in with the same canonical helper (P1b, fixture-relative-assert.test.sh).
  assert_fixture_dir "${log%/*}"
  ( cd "$cwd" && env "${FIXTURE_GIT_ENV[@]}" SOLEUR_SESSION_STATE_ROOT="$root" \
      bash "$script" cleanup-merged ) > "$log" 2>&1
  RC=$?
}

local_branch_exists() { fgit -C "$1" show-ref --verify --quiet "refs/heads/$2"; }
remote_branch_exists() { [[ -n "$(fgit -C "$1" ls-remote --heads origin "$2" 2>/dev/null)" ]]; }

# ===========================================================================================
# A1 — the canonical case. A merged branch with NO worktree, held by a LIVE lease, must not
# be deleted locally or on the remote.
#
# RED before Phase 1: the lease check is `[[ -n "$worktree_path" ]] && is_lease_active ...`,
# so with no worktree path the conjunct short-circuits, the guard never runs, and the loop
# reaches `git push origin --delete` and `git branch -D`.
# ===========================================================================================
echo "A1. worktree-less merged branch, live lease -> held"
A1="$TMP/a1"; mk_repo "$A1"
mk_merged_branch "$A1/clone" "feat-a1-leased"
A1_STATE="$TMP/a1-state"; arm_reaper "$A1_STATE"
hold_lease "$A1_STATE" "feat-a1-leased"
run_reaper "$SCRIPT" "$A1/clone" "$A1_STATE" "$TMP/a1.log"

if local_branch_exists "$A1/clone" "feat-a1-leased"; then
  pass "A1a: local branch survived (git branch -D not reached)"
else
  fail "A1a: local branch DELETED while a live lease was held — git branch -D was reached"
fi
if remote_branch_exists "$A1/clone" "feat-a1-leased"; then
  pass "A1b: remote branch survived (git push origin --delete not reached)"
else
  fail "A1b: remote branch DELETED while a live lease was held — git push origin --delete was reached"
fi
# The reason line is part of the contract: an operator reading a terminal must be able to
# tell "held by a lease" from "held because the lease library is missing".
if grep -qF 'active lease' "$TMP/a1.log"; then
  pass "A1c: the hold is reported as an active lease"
else
  fail "A1c: no 'active lease' line — the branch was held (or not) for some other reason"
fi

# ===========================================================================================
# A2 — the commit-age grace, worktree-less arm. No lease at all; the branch tip was committed
# seconds ago. RED before Phase 1: the grace read is gated on `-d "$worktree_path"`.
# ===========================================================================================
echo "A2. worktree-less merged branch, recent commit, no lease -> held"
A2="$TMP/a2"; mk_repo "$A2"
mk_merged_branch "$A2/clone" "feat-a2-fresh" 5
A2_STATE="$TMP/a2-state"; arm_reaper "$A2_STATE"
run_reaper "$SCRIPT" "$A2/clone" "$A2_STATE" "$TMP/a2.log"

if local_branch_exists "$A2/clone" "feat-a2-fresh"; then
  pass "A2a: a branch committed 5s ago survived the grace window"
else
  fail "A2a: a branch committed 5s ago was reaped — the commit-age grace never evaluated it"
fi
if remote_branch_exists "$A2/clone" "feat-a2-fresh"; then
  pass "A2b: its remote ref survived"
else
  fail "A2b: its remote ref was deleted"
fi
# THE REASON, not only the survival. Plan scenario 2 asks for both and only survival was
# ticked — but survival is satisfiable by ANY skip, including the lease guard firing by
# accident, and including a silent one. This arm is the worktree-LESS grace, whose whole
# point is that it prints unconditionally (the worktree arm's line was `verbose`-gated, i.e.
# invisible under `claude --bg`, which is how A9 went undiagnosed for a round). Asserting the
# wording is what makes "held BY THE COMMIT-AGE GRACE" distinguishable from "held somehow".
if grep -qE '^\(skip\) feat-a2-fresh - branch ref committed <10min ago' "$TMP/a2.log"; then
  pass "A2c: the worktree-less grace names itself, and does so with no tty"
else
  fail "A2c: the hold is unattributed — plan scenario 2 asks for the branch-ref skip reason, not just survival"
fi

# ===========================================================================================
# A3 — must-PASS, and NOT the canonical input. A stale branch WITH a worktree, unleased,
# clean, last commit far outside the grace window must still be reaped exactly as today.
# This is what distinguishes "the guard now evaluates every branch" from "the guard now
# refuses everything", and mutants that blanket-refuse are caught here rather than by A1.
# ===========================================================================================
echo "A3. worktree-bearing, unleased, clean, old commit -> reaped (no blanket refusal)"
A3="$TMP/a3"; mk_repo "$A3"
# 900s, NOT the 100000s default, and the number is the assertion. The grace is `_delta < 600`;
# with fixtures at 5s (held) and 27.8h (reaped) every window in that range satisfies both arms,
# so widening the constant to a DAY stayed green — a grace silently widened to 86400 stops
# reaping the entire normal cohort, which is the blanket-refusal failure this very row exists to
# catch, one dimension over. 900 sits 300s outside the window: tight enough that a widening reds
# here, loose enough that suite runtime cannot drift a fixture across it.
mk_merged_branch "$A3/clone" "feat-a3-reapme" 900
A3_WT="$A3/wt-a3"; assert_fixture_dir "$A3_WT"
fgit -C "$A3/clone" worktree add -q "$A3_WT" "feat-a3-reapme"
A3_STATE="$TMP/a3-state"; arm_reaper "$A3_STATE"
run_reaper "$SCRIPT" "$A3/clone" "$A3_STATE" "$TMP/a3.log"

if local_branch_exists "$A3/clone" "feat-a3-reapme"; then
  fail "A3a: an unleased, clean, old worktree-bearing branch was NOT reaped — the fix degraded into a blanket refusal"
else
  pass "A3a: an unleased, clean, old worktree-bearing branch is still reaped"
fi
# THE POSITIVE WITNESS FOR THE REMOTE DELETE. `remote_branch_exists` was called twice in this
# file, both times expecting TRUE, so `remote_branch_exists() { return 0; }` — and disabling the
# SUT's remote delete outright — both scored a clean 30/30. "The remote branch survived" was
# therefore indistinguishable from "this fixture can never delete a remote ref": every hold row
# passed at a gate EARLIER than the one under test. The SUT's own comment calls this "the one
# irreversible write" (it closes the PR), and it had no witness at all.
if remote_branch_exists "$A3/clone" "feat-a3-reapme"; then
  fail "A3b: the remote ref survived a reap — the hold rows above prove nothing about a delete that never fires"
else
  pass "A3b: the remote ref is deleted too (the hold rows are measuring a live delete path)"
fi
# The sentinel already CARRIES the field; nothing read it. A8e greps only `^SOLEUR_WORKTREE_REAPED `,
# which is satisfied by a reap that silently failed to reach the remote.
if grep -qE '^SOLEUR_WORKTREE_REAPED .*[[:space:]]remote=yes' "$TMP/a3.log"; then
  pass "A3c: the sentinel reports remote=yes, so the marker's own field is load-bearing"
else
  fail "A3c: the reap sentinel does not report remote=yes — recovery reads a field nothing asserts"
fi

# ===========================================================================================
# A4 — must-PASS, second non-canonical input: a slash-bearing branch. `_safe_worktree_name`
# is `tr '/' '-'`, so `ci/probe` leases under the key `ci-probe`. Phase 1 changes the lease
# KEY as well as dropping the path conjunct, and the key change is the one that can regress.
# ===========================================================================================
echo "A4. slash-bearing branch, leased under its safe name -> held"
A4="$TMP/a4"; mk_repo "$A4"
mk_merged_branch "$A4/clone" "ci/probe"
A4_STATE="$TMP/a4-state"; arm_reaper "$A4_STATE"
hold_lease "$A4_STATE" "ci-probe"
run_reaper "$SCRIPT" "$A4/clone" "$A4_STATE" "$TMP/a4.log"

if local_branch_exists "$A4/clone" "ci/probe"; then
  pass "A4: ci/probe held by a lease keyed ci-probe (the safe-name transform still resolves)"
else
  fail "A4: ci/probe was reaped though a lease was held under its safe name ci-probe"
fi

# ===========================================================================================
# A5 — the post-loop `reset --hard HEAD`. A non-bare checkout parked on a feature branch with
# an uncommitted TRACKED modification, plus a separate reapable branch so `${#cleaned[@]}`
# reaches the summary block at all.
#
# RED before Phase 1 step 4: the reset is guarded ONLY by the dirty check, so it fires
# precisely in the destructive case, and the `current_branch != main` test that would justify
# its "direct commits to main are prohibited" premise runs AFTER it.
#
# This arm MOVES the precondition rather than deleting the reset: a delete-only mutation
# would red any case that reads the tree at all, which proves nothing about ordering.
# ===========================================================================================
echo "A5. non-bare checkout parked off main -> uncommitted work survives cleanup"
A5="$TMP/a5"; mk_repo "$A5"
mk_merged_branch "$A5/clone" "feat-a5-reapme"
# A tracked file, committed on `parked`, then modified: `git diff --quiet HEAD` is what the
# dirty check reads, and it does not see untracked files.
fgit -C "$A5/clone" checkout -q -b parked
printf 'committed contents\n' > "$A5/clone/work.txt"
fgit -C "$A5/clone" add work.txt
fgit -C "$A5/clone" commit -q -m "parked work"
printf 'UNCOMMITTED OPERATOR WORK\n' > "$A5/clone/work.txt"
A5_STATE="$TMP/a5-state"; arm_reaper "$A5_STATE"
run_reaper "$SCRIPT" "$A5/clone" "$A5_STATE" "$TMP/a5.log"

# Precondition: the summary block is reached only when at least one branch was cleaned. If
# nothing was reaped this arm is vacuous — it would "pass" without the reset ever being
# reachable, which is the own-dispatch failure this check exists to make loud.
if local_branch_exists "$A5/clone" "feat-a5-reapme"; then
  fail "A5-precondition: nothing was reaped, so the post-loop summary block never ran and this arm proves nothing"
else
  pass "A5-precondition: a branch was reaped, so the post-loop main-update block was reached"
fi
if [[ "$(cat "$A5/clone/work.txt" 2>/dev/null)" == "UNCOMMITTED OPERATOR WORK" ]]; then
  pass "A5a: uncommitted work in a checkout parked off main survived cleanup-merged"
else
  fail "A5a: uncommitted work was DISCARDED — reset --hard HEAD ran on a checkout that was not on main"
fi
if grep -qE "^Skipped stale-index reset: checkout is on 'parked', not main/master" "$TMP/a5.log"; then
  pass "A5b: the skip is reported on stdout, naming the branch it found"
else
  fail "A5b: the reset skip is silent — an operator cannot tell it from a run that reset nothing"
fi

# ===========================================================================================
# A6 — the loop evaluates EVERY member, not just the first. Two worktree-less stale branches:
# the first held by a lease, the second reapable. A guard that stops at the first member is
# the defect class itself.
# ===========================================================================================
echo "A6. two worktree-less stale branches -> both evaluated"
A6="$TMP/a6"; mk_repo "$A6"
mk_merged_branch "$A6/clone" "feat-a6-aaa-held"
mk_merged_branch "$A6/clone" "feat-a6-zzz-reap"
A6_STATE="$TMP/a6-state"; arm_reaper "$A6_STATE"
hold_lease "$A6_STATE" "feat-a6-aaa-held"
run_reaper "$SCRIPT" "$A6/clone" "$A6_STATE" "$TMP/a6.log"

if local_branch_exists "$A6/clone" "feat-a6-aaa-held"; then
  pass "A6a: the leased member was held"
else
  fail "A6a: the leased member was reaped"
fi
if local_branch_exists "$A6/clone" "feat-a6-zzz-reap"; then
  fail "A6b: the unleased member was NOT reaped — the loop stopped at the first member"
else
  pass "A6b: the unleased member was still reaped (the loop continued past the held one)"
fi

# ===========================================================================================
# A7 — OWN DISPATCH. Assert the suite actually drove branches through the loop. A run that
# returns at the early `[[ -z "$all_stale_branches" ]]` guard reports success having
# evaluated nothing, and every arm above would pass vacuously on it.
#
# The floor counts branches this suite OBSERVED a per-branch decision for, derived from the
# logs rather than from a remembered list.
# ===========================================================================================
echo "A7. own dispatch: the loop was actually entered"
_driven=0
for _lg in "$TMP/a1.log" "$TMP/a2.log" "$TMP/a3.log" "$TMP/a4.log" "$TMP/a5.log" "$TMP/a6.log"; do
  [[ -f "$_lg" ]] || continue
  # `grep -c` exits 1 on zero matches under `set -o pipefail`; `|| true` keeps the count.
  _n=$(grep -cE '^\(skip\)|^\(hold\)|Cleaned [0-9]+ merged worktree' "$_lg" 2>/dev/null || true)
  _driven=$(( _driven + ${_n:-0} ))
done
# 7 = A1(1 skip) + A2(1 skip) + A3(1 cleaned) + A4(1 skip) + A5(1 cleaned) + A6(1 skip + 1 cleaned).
if [[ "$_driven" -ge 7 ]]; then
  pass "A7: $_driven per-branch decisions observed across the arms (floor 7)"
else
  fail "A7: only $_driven per-branch decisions observed (floor 7) — arms ran against an empty stale-branch list and prove nothing"
fi

# ===========================================================================================
# A8 — static rows. The documented scope must not drift back below the enforced one, and the
# capability token Phase 2 feature-detects must exist and be observable at runtime.
#
# Anchored on the syntactic construct, never on a bare token: a body-grep sees comments too,
# and this script's own comments discuss branch deletion at length.
# ===========================================================================================
echo "A8. banner scope and the reap-capability token"
if grep -qE 'REFUSE to reap any worktree \*?\*?or delete any branch' "$SCRIPT"; then
  pass "A8a: the fail-closed banner names BRANCH deletion, not only worktree reaping"
else
  fail "A8a: the banner still claims worktree-only scope while the code now guards branches too"
fi
# The token must be an ASSIGNMENT, not a mention: `grep -q SOLEUR_WORKTREE_REAP_CAPABILITY`
# would be satisfied by the comment that explains it.
if grep -qE '^[[:space:]]*SOLEUR_WORKTREE_REAP_CAPABILITY=' "$SCRIPT"; then
  pass "A8b: the capability token is assigned as a literal (statically greppable by go.md)"
else
  fail "A8b: no SOLEUR_WORKTREE_REAP_CAPABILITY= assignment — go.md's feature-detect can never match"
fi
# Membership in a space-separated set, never a version literal: a `-v1` suffix re-imports the
# version-sniff failure mode; set membership is additive forever.
if grep -qE '^[[:space:]]*SOLEUR_WORKTREE_REAP_CAPABILITY=.*branch-keyed-guards' "$SCRIPT"; then
  pass "A8c: the token names the capability (branch-keyed-guards), not a version"
else
  fail "A8c: the token does not carry the branch-keyed-guards capability name"
fi
# Observable at runtime, on stdout: stderr is invisible under `claude --bg`, the mode
# cleanup-merged actually runs in.
_probe_log="$TMP/capability-probe.log"
( cd "$A1/clone" && env "${FIXTURE_GIT_ENV[@]}" bash "$SCRIPT" list ) > "$_probe_log" 2>/dev/null
if grep -qE '^SOLEUR_WORKTREE_REAP_CAPABILITY=.*branch-keyed-guards' "$_probe_log"; then
  pass "A8d: the token is emitted on STDOUT at load"
else
  fail "A8d: the token is not emitted on stdout at load — it is not observable at runtime"
fi
# A reap must be visible without `verbose`. `Deleted remote branch:` is `verbose`-gated, i.e.
# invisible under `claude --bg`, which left the single destructive event here as the only
# event in this function with no sentinel.
if grep -qE '^SOLEUR_WORKTREE_REAPED ' "$TMP/a3.log"; then
  pass "A8e: a reap emits SOLEUR_WORKTREE_REAPED unconditionally on stdout"
else
  fail "A8e: a reap emitted no SOLEUR_WORKTREE_REAPED sentinel — the destructive event is invisible in the mode this runs in"
fi

# ===========================================================================================
# MUTANTS. Each reverts exactly one Phase 1 edit against a COPY of the shipped script and
# asserts the corresponding arm goes RED. A mutation that does not land reports the BASELINE,
# which is indistinguishable from a pass — hence build_mutant's per-mutation `diff` check.
# ===========================================================================================
echo "M. mutants"

# M1 — restore the worktree-path conjunct on the lease check. A1 must fail.
M1="$(build_mutant m1-lease-path-conjunct restore_lease_path_conjunct)"
M1F="$TMP/m1"; mk_repo "$M1F"
mk_merged_branch "$M1F/clone" "feat-m1-leased"
M1_STATE="$TMP/m1-state"; arm_reaper "$M1_STATE"
hold_lease "$M1_STATE" "feat-m1-leased"
run_reaper "$M1" "$M1F/clone" "$M1_STATE" "$TMP/m1.log"
if local_branch_exists "$M1F/clone" "feat-m1-leased"; then
  fail "M1: SURVIVED — restoring the worktree-path conjunct did not re-expose the leased worktree-less branch, so A1 is not testing that conjunct"
else
  pass "M1: killed — with the path conjunct restored, the leased worktree-less branch is reaped again"
fi

# M2 — the pre-#5454 fail-open. A1 must fail for a different reason than M1, so the two
# together pin the guard's presence AND its predicate.
M2="$(build_mutant m2-lease-fail-open neuter_is_lease_active)"
M2F="$TMP/m2"; mk_repo "$M2F"
mk_merged_branch "$M2F/clone" "feat-m2-leased"
M2_STATE="$TMP/m2-state"; arm_reaper "$M2_STATE"
hold_lease "$M2_STATE" "feat-m2-leased"
run_reaper "$M2" "$M2F/clone" "$M2_STATE" "$TMP/m2.log"
if local_branch_exists "$M2F/clone" "feat-m2-leased"; then
  fail "M2: SURVIVED — is_lease_active returning 1 for every key did not reap the leased branch, so A1 passes for a reason other than the lease"
else
  pass "M2: killed — a fail-open is_lease_active reaps the leased branch"
fi

# M3 — un-hoist the on-main precondition. A5 must fail.
M3="$(build_mutant m3-unhoist-main-check unhoist_main_branch_check)"
M3F="$TMP/m3"; mk_repo "$M3F"
mk_merged_branch "$M3F/clone" "feat-m3-reapme"
fgit -C "$M3F/clone" checkout -q -b parked
printf 'committed contents\n' > "$M3F/clone/work.txt"
fgit -C "$M3F/clone" add work.txt
fgit -C "$M3F/clone" commit -q -m "parked work"
printf 'UNCOMMITTED OPERATOR WORK\n' > "$M3F/clone/work.txt"
M3_STATE="$TMP/m3-state"; arm_reaper "$M3_STATE"
run_reaper "$M3" "$M3F/clone" "$M3_STATE" "$TMP/m3.log"
if [[ "$(cat "$M3F/clone/work.txt" 2>/dev/null)" == "UNCOMMITTED OPERATOR WORK" ]]; then
  fail "M3: SURVIVED — moving the on-main check back below the reset did not discard the uncommitted file, so A5 is not testing the ordering"
else
  pass "M3: killed — with the check un-hoisted, reset --hard discards uncommitted work on a checkout parked off main"
fi

# ===========================================================================================
# INSTRUMENT SELF-TEST. Every verdict above flows through pass()/fail(), so a suite whose
# helpers do not move their counters reports a clean run having asserted nothing. Drive BOTH
# helpers once and require every observable to move — the counters AND the failure ledger the
# verdict actually reads.
#
# Runs LAST against saved-and-restored counters rather than first, so the self-test's own
# synthetic verdicts never enter the tally and the floor below needs no subtrahend.
# ===========================================================================================
# ===========================================================================================
# A9 — the SQUASH-MERGED cohort must still be reaped, with no partial state.
#
# Before the review fix this arm was impossible to pass: the remote delete ran first, pruning
# the upstream that `git branch -d` relies on, the ancestry test then downgraded to `-d`, `-d`
# refused, and the loop `continue`d — leaving the remote ref deleted (PR closed), the worktree
# removed and the local ref kept, with no reap sentinel. Reproduced end to end before fixing.
# ===========================================================================================
echo "A9. squash-merged branch (this repo's default merge) -> reaped cleanly"
A9="$TMP/a9"; mk_repo "$A9"
mk_squash_merged_branch "$A9/clone" "feat-a9-squashed"
# `gh_merged_branches` is the ONLY evidence available for a squash merge, it is built from
# `gh pr list`, and the loop that builds it only considers branches that still have a worktree.
# So the fixture needs both a worktree and a `gh` stub reporting the PR merged.
A9_WT="$A9/wt-a9"; assert_fixture_dir "$A9_WT"
fgit -C "$A9/clone" worktree add -q "$A9_WT" "feat-a9-squashed"
A9_BIN="$TMP/a9-bin"; mkdir -p "$A9_BIN"
cat > "$A9_BIN/gh" <<'GH_EOF'
#!/usr/bin/env bash
# Model the real contract: `gh pr list --head <b> --state merged --limit 1 --json number
# --jq length` prints the COUNT. Refuse anything else so a drifted call shape is loud (exit 64)
# rather than silently answering the wrong question.
if [ "$1" = pr ] && [ "$2" = list ]; then
  case " $* " in *" --state merged "*) printf '1
'; exit 0 ;; esac
  printf '0
'; exit 0
fi
echo "gh stub: unexpected invocation: $*" >&2
exit 64
GH_EOF
chmod +x "$A9_BIN/gh"
A9_STATE="$TMP/a9-state"; arm_reaper "$A9_STATE"
PATH="$A9_BIN:$PATH" run_reaper "$SCRIPT" "$A9/clone" "$A9_STATE" "$TMP/a9.log"

if local_branch_exists "$A9/clone" "feat-a9-squashed"; then
  fail "A9a: a squash-merged branch was NOT reaped — the dominant cohort stopped being cleaned up"
else
  pass "A9a: a squash-merged branch is reaped (merge evidence, not ancestry, licenses it)"
fi
if grep -qE '^SOLEUR_WORKTREE_REAP_PARTIAL' "$TMP/a9.log"; then
  fail "A9b: a partial reap was reported — the remote was deleted and the local delete refused"
else
  pass "A9b: no partial state (remote and local agree)"
fi

# ===========================================================================================
# A10 — a [gone] branch with NO merge evidence must be skipped BEFORE any write.
# ===========================================================================================
echo "A10. [gone] upstream, unmerged -> skipped before any destructive write"
A10="$TMP/a10"; mk_repo "$A10"
fgit -C "$A10/clone" checkout -q -b feat-a10-gone
printf 'unmerged\n' > "$A10/clone/a10.txt"
fgit -C "$A10/clone" add a10.txt
env "${FIXTURE_GIT_ENV[@]}" GIT_COMMITTER_DATE="$(( $(date +%s) - 100000 ))" \
  GIT_AUTHOR_DATE="$(( $(date +%s) - 100000 ))" \
  git -C "$A10/clone" commit -q -m "unmerged work"
fgit -C "$A10/clone" push -q -u origin feat-a10-gone
fgit -C "$A10/clone" push -q origin --delete feat-a10-gone
# `--no-tags` is the battery-tag-authorship declaration (ADR-207): this fetch exists to prune
# the deleted upstream, and it authors no tag. Without it the site grades OFFENDER in a census
# no diff-derived suite selection reaches.
fgit -C "$A10/clone" fetch -q --prune --no-tags
fgit -C "$A10/clone" checkout -q main
A10_STATE="$TMP/a10-state"; arm_reaper "$A10_STATE"
run_reaper "$SCRIPT" "$A10/clone" "$A10_STATE" "$TMP/a10.log"

if local_branch_exists "$A10/clone" "feat-a10-gone"; then
  pass "A10a: an unmerged [gone] branch survives (a deleted upstream is not merge evidence)"
else
  fail "A10a: an unmerged [gone] branch was force-deleted — its commits exist nowhere else"
fi
if grep -qF 'no merge evidence' "$TMP/a10.log"; then
  pass "A10b: the skip names the measured cause"
else
  fail "A10b: the skip did not report the absence of merge evidence"
fi

# ===========================================================================================
# A11 — F2: the dirty file must exist ON MAIN TOO. `git checkout main` refuses only when the
# dirty paths would be OVERWRITTEN; when the committed content matches it SUCCEEDS and carries
# the edit onto main, where the NEXT run's reset destroys it. A5's fixture commits its file
# only on the feature branch, which is the case where checkout does refuse — so A5 alone
# cannot see this.
# ===========================================================================================
echo "A11. dirty file that also exists on main -> not carried onto main"
A11="$TMP/a11"; mk_repo "$A11"
printf 'base\n' > "$A11/clone/shared.txt"
fgit -C "$A11/clone" add shared.txt
fgit -C "$A11/clone" commit -q -m "shared on main"
fgit -C "$A11/clone" push -q origin main
mk_merged_branch "$A11/clone" "feat-a11-reapme"
fgit -C "$A11/clone" checkout -q -b parked
printf 'PRECIOUS UNCOMMITTED WORK\n' > "$A11/clone/shared.txt"
A11_STATE="$TMP/a11-state"; arm_reaper "$A11_STATE"
run_reaper "$SCRIPT" "$A11/clone" "$A11_STATE" "$TMP/a11.log"

if [[ "$(fgit -C "$A11/clone" rev-parse --abbrev-ref HEAD)" == "parked" ]]; then
  pass "A11a: the operator was left on their own branch"
else
  fail "A11a: cleanup switched the checkout to $(fgit -C "$A11/clone" rev-parse --abbrev-ref HEAD) while it was dirty"
fi
if [[ "$(cat "$A11/clone/shared.txt" 2>/dev/null)" == "PRECIOUS UNCOMMITTED WORK" ]]; then
  pass "A11b: the uncommitted edit survived"
else
  fail "A11b: the uncommitted edit was lost"
fi

# ===========================================================================================
# A12 — the reap sentinel is PER-REAP, not once per run. A8e greps a one-reap log, which is
# satisfied identically by an emit hoisted out of the loop.
# ===========================================================================================
echo "A12. two reaps in one pass -> two sentinels"
A12="$TMP/a12"; mk_repo "$A12"
mk_merged_branch "$A12/clone" "feat-a12-one"
mk_merged_branch "$A12/clone" "feat-a12-two"
A12_STATE="$TMP/a12-state"; arm_reaper "$A12_STATE"
run_reaper "$SCRIPT" "$A12/clone" "$A12_STATE" "$TMP/a12.log"
_n_reaped=$(grep -cE '^SOLEUR_WORKTREE_REAPED ' "$TMP/a12.log" 2>/dev/null || true)
if [[ "${_n_reaped:-0}" -eq 2 ]]; then
  pass "A12: two reaps emitted two SOLEUR_WORKTREE_REAPED lines"
else
  fail "A12: two reaps emitted ${_n_reaped:-0} sentinel(s), want 2 (is the emit inside the loop?)"
fi

# ===========================================================================================
# A13 — the WORKTREE commit-age hold must be AUDIBLE. Sibling of the worktree-less arm, and
# until this PR the two disagreed: the worktree-less one prints unconditionally, the
# worktree one was `verbose`-gated, and `verbose` is `[[ -t 1 ]]`. `cleanup-merged` runs at
# session start under `claude --bg`, where stdout is not a tty, so the gated line printed
# nothing and a HELD branch was byte-identical on stdout to a branch the loop never
# considered. That collapse is the #7442 class this PR exists to remove, one guard over.
#
# Not a duplicate of A2 (which asserts the branch SURVIVES): survival is satisfiable by any
# skip, including a silent one. This row asserts the REASON reached stdout.
# ===========================================================================================
echo "A13. worktree-bearing merged branch, fresh commit -> held AUDIBLY"
A13="$TMP/a13"; mk_repo "$A13"
# age 0: the commit is seconds old, so the worktree commit-age arm is the guard that fires.
mk_merged_branch "$A13/clone" "feat-a13-fresh" 0
A13_WT="$A13/wt-a13"; assert_fixture_dir "$A13_WT"
fgit -C "$A13/clone" worktree add -q "$A13_WT" "feat-a13-fresh"
A13_STATE="$TMP/a13-state"; arm_reaper "$A13_STATE"
run_reaper "$SCRIPT" "$A13/clone" "$A13_STATE" "$TMP/a13.log"
if grep -qE '^\(skip\) feat-a13-fresh - recent commit' "$TMP/a13.log"; then
  pass "A13a: the worktree commit-age hold names itself on stdout with no tty"
else
  fail "A13a: the worktree commit-age hold was SILENT — a held branch is indistinguishable from an unconsidered one"
fi
if local_branch_exists "$A13/clone" "feat-a13-fresh"; then
  pass "A13b: the freshly-committed branch survives"
else
  fail "A13b: the freshly-committed branch was reaped inside its grace window"
fi

echo "S. instrument self-test"
_real_pass=$PASS; _real_fail=$FAIL; _real_asserted=$ASSERTED
_real_failures=("${FAILURES[@]+"${FAILURES[@]}"}")
PASS=0; FAIL=0; ASSERTED=0; FAILURES=()
pass "self-test: pass() reached" >/dev/null
fail "self-test: fail() reached" >/dev/null
_st_ok=true
[[ "$PASS" -eq 1 ]] || _st_ok=false
[[ "$FAIL" -eq 1 ]] || _st_ok=false
[[ "$ASSERTED" -eq 2 ]] || _st_ok=false
[[ "${#FAILURES[@]}" -eq 1 ]] || _st_ok=false
PASS=$_real_pass; FAIL=$_real_fail; ASSERTED=$_real_asserted
FAILURES=("${_real_failures[@]+"${_real_failures[@]}"}")
if [[ "$_st_ok" != true ]]; then
  # Reported with printf + exit, NEVER through fail(): a floor that calls the helper it
  # backstops is disarmed by the same edit that disarms the helper.
  printf 'FATAL: instrument self-test failed — pass()/fail() do not move every observable the verdict reads.\n' >&2
  exit 1
fi
printf '  pass: self-test — pass() and fail() both move the counters and the ledger\n'

# ===========================================================================================
# ANTI-VACUITY FLOOR. A suite that silently stops executing rows reports 0 failures.
# The threshold is declared on the line IMMEDIATELY above its `if`: guard-vacuity-floor's
# mutant slices the `if` plus its CONTIGUOUS simple assignments, and a threshold bound far
# above is unbound in that slice, so the mutant dies at `set -u` and the floor scores
# CONSTRUCTION rather than FIRES.
# ===========================================================================================
MIN_ASSERTIONS=33
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: only %s assertions executed, floor is %s — rows were removed or an arm aborted early.\n' \
    "$ASSERTED" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf 'worktree-manager-cleanup-merged-no-worktree.test.sh: %s passed, %s failed, %s assertion(s) executed (floor %s)\n' \
  "$PASS" "$FAIL" "$ASSERTED" "$MIN_ASSERTIONS"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'Failed rows:\n' >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
