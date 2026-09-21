#!/usr/bin/env bash
# BEHIND resync — merge origin/main into the current PR branch and push.
#
# Portable extract of ship Phase 7 BEHIND auto-sync for Grok Build agents
# polling outside the Monitor tool. Emits structured lines for AwaitShell
# pattern matching.
#
# Usage: bash plugins/soleur/scripts/sync-pr-behind.sh <pr-number> [--max-attempts N]
# Preconditions: run from inside the PR feature worktree (not bare repo root).
set -euo pipefail

PR="${1:-}"
MAX_ATTEMPTS=1
if [[ "${2:-}" == "--max-attempts" && -n "${3:-}" ]]; then
  MAX_ATTEMPTS="$3"
fi

if [[ -z "$PR" || ! "$PR" =~ ^[0-9]+$ ]]; then
  echo "usage: sync-pr-behind.sh <pr-number> [--max-attempts N]" >&2
  exit 2
fi

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

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Never touch an operation this script did not start (#8339): an unconditional
# `git merge --abort` below would discard an operator's staged resolution of a
# merge/rebase/cherry-pick/revert in progress — measured on real git. The same
# precondition guards the ship / merge-pr Phase 7 fences.
git_dir="$(git rev-parse --git-dir)"
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   || [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" \
         || -f "$git_dir/CHERRY_PICK_HEAD" || -f "$git_dir/REVERT_HEAD" ]]; then
  echo "[pr-behind-sync] merge in progress — a merge/rebase/cherry-pick/revert is in progress on $BRANCH; not touching it. Finish or abort it by hand, then re-run." >&2
  exit 9
fi
if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
  echo "[pr-behind-sync] ERROR: HEAD is detached — git push would have no branch to update; check out the PR branch first" >&2
  exit 9
fi
attempt=0

while [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" \
    || { echo "[pr-behind-sync] gh pr view failed: $state_line" >&2; exit 4; }

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

  if ! git fetch --no-tags origin main 2>&1 | tail -3; then
    echo "[pr-behind-sync] fetch origin main failed" >&2
    exit 5
  fi

  resolved_by_regen=0
  # Key on merge-tree's exit code; on failure its stdout carries the real conflicted paths
  # (no merge is in progress, so `git diff --diff-filter=U` could only ever print nothing).
  if ! mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"; then
    # REGENERABLE-ARTIFACT CONFLICT (ADR-235). One generated file is still committed --
    # model.likec4.json, which the web-platform C4 viewer fetches from GitHub as a committed
    # blob on the request path (app/api/kb/c4/project/route.ts; no build step) -- so it
    # conflicts whenever two branches touch the .c4 sources. The
    # resolver completes the merge and regenerates it from the MERGED sources, which is the
    # only correct resolution (side-picking yields an artifact matching neither side).
    #
    # FAIL-CLOSED BY CONTRACT: it exits non-zero having touched nothing unless it committed
    # the merge, so the fall-through below is exactly today's behaviour. It never pushes --
    # the push and its rejection handling (exit 7) stay here.
    # The resolver is a TOOL that ships beside this script, so it is located from this
    # file's directory; the TARGET is still the caller's worktree ($PWD), which the resolver
    # derives itself via `git rev-parse --show-toplevel`. Do not reintroduce $REPO_ROOT here:
    # it was removed above (see "NO `cd` HERE") and an unset one makes this path
    # "/plugins/...", so `-f` fails and every regenerable conflict silently degrades to
    # "manual resolution required" -- the regen arm dead with no error.
    resolver="$(dirname "${BASH_SOURCE[0]}")/resolve-regenerable-conflicts.sh"
    if [[ -f "$resolver" ]] && bash "$resolver" origin/main; then
      echo "[pr-behind-sync] regenerable conflict resolved — merge committed locally"
      resolved_by_regen=1
    else
      echo "[pr-behind-sync] merge conflict — manual resolution required" >&2
      printf '%s\n' "$mt_out" | grep '^CONFLICT ' >&2 || true
      git merge --abort 2>/dev/null || true
      exit 6
    fi
  fi

  # Skip the merge when the resolver already committed one. `git merge` would report
  # "Already up to date" and exit 0 here, so this guard is for the LOG rather than for
  # correctness -- it keeps the output honest about which path produced the commit.
  if [[ "$resolved_by_regen" -eq 0 ]]; then
    if ! git merge origin/main --no-edit 2>&1 | tail -8; then
      echo "[pr-behind-sync] merge conflict — manual resolution required" >&2
      git diff --name-only --diff-filter=U >&2 || true
      git merge --abort 2>/dev/null || true
      exit 6
    fi
  fi

  if ! git push 2>&1 | tail -3; then
    echo "[pr-behind-sync] push failed after merge" >&2
    exit 7
  fi

  echo "[pr-behind-sync] auto-sync ${attempt} pushed — CI will re-run on new SHA"

  state_line="$(gh pr view "$PR" --json state,mergeStateStatus \
    --jq '"\(.state) \(.mergeStateStatus)"' 2>&1)" \
    || { echo "[pr-behind-sync] post-push gh pr view failed: $state_line" >&2; exit 4; }
  echo "[pr-behind-sync] post-sync state: $state_line"

  if [[ "$state_line" != *BEHIND* ]]; then
    echo "[pr-behind-sync] BEHIND resolved: branch caught up to main"
    exit 0
  fi
done

echo "[pr-behind-sync] BEHIND still present after ${MAX_ATTEMPTS} sync(s) — main may be moving faster than CI" >&2
exit 8