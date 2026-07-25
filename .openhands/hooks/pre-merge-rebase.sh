#!/usr/bin/env bash
# PreToolUse hook: review evidence gate + auto-sync against origin/main before gh pr merge.
# OpenHands port of .claude/hooks/pre-merge-rebase.sh.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Exit 0 + JSON {"additionalContext":"..."} to inject context.
# Input: HookEvent JSON on stdin with tool_input.command and working_dir.
#
# Corresponding prose rules: see .claude/hooks/pre-merge-rebase.sh

set -eo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands.
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

# Determine working directory from hook input.
WORK_DIR=$(echo "$INPUT" | jq -r '.working_dir // ""')
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

deny() {
  jq -n --arg reason "$1" '{"decision":"deny","reason":$reason}'
  exit 2
}

CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# Refresh origin/main BEFORE the gate (#6724). Both local signals are scoped
# with `origin/main..HEAD`, so a stale ref widens the range and lets commits
# already on main count as this branch's review evidence. Deliberately does not
# exit on failure: the sync below fails open on network error, and keeping that
# behaviour here would make "unplug the network" a universal gate bypass.
FETCH_OK=1
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
  FETCH_OK=0
fi

# pre-merge:review-evidence-gate
# Check 1 was a repo-global `grep -rl "code-review" "$WORK_DIR/todos/"` and was
# therefore structurally unfailable (#6724): todos/ lives on main, so one
# long-lived review todo satisfied the gate for every branch forever. Now scoped
# to paths touched by commits unique to this branch.
# `-G` selects commits whose DIFF touched the tag (so the BRANCH introduced it),
# and the HEAD-blob check requires it to still be there — `-G` alone matches
# removals, so a sweep deleting a completed todo would otherwise count.
REVIEW_TODOS=""
while IFS= read -r _todo; do
  [[ -n "$_todo" ]] || continue
  if git -C "$WORK_DIR" show "HEAD:$_todo" 2>/dev/null | grep -q "code-review"; then
    REVIEW_TODOS="$_todo"
    break
  fi
done < <(git -C "$WORK_DIR" log origin/main..HEAD -G'code-review' \
           --name-only --format= -- todos/ 2>/dev/null | sort -u)
# Signal 2 had drifted out of sync with the .claude/hooks copy: it matched only
# the legacy "refactor: add code review findings" subject, missing the "review: "
# fix-inline convention (post-#2374) entirely. Both are now matched here, plus
# the durable `Reviewed-By-Soleur:` trailer that emit-review-trailer.sh emits —
# the only signal a zero-finding review can produce.
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep -E "^[a-f0-9]+ (refactor: add code review findings|review: )" || true)
if [[ -z "$REVIEW_COMMIT" ]]; then
  REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD \
    --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' 2>/dev/null \
    | grep '[^[:space:]]' || true)
fi

REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  PR_NUMBER=$(echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+' || true)
  if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    # Kept in lockstep with .claude/hooks/pre-merge-rebase.sh. Two load-bearing details:
    # --state all, because a review issue that was filed and then CLOSED (the fix-inline
    # default) is still evidence /review ran — open-only discards the healthy case (#6786);
    # and the literal quotes, so GitHub search treats "PR #N" as an exact phrase (otherwise
    # `#123` tokenizes loosely and matches unrelated issues — confirmed in soleur/#2186).
    REVIEW_ISSUES=$(gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

# A stale origin/main makes both local signals untrustworthy in the UNSAFE
# direction (the range widens to include commits already on main, and this hook
# merges origin/main on every run), so discard them rather than warn. Signal 3
# queries the remote and is unaffected, so a fetch failure degrades to
# Signal-3-only instead of to a bypass (#6724).
if [[ "$FETCH_OK" != "1" ]]; then
  REVIEW_TODOS=""
  REVIEW_COMMIT=""
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  deny "BLOCKED: No review evidence for commits in origin/main..HEAD. If review has NOT run: run /soleur:review. If it HAS run (or found nothing, which emits no artifacts): bash plugins/soleur/skills/review/scripts/emit-review-trailer.sh --findings <n>. Scope is this branch only — evidence already on main does not count."
fi

# Check for detached HEAD
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Warning: Detached HEAD state. Skipping auto-sync." >&2
  exit 0
fi

# Check for uncommitted changes
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    deny "BLOCKED: Uncommitted changes detected. Commit before merging."
  fi
fi

# The fetch happens above the review-evidence gate (#6724); its outcome is
# consumed here, preserving fail-open-on-network-error for SYNCING only.
if [[ "$FETCH_OK" != "1" ]]; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  echo "Warning: Could not determine branch relationship with main. Proceeding with merge." >&2
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  echo "[ok] Branch already up-to-date with origin/main." >&2
  exit 0
fi

# Attempt merge
if ! git -C "$WORK_DIR" merge origin/main >/dev/null 2>&1; then
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" merge --abort 2>/dev/null || true
  deny "BLOCKED: Merge of origin/main failed. Conflicting files: ${CONFLICT_FILES:-unknown}. Resolve conflicts manually before merging."
fi

# Push the merged result
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push origin HEAD 2>&1); then
  deny "BLOCKED: Merge succeeded but push failed. Push manually before merging. Error: $PUSH_OUTPUT"
fi

# Success with context
jq -n --arg branch "$CURRENT_BRANCH" \
  '{"additionalContext":("Pre-merge hook: merged origin/main into " + $branch + " and pushed. Branch is now current.")}'
exit 0
