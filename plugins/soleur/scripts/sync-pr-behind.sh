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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[pr-behind-sync] ERROR: not inside a worktree — cd to .worktrees/feat-* first" >&2
  exit 3
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
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
    # REGENERABLE-ARTIFACT CONFLICT (ADR-230). One generated file is still committed --
    # model.likec4.json, which the web-platform C4 viewer reads out of repos that ship no
    # likec4 compiler -- so it conflicts whenever two branches touch the .c4 sources. The
    # resolver completes the merge and regenerates it from the MERGED sources, which is the
    # only correct resolution (side-picking yields an artifact matching neither side).
    #
    # FAIL-CLOSED BY CONTRACT: it exits non-zero having touched nothing unless it committed
    # the merge, so the fall-through below is exactly today's behaviour. It never pushes --
    # the push and its rejection handling (exit 7) stay here.
    resolver="$REPO_ROOT/plugins/soleur/scripts/resolve-regenerable-conflicts.sh"
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