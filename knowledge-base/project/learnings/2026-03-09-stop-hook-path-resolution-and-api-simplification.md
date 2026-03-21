# Learning: Stop hook path resolution and API simplification

## Problem

The ralph-loop stop-hook.sh had three interrelated bugs:

1. **Relative path resolution** — `RALPH_STATE_FILE=".claude/ralph-loop.local.md"` assumed CWD was the project root. In worktrees (`.worktrees/feat-*`) or subdirectories, the file wasn't found, causing the hook to silently exit and break the ralph loop.

2. **Stdin blocking** — `HOOK_INPUT=$(cat)` read all stdin before checking if the state file existed. When no ralph loop was active, the hook would hang waiting for stdin instead of exiting immediately.

3. **Redundant transcript parsing** — The hook extracted the last assistant message by grepping a JSONL transcript file and parsing JSON content blocks with jq (~25 lines). The stop hook API already provides `last_assistant_message` directly in the hook input JSON, making this unnecessary.

## Solution

Three targeted fixes:

1. Added `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` to resolve paths relative to the git root, regardless of CWD. Applied to both `stop-hook.sh` and `setup-ralph-loop.sh`.

2. Moved the state file existence check (`if [[ ! -f "$RALPH_STATE_FILE" ]]; then exit 0; fi`) before `HOOK_INPUT=$(cat)` so the hook exits immediately when no loop is active.

3. Replaced transcript parsing with a single line:

   ```bash
   LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
   ```

Net result: -23 lines of code. Tests updated from transcript-based helpers to direct `last_assistant_message` passing, plus 2 new subdirectory CWD tests.

## Key Insight

When a framework API provides data directly, use it instead of reconstructing it from lower-level artifacts. The transcript file was an implementation detail — the hook input contract (`last_assistant_message`) was the stable API surface. Similarly, shell scripts invoked from varying CWDs must resolve paths from the project root, not assume a specific working directory.

## Related

- PR #456: scope frontmatter parser and sed substitution to YAML block
- PR #454: add stuck-detection to stop hook for empty responses
- PR #229: bundle ralph-loop into Soleur plugin

## Tags

category: runtime-errors
module: plugins/soleur/hooks
