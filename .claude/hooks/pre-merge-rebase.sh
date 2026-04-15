#!/usr/bin/env bash
# PreToolUse hook: review evidence gate + auto-sync against origin/main before gh pr merge.
#
# pre-merge:review-evidence-gate — blocks gh pr merge when no review evidence exists on the branch.
# Review evidence is detected via three signals (any one suffices):
# (1) todos/ files tagged "code-review" (legacy, pre-#1329)
# (2) a commit matching "refactor: add code review findings" (legacy, pre-#1329)
# (3) GitHub issues with "code-review" label referencing the branch's PR (current, post-#1329)
# No escape hatch — run /review before merging.
#
# Auto-sync: merges origin/main into the feature branch to ensure it is current before merge.
# Note: filename says "rebase" for historical reasons; strategy is merge (not rebase).
#
# Corresponding prose rules:
#   constitution.md "Before creating a PR or merging, merge latest origin/main into the feature branch"
#   pre-merge:review-evidence-gate — blocks gh pr merge without review evidence (self-documented in this script)
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree, push failure, missing review evidence).

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands.
# Word boundary (\s|$) prevents false positives on hypothetical merge-* subcommands.
# Chain operator pattern from guardrails.sh catches chained commands.
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

# Determine working directory from hook input (.cwd is authoritative).
WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

# Verify we are in a git repository
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Resolve current branch for main/master skip and detached HEAD handling
CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Skip if already on main/master -- no local review evidence to check,
# and nothing to sync (the agent is merging a PR *into* main, not from it)
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# pre-merge:review-evidence-gate — Review evidence gate.
# Block gh pr merge when no review evidence exists on the branch.
# Signals 1-2 are local; Signal 3 requires network (gh API).
# Fires before detached HEAD exit because gh pr merge operates on a PR number,
# not the local checkout state -- review evidence is still visible in detached HEAD.

# Check 1 (legacy): todo files tagged "code-review"
REVIEW_TODOS=$(grep -rl "code-review" "$WORK_DIR/todos/" 2>/dev/null | head -1 || true)

# Check 2 (legacy): review commit (coupled to review SKILL.md Step 5 commit message;
# uses locally-cached origin/main — may be stale if not recently fetched)
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep "refactor: add code review findings" || true)

# Check 3 (current): GitHub issues with "code-review" label referencing this PR.
# Coupled to review-todo-structure.md issue body template ("**Source:** PR #<number>").
# Fail open if gh is unavailable or network fails (Signal 3 is additive, not required).
REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  # Only run the network check if local signals found nothing
  PR_NUMBER=$(echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+' || true)
  if [[ -z "$PR_NUMBER" ]]; then
    # No PR number in command args -- fall back to branch-based lookup
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    # Wrap the phrase in literal quotes so GitHub search treats "PR #N" as an
    # exact phrase (otherwise `#123` tokenizes loosely and matches unrelated
    # issues that happen to reference the PR prefix — confirmed in soleur/#2186
    # session when search "PR #123" returned issues that never mentioned 123).
    REVIEW_ISSUES=$(gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: No review evidence found on this branch. Run /review before merging."
    }
  }'
  exit 0
fi

# Check for detached HEAD -- auto-sync needs a branch to push
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Warning: Detached HEAD state. Skipping auto-sync." >&2
  exit 0
fi

# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with merge and should not block it).
# Skip if not inside a work tree (bare repo context): git diff --quiet HEAD
# returns 128 and git diff --cached --quiet returns 1 (empty index vs HEAD),
# both false positives. Fail open in bare repo setups (#1386).
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit before merging."
      }
    }'
    exit 0
  fi
fi

# Fetch latest main -- fail open on network error
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

# Check if sync is needed by comparing merge-base with origin/main tip
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  # Could not determine relationship -- fail open
  echo "Warning: Could not determine branch relationship with main. Proceeding with merge." >&2
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no sync needed
  echo "[ok] Branch already up-to-date with origin/main." >&2
  exit 0
fi

# Attempt merge
if ! git -C "$WORK_DIR" merge origin/main >/dev/null 2>&1; then
  # Merge failed -- capture conflicts BEFORE aborting (abort clears conflict state)
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" merge --abort 2>/dev/null || true
  jq -n --arg files "${CONFLICT_FILES:-unknown}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Merge of origin/main failed. Conflicting files: " + $files + ". Resolve conflicts manually before merging.")
    }
  }'
  exit 0
fi

# Merge succeeded -- push to update the remote branch.
# Regular push (not force-push) since merge does not rewrite history.
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push origin HEAD 2>&1); then
  jq -n --arg output "$PUSH_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Merge succeeded but push failed. Push manually before merging. Error: " + $output)
    }
  }'
  exit 0
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: merged origin/main into " + $branch + " and pushed. Branch is now current.")
  }
}'
exit 0
