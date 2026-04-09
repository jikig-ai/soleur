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
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)'; then
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

# pre-merge:review-evidence-gate
REVIEW_TODOS=$(grep -rl "code-review" "$WORK_DIR/todos/" 2>/dev/null | head -1 || true)
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep "refactor: add code review findings" || true)

REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  PR_NUMBER=$(echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+' || true)
  if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    REVIEW_ISSUES=$(gh issue list --label code-review --search "PR #${PR_NUMBER}" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  deny "BLOCKED: No review evidence found on this branch. Run /review before merging."
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

# Fetch latest main
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
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
