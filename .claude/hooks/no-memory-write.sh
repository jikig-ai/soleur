#!/usr/bin/env bash
# PreToolUse hook for Write, Edit, MultiEdit, NotebookEdit, and Bash.
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
#
# Coverage: file-tool tools (Write/Edit/MultiEdit/NotebookEdit) check
# `file_path` / `notebook_path`; Bash checks the command string for memory-path
# substrings to catch the obvious redirect/copy/edit bypasses
# (`tee`, `cat >`, `printf >>`, `cp`, `mv`, `sed -i`, `python -c open().write`,
# editor `:w`, etc.). Determined adversarial evasion (`eval`, base64) is out of
# scope — this gate exists for accidental rationalization, not bypass-defeat.

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)

# Fail-open on malformed JSON: a parse failure in the harness payload should
# NOT silently block every tool call. Exit 0 (pass-through) and let the
# downstream tool see the original payload; the harness will surface the
# malformed input separately.
if ! TARGET=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.command
  // ""
' 2>/dev/null); then
  exit 0
fi

[[ -z "$TARGET" ]] && exit 0

# Match anywhere in the path/command so a tool invocation via a different
# absolute prefix (symlinked $HOME) or a Bash command quoting a memory path
# still trips. The `[^/]+` requires a project-slug segment between
# `projects/` and `memory` so an unrelated `.../memory/` outside the projects
# tree is not blocked. The `(/|$|["'\''[:space:]])` boundary catches Bash
# commands that quote or terminate the path (e.g., `tee "$HOME/.claude/...memory/foo.md"`).
if [[ "$TARGET" =~ /\.claude/projects/[^/]+/memory(/|$|[\"\'[:space:]]) ]]; then
  emit_incident hr-never-write-to-claude-code-memory-claude deny \
    "Memory writes do not transfer across machines/operators" "$TARGET"
  jq -n --arg target "$TARGET" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: hr-never-write-to-claude-code-memory-claude (Source: AGENTS.core.md).\n\nTarget: " + $target + "\n\nWrites to ~/.claude/projects/*/memory/ do not transfer across machines or operators. Commit knowledge to one of these committed repo files instead:\n  - AGENTS.md / AGENTS.{core,docs,rest}.md (hard rules + workflow gates)\n  - knowledge-base/overview/constitution.md (architecture + style)\n  - knowledge-base/project/learnings/<category>/<slug>.md (session learnings)\n\nSee plugins/soleur/skills/compound for the canonical learning-write flow.")
    }
  }'
  exit 0
fi

exit 0
