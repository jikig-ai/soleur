#!/usr/bin/env bash
# pre-push-ratchet-lane.sh — the fast "affected-ratchets" pre-push lane (#9400).
#
# WHAT IT IS. A deliberately narrow pre-push net: fetch origin/main, materialize
# the merged branch+main tree in a scratch git worktree (the operator's branch is
# never mutated), and run only the cheap ratchet/lint members a diff can trip —
# the highwater family, plugin-root anchor-debt, the fixture-scan suites, and the
# merge-base byte/body lints — plus a condition-triggered kb-consumers member and
# a branch-touched suite tier run in the deps-free, disk-backed-TMPDIR scratch
# (the vitest-absent + non-tmpfs CI shape). ~1–2 min for the common case. The
# required `test` context remains the merge gate (ADR-183) — this lane is the
# cheap local net, not a claimed equivalent.
#
# RECEIPT. One `RATCHET_LANE member=<name> tier=<t> verdict=<v> seconds=<n>` line
# per member, a `RATCHET_LANE merge=<state>` line, and a terminal
# `RATCHET_LANE verdict=PASS|RED|MERGE_CONFLICT|ABORT` line.
# Exit: 0 pass · 1 member red · 2 infra abort / merge conflict.
#
# `--print-members` prints the member table and exits BEFORE any fetch, worktree
# or suite runs — safe for preflight probes.
#
# TEST SEAMS (documented, read by scripts/pre-push-ratchet-lane.test.sh):
#   PREPUSH_LANE_MEMBERS_FILE  — substitute member table (name|tier|argv rows)
#   PREPUSH_LANE_WORKTREE_DIR  — pin the scratch worktree path (a pre-existing
#                                non-empty dir exercises the add-failure arm)
#   PREPUSH_LANE_MEMBER_TIMEOUT / PREPUSH_LANE_FETCH_TIMEOUT /
#   PREPUSH_LANE_CONDITIONAL_TIMEOUT — bound overrides (seconds)
#   SOLEUR_SCRATCH_ROOT — honoured by scripts/lib/scratch-root.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Git-hook env scrub — lefthook/git export the git-location family, and every git
# call below (and every member's) must target THIS repo's worktree, never the
# exporting parent's. The unset list is the canonical GIT_LOCATION_VARS
# (plugins/soleur/test/lib/git-fixture-env.ts) plus SSH_ASKPASS — the one
# execution vector with no GIT_ prefix — pinned by the suite against the source
# of truth. One `unset` line so the parity arm can read it.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH SSH_ASKPASS
# Ambient CI/GITHUB_*/LEFTHOOK* inheritance has produced false-local-green
# (learnings 2026-10-01): scrub by prefix so no member reads a runner's
# environment as the tree's truth. Trace vars are presence-checked — a `=0`
# export would ENABLE them (#8474) — so they are removed, never zeroed.
for _v in ${!CI@} ${!GITHUB_@} ${!LEFTHOOK@} ${!GIT_TRACE@} GIT_CURL_VERBOSE; do
  unset "$_v"
done
unset _v

MEMBER_TIMEOUT="${PREPUSH_LANE_MEMBER_TIMEOUT:-300}"
FETCH_TIMEOUT="${PREPUSH_LANE_FETCH_TIMEOUT:-90}"
COND_TIMEOUT="${PREPUSH_LANE_CONDITIONAL_TIMEOUT:-900}"
BRANCH_TIER_CAP=12

# --- Member table ---------------------------------------------------------------
# Rows: name|tier|argv. tier ∈ fast|conditional. __BASE__ expands to the
# branch/origin-main merge base at dispatch. Parity with the registrations these
# members come from is asserted by the suite — a member row whose argv is not the
# argv CI/test-all runs is drift, and drift is what this lane exists to catch.
# __LANE_MEMBERS_BEGIN__
LANE_MEMBERS=(
  "lint-trap-tempfile-ownership|fast|python3 scripts/lint-trap-tempfile-ownership.py --check-highwater"
  "lint-supabase-deprecated-endpoints|fast|bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater"
  "lint-diagnosis-claims|fast|bash scripts/lint-diagnosis-claims.test.sh"
  "alarm-issue-filing-guard|fast|bash scripts/alarm-issue-filing-guard.test.sh"
  "lint-workflow-step-env-refs|fast|python3 scripts/lint-workflow-step-env-refs.py"
  "plugin-root-anchor-debt|fast|bash scripts/plugin-root-anchor-debt.sh"
  "fixture-relative-assert|fast|bash plugins/soleur/test/fixture-relative-assert.test.sh"
  "fixture-dir-operand-assert|fast|bash plugins/soleur/test/fixture-dir-operand-assert.test.sh"
  "fixture-cd-containment|fast|bash plugins/soleur/test/fixture-cd-containment.test.sh"
  "skill-body-budget|fast|python3 scripts/lint-skill-body-budget.py --base __BASE__"
  "rule-bodies|fast|python3 scripts/lint-rule-bodies.py --check --base __BASE__"
  "test-affected-kb-consumers|conditional|bash scripts/test-affected-kb-consumers.test.sh"
)
# __LANE_MEMBERS_END__

# Conditional-tier trigger inputs: when any of these moved on EITHER side of the
# merge delta, the kb-consumers ratchet can newly fail and its member runs.
KB_CONSUMERS_INPUTS=(
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-affected-kb-consumers.test.sh"
  "scripts/test-affected-kb-consumers.baseline.txt"
)

MEMBERS=()
if [[ -n "${PREPUSH_LANE_MEMBERS_FILE:-}" ]]; then
  while IFS= read -r _line; do
    [[ -z "${_line// }" || "$_line" == \#* ]] && continue
    MEMBERS+=("$_line")
  done < "$PREPUSH_LANE_MEMBERS_FILE"
else
  MEMBERS=("${LANE_MEMBERS[@]}")
fi

if [[ "${1:-}" == "--print-members" ]]; then
  # Pure print arm — runs before any repo, fetch or worktree dependency.
  for _row in ${MEMBERS[@]+"${MEMBERS[@]}"}; do
    printf '%s\n' "$_row"
  done
  exit 0
fi

say() { printf 'RATCHET_LANE %s\n' "$@"; }
member_line() {
  printf 'RATCHET_LANE member=%s tier=%s verdict=%s seconds=%s%s\n' \
    "$1" "$2" "$3" "$4" "${5:+ reason=$5}"
}

# BYTE-IDENTICAL to plugins/soleur/test/test-helpers.sh's assert_fixture_dir() —
# the operand-provenance ratchets recognise ONLY this executed statement. The
# lane is not a fixture builder, but every `git -C "$REPO_ROOT"` below is a dir
# operand the corpus scanner insists on seeing guarded; REPO_ROOT is bound from
# `git rev-parse` output, so the guard is also the honest empty/relative check.
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

T0="$(date +%s)"

REPO_ROOT=""
if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  say "merge=skipped:not-a-repo"
  say "verdict=ABORT members=0 red=0 seconds=0"
  exit 2
fi
assert_fixture_dir "$REPO_ROOT"

# A bound is optional on hosts without coreutils `timeout` — stock macOS ships
# neither `timeout` nor `gtimeout`, and a missing bound must never read as a
# member failure. The bare fallback is the documented portability arm.
TO_BIN=""
if command -v timeout >/dev/null 2>&1; then TO_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TO_BIN="gtimeout"
fi

# run_bounded <secs> <cmd...> — run under the timeout binary when one exists.
run_bounded() {
  local _secs="$1"; shift
  local _rc=0
  if [[ -n "$TO_BIN" ]]; then
    "$TO_BIN" "$_secs" "$@" || _rc=$?
  else
    "$@" || _rc=$?
  fi
  return "$_rc"
}

# --- Fetch (bounded) -------------------------------------------------------------
fetch_rc=0
run_bounded "$FETCH_TIMEOUT" git -C "$REPO_ROOT" fetch --no-tags --quiet origin main || fetch_rc=$?

# --- Base + branch diff -----------------------------------------------------------
BASE=""
if ! BASE="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null)"; then
  BASE=""
fi

# Nothing to gate: the branch carries no diff vs origin/main — same early exit
# as scripts/hooks/pre-push. Measured post-fetch so a stale remote-tracking ref
# cannot green a branch that only LOOKED empty.
if [[ -n "$BASE" ]] && git -C "$REPO_ROOT" diff --quiet "$BASE" HEAD; then
  say "merge=skipped:no-diff base=$BASE"
  say "verdict=PASS members=0 red=0 seconds=$(( $(date +%s) - T0 ))"
  exit 0
fi

# --- Scratch worktree --------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/lib/scratch-root.sh" ]]; then
  say "merge=skipped:no-scratch-lib"
  say "verdict=ABORT members=0 red=0 seconds=$(( $(date +%s) - T0 ))"
  exit 2
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/scratch-root.sh"
LANE_BASE=""
if ! LANE_BASE="$(soleur_scratch_root)"; then
  say "merge=skipped:no-scratch-root"
  say "verdict=ABORT members=0 red=0 seconds=$(( $(date +%s) - T0 ))"
  exit 2
fi
PARENT="$(mktemp -d "$LANE_BASE/prepush-lane.XXXXXXXX")"
SCRATCH=""
cleanup() {
  if [[ -n "${SCRATCH:-}" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$SCRATCH" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  fi
  if [[ -n "${PARENT:-}" && -d "${PARENT:-}" ]]; then
    assert_fixture_dir "$PARENT"
    rm -rf "$PARENT"
  fi
}
trap cleanup EXIT INT TERM HUP
# Guard the scratch parent for every write below — the operand-provenance
# ratchet reads only executed statements, and $PARENT chains to a sourced
# helper the corpus cannot resolve.
assert_fixture_dir "$PARENT"

if [[ -n "${PREPUSH_LANE_WORKTREE_DIR:-}" ]]; then
  SCRATCH="$PREPUSH_LANE_WORKTREE_DIR"
else
  SCRATCH="$PARENT/scratch"
fi
add_rc=0
git -C "$REPO_ROOT" -c core.hooksPath=/dev/null worktree add --detach "$SCRATCH" HEAD \
  >/dev/null 2>&1 || add_rc=$?
if (( add_rc != 0 )); then
  say "merge=skipped:worktree-add-failed"
  say "verdict=ABORT members=0 red=0 seconds=$(( $(date +%s) - T0 ))"
  exit 2
fi
# TMPDIR pin — disk-backed (the non-tmpfs CI shape) but OUTSIDE the scratch
# worktree: a member's mktemp dir must not resolve `git rev-parse` against the
# lane's scratch repo — the first dogfood run showed fixture-dir-operand-assert
# losing its non-repository control exactly that way.
LANE_TMP="$PARENT/lane-tmp"
mkdir -p "$LANE_TMP"

# Diff manifests (computed BEFORE the in-scratch merge, so they describe the
# branch as pushed — the merged scratch is only where members execute). Guard
# each manifest var: the operand ratchet reads the chain's END var (LANE_BASE
# resolves through a sourced call), so guarding $PARENT alone misses them.
BRANCH_ALL="$PARENT/branch-all.txt"     # all changes incl. deletions (triggers)
BRANCH_TIER="$PARENT/branch-tier.txt"   # suite files the branch tier will run
MAIN_CHANGES="$PARENT/main-changes.txt" # what arrived on main since the fork
assert_fixture_dir "$BRANCH_ALL"
assert_fixture_dir "$MAIN_CHANGES"
assert_fixture_dir "$BRANCH_TIER"
if [[ -n "$BASE" ]]; then
  git -C "$REPO_ROOT" diff --name-only "$BASE" HEAD > "$BRANCH_ALL"
  git -C "$REPO_ROOT" diff --name-only "$BASE" origin/main > "$MAIN_CHANGES"
else
  : > "$BRANCH_ALL"; : > "$MAIN_CHANGES"
fi
: > "$BRANCH_TIER"

is_suite_file() {
  # Basename conventions for registered suites. Exclusions: the test-all RUNNER
  # itself (basename test-all.sh matches test-*.sh but is not a suite — running
  # it bare is the rc=4 refusal the arm-13 dogfood caught) and anything under a
  # lib/ dir (test-affected-paths.sh et al. are sourced libraries, not suites).
  case "$1" in
    */lib/*|scripts/test-all.sh) return 1 ;;
  esac
  case "${1##*/}" in
    *.test.sh|test_*.sh|test-*.sh) return 0 ;;
    *) return 1 ;;
  esac
}

# conditional_reason — prints WHY the conditional member fires; empty + rc 1
# means no trigger (member is skipped with a receipt reason). Defined ahead of
# the marked blocks because the suite's reorder arm splices those two regions —
# everything the dispatch block calls must already exist above them.
conditional_reason() {
  [[ -z "$BASE" ]] && return 1
  local f bf
  assert_fixture_dir "$PARENT"
  for f in "${KB_CONSUMERS_INPUTS[@]}"; do
    if grep -qxF "$f" "$BRANCH_ALL" || grep -qxF "$f" "$MAIN_CHANGES"; then
      printf 'input-moved:%s' "$f"; return 0
    fi
  done
  # (b) a branch-touched suite carrying a knowledge-base/ literal — the F2 shape.
  while IFS= read -r bf; do
    if [[ -f "$SCRATCH/$bf" ]] && grep -qF 'knowledge-base/' "$SCRATCH/$bf"; then
      printf 'kb-reading-suite:%s' "$bf"; return 0
    fi
  done < "$BRANCH_ALL"
  # (c) a new scripts/*.baseline.txt in the merge delta (either side).
  git -C "$REPO_ROOT" diff --name-status "$BASE" origin/main \
    -- 'scripts/*.baseline.txt' > "$PARENT/main-baselines.txt" || true
  git -C "$REPO_ROOT" diff --name-status "$BASE" HEAD \
    -- 'scripts/*.baseline.txt' > "$PARENT/branch-baselines.txt" || true
  if grep -q '^A' "$PARENT/main-baselines.txt" || grep -q '^A' "$PARENT/branch-baselines.txt"; then
    printf 'new-baseline-in-delta'; return 0
  fi
  return 1
}

# __MERGE_BLOCK_BEGIN__
MERGE_STATE="ok"
if (( fetch_rc != 0 )); then
  MERGE_STATE="skipped:fetch-failed"
elif [[ -z "$BASE" ]]; then
  MERGE_STATE="skipped:no-merge-base"
else
  merge_rc=0
  git -C "$SCRATCH" -c user.name=ratchet-lane -c user.email=ratchet-lane@localhost \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      merge --no-edit --quiet origin/main || merge_rc=$?
  if (( merge_rc != 0 )); then
    say "merge=conflict"
    say "verdict=MERGE_CONFLICT members=0 red=0 seconds=$(( $(date +%s) - T0 ))"
    exit 2
  fi
fi
# __MERGE_BLOCK_END__
say "merge=$MERGE_STATE base=${BASE:-none}"

# __DISPATCH_BLOCK_BEGIN__
members_run=0; members_red=0
for row in ${MEMBERS[@]+"${MEMBERS[@]}"}; do
  IFS='|' read -r name tier argv <<<"$row"
  [[ -z "$name" ]] && continue
  timeout_n="$MEMBER_TIMEOUT"
  case "$tier" in
    conditional)
      if _reason="$(conditional_reason)"; then
        timeout_n="$COND_TIMEOUT"
      else
        member_line "$name" "$tier" SKIP 0 "no-trigger"
        continue
      fi
      ;;
    fast) ;;
    *) member_line "$name" "$tier" SKIP 0 "unknown-tier"; continue ;;
  esac
  if [[ "$argv" == *__BASE__* && -z "$BASE" ]]; then
    member_line "$name" "$tier" SKIP 0 "no-merge-base"
    continue
  fi
  argv="${argv//__BASE__/$BASE}"
  mlog="$PARENT/member-${name}.log"
  assert_fixture_dir "$mlog"
  mrc=0
  _s="$(date +%s)"
  ( cd "$SCRATCH" && export TMPDIR="$LANE_TMP" && run_bounded "$timeout_n" bash -c "$argv" ) \
    >"$mlog" 2>&1 || mrc=$?
  _e="$(date +%s)"
  case "$mrc" in
    0) mv=PASS ;;
    124|137) mv=TIMEOUT ;;
    *) mv=RED ;;
  esac
  member_line "$name" "$tier" "$mv" "$((_e - _s))"
  if [[ "$mv" != "PASS" ]]; then
    tail -5 "$mlog" | sed 's/^/    /'
  fi
  members_run=$((members_run + 1))
  [[ "$mv" == "PASS" ]] || members_red=$((members_red + 1))
done

# --- Branch-touched suite tier ------------------------------------------------------
# Suite files the branch diff touched run inside the deps-free scratch under an
# env -i allowlist and a disk-backed TMPDIR — the vitest-absent, non-tmpfs CI
# shape (F4/F5). Cap + per-member bound keep this tier honest.
_br_count=0
while IFS= read -r bf; do
  is_suite_file "$bf" || continue
  [[ -f "$SCRATCH/$bf" ]] || continue
  if (( _br_count >= BRANCH_TIER_CAP )); then
    say "branch-tier truncated at cap=$BRANCH_TIER_CAP"
    break
  fi
  _br_count=$((_br_count + 1))
  bname="${bf##*/}"; bname="${bname%.sh}"
  mlog="$PARENT/member-branch-${bname}.log"
  assert_fixture_dir "$mlog"
  mrc=0
  _s="$(date +%s)"
  ( cd "$SCRATCH" && run_bounded "$MEMBER_TIMEOUT" env -i \
      PATH="$PATH" HOME="$HOME" TMPDIR="$LANE_TMP" \
      LANG="${LANG:-C.UTF-8}" USER="${USER:-lane}" LOGNAME="${LOGNAME:-lane}" \
      SHELL="${SHELL:-/bin/sh}" TERM="${TERM:-dumb}" \
      bash "$bf" ) >"$mlog" 2>&1 || mrc=$?
  _e="$(date +%s)"
  case "$mrc" in
    0) mv=PASS ;;
    124|137) mv=TIMEOUT ;;
    *) mv=RED ;;
  esac
  member_line "$bname" "branch" "$mv" "$((_e - _s))"
  if [[ "$mv" != "PASS" ]]; then
    tail -5 "$mlog" | sed 's/^/    /'
  fi
  members_run=$((members_run + 1))
  [[ "$mv" == "PASS" ]] || members_red=$((members_red + 1))
done < "$BRANCH_ALL"
# __DISPATCH_BLOCK_END__

# Dispatch vacuity: a lane that measured nothing cannot pass.
say "merge=$MERGE_STATE base=${BASE:-none}"
if (( members_run == 0 )); then
  say "verdict=RED members=0 red=0 seconds=$(( $(date +%s) - T0 )) dispatch=empty-table"
  exit 1
fi
if (( members_red > 0 )); then
  say "verdict=RED members=$members_run red=$members_red seconds=$(( $(date +%s) - T0 ))"
  exit 1
fi
say "verdict=PASS members=$members_run red=0 seconds=$(( $(date +%s) - T0 ))"
exit 0
