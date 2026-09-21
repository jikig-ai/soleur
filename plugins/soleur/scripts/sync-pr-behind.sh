#!/usr/bin/env bash
# BEHIND resync — merge origin/main into the current PR branch and push.
#
# THE ONE IMPLEMENTATION of the Phase 7 BEHIND auto-sync (#8383). Three callers:
#   1. ship/SKILL.md Phase 7 poll fence      — runs `sync-pr-behind.sh <n> --step`
#   2. merge-pr/SKILL.md §5.2 mirror fence   — runs `sync-pr-behind.sh <n> --step`
#   3. standalone (Grok AwaitShell, review/SKILL.md's CONFLICTING-but-clean
#      recovery)                             — runs `sync-pr-behind.sh <n> [--max-attempts N]`
# A fix to the merge/push path is made in sync_step() below and reaches all three.
# The fences keep their own `BEHIND detected` / `auto-sync N pushed` lines and their
# counters; this script owns the attempt and reports it.
#
# What one attempt does (sync_step), and why:
#   1. Refuses to touch an operation it did not start: MERGE_HEAD, or a rebase /
#      cherry-pick / revert in progress -> kind=merge_in_progress (an unconditional
#      `--abort` there discards the operator's staged resolution — measured, #8339).
#      Detached HEAD -> kind=detached_head (git push would have no branch to update).
#   2. Fetches main with an explicit refspec (a worktree whose remote.origin.fetch does
#      not map main would otherwise merge a STALE origin/main). Failure is exit 5: the
#      poll skips and counts the attempt, and the next tick retries.
#   3. Merges origin/main with --no-edit, reading git's OWN exit status — captured
#      before any display `tail`, since `cmd | tail` returns tail's 0 (#8339). rc 1
#      with MERGE_HEAD is a conflict (or a rejecting pre-merge-commit hook) this
#      attempt started: abort, exit 6. Any other rc with MERGE_HEAD arrived during the
#      fetch window — left alone, exit 9. Non-zero without MERGE_HEAD is a refusal
#      (dirty tree, untracked overwrite): nothing to abort, exit 10. A merge that
#      moved nothing is exit 11 (GitHub's mergeStateStatus lags) — no push.
#   4. Pushes the merge commit so GitHub re-evaluates the queued auto-merge. A failure
#      is exit 7 and retains the local merge commit.
# Every tagged line is `[pr-behind-sync] kind=<k> rc=<n> — …` on STDOUT (a Monitor
# streams stdout only). rc is git's own exit status where a git command failed, else
# this script's exit code. Exit codes: see usage() / --help — the one table.
#
# Any unrecognised argument exits 2. The strictness is load-bearing: an older copy
# silently ignored unknown flags, so `--step` ran a full standalone sync and exited 0
# on "no sync needed" — which a fence would print as `pushed`. The fences refuse a
# copy whose --help does not name --step.
#
# Portability: runs on customer hosts including macOS's bash 3.2 — no mapfile, no
# ${x,,}, no associative arrays, no timeout/date/sleep (the Phase 7 fixture shadows
# date and sleep in the PARENT only).
# Preconditions: run from inside the PR feature worktree (not bare repo root).
set -euo pipefail

# git treats GIT_CURL_VERBOSE as on when merely PRESENT (even =0), and every trace knob
# can print token-bearing URLs and push result lines out of the `tail` windows below.
# Stripped once for every git call this process makes; the caller's shell is untouched.
unset GIT_CURL_VERBOSE GIT_TRACE GIT_TRACE_CURL GIT_TRACE_PACKET GIT_TRACE2 \
      GIT_TRACE2_EVENT GIT_TRACE2_PERF GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP
export GIT_TRACE_REDACT=1

usage() {
  cat <<'USAGE'
usage: sync-pr-behind.sh <pr-number> [--max-attempts N]
       sync-pr-behind.sh <pr-number> --step
       sync-pr-behind.sh --help

  --step            one sync attempt on the current branch (merge origin/main, push);
                    no gh calls — the caller already read mergeStateStatus
  --max-attempts N  standalone loop (N = 1..999): check the PR's head branch is the
                    current branch, read state, sync while BEHIND, up to N times

exit codes (each non-zero exit prints one tagged `kind=<k> rc=<n>` line on stdout):
  0   synced and pushed (--step), or nothing to do / BEHIND resolved (standalone)
  2   usage error or unknown argument (kind=usage)
  3   not inside a work tree (kind=not_worktree)
  4   gh pr view failed (standalone, kind=gh)
  5   fetching main failed (kind=fetch)
  6   merge conflict, or merge not committed (hook) — the merge was aborted (kind=merge)
  7   git push failed — the local merge commit is retained (kind=push)
  8   still BEHIND after N attempts (standalone, kind=exhausted)
  9   a merge/rebase/cherry-pick/revert this script did not start, or detached HEAD
  10  git merge refused to start (nothing to abort, kind=merge_refused)
  11  origin/main already merged and pushed — nothing to push (kind=noop); GitHub's
      mergeStateStatus lags the ref. Fences keep polling; standalone exits so the
      caller re-runs once GitHub recomputes the state
  12  the current branch is not the PR's head branch (standalone, kind=wrong_branch)
USAGE
}

tag() { local k="$1" r="$2"; shift 2; echo "[pr-behind-sync] kind=$k rc=$r — $*"; }
usage_err() { tag usage 2 "$1"; usage; exit 2; }

PR=""; MODE=loop; MAX_ATTEMPTS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --step) MODE=step ;;
    --max-attempts)
      [[ "${2:-}" =~ ^[1-9][0-9]{0,2}$ ]] || usage_err "--max-attempts takes 1..999, got '${2:-}'"
      MAX_ATTEMPTS="$2"; shift ;;
    *)
      if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then PR="$1"; else usage_err "unexpected argument '$1'"; fi ;;
  esac
  shift
done
[[ -n "$PR" ]] || usage_err "missing <pr-number>"
if [[ "$MODE" == step && "$MAX_ATTEMPTS" != 1 ]]; then usage_err "--step takes no --max-attempts"; fi

# No `cd`: this script syncs the CALLER's worktree ($PWD). Resolving it from BASH_SOURCE
# synced the wrong repository (#8428) — pinned by the "SUT outside repo" test case.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tag not_worktree 3 "not inside a work tree — cd to the PR worktree (.worktrees/<branch>) and re-run"
  exit 3
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

# One sync attempt. Returns the exit code documented in usage() and prints the tagged
# line for every non-zero outcome. Every git rc is captured with `|| rc=$?` before any
# display. Callers run it as `sync_step || rc=$?` (errexit is suspended inside); the
# `|| true` on display pipes keeps a future bare call from dying before the --abort.
sync_step() {
  local git_dir rc out before conflicted
  git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
     || [[ -n "$git_dir" && ( -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" \
           || -f "$git_dir/CHERRY_PICK_HEAD" || -f "$git_dir/REVERT_HEAD" ) ]]; then
    tag merge_in_progress 9 "a merge/rebase/cherry-pick/revert is in progress on $BRANCH; not touching it. If you did not start it (a previous poll may have died mid-sync), run git status, abort it, then re-arm the poll."
    return 9
  fi
  if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
    tag detached_head 9 "HEAD is detached; git push would have no branch to update. Check out the PR branch first — run the poll from the PR worktree."
    return 9
  fi

  rc=0; out="$(git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -2 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    tag fetch "$rc" "fetch origin main failed"
    return 5
  fi

  before="$(git rev-parse HEAD 2>/dev/null || true)"
  rc=0; out="$(git merge origin/main --no-edit 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -5 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 1 ]] && git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      # rerere.autoupdate can empty --diff-filter=U; the merge output cannot.
      conflicted="$( { git diff --name-only --diff-filter=U 2>/dev/null || true; printf '%s\n' "$out" | grep '^CONFLICT ' || true; } )"
      if [[ -n "$conflicted" ]]; then
        tag merge "$rc" "git merge origin/main failed — merge conflict, aborting sync. Conflicted paths:"
        printf '%s\n' "$conflicted"
      else
        tag merge "$rc" "git merge origin/main failed — merge not committed (hook rejected?), no conflicted paths; aborting sync."
      fi
      git merge --abort 2>&1 || echo "git merge --abort failed (rc=$?)"
      echo "Manual conflict resolution required on $BRANCH. Next: git merge origin/main, resolve, commit, push, then re-arm the poll."
      return 6
    elif git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      tag merge_in_progress "$rc" "MERGE_HEAD appeared during the sync (not started by this script); not touching it. Run git status, finish or abort it, then re-arm the poll."
      return 9
    fi
    tag merge_refused "$rc" "git merge origin/main failed — refused to start (nothing to abort; run git status to see which operation is in progress). Worktree state:"
    git status --short 2>&1 | head -20 || true
    echo "Clear the worktree state on $BRANCH shown above, then re-run the Phase 7 poll (or this script)."
    return 10
  fi

  # Nothing merged AND nothing unpushed: GitHub's BEHIND is stale. A retained merge
  # commit from an earlier failed push (HEAD != upstream) still gets pushed below.
  if [[ -n "$before" && "$(git rev-parse HEAD 2>/dev/null || true)" == "$before" \
        && "$(git rev-parse '@{u}' 2>/dev/null || true)" == "$before" ]]; then
    tag noop 0 "origin/main is already merged into $BRANCH and pushed; nothing to push. GitHub's mergeStateStatus lags — keep polling."
    return 11
  fi

  rc=0; out="$(git push 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -2 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    tag push "$rc" "git push failed after merge — auto-sync incomplete; the local merge commit is retained, nothing was aborted. Usually a concurrent push to $BRANCH: run git fetch origin $BRANCH, inspect git log --oneline HEAD...origin/$BRANCH, reconcile, then re-arm the poll."
    return 7
  fi
  return 0
}

if [[ "$MODE" == step ]]; then
  rc=0; sync_step || rc=$?
  exit "$rc"
fi

# Standalone: the PR number must name THIS branch, or the sync lands on the wrong PR.
rc=0; head_ref="$(gh pr view "$PR" --json headRefName --jq .headRefName 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "gh pr view failed: $head_ref"; exit 4; fi
if [[ "$head_ref" != "$BRANCH" ]]; then
  tag wrong_branch 12 "PR #$PR's head branch is '$head_ref' but this worktree is on '$BRANCH' — cd to that PR's worktree (or pass the right PR number); not syncing."
  exit 12
fi

attempt=0
while [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  rc=0; state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "gh pr view failed: $state_line"; exit 4; fi

  tag state 0 "PR #$PR state: $state_line (branch: $BRANCH)"

  if [[ "$state_line" == MERGED* || "$state_line" == CLOSED* ]]; then
    tag closed 0 "PR is ${state_line%% *} — no sync needed"
    exit 0
  fi

  if [[ "$state_line" != *BEHIND* && "$state_line" != *DIRTY* ]]; then
    tag not_behind 0 "BEHIND unchanged: mergeStateStatus is not BEHIND — no sync needed"
    exit 0
  fi

  tag behind 0 "BEHIND detected — auto-sync attempt ${attempt}/${MAX_ATTEMPTS}"

  # GitHub DIRTY with a clean local merge-tree is the kb-index class: the server-side
  # merge lacks the local driver. Key on merge-tree's exit code; on failure its stdout
  # carries the real conflicted paths (no merge is in progress, so --diff-filter=U is
  # empty). BEHIND needs no classification — sync_step's merge is the test.
  if [[ "$state_line" == *DIRTY* ]]; then
    rc=0; out="$(git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      tag fetch "$rc" "fetch origin main failed while classifying DIRTY"
      exit 5
    fi
    rc=0; mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      tag merge "$rc" "merge conflict — manual resolution required (merge-tree). Next: git merge origin/main, resolve, commit, push, then re-run. Conflicted paths:"
      printf '%s\n' "$mt_out" | grep '^CONFLICT ' || true
      exit 6
    fi
  fi

  rc=0; sync_step || rc=$?
  # 11 (noop) exits too: re-reading state here would see the same lagging BEHIND and
  # burn the remaining attempts on no-ops. The caller re-runs once GitHub catches up.
  if [[ "$rc" -ne 0 ]]; then exit "$rc"; fi

  tag pushed 0 "auto-sync ${attempt} pushed — CI will re-run on new SHA"

  rc=0; state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "post-push gh pr view failed: $state_line"; exit 4; fi
  tag state 0 "post-sync state: $state_line"

  if [[ "$state_line" != *BEHIND* ]]; then
    tag resolved 0 "BEHIND resolved: branch caught up to main"
    exit 0
  fi
done

tag exhausted 8 "BEHIND still present after ${MAX_ATTEMPTS} sync(s) — main may be moving faster than CI"
exit 8
