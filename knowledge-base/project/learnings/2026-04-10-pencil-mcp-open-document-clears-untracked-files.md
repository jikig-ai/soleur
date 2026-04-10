# Learning: Pencil MCP open_document silently clears untracked .pen file contents

## Problem

Pencil MCP's `open_document` tool silently destroys `.pen` file contents when opening them. A file containing 27,634 tokens of valid JSON design data (6 complete UI screens) was reduced to 40 characters (`{"version":"2.9","children":[]}`) after a single `open_document` call. The tool returned success with no error or warning.

The failure sequence:

1. `Read` tool confirmed the file had full content (27,634 tokens of valid JSON)
2. `open_document` returned success
3. `get_editor_state` reported "document is empty (no top-level nodes)"
4. `snapshot_layout` returned empty nodes
5. Direct file read via Python confirmed the file had been overwritten with an empty document skeleton
6. `git status` showed the file as untracked -- no git history to recover from

## Root Cause

Pencil MCP's `open_document` overwrites the target file with an empty document when it cannot properly parse or load the existing content. Instead of failing with an error, it silently re-initializes the file. There is no warning, no backup, and no undo mechanism.

## Solution

Rebuilt all 6 design screens from the exported PNG screenshots that existed alongside the `.pen` file. Used `batch_design` operations to recreate the designs programmatically from visual references.

## Prevention

1. **Always commit `.pen` files to git before opening them with Pencil MCP.** This ensures `git checkout -- <file>` or `git show HEAD:<file>` can recover content if the tool clears it.
2. **Add a PreToolUse hook** for `mcp__pencil__open_document` that blocks opening untracked files. Draft:

    ```bash
    #!/usr/bin/env bash
    set -euo pipefail
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.filePath // ""')
    [[ -z "$FILE_PATH" ]] && exit 0
    if ! git ls-files --error-unmatch "$FILE_PATH" &>/dev/null; then
      jq -n '{hookSpecificOutput:{permissionDecision:"deny",
        permissionDecisionReason:"BLOCKED: .pen file is untracked in git. Commit it first to enable recovery if open_document corrupts the file."}}'
      exit 0
    fi
    exit 0
    ```

3. **Verify content after opening.** Immediately after `open_document`, call `get_editor_state` and check that the node count is non-zero. If empty but the file previously had content, restore from git before proceeding.
4. **Never trust `open_document` success status.** The tool returns success even when it has destroyed the file contents. Always validate post-open state.

## Session Errors

1. **Pencil MCP `open_document` cleared .pen file contents** -- Recovery: rebuilt all 6 screens from exported PNG screenshots using batch_design. Prevention: commit .pen files before opening; add PreToolUse hook to block opening untracked files.
2. **Pencil MCP `get_editor_state` and `snapshot_layout` returned empty after opening** -- Recovery: investigated with direct file reads, confirmed file was overwritten. Prevention: verify post-open state and restore from git if empty.

## Key Insight

MCP tools that open files for editing should be treated as potentially destructive until verified safe. Always ensure design files are tracked in git before invoking MCP open operations. The cost of a `git add && git commit` is trivial compared to rebuilding lost designs.

## Related Learnings

- `2026-02-14-pencil-mcp-local-binary-constraint.md`
- `2026-02-27-pencil-editor-operational-requirements.md`
- `2026-03-10-pencil-batch-design-text-node-gotchas.md`

## Tags

category: integration-issues
module: design-tooling/mcp-tools
severity: critical
tags: pencil-mcp, data-loss, mcp-tools, design-tooling, untracked-files
