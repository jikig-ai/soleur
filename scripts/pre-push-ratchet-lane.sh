#!/usr/bin/env bash
# pre-push-ratchet-lane.sh — the fast "affected-ratchets" pre-push lane (#9400).
#
# WHAT IT IS. A deliberately narrow pre-push net: fetch origin/main, materialize
# the merged branch+main tree in a scratch git worktree (the operator's branch is
# never mutated), and run only the cheap ratchet/lint members a diff can trip —
# the highwater family, plugin-root anchor-debt, the fixture-scan suites, and the
# merge-base byte/body lints — plus a condition-triggered kb-consumers member
# (fires only when a registered suite in the diff GAINS a knowledge-base/ read
# or a declared input moved) and a branch-touched suite tier run in the
# deps-free, disk-backed-TMPDIR scratch (the vitest-absent + non-tmpfs CI
# shape), gated to the runner's `scripts` TEST_GROUP so deps-requiring suites
# SKIP rather than false-RED. ~1–2 min for the common case. The
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
# TEST SEAMS (documented, read by scripts/pre-push-ratchet-lane.test.sh). They
# are ambient env vars, so they are also reachable in hook context — env
# control of the hook already implies code execution, but treat them as
# operator/test-facing, never as untrusted input:
#   PREPUSH_LANE_MEMBERS_FILE  — substitute member table (name|tier|argv rows)
#   PREPUSH_LANE_WORKTREE_DIR  — pin the scratch worktree path (a pre-existing
#                                non-empty dir exercises the add-failure arm)
#   PREPUSH_LANE_MEMBER_TIMEOUT / PREPUSH_LANE_FETCH_TIMEOUT /
#   PREPUSH_LANE_CONDITIONAL_TIMEOUT / PREPUSH_LANE_BUDGET — bound overrides
#   SOLEUR_SCRATCH_ROOT — honoured by scripts/lib/scratch-root.sh
#
# PUSHED REFS. The hook's stdin ref list is deliberately not read: the lane
# always gates HEAD vs origin/main, so `git push origin <other>:main` or a tag
# push evaluates HEAD's diff, not the pushed ref's. The receipt's base=/merge=
# lines certify the HEAD tree only. That is the right scope for a cheap local
# net — the required `test` context remains the merge gate (ADR-183).
set -euo pipefail

# The scrub below names credential variables (GH_TOKEN & family), which puts
# this file in scope for lint-shell-trace-credential-refusal (#7797): under -x
# the trace would print the names — and any _TOKEN/_SECRET expansion the file
# ever gains — verbatim. Refuse tracing unconditionally.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

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
# Whole-lane bound: per-member caps still permit a pathological tail (every
# member timing out serially). Past this, dispatch stops and the lane ABORTs —
# a lane that could not evaluate cannot certify (same fail-closed shape as
# exit 2 elsewhere in this file).
LANE_BUDGET="${PREPUSH_LANE_BUDGET:-1800}"

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
# san — strip control chars from anything a member/receipt field interpolated
# into a receipt line (branch file names are pushed-branch-controlled bytes;
# a raw control char could overprint or forge receipt lines for a human
# reader — the exit code stays authoritative regardless).
san() { printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]'; }
# member_line <name> <tier> <verdict> <seconds> [extra] — the 5th arg is a
# raw `key=value` field (reason=no-trigger, trigger=input-moved:x, …), not a
# bare reason string.
member_line() {
  printf 'RATCHET_LANE member=%s tier=%s verdict=%s seconds=%s%s\n' \
    "$(san "$1")" "$2" "$3" "$4" "${5:+ $(san "$5")}"
}

VERDICT_EMITTED=0
# verdict_out <fields> — the single terminal-line emitter so the EXIT trap can
# tell a scored exit from an unguarded one (set -e abort, assert_fixture_dir
# FATAL). Every exit path must either route through this or abort().
verdict_out() { VERDICT_EMITTED=1; say "verdict=$*"; }
# abort <merge-field-or-dash> <reason> — infra aborts always carry a receipt
# line and exit 2. "-" suppresses the merge= field for mid-dispatch aborts.
abort() {
  [[ "${1:-}" == "-" ]] || say "merge=$1"
  verdict_out "ABORT members=${members_run:-0} red=${members_red:-0} seconds=$(( $(date +%s) - T0 )) reason=${2:-abort} hint='members: bash scripts/pre-push-ratchet-lane.sh --print-members'"
  exit 2
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
  abort "skipped:not-a-repo" "not-a-repo"
fi
assert_fixture_dir "$REPO_ROOT"

# A bound is optional on hosts without coreutils `timeout` — stock macOS ships
# neither `timeout` nor `gtimeout`, and a missing bound must never read as a
# member failure. The bare fallback is the documented portability arm; it is
# disclosed on the receipt (`bounds=unbounded`) rather than silent.
TO_BIN=""
if command -v timeout >/dev/null 2>&1; then TO_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TO_BIN="gtimeout"
fi

# Members are dispatched by argv; a missing interpreter must not read as a
# ratchet RED — it is a SKIP (reason=no-python3), not a violation.
HAVE_PY3=1
command -v python3 >/dev/null 2>&1 || HAVE_PY3=0

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
  verdict_out "PASS members=0 red=0 seconds=$(( $(date +%s) - T0 )) merge=skipped:no-diff"
  exit 0
fi

# --- Scratch worktree --------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/lib/scratch-root.sh" ]]; then
  abort "skipped:no-scratch-lib" "no-scratch-lib"
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/scratch-root.sh"
LANE_BASE=""
if ! LANE_BASE="$(soleur_scratch_root)"; then
  abort "skipped:no-scratch-root" "no-scratch-root"
fi
PARENT=""
if ! PARENT="$(mktemp -d "$LANE_BASE/prepush-lane.XXXXXXXX")"; then
  abort "skipped:mktemp-failed" "mktemp"
fi
SCRATCH=""
SCRATCH_OWNED=0
cleanup() {
  # Only ever remove a worktree the lane itself created — an env-pinned
  # PREPUSH_LANE_WORKTREE_DIR that add failed on may be a pre-existing
  # registered worktree of this repo; removing it would destroy that state.
  if [[ "${SCRATCH_OWNED:-0}" == 1 && -n "${SCRATCH:-}" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$SCRATCH" >/dev/null 2>&1 || true
    # --expire=now: default prune expiry (~3mo) never reaps a fresh orphaned
    # registration — the crash-left case this line exists for.
    git -C "$REPO_ROOT" worktree prune --expire now >/dev/null 2>&1 || true
  fi
  if [[ -n "${PARENT:-}" && -d "${PARENT:-}" ]]; then
    assert_fixture_dir "$PARENT"
    rm -rf "$PARENT"
  fi
  # Any exit that reached the trap without a verdict (set -e abort, an
  # assert_fixture_dir FATAL) still owes the caller a terminal line —
  # exit 2 is the documented "infra abort" and must be readable as one.
  if [[ "${VERDICT_EMITTED:-0}" != 1 ]]; then
    say "verdict=ABORT members=0 red=0 seconds=$(( $(date +%s) - T0 )) reason=unguarded-exit"
  fi
}
# Signal traps EXIT rather than merely cleaning: a trapped INT/TERM/HUP must not
# resume dispatch — cleanup already deleted $PARENT, so every later member log
# write would fail into a deleted dir and read as cascading false-REDs.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT
# Guard the scratch parent for every write below — the operand-provenance
# ratchet reads only executed statements, and $PARENT chains to a sourced
# helper the corpus cannot resolve.
assert_fixture_dir "$PARENT"

if [[ -n "${PREPUSH_LANE_WORKTREE_DIR:-}" ]]; then
  SCRATCH="$PREPUSH_LANE_WORKTREE_DIR"
else
  SCRATCH="$PARENT/scratch"
fi
# The seam is the one filesystem operand that bypasses assert_fixture_dir by
# construction — an env value could be relative/`..`/synthetic; assert it like
# every other chained dir.
assert_fixture_dir "$SCRATCH"
add_rc=0
run_bounded "$MEMBER_TIMEOUT" \
  git -C "$REPO_ROOT" -c core.hooksPath=/dev/null worktree add --detach "$SCRATCH" HEAD \
  >/dev/null 2>&1 || add_rc=$?
if (( add_rc != 0 )); then
  abort "skipped:worktree-add-failed" "worktree-add"
fi
SCRATCH_OWNED=1
# TMPDIR pin — disk-backed (the non-tmpfs CI shape) but OUTSIDE the scratch
# worktree: a member's mktemp dir must not resolve `git rev-parse` against the
# lane's scratch repo — the first dogfood run showed fixture-dir-operand-assert
# losing its non-repository control exactly that way.
LANE_TMP="$PARENT/lane-tmp"
mkdir -p "$LANE_TMP" || abort "skipped:lane-tmp-failed" "lane-tmp"

# Shared env -i allowlist for EVERY spawned process — member dispatch, the
# branch tier, and the enumerate probes. Ambient vars must not reach a suite:
# GIT_SSH_COMMAND/GIT_ASKPASS/GIT_EXTERNAL_DIFF/GIT_CONFIG_* are exec vectors,
# BASH_ENV/LD_* preload code, GH_TOKEN/*_TOKEN/*_SECRET/*_API_KEY and *_proxy
# leak credentials into member environments, and runner-control vars
# (TEST_GROUP, SCRIPTS_SHARD, SOLEUR_SUBAGENT, SOLEUR_TEST_FORCE_ALL,
# SOLEUR_INCIDENT_SKIP, SOLEUR_ALLOW_FULL_GATE) corrupt the enumerate probes
# (TEST_GROUP env OVERRIDES the positional group arg in test-all.sh).
LANE_ENV=(env -i
  PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}"
  TMPDIR="$LANE_TMP" LANG="${LANG:-C.UTF-8}" USER="${USER:-lane}"
  LOGNAME="${LOGNAME:-lane}" SHELL="${SHELL:-/bin/sh}" TERM="${TERM:-dumb}"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null)

# Diff manifests (computed BEFORE the in-scratch merge, so they describe the
# branch as pushed — the merged scratch is only where members execute). Guard
# each manifest var: the operand ratchet reads the chain's END var (LANE_BASE
# resolves through a sourced call), so guarding $PARENT alone misses them.
BRANCH_ALL="$PARENT/branch-all.txt"     # all changes incl. deletions (triggers)
MAIN_CHANGES="$PARENT/main-changes.txt" # what arrived on main since the fork
assert_fixture_dir "$BRANCH_ALL"
assert_fixture_dir "$MAIN_CHANGES"
if [[ -n "$BASE" ]]; then
  git -C "$REPO_ROOT" diff --name-only "$BASE" HEAD > "$BRANCH_ALL" \
    || abort - "branch-diff-failed"
  git -C "$REPO_ROOT" diff --name-only "$BASE" origin/main > "$MAIN_CHANGES" \
    || abort - "main-diff-failed"
else
  : > "$BRANCH_ALL"; : > "$MAIN_CHANGES"
fi

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
  # (b) a branch-touched suite gaining a knowledge-base/ read — the F2 shape.
  # Narrowed on BOTH axes (design-review P1): is_suite_file only — a markdown or
  # data file cannot register a consumer, and grepping every touched file's
  # content fired on ~73% of commits, collapsing the 1-2 min budget into the
  # 4-11 min member's cadence — and ADDED lines only, since a kb/ read that
  # already existed at the merge base is already in the consumer baseline.
  # The added-lines filter must grep a FILE, never `producer | grep -q`: under
  # pipefail, `grep -q` exits on first match and SIGPIPE kills the upstream
  # greps (rc 141), so an early match on a large diff reads as no-match —
  # the F2 trigger would silently miss on exactly the diffs it exists to catch.
  while IFS= read -r bf; do
    is_suite_file "$bf" || continue
    [[ -f "$SCRATCH/$bf" ]] || continue
    if ! git -C "$REPO_ROOT" diff -U0 "$BASE" HEAD -- "$bf" > "$PARENT/bdiff.txt"; then
      printf 'kb-diff-error:%s' "$bf"; return 0
    fi
    { grep '^+' "$PARENT/bdiff.txt" || true; } \
      | { grep -v '^+++' || true; } > "$PARENT/added-lines.txt"
    if grep -qF 'knowledge-base/' "$PARENT/added-lines.txt"; then
      printf 'kb-reading-suite:%s' "$bf"; return 0
    fi
  done < "$BRANCH_ALL"
  # (c) a new scripts/*.baseline.txt in the merge delta (either side). A diff
  # failure cannot certify "no new baseline" — fail TOWARD coverage and fire.
  if ! git -C "$REPO_ROOT" diff --name-status "$BASE" origin/main \
      -- 'scripts/*.baseline.txt' > "$PARENT/main-baselines.txt"; then
    printf 'baseline-diff-error:main'; return 0
  fi
  if ! git -C "$REPO_ROOT" diff --name-status "$BASE" HEAD \
      -- 'scripts/*.baseline.txt' > "$PARENT/branch-baselines.txt"; then
    printf 'baseline-diff-error:branch'; return 0
  fi
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
  run_bounded "$MEMBER_TIMEOUT" \
    git -C "$SCRATCH" -c user.name=ratchet-lane -c user.email=ratchet-lane@localhost \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      merge --no-edit --quiet origin/main || merge_rc=$?
  if (( merge_rc != 0 )); then
    say "merge=conflict"
    verdict_out "MERGE_CONFLICT members=0 red=0 seconds=$(( $(date +%s) - T0 )) hint='merge origin/main into the branch first'"
    exit 2
  fi
fi
# __MERGE_BLOCK_END__
say "merge=$MERGE_STATE base=${BASE:-none}"

# retain_log <name> <log> — non-PASS member logs survive the scratch cleanup
# under the repo's shared gitdir so a blocked push can be diagnosed post-hoc;
# tail -5 alone cannot name a long violation list.
LOG_RETAIN=""
retain_log() {
  if [[ -z "$LOG_RETAIN" ]]; then
    LOG_RETAIN="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)/ratchet-lane"
    if [[ -z "$LOG_RETAIN" || "$LOG_RETAIN" == "/ratchet-lane" || "$LOG_RETAIN" != /* ]]; then
      LOG_RETAIN=""; return 0
    fi
    # Guard before mkdir/cp — the operand ratchet reads the chain's end var.
    assert_fixture_dir "$LOG_RETAIN"
  fi
  mkdir -p "$LOG_RETAIN" 2>/dev/null || return 0
  local _dest
  _dest="$LOG_RETAIN/$(date +%Y%m%d-%H%M%S)-$(san "$1").log"
  cp "$2" "$_dest" 2>/dev/null && say "member=$(san "$1") retained-log=$_dest"
}

# __DISPATCH_BLOCK_BEGIN__
members_run=0; members_red=0; budget_stop=0
[[ -n "$TO_BIN" ]] || say "bounds=unbounded reason=no-timeout-binary"
for row in ${MEMBERS[@]+"${MEMBERS[@]}"}; do
  IFS='|' read -r name tier argv <<<"$row"
  [[ -z "$name" ]] && continue
  if (( $(date +%s) - T0 >= LANE_BUDGET )); then
    say "budget=exceeded cap=${LANE_BUDGET}s — remaining members not dispatched"
    budget_stop=1
    break
  fi
  timeout_n="$MEMBER_TIMEOUT"; _reason=""
  case "$tier" in
    conditional)
      # conditional_reason runs in a capture subshell — an internal
      # assert_fixture_dir FATAL exits it with rc 2, which must NOT launder
      # into a benign no-trigger skip. Distinguish the codes.
      _crc=0
      _reason="$(conditional_reason)" || _crc=$?
      if (( _crc == 2 )); then
        abort - "trigger-guard"
      elif (( _crc != 0 )); then
        member_line "$name" "$tier" SKIP 0 "reason=no-trigger"
        continue
      fi
      timeout_n="$COND_TIMEOUT"
      ;;
    fast) ;;
    *) member_line "$name" "$tier" SKIP 0 "reason=unknown-tier"; continue ;;
  esac
  if [[ "$argv" == *__BASE__* && -z "$BASE" ]]; then
    member_line "$name" "$tier" SKIP 0 "reason=no-merge-base"
    continue
  fi
  argv="${argv//__BASE__/$BASE}"
  if [[ "$argv" == python3\ * ]] && (( HAVE_PY3 == 0 )); then
    member_line "$name" "$tier" SKIP 0 "reason=no-python3"
    continue
  fi
  mlog="$PARENT/member-${name}.log"
  assert_fixture_dir "$mlog"
  mrc=0
  _s="$(date +%s)"
  ( cd "$SCRATCH" && run_bounded "$timeout_n" "${LANE_ENV[@]}" bash -c "$argv" ) \
    >"$mlog" 2>&1 || mrc=$?
  _e="$(date +%s)"
  case "$mrc" in
    0) mv=PASS ;;
    124|137) mv=TIMEOUT ;;
    *) mv=RED ;;
  esac
  member_line "$name" "$tier" "$mv" "$((_e - _s))" "${_reason:+trigger=$_reason}"
  if [[ "$mv" != "PASS" ]]; then
    retain_log "$name" "$mlog"
    tail -5 "$mlog" | LC_ALL=C sed 's/[^[:print:]]/?/g; s/^/    /'
  fi
  members_run=$((members_run + 1))
  [[ "$mv" == "PASS" ]] || members_red=$((members_red + 1))
done

# --- Branch-touched suite tier ------------------------------------------------------
# Suite files the branch diff touched run inside the deps-free scratch under an
# env -i allowlist and a disk-backed TMPDIR — the vitest-absent, non-tmpfs CI
# shape (F4/F5). Three gates keep this tier honest (design-pass findings):
#   * dedup — a file already evaluated as a member does not run twice;
#   * group — only the `scripts` TEST_GROUP is deps-free. Suites registered
#     under bun/webplat/infra would false-RED on missing node_modules (measured:
#     apps/cla-evidence/test/ccla-add.test.sh exits 2 without them) and
#     scripts-heavy members would die on their own timeout — both classes are a
#     blocked push for a non-defect, so they SKIP with a reason. Membership
#     comes from the runner's own --enumerate-commands against the MERGED
#     scratch, so a suite's group is read where the system's own matcher keeps
#     it — never restated here; an enumerate failure disables skipping entirely
#     (fail toward coverage, receipt noted);
#   * cap + per-member bound + the whole-lane budget — the tier's cost stays
#     bounded even on a refactor-sized diff.
declare -A MEMBER_FILES=()
for row in ${MEMBERS[@]+"${MEMBERS[@]}"}; do
  IFS='|' read -r _mname _mtier _margv <<<"$row"
  for tok in $_margv; do
    case "$tok" in
      */*.test.sh|*/test_*.sh|*/test-*.sh) MEMBER_FILES["$tok"]=1 ;;
    esac
  done
done

# The enumerate probes run in the merged scratch under the same env -i
# allowlist — an ambient TEST_GROUP would override the positional group arg in
# test-all.sh and silently enumerate the wrong group.
declare -A NONSCRIPTS_FILES=() SCRIPTS_FILES=()
MEMBERSHIP_OK=1
if [[ -f "$SCRATCH/scripts/test-all.sh" ]]; then
  # `scripts` builds the runnable-lib set (SUITE_GLOBS registers real suites
  # under lib/ dirs — is_suite_file's */lib/* rejection cannot tell them from
  # sourced helpers); the deps/heavy groups build the skip set.
  for _grp in scripts bun webplat infra scripts-heavy; do
    _enum=""
    if ! _enum="$(cd "$SCRATCH" && run_bounded 90 \
        "${LANE_ENV[@]}" bash scripts/test-all.sh --enumerate-commands "$_grp" 2>/dev/null)"; then
      MEMBERSHIP_OK=0
      break
    fi
    while IFS= read -r _eline; do
      # Exact SUITE_COMMAND<TAB> records only — SUITE_COMMAND_DECLINED rows
      # carry a free-text rerun string, not a suite path.
      [[ "$_eline" == "SUITE_COMMAND"$'\t'* ]] || continue
      for tok in $_eline; do
        case "$tok" in
          */*.test.sh|*/test_*.sh|*/test-*.sh)
            case "$_grp" in
              scripts) SCRIPTS_FILES["$tok"]=1 ;;
              *) NONSCRIPTS_FILES["$tok"]=1 ;;
            esac
            ;;
        esac
      done
    done <<< "$_enum"
  done
else
  MEMBERSHIP_OK=0
fi
[[ "$MEMBERSHIP_OK" == 1 ]] || say "membership-probe=degraded reason=enumerate-failed skips=disabled"

_br_count=0
while IFS= read -r bf; do
  if ! is_suite_file "$bf"; then
    # Suite-shaped but rejected by is_suite_file. The runner (scripts/
    # test-all.sh) is never a suite. A lib/ file is only dispatchable when the
    # runner itself enumerates it under the deps-free `scripts` group —
    # unenumerated lib paths are likely sourced helpers, not suites; either
    # way the exclusion gets a receipt rather than a silent drop.
    case "${bf##*/}" in
      *.test.sh|test_*.sh|test-*.sh)
        _bname0="${bf##*/}"; _bname0="${_bname0%.sh}"
        if [[ "$MEMBERSHIP_OK" == 1 && "$bf" == */lib/* ]]; then
          if [[ -n "${SCRIPTS_FILES[$bf]:-}" ]]; then
            : # registered lib suite — dispatch below like any other suite
          elif [[ -n "${NONSCRIPTS_FILES[$bf]:-}" ]]; then
            member_line "$_bname0" "branch" SKIP 0 "reason=needs-deps"; continue
          else
            member_line "$_bname0" "branch" SKIP 0 "reason=lib-not-registered"; continue
          fi
        else
          member_line "$_bname0" "branch" SKIP 0 "reason=not-a-suite"; continue
        fi
        ;;
      *) continue ;;
    esac
  fi
  [[ -f "$SCRATCH/$bf" ]] || continue
  bname="${bf##*/}"; bname="${bname%.sh}"
  bslug="${bf//\//_}"; bslug="${bslug//./_}"
  if [[ -n "${MEMBER_FILES[$bf]:-}" ]]; then
    member_line "$bname" "branch" SKIP 0 "reason=in-member-table"
    continue
  fi
  if [[ "$MEMBERSHIP_OK" == 1 && -n "${NONSCRIPTS_FILES[$bf]:-}" ]]; then
    member_line "$bname" "branch" SKIP 0 "reason=needs-deps"
    continue
  fi
  if (( _br_count >= BRANCH_TIER_CAP )); then
    say "branch-tier truncated at cap=$BRANCH_TIER_CAP"
    break
  fi
  if (( $(date +%s) - T0 >= LANE_BUDGET )); then
    say "budget=exceeded cap=${LANE_BUDGET}s — remaining branch members not dispatched"
    budget_stop=1
    break
  fi
  _br_count=$((_br_count + 1))
  mlog="$PARENT/member-branch-${bslug}.log"
  assert_fixture_dir "$mlog"
  mrc=0
  _s="$(date +%s)"
  ( cd "$SCRATCH" && run_bounded "$MEMBER_TIMEOUT" "${LANE_ENV[@]}" bash -- "$bf" ) \
    >"$mlog" 2>&1 || mrc=$?
  _e="$(date +%s)"
  case "$mrc" in
    0) mv=PASS ;;
    124|137) mv=TIMEOUT ;;
    *) mv=RED ;;
  esac
  member_line "$bname" "branch" "$mv" "$((_e - _s))"
  if [[ "$mv" != "PASS" ]]; then
    retain_log "$bname" "$mlog"
    tail -5 "$mlog" | LC_ALL=C sed 's/[^[:print:]]/?/g; s/^/    /'
  fi
  members_run=$((members_run + 1))
  [[ "$mv" == "PASS" ]] || members_red=$((members_red + 1))
done < "$BRANCH_ALL"
# __DISPATCH_BLOCK_END__

# Dispatch vacuity: a lane that measured nothing cannot pass — an empty table
# and an all-SKIP table are the same non-coverage shape. A budget-stopped lane
# likewise evaluated only a prefix — ABORT, not PASS on what ran.
if (( budget_stop == 1 )); then
  verdict_out "ABORT members=$members_run red=$members_red seconds=$(( $(date +%s) - T0 )) reason=budget-exceeded"
  exit 2
fi
if (( members_run == 0 )); then
  verdict_out "RED members=0 red=0 seconds=$(( $(date +%s) - T0 )) dispatch=nothing-ran merge=$MERGE_STATE"
  exit 1
fi
if (( members_red > 0 )); then
  verdict_out "RED members=$members_run red=$members_red seconds=$(( $(date +%s) - T0 )) merge=$MERGE_STATE hint='logs: retained under .git/ratchet-lane/ · members: bash scripts/pre-push-ratchet-lane.sh --print-members · bypass: git push --no-verify'"
  exit 1
fi
verdict_out "PASS members=$members_run red=0 seconds=$(( $(date +%s) - T0 )) merge=$MERGE_STATE"
exit 0
