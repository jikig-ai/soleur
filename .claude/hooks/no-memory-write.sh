#!/usr/bin/env bash
# PreToolUse hook for Write, Edit, NotebookEdit, and MultiEdit tools.
# Blocks writes to Claude Code memory directories (~/.claude/projects/*/memory/).
#
# Source rule: AGENTS.core.md hr-never-write-to-claude-code-memory-claude
# Source learning: knowledge-base/project/learnings/workflow-issues/2026-05-22-honor-skill-chain-through-do-not-rationalize-stops.md
#
# Knowledge must go to committed repo files so it transfers across machines and
# operators — local memory writes do not. The prose rule is documented but the
# memory paths sit outside the repo root and worktree-write-guard.sh allows
# them. Without this gate, every session is one rationalization away from a
# non-transferable write.

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

[[ -z "$FILE_PATH" ]] && exit 0

# Memory paths follow ~/.claude/projects/<project-slug>/memory/ on every host.
# Match anywhere in the path so a tool invocation via a different absolute
# prefix (e.g., a symlinked $HOME) still trips. The `[^/]+` requires a
# project-slug segment between `projects/` and `memory/` so an unrelated
# `.../memory/` outside the projects tree is not blocked.
if [[ "$FILE_PATH" =~ /\.claude/projects/[^/]+/memory(/|$) ]]; then
  emit_incident hr-never-write-to-claude-code-memory-claude deny \
    "Memory writes do not transfer across machines/operators" "$FILE_PATH"
  jq -n --arg path "$FILE_PATH" '{
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: hr-never-write-to-claude-code-memory-claude. Path: " + $path + "\n\nWrites to ~/.claude/projects/*/memory/ do not transfer across machines or operators. Commit knowledge to one of these committed repo files instead:\n  - AGENTS.md / AGENTS.{core,docs,rest}.md (hard rules + workflow gates)\n  - knowledge-base/overview/constitution.md (architecture + style)\n  - knowledge-base/project/learnings/<category>/<slug>.md (session learnings)\n\nSee plugins/soleur/skills/compound for the canonical learning-write flow.")
    }
  }'
  exit 0
fi

exit 0
