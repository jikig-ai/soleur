---
title: "fix: ralph-loop stop hook fires awk error when no loop is active"
type: fix
date: 2026-03-09
semver: patch
---

# fix: ralph-loop stop hook fires awk error when no loop is active

## Enhancement Summary

**Deepened on:** 2026-03-09
**Sections enhanced:** 5 (Problem Statement, Root Cause, Proposed Solution, Acceptance Criteria, Test Scenarios)
**Research sources:** Claude Code hooks API reference (code.claude.com/docs/en/hooks), project learnings (set-euo-pipefail-upgrade-pitfalls, cleanup-merged-path-mismatch, sessionstart-hook-api-contract)

### Key Improvements
1. Discovered `stop_hook_active` input field -- the hook must check this to prevent infinite re-entry, which is the actual root cause of the infinite loop
2. Discovered `last_assistant_message` input field -- eliminates transcript file parsing entirely, simplifying ~20 lines of jq/grep logic
3. Corrected exit code analysis: exit 1 under `set -e` is a non-blocking error (stop proceeds), NOT a blocking error. Only exit 2 or `{"decision": "block"}` blocks the stop. The infinite loop is caused by the hook successfully returning `{"decision": "block"}` after the state file is deleted mid-iteration

### New Considerations Discovered
- The hook does not check `stop_hook_active`, violating the upstream API recommendation for preventing infinite loops
- The `last_assistant_message` field in hook input makes transcript parsing redundant (lines 66-89 of current stop-hook.sh)
- The `cwd` field in hook input could be used as a fallback for project root resolution

## Overview

The ralph-loop stop hook (`plugins/soleur/hooks/stop-hook.sh`) produces an awk error and enters an infinite exit-blocking loop when no ralph loop is active. The relative path `.claude/ralph-loop.local.md` does not resolve correctly when the hook is invoked from a worktree directory, and the hook does not check the `stop_hook_active` field, allowing infinite re-entry.

## Problem Statement

Four interacting defects (revised from three after API research):

1. **Relative path resolution**: The stop hook uses `RALPH_STATE_FILE=".claude/ralph-loop.local.md"` (line 16) -- a bare relative path. Claude Code invokes hooks with CWD set to the project root, but in worktree scenarios the CWD may be the worktree directory (`.worktrees/feat-*`), not the repo root where `.claude/` lives. The welcome hook (`welcome-hook.sh`) already solves this with `git rev-parse --show-toplevel`, but the stop hook does not.

2. **No `stop_hook_active` guard**: The Claude Code Stop hook API provides a `stop_hook_active` boolean field in the JSON input. When `true`, Claude Code is already continuing as a result of a previous stop hook invocation. The upstream docs explicitly state: "Check this value or process the transcript to prevent Claude Code from running indefinitely." The current stop hook never checks this field, which is the primary cause of the infinite loop described in #464.

3. **No early-exit on missing file before stdin read**: The file-existence check (line 18) runs after `HOOK_INPUT=$(cat)` (line 13). If the state file does not exist, the script still consumes stdin before exiting. Reordering the check before the stdin read is more robust -- it avoids any downstream failures when the hook has nothing to do.

4. **Transcript parsing when `last_assistant_message` is available**: The hook reads the transcript file (lines 66-89) to extract the last assistant message, parsing JSONL with grep and jq. The Stop hook API provides `last_assistant_message` directly in the input JSON, making the transcript parsing unnecessary and fragile. While not a direct cause of #464, it adds complexity and failure surface.

### Research Insights: Exit Code Semantics

The original analysis assumed that exit code 1 (from `set -e` aborting on awk/jq errors) would cause the hook to block the stop. This is incorrect per the Claude Code hooks API:

| Exit code | Behavior for Stop hooks |
|-----------|------------------------|
| 0 | Success. JSON output parsed for `decision` field |
| 2 | Blocking error. Prevents Claude from stopping, stderr fed to Claude |
| Any other (including 1) | Non-blocking error. Shown in verbose mode, stop proceeds |

Exit code 1 from `set -e` is a **non-blocking error** -- the stop proceeds. The infinite loop is NOT caused by exit code 1. Instead, the loop occurs when:
1. A ralph loop is active and the hook correctly returns `{"decision": "block"}`
2. The loop completes (state file deleted mid-iteration)
3. The hook fires again but encounters the awk error on the now-deleted file
4. However, step 3 would exit 1 (non-blocking), allowing the stop -- so the loop eventually ends

The more likely infinite loop scenario is: the hook successfully returns `{"decision": "block"}` on every invocation because the state file exists but the loop cannot make progress (e.g., stuck detection is not triggering fast enough, or the completion promise is never emitted). Without `stop_hook_active` checking, there is no escape hatch.

## Root Cause Analysis

The stop hook was ported from the upstream ralph-loop plugin which assumed a single-project-root working directory. The Soleur plugin operates in a worktree model where CWD varies. The welcome hook was updated with `git rev-parse --show-toplevel` but the stop hook was not.

The primary cause of the infinite loop is the missing `stop_hook_active` guard. The Claude Code hooks API provides this field specifically to prevent stop hooks from running indefinitely. Without checking it, a stuck ralph loop has no escape mechanism other than waiting for stuck detection to fire (which requires 3 consecutive empty responses, each burning a full Claude turn).

### Applicable Learnings

**From `set-euo-pipefail-upgrade-pitfalls`:** The stop hook uses `set -euo pipefail` and has grep pipelines (lines 25-28, 34-35) that use `|| true` guards. These were correctly applied in PR #454. However, if `git rev-parse --show-toplevel` fails (e.g., outside a git repo), the `|| PROJECT_ROOT="."` fallback handles this. No new pipefail traps are introduced by the fix.

**From `cleanup-merged-path-mismatch`:** Never construct filesystem paths from git ref names. The stop hook does not do this, but the learning reinforces using `git rev-parse --show-toplevel` over assumptions about CWD.

**From `sessionstart-hook-api-contract`:** Always verify hook API claims against the upstream spec. The original plan assumed exit code 1 blocks the stop (it does not). This finding was corrected by reading the actual API docs.

## Proposed Solution

### Fix 1: Resolve project root (like welcome-hook.sh)

Add the same `PROJECT_ROOT` resolution pattern used in `welcome-hook.sh`:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"
```

This ensures the state file path resolves correctly regardless of CWD.

### Fix 2: Move file-existence check before stdin read

Reorder the script so the `if [[ ! -f "$RALPH_STATE_FILE" ]]` check runs before `HOOK_INPUT=$(cat)`. When no ralph loop is active, the hook exits immediately without touching stdin, jq, or awk.

```bash
# Resolve project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# Check if ralph-loop is active BEFORE reading stdin
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Only read hook input if we need it
HOOK_INPUT=$(cat)
```

### Fix 3: Use `last_assistant_message` from hook input instead of transcript parsing

The Stop hook API provides `last_assistant_message` in the JSON input. Replace the transcript file parsing (lines 66-89) with:

```bash
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
```

This eliminates:
- `TRANSCRIPT_PATH` extraction and file existence check (lines 66-72)
- `grep` for assistant messages in transcript (lines 75-81)
- Complex `jq` extraction of text content blocks (lines 84-89)

Reduces ~25 lines to 1, removes a failure path (transcript file not found), and uses the API as intended.

### Fix 4: Apply PROJECT_ROOT to all file operations

The setup script (`plugins/soleur/scripts/setup-ralph-loop.sh`) also uses bare relative paths for `.claude/ralph-loop.local.md`. Apply the same `git rev-parse --show-toplevel` pattern there for consistency, so the state file is always created at the repo root regardless of CWD.

### Edge Cases

- **`git rev-parse` outside a git repo:** Fallback `|| PROJECT_ROOT="."` handles this. The hook degrades to current behavior.
- **State file deleted between `-f` check and awk read:** Possible race condition if an external process removes the file. The awk would fail with exit 1, which is a non-blocking error (stop proceeds). Acceptable behavior.
- **`last_assistant_message` field absent in older Claude Code versions:** Use `jq -r '.last_assistant_message // ""'` with `// ""` fallback so the field defaults to empty string. If absent, stuck detection treats it as a minimal response and the counter increments, eventually terminating the loop.

## Non-Goals

- Changing the ralph-loop state file format or location
- Adding new ralph-loop features beyond the bug fix scope
- Modifying the hook API contract
- Adding `stop_hook_active` checking (this is a safety improvement that should be tracked as a separate enhancement to avoid scope creep in this bug fix; however, if implementation is trivial -- a 3-line guard -- it can be included)

## Acceptance Criteria

- [ ] When `.claude/ralph-loop.local.md` does not exist, the stop hook exits 0 cleanly on the first invocation with no awk/jq errors (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The stop hook resolves the state file path using `git rev-parse --show-toplevel`, not a bare relative path (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The file-existence check runs before `HOOK_INPUT=$(cat)` so no stdin is consumed when no loop is active (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The stop hook uses `last_assistant_message` from hook input instead of parsing the transcript file (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The setup script also resolves project root for state file creation consistency (`plugins/soleur/scripts/setup-ralph-loop.sh`)
- [ ] All existing tests in `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` continue to pass (update transcript-based tests to use `last_assistant_message` in hook input)
- [ ] New test: hook exits 0 from a non-root CWD when state file does not exist
- [ ] New test: hook exits 0 from a non-root CWD when state file exists at the repo root

## Test Scenarios

- Given no `.claude/ralph-loop.local.md` exists, when the stop hook fires from the repo root, then it exits 0 with no output on stdout or stderr
- Given no `.claude/ralph-loop.local.md` exists, when the stop hook fires from a subdirectory (simulating worktree CWD), then it exits 0 with no output
- Given a valid state file at `<project-root>/.claude/ralph-loop.local.md`, when the stop hook fires from a subdirectory, then it finds the file and processes normally (blocks exit, continues loop)
- Given no state file exists, when the stop hook fires with empty stdin, then it exits 0 (no crash from jq parsing empty input)
- Given hook input with `last_assistant_message` containing a completion promise, when the hook fires, then it detects the promise and exits 0 (state file removed)
- Given hook input with `last_assistant_message` containing a short response, when stuck_count is at threshold - 1, then stuck detection terminates the loop
- Given all 15 existing tests, when updated to provide `last_assistant_message` in hook input, then all pass

### Test Infrastructure Changes

The existing test helper `run_hook` constructs hook input with only `transcript_path`. After Fix 3 (using `last_assistant_message`), the helper must also include `last_assistant_message` in the JSON input:

```bash
run_hook() {
  local dir="$1"
  local transcript_path="$2"
  local last_message="${3:-}"

  local hook_input
  hook_input=$(jq -n --arg tp "$transcript_path" --arg lm "$last_message" \
    '{"transcript_path": $tp, "last_assistant_message": $lm}')

  cd "$dir"
  echo "$hook_input" | bash "$HOOK" 2>/dev/null || true
}
```

Existing callers that pass transcript content via file will need to also pass the text content as the third argument.

## MVP

### plugins/soleur/hooks/stop-hook.sh (lines 10-24, reordered)

```bash
set -euo pipefail

# Resolve project root (worktree-safe)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# Check if ralph-loop is active BEFORE reading stdin
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop -- allow exit
  exit 0
fi

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)
```

### plugins/soleur/hooks/stop-hook.sh (lines 66-89 replaced with single line)

```bash
# Use last_assistant_message from hook input (Stop hook API provides this directly)
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
```

### plugins/soleur/scripts/setup-ralph-loop.sh (add near top)

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
# ... then use ${PROJECT_ROOT}/.claude/ for mkdir and state file creation
```

## References

- GitHub issue: #464
- Claude Code hooks API: https://code.claude.com/docs/en/hooks (Stop hook input, exit code semantics, `stop_hook_active`, `last_assistant_message`)
- Stop hook: `plugins/soleur/hooks/stop-hook.sh`
- Setup script: `plugins/soleur/scripts/setup-ralph-loop.sh`
- Welcome hook (reference pattern): `plugins/soleur/hooks/welcome-hook.sh`
- Existing tests: `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`
- Learning: `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
- Learning: `knowledge-base/project/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
- Learning: `knowledge-base/project/learnings/2026-02-22-cleanup-merged-path-mismatch.md`
- Learning: `knowledge-base/project/learnings/2026-03-04-sessionstart-hook-api-contract.md`
- Prior PR: #456 (scoped frontmatter parser)
- Prior PR: #454 (stuck detection)
