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
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

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
  # Three patterns: "cd /worktree && ...", "git -C /worktree commit", or bare
  # "git commit" when Claude Code's shell CWD is already the worktree.
  GIT_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    GIT_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    # Fallback: check the hook input for a cwd field (future-proofing),
    # then fall back to the hook's own CWD (repo root).
    HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      BRANCH=$(git -C "$HOOK_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    else
      BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi
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
# CWD resolution mirrors guardrails:block-commit-on-main: cd, git -C, .cwd fallback.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)'; then
  CONFLICT_MARKERS_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$CONFLICT_MARKERS_DIR" ] || [ ! -d "$CONFLICT_MARKERS_DIR" ]; then
    CONFLICT_MARKERS_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
    if [ -n "$CONFLICT_MARKERS_CWD" ] && [ -d "$CONFLICT_MARKERS_CWD" ]; then
      CONFLICT_MARKERS_DIR="$CONFLICT_MARKERS_CWD"
    fi
  fi
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

# guardrails:block-stash-in-worktrees — Block git stash in worktrees
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+stash'; then
  # Resolve CWD: check cd target, git -C path, .cwd field, then hook CWD
  STASH_GUARD_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$STASH_GUARD_DIR" ] || [ ! -d "$STASH_GUARD_DIR" ]; then
    STASH_GUARD_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
    if [ -n "$STASH_GUARD_CWD" ] && [ -d "$STASH_GUARD_CWD" ]; then
      STASH_GUARD_DIR="$STASH_GUARD_CWD"
    fi
  fi
  RESOLVE_DIR="${STASH_GUARD_DIR:-.}"
  if echo "$(cd "$RESOLVE_DIR" 2>/dev/null && pwd)" | grep -qF '.worktrees'; then
    emit_incident "hr-never-git-stash-in-worktrees" "deny" "Never git stash in worktrees" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: git stash in worktrees is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
      }
    }'
    exit 0
  fi
fi

# All checks passed
exit 0
