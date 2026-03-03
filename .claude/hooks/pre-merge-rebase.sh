#!/usr/bin/env bash
# PreToolUse hook: auto-rebase against origin/main before gh pr merge.
# Ensures the branch is current before merge to prevent post-queue conflicts.
#
# Design: This hook has SIDE EFFECTS (rebase + push), unlike guardrails.sh
# which is pure inspection. Side effects are always beneficial (branch becomes
# more current) and non-reversible (acceptable because staleness is never better).
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree).

set -eo pipefail
# Note: -u (nounset) is omitted intentionally. Hook scripts must return JSON
# on failure paths, and an unset variable causing immediate exit prevents the
# structured error response that Claude Code needs to show the agent why the
# tool call was blocked.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Early exit: only intercept gh pr merge commands.
# Uses the (^|&&|\|\||;) pattern from guardrails.sh to catch chained commands.
if ! echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge'; then
  exit 0
fi

# Determine the working directory.
# Priority: cd in command > cwd from hook input > fail open.
GIT_DIR=""
if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
  GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
fi
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [[ -n "$GIT_DIR" ]] && [[ -d "$GIT_DIR" ]]; then
  WORK_DIR="$GIT_DIR"
elif [[ -n "$HOOK_CWD" ]] && [[ -d "$HOOK_CWD" ]]; then
  WORK_DIR="$HOOK_CWD"
else
  # Not in a recognizable directory -- fail open
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
if ! git -C "$WORK_DIR" fetch origin main 2>/dev/null; then
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
# --force-with-lease: prevents overwriting remote work pushed by others.
# --force-if-includes: ensures local branch has incorporated remote tracking
# branch state, protecting against background fetches weakening the lease.
PUSH_OUTPUT=""
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push --force-with-lease --force-if-includes 2>&1); then
  # Try fallback without --force-if-includes for older git versions
  if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push --force-with-lease 2>&1); then
    echo "Warning: Rebase succeeded but force-push failed: $PUSH_OUTPUT" >&2
    # Still allow merge -- the agent may need to push manually
  fi
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: rebased " + $branch + " onto origin/main and force-pushed. Branch is now current.")
  }
}'
exit 0
