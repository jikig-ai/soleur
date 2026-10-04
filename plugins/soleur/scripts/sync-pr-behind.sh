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
#   Before 1. Merge queue (#9454): a PR that is IN the merge queue is skipped before any
#      git work — nothing merged or pushed: `--step` prints `kind=queued rc=11` and exits 11
#      (the fences' uncounted sync_noop arm), the standalone loop `kind=queued rc=0`, exit 0. A push to a
#      queued PR dequeues it, and the queue itself keeps the entry current. The read is
#      queue_state_read() below, retried once on a transient failure, and is also the one
#      shared read: `sync-pr-behind.sh <pr> --queue-state` prints it (the pre-merge hook and
#      monitor-pr-checks.sh call that). It lives in THIS file, not a sibling, because the Phase 7
#      fences run a frozen snapshot of this script that has no sibling files. A read that still
#      fails is `kind=gh` (exit 4), NEVER "not queued" — that would push to a queued PR.
#      A queued sighting leaves a marker in the git dir. The first later read that finds the
#      PR OPEN, out of the queue and auto-merge DISARMED is a dequeue (a failed merge_group
#      run, or a removal): `kind=dequeued rc=13`, exit 13, nothing merged or pushed — a
#      sync cannot help because nothing is armed to merge it; the line carries the recovery.
#      Seen only on a tick that reaches this script (the fences call it while BEHIND).
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
# ${x,,}, no associative arrays, no date; `timeout` only when present and `sleep` only between
# queue-read retries (the Phase 7 fixture shadows date and sleep in the PARENT only and sets
# PR_QUEUE_RETRY_SLEEP=0 for the child).
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
       sync-pr-behind.sh <pr-number> --queue-state
       sync-pr-behind.sh --help

  Run from the PR's feature worktree, on its branch: the script syncs $PWD's branch.

  --step            one sync attempt on the current branch (merge origin/main, push);
                    its only gh call is the merge-queue read — the caller already read
                    mergeStateStatus. A PR in the merge queue is skipped (a push would
                    dequeue it)
  --queue-state     read-only: print `<queued|not_queued> <OPEN|CLOSED|MERGED> <armed|disarmed>` (the merge
                    queue state; no git, no push, no worktree needed) and exit 0, or `kind=gh` exit 4.
                    Env: PR_QUEUE_TIMEOUT (s, default 10), PR_QUEUE_ATTEMPTS (default 1),
                    PR_QUEUE_RETRY_SLEEP (s, default 2), PR_QUEUE_REPO=OWNER/REPO (else the cwd repo)
  --max-attempts N  standalone loop (N = 1..999): check the PR's head branch is the
                    current branch, read state, sync while BEHIND, up to N times

exit codes (each non-zero exit prints one tagged `kind=<k> rc=<n>` line on stdout):
  0   synced and pushed (--step), or nothing to do / BEHIND resolved (standalone), or
      the PR is in the merge queue — standalone only: skipped, nothing merged or pushed
      (kind=queued; --step exits 11 for it, see below)
  2   usage error or unknown argument (kind=usage)
  3   not inside a work tree (kind=not_worktree)
  4   a gh call failed: gh pr view (standalone) or the merge-queue read, after one retry (kind=gh)
  5   fetching main failed (kind=fetch)
  6   merge conflict, or merge not committed (hook) — the merge was aborted (kind=merge)
  7   git push failed — the local merge commit is retained (kind=push)
  8   still BEHIND after N attempts (standalone, kind=exhausted); after a kind=pushed
      line the push landed and GitHub has not recomputed yet — re-arm the poll
  9   a merge/rebase/cherry-pick/revert this script did not start, or detached HEAD
      (kind=merge_in_progress or detached_head)
  10  git merge refused to start (nothing to abort, kind=merge_refused)
  11  origin/main already merged and pushed — nothing to push (kind=noop); GitHub's
      mergeStateStatus lags the ref. Also --step on a PR in the merge queue: skipped,
      nothing merged or pushed (kind=queued). Fences keep polling; standalone exits so the
      caller re-runs once GitHub recomputes the state
  12  the current branch is not the PR's head branch (standalone, kind=wrong_branch)
  13  the PR was in the merge queue, then left it unmerged with auto-merge disarmed (a failed
      merge_group run or a removal; kind=dequeued) — nothing merged or pushed; the line has the recovery
USAGE
}

tag() { local k="$1" r="$2"; shift 2; echo "[pr-behind-sync] kind=$k rc=$r — $*"; }
usage_err() { tag usage 2 "$1"; usage; exit 2; }

PR=""; MODE=loop; MAX_ATTEMPTS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --step) MODE=step ;;
    --queue-state) MODE=queue_state ;;
    --max-attempts)
      [[ "${2:-}" =~ ^[1-9][0-9]{0,2}$ ]] || usage_err "--max-attempts takes 1..999, got '${2:-}'"
      MAX_ATTEMPTS="$2"; shift ;;
    *)
      if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then PR="$1"; else usage_err "unexpected argument '$1'"; fi ;;
  esac
  shift
done
[[ -n "$PR" ]] || usage_err "missing <pr-number>"
if [[ "$MODE" != loop && "$MAX_ATTEMPTS" != 1 ]]; then usage_err "--step and --queue-state take no --max-attempts"; fi

# queue_state_read — THE ONE copy of the merge-queue GraphQL read and its jq verdict program (the
# pre-merge hook and monitor-pr-checks.sh reach it through --queue-state). Sets QS_OUT to
# `<queued|not_queued> <state> <armed|disarmed>` (`-` for a field the answer lacks) and returns 0, or
# sets QS_CAUSE (timeout | gh_error | unparseable) and QS_DETAIL and returns 1: a failed read is
# NEVER a verdict. `{owner}` / `{repo}` are filled by gh from the cwd repository (PR_QUEUE_REPO=o/r
# overrides). Both queue fields are read (an entry exists iff isInMergeQueue); the call runs under
# `bash -c` so a gh that is a shell function (an exported test mock) is still reached, and under
# timeout/gtimeout when present so a hung call cannot hang a poll tick or a hook.
queue_state_read() {
  local to_s="${PR_QUEUE_TIMEOUT:-10}" attempts="${PR_QUEUE_ATTEMPTS:-1}" nap="${PR_QUEUE_RETRY_SLEEP:-2}"
  local owner='{owner}' repo='{repo}' n=0 rc out errf query jqp
  [[ "$to_s" =~ ^[1-9][0-9]{0,3}$ ]] || to_s=10
  [[ "$attempts" =~ ^[1-9]$ ]] || attempts=1
  [[ "$nap" =~ ^[0-9]{1,3}$ ]] || nap=2
  if [[ "${PR_QUEUE_REPO:-}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then owner="${PR_QUEUE_REPO%%/*}"; repo="${PR_QUEUE_REPO#*/}"; fi
  local to=()
  if command -v timeout >/dev/null 2>&1; then to=(timeout -k 2 "$to_s")
  elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout -k 2 "$to_s"); fi
  # shellcheck disable=SC2016  # the GraphQL `$owner`/`$name`/`$number` are variables of the query, not shell
  query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { isInMergeQueue mergeQueueEntry { state } state autoMergeRequest { enabledAt } }
  }
}'
  jqp='.data.repository.pullRequest
  | if . == null then "unreadable"
    else (if .isInMergeQueue == true or .mergeQueueEntry != null then "queued"
          elif .isInMergeQueue == false then "not_queued"
          else "unreadable" end)
         + " " + (.state // "-")
         + " " + (if has("autoMergeRequest") then (if .autoMergeRequest == null then "disarmed" else "armed" end) else "-" end)
    end'
  errf="$(mktemp)" || { QS_CAUSE=gh_error; QS_DETAIL="mktemp failed"; return 1; }
  while [[ "$n" -lt "$attempts" ]]; do
    n=$((n + 1)); rc=0
    # shellcheck disable=SC2016  # $1..$5 are bash -c's own positional parameters, not this shell's
    out="$(${to[@]+"${to[@]}"} bash -c 'gh api graphql -F owner="$4" -F name="$5" -F number="$1" -f query="$2" --jq "$3"' \
            _ "$PR" "$query" "$jqp" "$owner" "$repo" 2>"$errf")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      case "$rc" in 124|137|143) QS_CAUSE=timeout ;; *) QS_CAUSE=gh_error ;; esac
      QS_DETAIL="rc=$rc $(head -c 200 "$errf" | tr '\n' ' ')"
    else
      out="${out%%$'\n'*}"
      case "${out%% *}" in
        queued|not_queued) rm -f "$errf"; QS_OUT="$out"; return 0 ;;
        *) QS_CAUSE=unparseable; QS_DETAIL="read returned '${out:0:80}' (want queued or not_queued)" ;;
      esac
    fi
    if [[ "$n" -lt "$attempts" ]]; then sleep "$nap"; fi
  done
  rm -f "$errf"
  return 1
}

# --queue-state: the shared read, nothing else — no git, no worktree, no push. Handled before the
# worktree check so a caller outside a work tree (monitor-pr-checks.sh --repo) can use it.
if [[ "$MODE" == queue_state ]]; then
  QS_OUT=""; QS_CAUSE=""; QS_DETAIL=""
  if queue_state_read; then printf '%s\n' "$QS_OUT"; exit 0; fi
  tag gh 4 "merge queue read failed (cause=$QS_CAUSE ${QS_DETAIL:0:200}) — queue state unknown"
  exit 4
fi

# No `cd`: this script syncs the CALLER's worktree ($PWD). Resolving it from BASH_SOURCE
# synced the wrong repository (#8428) — pinned by the "SUT outside repo" test case.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tag not_worktree 3 "not inside a work tree — cd to the PR worktree (.worktrees/<branch>) and re-run"
  exit 3
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

# Merge-queue gate (#9454). Exits 11 in --step mode, 0 in the loop (kind=queued) when the PR is in the merge queue,
# 13 (kind=dequeued) when it was seen queued and has since left the queue unmerged, and
# 4 (kind=gh) when the read fails or answers anything but queued / not_queued; returns
# normally only on a positive "not queued". The read is queue_state_read() above, which owns the query
# (both queue fields, so an entry exists iff isInMergeQueue) and the verdict program; two
# attempts ride out a transient 5xx or rate limit, so the fence needs no arm of its own.
queue_gate() {
  local verdict st am marker git_dir q
  git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
  marker="$git_dir/pr-queue-seen-$PR"
  QS_OUT=""; QS_CAUSE=""; QS_DETAIL=""
  if ! PR_QUEUE_ATTEMPTS=2 queue_state_read; then
    tag gh 4 "merge queue read failed (cause=$QS_CAUSE ${QS_DETAIL:0:200}) — not syncing; a push to a queued PR would dequeue it"
    exit 4
  fi
  q="$QS_OUT"
  read -r verdict st am <<<"$q"
  case "$verdict" in
    not_queued)
      [[ -n "$git_dir" && -f "$marker" ]] || return 0
      rm -f "$marker"
      case "$st $am" in
        "OPEN disarmed")
          tag dequeued 13 "PR #$PR was in the merge queue and is no longer (OPEN, auto-merge disarmed): a failed merge_group run or a removal — NOT syncing, nothing is armed to merge it. Recover: (1) read why: gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith(\"gh-readonly-queue/main/pr-$PR-\"))' then gh run view <databaseId> --log-failed; (2) fix on the branch, git merge origin/main, push; (3) re-arm once: gh pr merge $PR --squash --auto. A second dequeue: stop and report it."
          exit 13 ;;
        "MERGED "*|"CLOSED "*)
          tag noop 11 "PR #$PR is $st — it left the queue; nothing to sync"
          exit 11 ;;
      esac
      return 0 ;;   # armed or unknown: not a dequeue; sync as before
    queued)
      [[ -n "$git_dir" ]] && { touch "$marker" 2>/dev/null || true; }
      # --step exits 11 (the fence's uncounted no-op arm: nothing was pushed, so the ship and
      # merge-pr fences must not count a sync); the standalone loop exits 0.
      if [[ "$MODE" == step ]]; then
        tag queued 11 "PR #$PR is in the merge queue; sync skipped (a push would dequeue it) — keep polling for MERGED or removal from the queue"
        exit 11
      fi
      tag queued 0 "PR #$PR is in the merge queue; sync skipped (a push would dequeue it) — keep polling for MERGED or removal from the queue"
      exit 0 ;;
    *)
      tag gh 4 "merge queue read returned '${q:0:80}' (want queued or not_queued) — not syncing; a push to a queued PR would dequeue it"
      exit 4 ;;
  esac
}

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
      if [[ -n "$conflicted" ]]; then
        echo "Manual conflict resolution required on $BRANCH. Next: git merge origin/main, resolve, commit, push, then re-arm the poll."
      else
        echo "No conflict on $BRANCH. Next: run git merge origin/main and read the pre-merge-commit hook's output; fix what it reports, commit, push, then re-arm the poll."
      fi
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
    tag noop 11 "origin/main is already merged into $BRANCH and pushed; nothing to push. GitHub's mergeStateStatus lags — keep polling."
    return 11
  fi

  rc=0; out="$(git push 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out" | tail -2 || true; fi
  if [[ "$rc" -ne 0 ]]; then
    tag push "$rc" "git push failed after merge — auto-sync incomplete; the local merge commit is retained, nothing was aborted. Usually a concurrent push to $BRANCH: run git fetch origin $BRANCH, inspect git log --oneline HEAD...origin/$BRANCH, then git merge origin/$BRANCH (do not rebase — it would flatten the retained merge commit), push, then re-arm the poll."
    return 7
  fi
  return 0
}

if [[ "$MODE" == step ]]; then
  queue_gate
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

  # A queued PR is never synced (queue_gate exits kind=queued, or 4 on a failed read).
  queue_gate

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
      # REGENERABLE-ARTIFACT CONFLICT (ADR-235): model.likec4.json is still committed, so
      # it conflicts whenever two branches touch the .c4 sources. The resolver merges and
      # regenerates it from the MERGED sources; it fails closed (touches nothing unless it
      # committed) and never pushes. It ships beside this script; the target stays $PWD.
      # After it commits, sync_step's merge is a no-op and HEAD != @{u}, so it pushes.
      resolver="$(dirname "${BASH_SOURCE[0]}")/resolve-regenerable-conflicts.sh"
      if [[ -f "$resolver" ]] && bash "$resolver" origin/main; then
        tag regen_resolved 0 "regenerable conflict resolved — merge committed locally"
      else
        tag merge "$rc" "merge conflict — manual resolution required (merge-tree). Next: git merge origin/main, resolve, commit, push, then re-run. Conflicted paths:"
        printf '%s\n' "$mt_out" | grep '^CONFLICT ' || true
        exit 6
      fi
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
