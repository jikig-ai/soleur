#!/usr/bin/env bash
# BEHIND resync — merge origin/main into the current PR branch and push.
#
# THE ONE IMPLEMENTATION of the Phase 7 BEHIND auto-sync (#8383). Three callers:
#   1. ship/SKILL.md Phase 7 poll fence      — runs `sync-pr-behind.sh <n> --step --fence`
#   2. merge-pr/SKILL.md §5.2 mirror fence   — runs `sync-pr-behind.sh <n> --step --fence`
#   3. standalone (Grok AwaitShell, review/SKILL.md's CONFLICTING-but-clean
#      recovery)                             — runs `sync-pr-behind.sh <n> [--max-attempts N]`
# A fix to the merge/push path is made in sync_step() below and reaches all three. Two read-only modes serve other
# callers: `--queue-state` (the pre-merge hook, monitor-pr-checks.sh) and `--queue-wait` (the pre-merge hook).
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
#      Dequeue: a read that finds the PR OPEN, out of the queue, and either seen queued before (a
#      marker in the per-worktree git dir, left by a queued sighting) or carrying a CURRENT
#      RemovedFromMergeQueueEvent (newer than the auto-merge re-arm and than the head commit) is a
#      dequeue — a failed merge_group run, or a removal: `kind=dequeued rc=13`, exit 13, nothing merged or
#      pushed; the line has the reason and the recovery. Auto-merge state is NOT consulted (measured 2026-10-05,
#      #9482: it stays armed after a failed_checks removal and GitHub re-queues the PR; a removed PR is
#      reported whether or not it is still armed). One re-read after a short nap precedes the report, so the
#      queue's own merge landing (not queued, OPEN, about to read MERGED) is never one. A PR with neither
#      marker nor event keeps the old reading (not queued yet / re-enqueues itself after a push). A dequeue
#      reached through the marker alone is reported ONCE: --step (exit 13) and --queue-state (the `dequeued` print) each
#      consume the marker, so a PR the agent fixed and re-armed is not reported again. The
#      fences reach this on a BEHIND tick via --step and on every 5th OPEN tick via --queue-state.
#   Before 1. Armed BEHIND on a merge-queue repo (2026-10-09, PR 9839; extended to --step and the hook 2026-10-20, #9869): a PR
#      that GitHub reports BEHIND or UNKNOWN (never DIRTY), with auto-merge armed and a merge_queue rule on the PR's OWN base branch (its
#      baseRefName; #10832), is skipped before any git work — nothing fetched, merged or pushed. The window it closes is between the arm and the enqueue, where
#      queue_gate sees no entry and a push restarts every required check for nothing. ONE predicate (queue_wait_eval() below)
#      serves three callers: the standalone loop answers `kind=queue_wait` rc=0 (exit 0); a FLAGLESS `--step` answers
#      `kind=queue_wait` rc=14 (exit 14: not 11, the fences' uncounted no-op arm, which an OLD pasted fence would loop on
#      silently — 14 hits its loud sync_failed stop); `--queue-wait` prints the verdict (`queue_wait` | `proceed`) for the
#      pre-merge hook. The Phase 7 fences pass `--fence`, which skips the guard entirely: the fence owns the queue-mode
#      decision and its expiry fallback, and its legitimate sync arms (expiry, DIRTY-derived BEHIND, no merge_queue rule, a
#      failed armed read) must still sync. `--fence` is accident prevention, not authentication.
#      Interim non-main refusal (#10832): this script's sync merges origin/main, so an ARMED BEHIND or UNKNOWN PR whose base is not
#      main and has NO merge_queue rule (or whose base name is empty or outside the allowlist: `badbase` also refuses a git-legal name
#      such as `rel+1` or `topic@x`, even when that base has a queue) is not synced either: flagless `--step` and the standalone loop
#      answer `kind=gh` exit 4 with a NOT A TRANSIENT ERROR text, `--queue-wait` prints `queue_wait` (read-only; the hook would treat a
#      non-zero exit as "sync anyway"). UNKNOWN is refused at flagless `--step` and `--queue-wait` only: the standalone loop exits
#      `not_behind` for it before the guard. It does not cover `--fence`, a disarmed, DIRTY, BLOCKED or CLEAN PR, or the fences' own
#      expiry arm; a convenience interlock, not an authorization boundary. An unknown internal verdict fails CLOSED at every caller.
# Every tagged line is `[pr-behind-sync] kind=<k> rc=<n> — …` on STDOUT (a Monitor
# streams stdout only). rc is git's own exit status where a git command failed, else
# this script's exit code. Exit codes: see usage() / --help — the one table.
#
# Any unrecognised argument exits 2. The strictness is load-bearing: an older copy
# silently ignored unknown flags, so `--step` ran a full standalone sync and exited 0
# on "no sync needed" — which a fence would print as `pushed`. The fences refuse a
# copy whose --help does not name --fence (a copy that predates the queue-armed
# refusal; --fence is valid only with --step, so a copy naming it has --step).
#
# Portability: runs on customer hosts including macOS's bash 3.2 — no mapfile, no
# ${x,,}, no associative arrays, no date; `timeout` only when present and `sleep` only between
# queue-read and rules-read retries (the Phase 7 fixture shadows date and sleep in the PARENT only and sets
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
       sync-pr-behind.sh <pr-number> --step [--fence]
       sync-pr-behind.sh <pr-number> --queue-state
       sync-pr-behind.sh <pr-number> --queue-wait
       sync-pr-behind.sh --help

  Run from the PR's feature worktree, on its branch: the script syncs $PWD's branch.

  --step            one sync attempt on the current branch (merge origin/main, push).
                    A PR in the merge queue is skipped (a push would dequeue it). Without
                    --fence it also refuses an OPEN, armed PR that GitHub reports BEHIND or
                    UNKNOWN (never DIRTY) whose own base branch (baseRefName) has a merge_queue
                    rule: kind=queue_wait, exit 14, nothing fetched, merged or pushed (the queue
                    makes the PR current; a resync restarts every required check). A non-main
                    base with no merge_queue rule, or an empty or unsupported base name (also a
                    git-legal name outside the allowlist, e.g. rel+1, even if that base has a
                    queue), is refused too, while armed: kind=gh, exit 4 (this script only merges
                    origin/main; sync by hand against that base). The Phase
                    7 fence's call: the fence owns the queue-mode decision (rule, armed,
                    expiry); do not call it from your own loop
  --fence           with --step only: the Phase 7 / merge-pr poll fences pass this;
                    nobody else. It skips the queue-armed refusal (and its extra gh reads)
                    because the fence has already made that decision, expiry included
  --queue-state     print `<queued|not_queued|dequeued> <OPEN|CLOSED|MERGED> <armed|disarmed> removal=<reason|none>`
                    (the merge queue state; `dequeued` = out of the queue, OPEN, and seen queued or a current removal
                    event; no push, no worktree needed) and exit 0, or `kind=gh` exit 4 after one retry. Writes
                    nothing except to CONSUME the seen-queued marker when it prints `dequeued`: that verdict is
                    reported once, so a re-armed PR is not reported again (a current removal event needs no marker)
                    Env: PR_QUEUE_TIMEOUT (s, default 10), PR_QUEUE_ATTEMPTS (default 2 = one retry),
                    PR_QUEUE_RETRY_SLEEP (s, default 2), PR_QUEUE_REPO=OWNER/REPO (else the cwd repo);
                    the same four govern the merge-queue rule read; the pr view read honors only
                    PR_QUEUE_TIMEOUT and PR_QUEUE_REPO (one attempt, no retry)
  --queue-wait      print `queue_wait` or `proceed` and exit 0, or `kind=gh` exit 4 (a failed, hung or
                    unparseable read is never read as `proceed`). `queue_wait` = the PR is OPEN, GitHub
                    reports BEHIND or UNKNOWN (not DIRTY), auto-merge is armed and the PR's own base branch has a
                    merge_queue rule; also printed for an armed BEHIND PR whose base is not main and has no
                    merge_queue rule, or is empty or unsupported (this script only merges origin/main). One
                    pr view snapshot (state, mergeStateStatus, autoMergeRequest, baseRefName) and one rules
                    read; no GraphQL queue read, no worktree, nothing written. The pre-merge hook calls it
                    after --queue-state said not_queued. `--queue-state`: is the PR in the queue;
                    `--queue-wait`: should a sync be skipped. Env: PR_QUEUE_TIMEOUT and PR_QUEUE_REPO (the pr view read is a single attempt)
  --max-attempts N  standalone loop (N = 1..999): check the PR's head branch is the
                    current branch, read state, sync while BEHIND, up to N times

exit codes (each non-zero exit prints one tagged `kind=<k> rc=<n>` line on stdout):
  0   synced and pushed (--step), or nothing to do / BEHIND resolved (standalone), or
      the PR is in the merge queue — standalone only: skipped, nothing merged or pushed
      (kind=queued; --step exits 11 for it, see below), or BEHIND + armed on a merge-queue
      repo — standalone only: skipped, nothing fetched, merged or pushed (kind=queue_wait;
      a flagless --step exits 14 for it, see below)
  2   usage error or unknown argument (kind=usage)
  3   not inside a work tree (kind=not_worktree)
  4   a gh call failed (kind=gh): gh pr view (standalone, flagless --step, --queue-wait), the merge-queue
      read after one retry, or (armed BEHIND PR) the merge-queue rule read of the PR's base branch; also,
      for an ARMED BEHIND PR (UNKNOWN: flagless --step and --queue-wait only; the standalone loop exits
      not_behind for it first): a non-main base with no merge-queue rule, or an empty or unsupported base
      name (standalone, flagless --step; NOT A TRANSIENT ERROR, nothing merged or pushed; not under --fence)
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
  13  the PR is out of the merge queue, OPEN, and was seen queued or has a current removal event (a failed
      merge_group run or a removal; kind=dequeued; auto-merge state is not consulted) — nothing merged or
      pushed; the line has the removal reason and the recovery
  14  flagless --step on an armed BEHIND/UNKNOWN PR of a merge-queue repo (kind=queue_wait): nothing fetched,
      merged or pushed. kind=queue_wait carries rc 0 standalone and rc 14 under --step, so no consumer keys
      on the kind alone
USAGE
}

tag() { local k="$1" r="$2"; shift 2; echo "[pr-behind-sync] kind=$k rc=$r — $*"; }
usage_err() { tag usage 2 "$1"; usage; exit 2; }

PR=""; MODE=loop; MAX_ATTEMPTS=1; FENCE=0; NMODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --step) MODE=step; NMODE=$((NMODE + 1)) ;;
    --queue-state) MODE=queue_state; NMODE=$((NMODE + 1)) ;;
    --queue-wait) MODE=queue_wait; NMODE=$((NMODE + 1)) ;;
    --fence) FENCE=1 ;;
    --max-attempts)
      [[ "${2:-}" =~ ^[1-9][0-9]{0,2}$ ]] || usage_err "--max-attempts takes 1..999, got '${2:-}'"
      MAX_ATTEMPTS="$2"; shift ;;
    *)
      if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then PR="$1"; else usage_err "unexpected argument '$1'"; fi ;;
  esac
  shift
done
[[ -n "$PR" ]] || usage_err "missing <pr-number>"
# The strictness invariant: a mode-flag misuse is a usage error, never a quiet pick of one of them (an older copy that ignored
# unknown flags once printed a false "pushed").
if [[ "$NMODE" -gt 1 ]]; then usage_err "at most one of --step, --queue-state, --queue-wait"; fi
if [[ "$FENCE" == 1 && "$MODE" != step ]]; then usage_err "--fence is only valid with --step"; fi
if [[ "$MODE" != loop && "$MAX_ATTEMPTS" != 1 ]]; then usage_err "--step, --queue-state and --queue-wait take no --max-attempts"; fi

# The env bounds and the stderr sanitiser, once each (#10832; before this they were pasted into four readers and three sanitised
# strings, so a change to a bound or to the sanitiser had to be made in every copy). qb_bounds sets QB_TIMEOUT / QB_ATTEMPTS / QB_NAP
# from PR_QUEUE_TIMEOUT / PR_QUEUE_ATTEMPTS / PR_QUEUE_RETRY_SLEEP, each clamped to its documented range (anything else is the
# default); EVERY reader (queue_state_read, queue_read_settled, queue_wait_eval, qw_snapshot) calls it itself first and reads the
# QB_* globals directly. QB_* (and QW_BASE, which queue_wait_eval resets on entry) are deliberately NOT initialised here: a reader that
# skipped its own qb_bounds call would abort under `set -u` (loud) instead of silently running on defaults that ignore the env. It is
# called directly, never inside `$( )`, so the globals survive. qb_clean is a stdin filter for gh's raw stderr, which reaches a
# model-visible `kind=gh` line: only [:alnum:] and ._:/=- and space survive (ESC, CR and a forged tag line cannot); LC_ALL=C because BSD
# tr (macOS) is locale-aware. Neither helper exits. qb_match <string> <ERE> classifies under LC_ALL=C in a subshell (qw_base_path's trick):
# under a UTF-8 locale `[^[:space:]]` also excludes U+2003, U+3000 and U+2028, all legal in a ref name, so a strict answer regex run in the
# caller's locale would fail on such a base and turn a refusal into `kind=gh` rc 4, which the hook reads as "sync anyway". A match is only
# a classification: the caller then splits the answer with `read -r` (no BASH_REMATCH survives the subshell).
LOOP_BASEREF=""
qb_bounds() {
  QB_TIMEOUT="${PR_QUEUE_TIMEOUT:-10}"; QB_ATTEMPTS="${PR_QUEUE_ATTEMPTS:-2}"; QB_NAP="${PR_QUEUE_RETRY_SLEEP:-2}"
  [[ "$QB_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || QB_TIMEOUT=10
  [[ "$QB_ATTEMPTS" =~ ^[1-9]$ ]] || QB_ATTEMPTS=2
  [[ "$QB_NAP" =~ ^[0-9]{1,3}$ ]] || QB_NAP=2
}
qb_clean() { LC_ALL=C tr -c '[:alnum:] ._:/=-' '?'; }
qb_match() ( LC_ALL=C; [[ "$1" =~ $2 ]] )
# qw_base_path <base> — prints the rules-URL path segment for a PR's base branch, exit 1 for an empty or unsupported name. A branch name
# is untrusted text (the PR author edits it) that reaches an API path and a model-visible line, so only plain components of
# [A-Za-z0-9._-] joined by single `/` are accepted (no `%`, `?`, `#`, `//`, a leading `.` or `-`, `..`, `.lock`; at most 255 characters)
# and the `/` is encoded as %2F (the admin-merge-ready.sh precedent). Hand-rolled and stricter than that script's regex on purpose: this
# script has no standalone jq and targets macOS bash 3.2, and here the value is echoed. A subshell function body, so LC_ALL=C (a locale
# range like [A-Za-z] accepts accented letters) cannot leak and `exit` cannot end the script.
qw_base_path() (
  LC_ALL=C; b="${1:-}"
  [[ ${#b} -le 255 && "$b" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] || exit 1
  [[ "$b" != *..* && "$b" != *.lock && "$b" != *.lock/* ]] || exit 1
  printf '%s' "${b//\//%2F}"
)

# queue_state_read — THE ONE copy of the merge-queue GraphQL read and its jq verdict program (the
# pre-merge hook and monitor-pr-checks.sh reach it through --queue-state). Sets QS_OUT to
# `<queued|not_queued> <state> <armed|disarmed> removal=<reason|none>` (`-` for a field the answer lacks;
# removal = the newest RemovedFromMergeQueueEvent, only while it is CURRENT: newer than the auto-merge re-arm
# and than the head commit, so a fixed-and-pushed or re-armed PR reads none) and returns 0, or
# sets QS_CAUSE (timeout | gh_error | unparseable) and QS_DETAIL and returns 1: a failed read is
# NEVER a verdict. `{owner}` / `{repo}` are filled by gh from the cwd repository (PR_QUEUE_REPO=o/r
# overrides). Both queue fields are read (an entry exists iff isInMergeQueue); the call runs under
# `bash -c` so a gh that is a shell function (an exported test mock) is still reached, and under
# timeout/gtimeout when present so a hung call cannot hang a poll tick or a hook.
queue_state_read() {
  qb_bounds
  local owner='{owner}' repo='{repo}' n=0 rc out errf query jqp
  if [[ "${PR_QUEUE_REPO:-}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then owner="${PR_QUEUE_REPO%%/*}"; repo="${PR_QUEUE_REPO#*/}"; fi
  local to=()
  if command -v timeout >/dev/null 2>&1; then to=(timeout -k 2 "$QB_TIMEOUT")
  elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout -k 2 "$QB_TIMEOUT"); fi
  # shellcheck disable=SC2016  # the GraphQL `$owner`/`$name`/`$number` are variables of the query, not shell
  query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      isInMergeQueue mergeQueueEntry { state } state autoMergeRequest { enabledAt }
      commits(last: 1) { nodes { commit { committedDate } } }
      timelineItems(last: 1, itemTypes: [REMOVED_FROM_MERGE_QUEUE_EVENT]) { nodes { ... on RemovedFromMergeQueueEvent { reason createdAt } } }
    }
  }
}'
  # shellcheck disable=SC2016  # `$r` / `$en` / `$hd` are jq variables, not shell
  jqp='.data.repository.pullRequest
  | if . == null then "unreadable"
    else (if .isInMergeQueue == true or .mergeQueueEntry != null then "queued"
          elif .isInMergeQueue == false then "not_queued"
          else "unreadable" end)
         + " " + (.state // "-")
         + " " + (if has("autoMergeRequest") then (if .autoMergeRequest == null then "disarmed" else "armed" end) else "-" end)
         + " removal=" + (if has("timelineItems") then
             (.timelineItems.nodes // [])[0] as $r
             | (.autoMergeRequest.enabledAt // "") as $en
             | ((.commits.nodes // [])[0].commit.committedDate // "") as $hd
             | if $r == null or ($r.createdAt // "") <= $en or ($r.createdAt // "") <= $hd then "none"
               else (($r.reason // "unknown") | tostring | gsub("[^A-Za-z0-9_-]"; "_")) end
           else "-" end)
    end'
  errf="$(mktemp)" || { QS_CAUSE=gh_error; QS_DETAIL="mktemp failed"; return 1; }  # lint-trap-ownership: ok — removed by rm -f on every return path of queue_state_read; a kill leaves one tiny file
  while [[ "$n" -lt "$QB_ATTEMPTS" ]]; do
    n=$((n + 1)); rc=0
    # shellcheck disable=SC2016  # $1..$5 are bash -c's own positional parameters, not this shell's
    out="$(${to[@]+"${to[@]}"} bash -c 'gh api graphql -F owner="$4" -F name="$5" -F number="$1" -f query="$2" --jq "$3"' \
            _ "$PR" "$query" "$jqp" "$owner" "$repo" 2>"$errf")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      case "$rc" in 124|137|143) QS_CAUSE=timeout ;; *) QS_CAUSE=gh_error ;; esac
      # gh's raw stderr reaches the `kind=gh rc=4` line a Monitor streams to the model: ESC, CR and a forged tag line must not.
      QS_DETAIL="$(printf '%s' "rc=$rc $(head -c 200 "$errf")" | qb_clean)"
    else
      out="${out%%$'\n'*}"
      case "${out%% *}" in
        queued|not_queued) rm -f "$errf"; QS_OUT="$out"; return 0 ;;
        *) QS_CAUSE=unparseable; QS_DETAIL="read returned '${out:0:80}' (want queued or not_queued)" ;;
      esac
    fi
    if [[ "$n" -lt "$QB_ATTEMPTS" ]]; then sleep "$QB_NAP"; fi
  done
  rm -f "$errf"
  return 1
}

# dq_candidate <marker> — 0 iff QS_OUT reads the PR out of the queue and OPEN AND it either was seen queued (the
# marker, per worktree git dir) or has a CURRENT removal event. Auto-merge state is NOT consulted: after a failed
# merge_group run it stays armed (measured 2026-10-05, #9482, two PRs) and GitHub may re-queue the PR, and a
# removed PR must be reported whether or not it is still armed. Only a PR with
# neither marker nor event keeps the old reading (not queued yet, or a push dequeued it and it re-enqueues itself).
dq_candidate() {
  local v st am rm
  read -r v st am rm <<<"$QS_OUT"
  [[ "$v" == not_queued && "$st" == OPEN ]] || return 1
  [[ ( -n "$1" && -f "$1" ) || ( -n "$rm" && "$rm" != removal=none && "$rm" != removal=- ) ]]
}

# queue_read_settled <marker> — queue_state_read, then ONE re-read after a short nap when the first answer is a
# dequeue candidate, so the instant the queue's own merge lands (not queued, OPEN, about to read MERGED) is never
# reported as a dequeue. Returns 1 (QS_CAUSE set) when either read fails: a failed read is never a verdict.
queue_read_settled() {
  qb_bounds
  queue_state_read || return 1
  if dq_candidate "$1"; then sleep "$QB_NAP"; queue_state_read || return 1; fi
  return 0
}

# queue_wait_eval — THE ONE copy of the armed-BEHIND predicate (2026-10-09, PR 9839; shared with --step and --queue-wait,
# #9869). Between `gh pr merge --auto` and the enqueue a PR is OPEN, BEHIND, armed and NOT in the queue, so queue_gate (which
# only sees an entry) lets it through, and a sync there pushes a commit that restarts every required check for nothing: on a
# merge-queue repo the queue makes the PR current itself. Fires when the PR is OPEN, GitHub says BEHIND or UNKNOWN (UNKNOWN is
# recompute lag; DIRTY never: a conflicting or kb-index-class PR still resolves) AND auto-merge is armed AND the PR's own base
# branch has a merge_queue rule (one rules read, selected by `.type`, never by position: merge_queue is not the first rule on a live repo, and
# the read asks for 100 rules per page: a merge_queue beyond rule 100 would read as absent). It always RETURNS 0 and reports
# through QW_VERDICT (wait | proceed | unreadable | badbase | foreign) and QW_DETAIL: a distinct non-zero return would kill a caller under
# `set -euo pipefail` on the common proceed path. A rules read that still fails after PR_QUEUE_ATTEMPTS tries (default 2, like
# queue_state_read), or answers empty or non-numeric, is `unreadable`: the one place this script fails CLOSED on an unreadable
# rules answer (ADR-270 addendum 2026-10-09) — an unknown answer is not a yes. The cause is in QW_DETAIL. The rules read is of the
# PR's OWN base branch (its baseRefName, the third argument: #10832), not a fixed `main`; the URL for base `main` is unchanged. The base
# is validated (qw_base_path) only AFTER the OPEN, BEHIND/UNKNOWN and armed checks, so a PR that never reaches the rules read is never
# affected by an odd or empty base. Two more internal verdicts, each with its own arm at every caller: `badbase` (the base is empty or
# unsupported: no request is made) and `foreign` (the base is not `main` and has no merge_queue rule: this script's sync merges
# origin/main, which is wrong for that PR, so the guarded callers refuse rather than sync). The refusal is a convenience interlock, not
# an authorization boundary: a PR author can retarget between the snapshot and the read.
queue_wait_eval() {  # <state_line: "<STATE> <MERGESTATE>"> <armed|disarmed|-> <base>
  qb_bounds
  local am="$2" base="${3:-}" out="" rc=0 n=0 detail="" errf owner='{owner}' repo='{repo}' bp="" to=()
  QW_VERDICT=proceed; QW_DETAIL=""; QW_BASE=""
  [[ "$1" == OPEN\ * ]] || return 0
  [[ ( "$1" == *BEHIND* || "$1" == *UNKNOWN* ) && "$1" != *DIRTY* ]] || return 0
  [[ "$am" == armed ]] || return 0
  if ! bp="$(qw_base_path "$base")"; then
    QW_VERDICT=badbase; QW_DETAIL="base branch '$(printf '%s' "$base" | qb_clean | cut -c1-60)' is empty or not a supported branch name"
    return 0
  fi
  QW_BASE="$base"
  if [[ "${PR_QUEUE_REPO:-}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then owner="${PR_QUEUE_REPO%%/*}"; repo="${PR_QUEUE_REPO#*/}"; fi
  if command -v timeout >/dev/null 2>&1; then to=(timeout -k 2 "$QB_TIMEOUT")
  elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout -k 2 "$QB_TIMEOUT"); fi
  errf="$(mktemp)" || { QW_VERDICT=unreadable; QW_DETAIL="rule read not attempted (mktemp failed)"; return 0; }  # lint-trap-ownership: ok — removed by rm -f on every return path of queue_wait_eval; a kill leaves one tiny file
  while [[ "$n" -lt "$QB_ATTEMPTS" ]]; do
    n=$((n + 1)); rc=0
    # shellcheck disable=SC2016  # $1..$4 are bash -c's own positional parameters, not this shell's
    out="$(${to[@]+"${to[@]}"} bash -c 'gh api "repos/$1/$2/rules/branches/$4?per_page=100" --jq "$3"' \
            _ "$owner" "$repo" '[.[] | select(.type == "merge_queue")] | length' "$bp" 2>"$errf")" || rc=$?
    out="${out%%$'\n'*}"
    if [[ "$rc" -eq 0 && "$out" =~ ^[0-9]{1,6}$ ]]; then break; fi
    detail="rc=$rc answered=${out:0:40} $(head -c 160 "$errf" | tr '\n' ' ')"
    if [[ "$n" -lt "$QB_ATTEMPTS" ]]; then sleep "$QB_NAP"; fi
  done
  rm -f "$errf"
  if [[ "$rc" -eq 0 && "$out" =~ ^[0-9]{1,6}$ ]]; then
    if (( 10#$out >= 1 )); then QW_VERDICT="wait"; QW_DETAIL="rules=$out"
    elif [[ "$QW_BASE" != main ]]; then QW_VERDICT=foreign; fi
    return 0
  fi
  detail="$(printf '%s' "$detail" | qb_clean)"
  QW_VERDICT=unreadable; QW_DETAIL="rule read failed after $n attempt(s) ($detail)"
  return 0
}

# The refusal text shared by every caller that refuses (the standalone loop, a flagless --step): what to do instead of a resync. The
# advice differs by the validated base (QW_BASE, always set when a `wait` verdict exists): for `main` the Phase 7 poll's expiry fallback
# is the sanctioned sync and a disarm / hand-sync / re-arm is safe; for any other base that sync merges origin/main, which is wrong for
# the PR, so the text says to sync by hand against that base and never to disarm and re-arm. The `main` text is byte-identical to the
# pre-#10832 text (the N7a golden row). The echoed base is cut to 60 characters (it is validated, but may be 255 long).
qw_refusal() {
  local b="${QW_BASE:0:60}" poll hand
  if [[ "$QW_BASE" == main ]]; then
    poll="; with no poll running, re-arm the Phase 7 poll with CLAUDE_PLUGIN_ROOT exported — its expiry fallback after 6 idle ticks is the sanctioned sync"
    hand="Truly need a hand sync? Disarm first (gh pr merge $PR --disable-auto), sync, then re-arm."
  else
    poll=""
    hand="Truly need a hand sync? This script and the Phase 7 poll's expiry fallback only merge origin/main, which is wrong for a PR based on '$b': sync by hand against that base (fetch origin <base>, merge origin/<base>, push) and do not disarm and re-arm."
  fi
  printf '%s' "PR #$PR is BEHIND, auto-merge is armed (not in the queue yet) and $b has a merge queue: not syncing — a resync alone restarts every required check and the queue makes the PR current. Wait for MERGED or a dequeue$poll. Red required check? Push the fix itself, not a resync. $hand Green and never enqueued? Follow plugins/soleur/skills/ship/references/merge-queue-dequeue.md ('Armed and green but never enqueued')."
}
# ... and the unreadable-rules text (fail closed): an unknown answer is not a yes. The hand-sync clause is conditional on the base as above.
qw_unreadable() {  # <detail>
  local b="${QW_BASE:0:60}" hand
  if [[ "$QW_BASE" == main ]]; then hand="resync by hand only after confirming $b has no merge queue"
  else hand="resync by hand only after confirming $b has no merge queue, and then against that base (this script and the Phase 7 poll's fallback merge origin/main, which is wrong for a PR based on '$b')"; fi
  printf '%s' "merge-queue $1 — not syncing: that read decides whether this armed BEHIND PR may be resynced and an unknown answer is not a yes. Retry the poll; a persistent failure means the token cannot read repository rules (raise PR_QUEUE_ATTEMPTS, or $hand)."
}
# The interim non-main refusal (#10832): an armed BEHIND or UNKNOWN PR whose base is not `main` and has no merge_queue rule. This
# script only ever merges origin/main, which is wrong for such a PR, so it is not syncing; the text LEADS with NOT A TRANSIENT ERROR
# because a retry cannot help, and does not advise "disarm, sync, re-arm" (that walks into the very merge this refuses) or retargeting
# (the script has never synced from a non-main trunk, so a repo whose default branch is not main would be told to do the impossible).
# <state_line> is GitHub's `<STATE> <MERGESTATE>` (the foreign verdict also fires for UNKNOWN, so the text echoes the real state).
qw_foreign() {  # <state_line>
  printf '%s' "NOT A TRANSIENT ERROR - PR #$PR is armed and ${1#* } on base '${QW_BASE:0:60}', not main, and that base has no merge queue; this script only syncs from origin/main (merging main into that PR would be wrong), so it is not syncing and retrying will not help. Sync by hand against that base."
}
# ... and the unusable-base text (empty, or a name outside qw_base_path's set; QW_DETAIL names the sanitised base).
qw_badbase() { printf '%s' "NOT A TRANSIENT ERROR - $QW_DETAIL; this script only syncs from origin/main, so it is not syncing; sync by hand against the PR's base branch."; }

# qw_snapshot — ONE bounded `gh pr view <PR> --json state,mergeStateStatus,autoMergeRequest,baseRefName` for the flagless --step and --queue-wait
# (no GraphQL queue read: --queue-wait's caller already classified queued / not_queued, and a second read would race a
# just-dequeued PR that still reads armed). Sets QW_STATE (`<STATE> <MERGESTATE>`), QW_ARMED (armed | disarmed) and QW_BASEREF (the PR's base branch, possibly empty: it is
# validated only inside queue_wait_eval, after the armed check, so an odd base never fails a path that does not reach the rules read; the
# answer is split with `read -r` only, never a suffix expansion, which would read a base named `disarmed` as the armed bit). It runs under
# the same timeout wrapper and PR_QUEUE_REPO handling as the other reads, with gh's stderr kept OUT of the string the match
# tests, and a strict match on the answer. ANY failure — non-zero, hung, empty, garbage — is `kind=gh` exit 4: never read as "not armed".
qw_snapshot() {
  qb_bounds
  local out="" rc=0 errf pvd repo_arg="" to=() st ms am base
  QW_STATE=""; QW_ARMED=""; QW_BASEREF=""
  if [[ "${PR_QUEUE_REPO:-}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then repo_arg="$PR_QUEUE_REPO"; fi
  if command -v timeout >/dev/null 2>&1; then to=(timeout -k 2 "$QB_TIMEOUT")
  elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout -k 2 "$QB_TIMEOUT"); fi
  errf="$(mktemp)" || { tag gh 4 "pr view snapshot not attempted (mktemp failed) — not syncing; retry the poll"; exit 4; }  # lint-trap-ownership: ok — removed by rm -f on every path of qw_snapshot; a kill leaves one tiny file
  # shellcheck disable=SC2016  # $1..$3 are bash -c's own positional parameters, not this shell's
  out="$(${to[@]+"${to[@]}"} bash -c 'if [[ -n "$3" ]]; then gh pr view "$1" --repo "$3" --json state,mergeStateStatus,autoMergeRequest,baseRefName --jq "$2"; else gh pr view "$1" --json state,mergeStateStatus,autoMergeRequest,baseRefName --jq "$2"; fi' \
          _ "$PR" '"\(.state) \(.mergeStateStatus) \(if .autoMergeRequest == null then "disarmed" else "armed" end) \(.baseRefName // "")"' "$repo_arg" 2>"$errf")" || rc=$?
  out="${out%%$'\n'*}"
  if [[ "$rc" -eq 0 ]] && qb_match "$out" '^(OPEN|CLOSED|MERGED) [A-Z_]+ (armed|disarmed) [^[:space:]]*$'; then
    rm -f "$errf"
    read -r st ms am base <<<"$out"
    QW_STATE="$st $ms"; QW_ARMED="$am"; QW_BASEREF="$base"
    return 0
  fi
  pvd="$(printf '%s' "rc=$rc answered=${out:0:40} $(head -c 160 "$errf")" | qb_clean)"
  rm -f "$errf"
  tag gh 4 "pr view snapshot read failed ($pvd) — not syncing: whether this PR is armed and BEHIND decides if a resync is allowed, and an unknown answer is not a yes. Retry."
  exit 4
}

# qw_probe — the snapshot plus the predicate, the place that passes the PR's base for the two snapshot callers (--queue-wait and the flagless
# --step guard); queue_wait_gate is the loop's own call site and passes LOOP_BASEREF (a forgotten base argument at a copy is the bug class,
# and the G1-2/G1-3/G1-4 rows pin each call). Called directly (never inside `$( )`) so QW_VERDICT, QW_DETAIL and QW_BASE reach the caller.
qw_probe() { qw_snapshot; queue_wait_eval "$QW_STATE" "$QW_ARMED" "$QW_BASEREF"; }

# --queue-wait: the read-only verdict for the pre-merge hook (#9869), handled beside --queue-state before the worktree check.
# Armed means autoMergeRequest != null in THIS snapshot, so an armed PR that is already in the queue also reads queue_wait (the
# stricter, safe direction for a caller that decides whether to push). Writes nothing — no marker. A foreign or unusable base answers
# `queue_wait` too (not `kind=gh`: the hook treats any non-zero exit as "sync anyway", which would merge origin/main into that PR).
if [[ "$MODE" == queue_wait ]]; then
  QW_STATE=""; QW_ARMED=""
  qw_probe
  case "$QW_VERDICT" in
    wait) echo queue_wait; exit 0 ;;
    foreign) echo queue_wait; exit 0 ;;
    badbase) echo queue_wait; exit 0 ;;
    unreadable) tag gh 4 "$(qw_unreadable "$QW_DETAIL")"; exit 4 ;;
    proceed) echo proceed; exit 0 ;;
    # An unknown verdict is NOT proceed: the stricter answer, one line, rc 0 (the hook reads any non-zero exit as "sync anyway").
    *) echo queue_wait; exit 0 ;;
  esac
fi

# step_guard — a FLAGLESS --step (#9869): refuse an armed BEHIND/UNKNOWN PR of a merge-queue repo with exit 14, a code of its
# own. 11 is the fences' uncounted "no sync needed" arm, so an OLD pasted fence would loop silently on it; 14 reaches its `*)`
# arm, a loud bounded stop whose line above names the action. The line opens with "NOT AN ERROR in itself" so an errexit reader
# does not fall back to a hand merge. Unreadable is fail closed (kind=gh, exit 4), as in the standalone loop.
step_guard() {
  QW_STATE=""; QW_ARMED=""
  qw_probe
  case "$QW_VERDICT" in
    wait) tag queue_wait 14 "NOT AN ERROR in itself (GitHub says: $QW_STATE) — exit 14 means this caller is not the current Phase 7 fence: re-READ ship/SKILL.md from disk and re-paste its fence (a copy held in context predates --fence); the PR itself needs no sync. $(qw_refusal)"
          exit 14 ;;
    foreign) tag gh 4 "$(qw_foreign "$QW_STATE")"; exit 4 ;;
    badbase) tag gh 4 "$(qw_badbase)"; exit 4 ;;
    unreadable) tag gh 4 "$(qw_unreadable "$QW_DETAIL")"; exit 4 ;;
    proceed) return 0 ;;
    *) tag gh 4 "unknown queue_wait verdict '$(printf '%s' "$QW_VERDICT" | head -c 60 | qb_clean)' — not syncing (an unknown answer is not a yes); this is a bug in this script, report it"; exit 4 ;;
  esac
}

# --queue-state: the shared read — no git work, no worktree needed, no push. It never WRITES the marker (only --step does,
# on a queued sighting); the one write it makes is the CONSUMPTION below: printing `dequeued` removes the marker, so the
# report is delivered once (a PR the agent fixed and re-armed — CI running, not queued yet — must not read dequeued on every
# later tick just because the marker outlived the first report). Handled before the worktree check so a caller outside a
# work tree (monitor-pr-checks.sh --repo) can use it.
if [[ "$MODE" == queue_state ]]; then
  QS_OUT=""; QS_CAUSE=""; QS_DETAIL=""
  qs_marker="$(git rev-parse --git-dir 2>/dev/null || true)"; [[ -z "$qs_marker" ]] || qs_marker="$qs_marker/pr-queue-seen-$PR"
  if queue_read_settled "$qs_marker"; then
    # The verdict a caller acts on: `dequeued` replaces `not_queued` for a candidate that survived the re-read. A
    # dequeue reached through the MARKER alone (removal=none) is reported ONCE: the report consumes the marker, exactly
    # as --step does on exit 13. A dequeue from a CURRENT removal event needs no marker (a re-arm after the fix makes
    # the event older than enabledAt, so it stops matching); a stale marker beside one is consumed by the same report.
    # A non-dequeued verdict (queued, MERGED, not_queued) never consumes it.
    if dq_candidate "$qs_marker"; then
      QS_OUT="dequeued ${QS_OUT#* }"
      [[ -z "$qs_marker" ]] || rm -f "$qs_marker"   # consume-on-report
    fi
    printf '%s\n' "$QS_OUT"; exit 0
  fi
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
# 13 (kind=dequeued) when it is out of the queue, OPEN, and either was seen queued or has a CURRENT removal event
# (auto-merge state is not consulted), and 4 (kind=gh) when the read fails or answers anything but queued /
# not_queued; returns normally only on a positive "not queued" with no dequeue evidence. The read is
# queue_read_settled() above (queue_state_read owns the query and the verdict program; two attempts ride out a
# transient 5xx or rate limit, and a dequeue candidate is re-read once), so the fence needs no arm of its own.
queue_gate() {
  local verdict st am rm marker git_dir reason
  git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
  marker=""; [[ -z "$git_dir" ]] || marker="$git_dir/pr-queue-seen-$PR"
  QS_OUT=""; QS_CAUSE=""; QS_DETAIL=""
  if ! queue_read_settled "$marker"; then
    tag gh 4 "merge queue read failed (cause=$QS_CAUSE ${QS_DETAIL:0:200}) — not syncing; a push to a queued PR would dequeue it"
    exit 4
  fi
  read -r verdict st am rm <<<"$QS_OUT"
  case "$verdict" in
    not_queued)
      case "$st" in
        MERGED|CLOSED)   # the PR left the queue by merging (or was closed): a stale marker is cleared, nothing to sync
          [[ -z "$marker" ]] || rm -f "$marker"
          tag noop 11 "PR #$PR is $st — it left the queue; nothing to sync"
          exit 11 ;;
      esac
      if dq_candidate "$marker"; then
        [[ -z "$marker" ]] || rm -f "$marker"
        reason="removal reason: ${rm#removal=}"
        [[ "$rm" != removal=none && "$rm" != removal=- ]] || reason="seen in the queue earlier, no removal event read"
        tag dequeued 13 "PR #$PR was in the merge queue and is no longer (OPEN, $am, $reason): a failed merge_group run or a removal — NOT syncing. Recover (ONE re-enqueue, procedure: plugins/soleur/skills/ship/references/merge-queue-dequeue.md): (1) read why: gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith(\"gh-readonly-queue/main/pr-$PR-\"))' then gh run view <databaseId> --log-failed; (2) fix on the branch, git merge origin/main, push; (3) re-arm once: gh pr merge $PR --squash --auto. A second dequeue: stop and report it."
        exit 13
      fi
      return 0 ;;
    queued)
      [[ -z "$marker" ]] || { touch "$marker" 2>/dev/null || true; }
      # --step exits 11 (the fence's uncounted no-op arm: nothing was pushed, so the ship and
      # merge-pr fences must not count a sync); the standalone loop exits 0.
      if [[ "$MODE" == step ]]; then
        tag queued 11 "PR #$PR is in the merge queue; sync skipped (a push would dequeue it) — keep polling for MERGED or removal from the queue"
        exit 11
      fi
      tag queued 0 "PR #$PR is in the merge queue; sync skipped (a push would dequeue it) — keep polling for MERGED or removal from the queue"
      exit 0 ;;
    *)
      tag gh 4 "merge queue read returned '${QS_OUT:0:80}' (want queued or not_queued) — not syncing; a push to a queued PR would dequeue it"
      exit 4 ;;
  esac
}

# Armed-and-BEHIND gate for the standalone loop (2026-10-09, PR 9839): queue_wait_eval's verdict, as the loop answers it. Runs
# after queue_gate, whose QS_OUT carries the armed bit (no extra call). `wait` -> `kind=queue_wait` rc=0, exit 0 with nothing
# fetched, merged or pushed; `proceed` -> return, the sync goes on; `unreadable`, `foreign` (a non-main base with no queue rule) and
# `badbase` (an empty or unsupported base) -> `kind=gh` exit 4. The base is LOOP_BASEREF, resolved once before the loop. The standalone answer has NO
# expiry of its own: re-arming the Phase 7 poll is the bound (its fallback sync).
queue_wait_gate() {  # <state_line>
  local v st am rm
  read -r v st am rm <<<"$QS_OUT"
  queue_wait_eval "$1" "$am" "$LOOP_BASEREF"
  case "$QW_VERDICT" in
    wait) tag queue_wait 0 "$(qw_refusal)"; exit 0 ;;
    foreign) tag gh 4 "$(qw_foreign "$1")"; exit 4 ;;
    badbase) tag gh 4 "$(qw_badbase)"; exit 4 ;;
    unreadable) tag gh 4 "$(qw_unreadable "$QW_DETAIL")"; exit 4 ;;
    proceed) return 0 ;;
    *) tag gh 4 "unknown queue_wait verdict '$(printf '%s' "$QW_VERDICT" | head -c 60 | qb_clean)' — not syncing (an unknown answer is not a yes); this is a bug in this script, report it"; exit 4 ;;
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
  # The Phase 7 fences pass --fence: they decided to sync (expiry fallback, DIRTY-derived BEHIND, no merge_queue rule, a failed armed
  # read) and made no extra read here. Any other caller gets the queue-armed refusal.
  if [[ "$FENCE" != 1 ]]; then
    step_guard
  fi
  rc=0; sync_step || rc=$?
  exit "$rc"
fi

# Standalone: the PR number must name THIS branch, or the sync lands on the wrong PR.
# The same read also carries the PR's base branch (baseRefName) for queue_wait_eval, so the loop adds no gh call. The base is resolved ONCE
# per run: a mid-loop retarget is judged against the old base (bounded by --max-attempts: each further BEHIND iteration can merge again if main
# moved, so the stale judgement can cost up to that many merges). Any answer
# that is not exactly `<head> <base>` on one line (a single token, or a multi-line answer because stderr is merged by 2>&1) leaves head_ref
# as the whole answer, as before, and LOOP_BASEREF empty; an empty base is fatal only where queue_wait_eval reaches the rules read.
rc=0; head_ref="$(gh pr view "$PR" --json headRefName,baseRefName --jq '"\(.headRefName) \(.baseRefName // "")"' 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "gh pr view failed: $(printf '%s' "$head_ref" | head -c 200 | qb_clean)"; exit 4; fi
if qb_match "$head_ref" '^[^[:space:]]+ [^[:space:]]*$'; then read -r head_ref LOOP_BASEREF <<<"$head_ref"; fi
if [[ "$head_ref" != "$BRANCH" ]]; then
  tag wrong_branch 12 "PR #$PR's head branch is '$(printf '%s' "$head_ref" | head -c 200 | qb_clean)' but this worktree is on '$BRANCH' — cd to that PR's worktree (or pass the right PR number); not syncing."
  exit 12
fi

attempt=0
while [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  rc=0; state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "gh pr view failed: $(printf '%s' "$state_line" | head -c 200 | qb_clean)"; exit 4; fi

  # gh's stderr is merged into the answer (2>&1), so even an rc-0 read can carry junk: every echo of it is sanitised (the tests below
  # still look at the raw $state_line).
  sdisp="$(printf '%s' "$state_line" | head -c 200 | qb_clean)"
  tag state 0 "PR #$PR state: $sdisp (branch: $BRANCH)"

  if [[ "$state_line" == MERGED* || "$state_line" == CLOSED* ]]; then
    tag closed 0 "PR is ${sdisp%% *} — no sync needed"
    exit 0
  fi

  if [[ "$state_line" != *BEHIND* && "$state_line" != *DIRTY* ]]; then
    tag not_behind 0 "BEHIND unchanged: mergeStateStatus is not BEHIND — no sync needed"
    exit 0
  fi

  # A queued PR is never synced (queue_gate exits kind=queued, or 4 on a failed read).
  queue_gate
  # An armed BEHIND PR on a merge-queue repo is not synced either (queue_wait_gate exits kind=queue_wait, or 4).
  queue_wait_gate "$state_line"

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
  if [[ "$rc" -ne 0 ]]; then tag gh "$rc" "post-push gh pr view failed: $(printf '%s' "$state_line" | head -c 200 | qb_clean)"; exit 4; fi
  tag state 0 "post-sync state: $(printf '%s' "$state_line" | head -c 200 | qb_clean)"

  if [[ "$state_line" != *BEHIND* ]]; then
    tag resolved 0 "BEHIND resolved: branch caught up to main"
    exit 0
  fi
done

tag exhausted 8 "BEHIND still present after ${MAX_ATTEMPTS} sync(s) — main may be moving faster than CI"
exit 8
