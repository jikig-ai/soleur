#!/usr/bin/env bash
# PreToolUse hook: auto-rebase against origin/main before gh pr merge.
# Ensures the branch is current before merge to prevent post-queue conflicts.
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree, push failure).

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands.
# Word boundary (\s|$) prevents false positives on hypothetical merge-* subcommands.
# Chain operator pattern from guardrails.sh catches chained commands.
if ! echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)'; then
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

# Check for detached HEAD -- rebase works but push will fail without upstream
CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Warning: Detached HEAD state. Skipping auto-rebase." >&2
  exit 0
fi

# Skip if already on main/master -- nothing to rebase
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with rebase and should not block it)
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

# Fetch latest main -- fail open on network error
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

# Check if rebase is needed by comparing merge-base with origin/main tip
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  # Could not determine relationship -- fail open
  echo "Warning: Could not determine branch relationship with main. Proceeding with merge." >&2
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no rebase needed
  echo "[ok] Branch already up-to-date with origin/main." >&2
  exit 0
fi

# Attempt rebase
if ! git -C "$WORK_DIR" rebase origin/main >/dev/null 2>&1; then
  # Rebase failed -- capture conflicts BEFORE aborting (abort clears conflict state)
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" rebase --abort 2>/dev/null || true
  jq -n --arg files "${CONFLICT_FILES:-unknown}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Rebase against origin/main failed. Conflicting files: " + $files + ". Resolve conflicts manually before merging.")
    }
  }'
  exit 0
fi

# Rebase succeeded -- force push to update the remote branch.
# --force-with-lease --force-if-includes: prevents overwriting remote work
# and guards against background fetches weakening the lease (Git 2.30+).
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push --force-with-lease --force-if-includes origin HEAD 2>&1); then
  jq -n --arg output "$PUSH_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Rebase succeeded but force-push failed. Push manually before merging. Error: " + $output)
    }
  }'
  exit 0
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: rebased " + $branch + " onto origin/main and force-pushed. Branch is now current.")
  }
}'
exit 0
