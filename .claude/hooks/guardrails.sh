#!/usr/bin/env bash
# PreToolUse guardrail hook for Bash commands.
# Blocks: commits on main, rm -rf on worktrees, --delete-branch with active worktrees,
# commits with conflict markers in staged content, gh issue create without --milestone,
# git stash in worktrees.
# NOTE: When adding or modifying guards, update the corresponding prose rule comments below.
#
# Corresponding prose rules:
#   guardrails:block-commit-on-main — constitution.md "Never allow agents to work directly on the default branch"
#   guardrails:block-rm-rf-worktrees — constitution.md "Never rm -rf on the current directory, a worktree path, or the repo root"
#   guardrails:block-delete-branch — constitution.md "Never use --delete-branch with gh pr merge"
#   guardrails:block-conflict-markers — constitution.md "grep staged content for conflict markers"
#   guardrails:require-milestone — constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"
#   guardrails:block-stash-in-worktrees — AGENTS.md "Never git stash in worktrees"

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
# Single jq fork: @sh shell-escapes both fields so eval is safe for embedded
# quotes, newlines ($'\n' ANSI-C form), and shell metacharacters. Previously
# two jq forks ran on every Bash tool invocation; collapsing to one halves
# the hook's hot-path overhead.
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"' 2>/dev/null || echo 'COMMAND="" TOOL_NAME=""')"

# Bypass preflight — records (does NOT block) when a known bypass flag is used.
# v1 scope: --no-verify, LEFTHOOK=0. Extend detect_bypass (lib/incidents.sh)
# once data justifies broader detection.
_bypass_rid=$(detect_bypass "$TOOL_NAME" "$COMMAND")
if [[ -n "$_bypass_rid" ]]; then
  emit_incident "$_bypass_rid" "bypass" "${COMMAND:0:50}" "$COMMAND"
fi

# guardrails:block-commit-on-main — Block git commit on main branch
# Match git commit at start of string OR after chain operators (&&, ||, ;)
# so chained commands like "git add && git commit" are caught.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  # Resolve the branch from the command's working directory, not the hook's CWD.
  # resolve_command_cwd (lib/incidents.sh) covers: "cd /worktree && ...",
  # "git -C /worktree commit", and hook-input .cwd. Falls through to the
  # hook's own CWD if none resolve.
  GIT_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    emit_incident "guardrails-block-commit-on-main" "deny" "Never allow agents to work directly on default branch" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
# Match rm with recursive-force flags followed by a worktree path as an argument.
# Uses a single pattern to avoid false positives when .worktrees/ appears in
# unrelated text (e.g., inside a gh issue comment body or heredoc).
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
  emit_incident "guardrails-block-rm-rf-worktrees" "deny" "Never rm -rf on a worktree path" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
    }
  }'
  exit 0
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    emit_incident "guardrails-block-delete-branch" "deny" "Never use --delete-branch with gh pr merge" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
# Matches git commit and git merge --continue (which internally commits).
# Allows optional -C <path> between git and commit/merge.
# Checks only added lines (^\+) to avoid blocking removal of markers.
# CWD resolution mirrors guardrails:block-commit-on-main via resolve_command_cwd.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)'; then
  CONFLICT_MARKERS_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    STAGED_DIFF=$(git -C "$CONFLICT_MARKERS_DIR" diff --cached 2>/dev/null || true)
  else
    STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
  fi
  if echo "$STAGED_DIFF" | grep -qE '^\+(<{7}|={7}|>{7})'; then
    emit_incident "guardrails-block-conflict-markers" "deny" "Resolve conflicts before committing" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."
      }
    }'
    exit 0
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'; then
  if ! echo "$COMMAND" | grep -qF -- '--milestone'; then
    emit_incident "guardrails-require-milestone" "deny" "gh issue create must include --milestone" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: gh issue create must include --milestone. Default to '\''Post-MVP / Later'\'' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash unconditionally
# Unconditional: CWD detection is unreliable in subagent contexts where the shell
# CWD is a worktree but no explicit "cd" prefix appears in the command. Blocking
# git stash everywhere is safe — AGENTS.md requires "commit WIP first" and there
# is no legitimate automated use case for git stash in this repo.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+stash'; then
  emit_incident "hr-never-git-stash-in-worktrees" "deny" "Never git stash in worktrees" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: git stash is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
    }
  }'
  exit 0
fi

# All checks passed
exit 0
