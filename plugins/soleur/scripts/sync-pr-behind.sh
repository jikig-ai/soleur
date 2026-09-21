#!/usr/bin/env bash
# BEHIND resync — merge origin/main into the current PR branch and push.
#
# THE ONE IMPLEMENTATION of the Phase 7 BEHIND auto-sync (#8383). Three callers:
#   1. ship/SKILL.md Phase 7 poll fence      — runs `sync-pr-behind.sh <n> --step`
#   2. merge-pr/SKILL.md §5.2 mirror fence   — runs `sync-pr-behind.sh <n> --step`
#   3. standalone (Grok AwaitShell, review/SKILL.md's CONFLICTING-but-clean
#      recovery)                             — runs `sync-pr-behind.sh <n> [--max-attempts N]`
# A fix to the merge/push path is made in sync_step() below and reaches all three.
# The fences keep their own `BEHIND detected` / `auto-sync N pushed` lines and the
# fetch_failures counter; this script owns the attempt and reports it.
#
# What one attempt does (sync_step), and why:
#   1. Refuses to touch an operation it did not start: MERGE_HEAD, or a rebase /
#      cherry-pick / revert in progress -> kind=merge_in_progress (an unconditional
#      `--abort` there discards the operator's staged resolution — measured, #8339).
#      Detached HEAD -> kind=detached_head (git push would have no branch to update).
#   2. Fetches origin/main. A failure (kind=fetch rc=N) is exit 5: the poll skips and
#      counts the attempt, and the next tick retries.
#   3. Merges origin/main with --no-edit, reading git's OWN exit status — captured
#      before any display `tail`, since `cmd | tail` returns tail's 0 (#8339). rc 1
#      with MERGE_HEAD is a conflict this attempt started: print the conflicted paths,
#      abort, exit 6 (kind=merge). Any other rc with MERGE_HEAD arrived during the fetch
#      window — left alone, exit 9. Non-zero without MERGE_HEAD is a refusal (dirty
#      tree, untracked overwrite, unmerged index): nothing to abort, worktree state
#      printed, exit 10 (kind=merge_refused).
#   4. Pushes the merge commit so GitHub re-evaluates the queued auto-merge. A failure
#      (kind=push rc=N) is exit 7 and retains the local merge commit. The usual cause is
#      a concurrent push (force-push, branch protection, a sibling session).
# Every tagged line is `[pr-behind-sync] kind=<k> rc=<git's rc> — …` on STDOUT: a Monitor
# streams stdout only, so a line on stderr is a line nobody sees.
#
# Usage:  sync-pr-behind.sh <pr-number> [--max-attempts N]   (standalone loop)
#         sync-pr-behind.sh <pr-number> --step               (one attempt, no gh calls)
#         sync-pr-behind.sh --help
# Any other argument exits 2. The strictness is load-bearing: an older copy of this
# script silently ignored unknown flags, so `--step` ran a full standalone sync and
# exited 0 on "no sync needed" — which a fence would print as `pushed`. The fences
# refuse a copy whose --help does not name --step.
#
# Portability: runs on customer hosts including macOS's bash 3.2 — no mapfile, no
# ${x,,}, no associative arrays, no timeout/date/sleep (the Phase 7 fixture shadows
# date and sleep in the PARENT only).
# Preconditions: run from inside the PR feature worktree (not bare repo root).
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: sync-pr-behind.sh <pr-number> [--max-attempts N]
       sync-pr-behind.sh <pr-number> --step
       sync-pr-behind.sh --help

  --step            one sync attempt on the current branch (merge origin/main, push);
                    no gh calls — the caller already read mergeStateStatus
  --max-attempts N  standalone loop: read state, sync while BEHIND, up to N times

exit codes:
  0   synced and pushed (--step), or nothing to do / BEHIND resolved (standalone)
  2   usage error or unknown argument
  3   not inside a work tree
  4   gh pr view failed (standalone)
  5   git fetch origin main failed
  6   merge conflict — the merge was aborted
  7   git push failed — the local merge commit is retained
  8   still BEHIND after N attempts (standalone)
  9   a merge/rebase/cherry-pick/revert this script did not start, or detached HEAD
  10  git merge refused to start (nothing to abort)
USAGE
}

usage_err() { usage >&2; exit 2; }

PR=""; MODE=loop; MAX_ATTEMPTS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --step) MODE=step ;;
    --max-attempts)
      [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]] || usage_err
      MAX_ATTEMPTS="$2"; shift ;;
    *)
      if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then PR="$1"; else usage_err; fi ;;
  esac
  shift
done
[[ -n "$PR" ]] || usage_err
if [[ "$MODE" == step && "$MAX_ATTEMPTS" != 1 ]]; then usage_err; fi

# NO `cd` HERE, DELIBERATELY. This script operates on the CALLER's worktree, and the
# only way to know which that is, is $PWD. An earlier revision resolved the target from
# this file's own location — `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"`
# followed by `cd "$REPO_ROOT"` — which points at whatever checkout the SCRIPT lives in,
# not the worktree the caller is in, and so discarded the precondition stated above.
#
# Measured on 2026-09-20 (PR #8428's ship round): invoked by ABSOLUTE path from
# .worktrees/docs-8392-session-errors-23-24, it refused with "HEAD is detached" while that
# worktree's `git symbolic-ref -q HEAD` returned refs/heads/docs-8392-... rc 0 — the
# detached HEAD belonged to the primary checkout it had silently relocated into. The refusal
# was the BENIGN branch: had the primary checkout been on a feature branch (the normal case),
# the merge and `git push` below would have synced and pushed an UNRELATED PR's branch,
# reporting success, with the caller's worktree untouched.
#
# Invoking by relative path from inside the worktree masked this, because
# `dirname(BASH_SOURCE)/../../..` then happens to resolve to that same worktree — which is
# also why the test suite could not see it (every case copies the SUT into its fixture repo,
# so the script's directory and the target are the same directory, a configuration production
# never has). See the SUT-outside-the-repo case in sync-pr-behind.test.sh.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[pr-behind-sync] ERROR: not inside a worktree — cd to .worktrees/feat-* first" >&2
  exit 3
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

# One sync attempt. Returns the exit code documented in usage(); prints the
# tagged line for every non-zero outcome. Every git call's rc is captured with
# `|| rc=$?` (an errexit-safe capture) before anything displays its output, and
# every display pipe ends in `|| true`: under this script's own pipefail a
# `git status | head` that outlives head is SIGPIPE 141, and a `grep` with no
# match is 1 — either would kill the script before the --abort below runs.
sync_step() {
  local git_dir rc out
  git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
     || [[ -n "$git_dir" && ( -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" \
           || -f "$git_dir/CHERRY_PICK_HEAD" || -f "$git_dir/REVERT_HEAD" ) ]]; then
    echo "[pr-behind-sync] kind=merge_in_progress — a merge/rebase/cherry-pick/revert is in progress on $BRANCH; not touching it. If you did not start it (a previous poll may have died mid-sync), run git status, abort it, then re-arm the poll."
    return 9
  fi
  if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
    echo "[pr-behind-sync] kind=detached_head — HEAD is detached; git push would have no branch to update. Check out the PR branch first — run the poll from the PR worktree."
    return 9
  fi

  rc=0; out="$(GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 git fetch origin main 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -2 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    echo "[pr-behind-sync] kind=fetch rc=$rc — fetch origin main failed"
    return 5
  fi

  rc=0; out="$(GIT_TRACE=0 git merge origin/main --no-edit 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -5 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 1 ]] && git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      echo "[pr-behind-sync] kind=merge rc=$rc — git merge origin/main failed — merge conflict, aborting sync. Conflicted paths:"
      git diff --name-only --diff-filter=U || true
      # rerere.autoupdate can empty --diff-filter=U; the merge output cannot.
      printf '%s\n' "$out" | grep '^CONFLICT ' || true
      git merge --abort 2>&1 || echo "git merge --abort failed (rc=$?)"
      echo "Manual conflict resolution required on $BRANCH."
      return 6
    elif git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      echo "[pr-behind-sync] kind=merge_in_progress rc=$rc — MERGE_HEAD appeared during the sync (not started by this script); not touching it."
      return 9
    fi
    echo "[pr-behind-sync] kind=merge_refused rc=$rc — git merge origin/main failed — refused to start (nothing to abort; run git status to see which operation is in progress). Worktree state:"
    git status --short 2>&1 | head -20 || true
    echo "Clear the worktree state on $BRANCH shown above, then re-run."
    return 10
  fi

  rc=0; out="$(GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 git push 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -2 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    echo "[pr-behind-sync] kind=push rc=$rc — git push failed after merge — auto-sync incomplete; any local merge commit from this sync is retained, nothing was aborted."
    return 7
  fi
  return 0
}

if [[ "$MODE" == step ]]; then
  rc=0; sync_step || rc=$?
  exit "$rc"
fi

attempt=0
while [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" \
    || { echo "[pr-behind-sync] gh pr view failed: $state_line"; exit 4; }

  echo "[pr-behind-sync] PR #$PR state: $state_line (branch: $BRANCH)"

  if [[ "$state_line" == MERGED* || "$state_line" == CLOSED* ]]; then
    echo "[pr-behind-sync] PR is ${state_line%% *} — no sync needed"
    exit 0
  fi

  if [[ "$state_line" != *BEHIND* && "$state_line" != *DIRTY* ]]; then
    echo "[pr-behind-sync] BEHIND unchanged: mergeStateStatus is not BEHIND — no sync needed"
    exit 0
  fi

  echo "[pr-behind-sync] BEHIND detected — auto-sync attempt ${attempt}/${MAX_ATTEMPTS}"

  # GitHub DIRTY with a clean local merge-tree is the kb-index class: the
  # server-side merge lacks the local driver. Key on merge-tree exit code;
  # on failure its stdout carries the real conflicted paths (no merge is in
  # progress, so `git diff --diff-filter=U` could only ever print nothing).
  # BEHIND needs no classification — sync_step's merge is the test.
  if [[ "$state_line" == *DIRTY* ]]; then
    rc=0; out="$(GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 git fetch origin main 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      echo "[pr-behind-sync] kind=fetch rc=$rc — fetch origin main failed while classifying DIRTY"
      exit 5
    fi
    if ! mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"; then
      echo "[pr-behind-sync] merge conflict — manual resolution required (merge-tree):"
      printf '%s\n' "$mt_out" | grep '^CONFLICT ' || true
      exit 6
    fi
  fi

  rc=0; sync_step || rc=$?
  if [[ "$rc" -ne 0 ]]; then exit "$rc"; fi

  echo "[pr-behind-sync] auto-sync ${attempt} pushed — CI will re-run on new SHA"

  state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" \
    || { echo "[pr-behind-sync] post-push gh pr view failed: $state_line"; exit 4; }
  echo "[pr-behind-sync] post-sync state: $state_line"

  if [[ "$state_line" != *BEHIND* ]]; then
    echo "[pr-behind-sync] BEHIND resolved: branch caught up to main"
    exit 0
  fi
done

echo "[pr-behind-sync] BEHIND still present after ${MAX_ATTEMPTS} sync(s) — main may be moving faster than CI"
exit 8
