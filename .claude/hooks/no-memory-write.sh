#!/usr/bin/env bash
# PreToolUse hook for Write, Edit, MultiEdit, NotebookEdit, and Bash.
# Blocks writes to Claude Code memory directories (~/.claude/projects/*/memory/).
#
# Source rule: AGENTS.rules.md hr-never-write-to-claude-code-memory-claude
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

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[no-memory-write] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)

# ADR-156: hook stdin is model-controlled. A non-string field is surfaced, never
# coerced — this hook never ran eval, but `jq -r` renders an array across lines,
# which would not match the memory-path regex below, so the payload slipped the
# guard entirely (#7164). ADR-157: it asks rather than continuing silently.
#
# This REPLACES the previous fail-open-on-malformed-JSON branch. The posture is
# unchanged in the direction that mattered — the hook still never blocks the
# session on a parse failure — but the disarm is no longer silent.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "no-memory-write"
  hook_input_should_ask && { hook_input_emit_ask "no-memory-write"; exit 0; }
  exit 0
fi

# file_path // notebook_path // command, as before. HOOK_FILE_PATH already folds
# notebook_path in. NB: an EXPLICITLY empty file_path now falls through to the
# command where jq's `//` would have kept the empty string — that makes the
# guard inspect strictly more payloads, never fewer.
TARGET="${HOOK_FILE_PATH:-$HOOK_CMD}"

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
      permissionDecisionReason: ("BLOCKED: hr-never-write-to-claude-code-memory-claude (Source: AGENTS.rules.md).\n\nTarget: " + $target + "\n\nWrites to ~/.claude/projects/*/memory/ do not transfer across machines or operators. Commit knowledge to one of these committed repo files instead:\n  - AGENTS.md / AGENTS.rules.md (hard rules + workflow gates)\n  - knowledge-base/project/constitution.md (architecture + style)\n  - knowledge-base/project/learnings/<category>/<slug>.md (session learnings)\n\nSee plugins/soleur/skills/compound for the canonical learning-write flow.")
    }
  }'
  exit 0
fi

exit 0
