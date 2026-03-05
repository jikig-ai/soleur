---
title: "fix: Ralph Loop stuck-detection for empty/minimal responses"
type: fix
date: 2026-03-05
semver: patch
deepened: 2026-03-05
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 3 (Technical Approach, MVP, Test Scenarios)
**Research sources:** constitution.md shell conventions, `set-euo-pipefail-upgrade-pitfalls` learning, `bundle-external-plugin-into-soleur` learning, stop-hook.sh source analysis

### Key Improvements
1. Fixed `set -euo pipefail` trap in MVP code: `grep` for missing frontmatter fields returns exit 1 under `pipefail`, aborting the hook -- must append `|| true`
2. Clarified placement order: stuck detection fires AFTER completion promise check but BEFORE iteration increment, so normal completions bypass the counter entirely
3. Added edge case for tool-use-only responses where `LAST_OUTPUT` extraction returns empty string (jq `map(select(.type == "text"))` yields nothing when response is all tool_use blocks)

# fix: Ralph Loop stuck-detection for empty/minimal responses

## Overview

Add stuck-detection to `plugins/soleur/hooks/stop-hook.sh` so that Ralph Loops auto-terminate after N consecutive empty or minimal assistant responses, instead of cycling indefinitely. This addresses a production incident where a crash-recovered session looped 31+ times with nothing to do because the completion promise was never emitted.

## Problem Statement

When a Ralph Loop's completion promise is never emitted (e.g., after crash recovery where the original task is already done), the stop hook enters an infinite cycle:

1. Assistant outputs empty/minimal response (nothing left to do)
2. Stop hook checks for `<promise>DONE</promise>` -- not found
3. Hook blocks exit and re-injects the prompt
4. Repeat (observed at 31+ iterations before manual intervention)

The root cause is that the stop hook has only two exit conditions: (1) max iterations reached, (2) completion promise matched. There is no detection for the degenerate case where the assistant has nothing substantive to contribute.

## Proposed Solution

Add a consecutive minimal-response counter to the stop hook. When the counter reaches a configurable threshold (default 3), auto-terminate with a warning and clean up the state file.

### What counts as "minimal"

A response is minimal if the text content (extracted from the JSONL transcript, stripped of whitespace) is fewer than 20 characters. This covers:

- Empty responses (0 characters)
- Whitespace-only responses
- Responses like "OK" or "Done" that contain no substantive work
- Tool-only responses with no accompanying text

The 20-character threshold is intentionally conservative -- a response with any substantive content (a file path, a command, an explanation) will exceed it.

### Counter mechanism

The counter is stored in the state file frontmatter as `stuck_count: N`. It is:

- **Incremented** when the current response is minimal
- **Reset to 0** when the current response is substantive (>= 20 characters)
- **Checked against threshold** before deciding to block or allow exit

### Threshold configuration

The `stuck_threshold` field in the state file frontmatter controls how many consecutive minimal responses trigger termination. Default: 3.

- Set via `--stuck-threshold <n>` flag in `setup-ralph-loop.sh`
- Set to 0 to disable stuck detection entirely

## Technical Approach

### Files Modified

#### `plugins/soleur/hooks/stop-hook.sh`

Changes to the stop hook (lines referenced from current file):

1. **Parse `stuck_count` and `stuck_threshold` from frontmatter** (after line 28):
   - Extract `stuck_count` (default 0) and `stuck_threshold` (default 3)
   - Validate as numeric, same pattern as `ITERATION` and `MAX_ITERATIONS` validation
   - **Critical: append `|| true` to grep commands** -- under `set -euo pipefail`, `grep` exits 1 when the field is missing (pre-existing state files), which aborts the script. See learning: `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`

2. **Measure response length** (after line 74, where `LAST_OUTPUT` is extracted):
   - Strip whitespace: `STRIPPED_OUTPUT=$(echo "$LAST_OUTPUT" | tr -d '[:space:]')`
   - Check length: `${#STRIPPED_OUTPUT}`

3. **Update stuck counter** (new section AFTER completion promise check at line 93, BEFORE the "Not complete" block at line 95):
   - If length < 20: increment `stuck_count`
   - If length >= 20: reset `stuck_count` to 0
   - **Placement rationale:** After the promise check so that a loop completing normally exits immediately without touching the counter. Before the iteration increment so stuck loops terminate before wasting another cycle.

4. **Check stuck threshold** (after updating counter):
   - If `stuck_threshold` > 0 AND `stuck_count` >= `stuck_threshold`:
     - Print warning to stderr: `"Ralph loop: terminated after N consecutive empty responses (stuck detection)"`
     - Remove state file
     - Exit 0 (allow session to stop)

5. **Persist updated `stuck_count`** in frontmatter -- combine with the existing iteration `sed` update (line 109) into a single `sed` pass to avoid double disk I/O and TOCTOU race between writes

#### `plugins/soleur/scripts/setup-ralph-loop.sh`

1. **Add `--stuck-threshold` argument parsing** (in the `while` loop at line 16):
   - Same pattern as `--max-iterations` (validate positive integer)
   - Default: 3

2. **Add `stuck_count: 0` and `stuck_threshold: <value>` to state file frontmatter** (in the `cat` block at line 109):
   - `stuck_count: 0`
   - `stuck_threshold: <parsed-value>`

3. **Update help text** (lines 19-55):
   - Document `--stuck-threshold` in OPTIONS
   - Add stuck detection explanation in DESCRIPTION
   - Note `--stuck-threshold 0` disables detection

#### `plugins/soleur/skills/one-shot/SKILL.md`

No changes needed. The one-shot skill invokes `setup-ralph-loop.sh` with `--completion-promise "DONE"`. Stuck detection defaults to 3, which provides a safety net. The one-shot pipeline generates substantive output each iteration, so the counter stays at 0 during normal operation.

### Non-goals

- Detecting *semantic* stuck states (same response repeated with different wording) -- too complex for a shell hook, and the character-length heuristic covers the production failure mode
- Configurable character threshold -- hardcode 20; if someone needs a different threshold, that is a separate feature
- Exponential backoff or retry logic -- the loop should terminate, not slow down
- Logging stuck events to a file -- stderr is sufficient

## Acceptance Criteria

- [ ] Stop hook detects N consecutive minimal responses and auto-terminates
- [ ] Warning message printed to stderr before termination: `"Ralph loop: terminated after N consecutive empty responses (stuck detection)"`
- [ ] State file (`.claude/ralph-loop.local.md`) cleaned up on stuck-detection termination
- [ ] Normal loops (with substantive output) are unaffected -- stuck_count resets on every substantive response
- [ ] Configurable threshold via `stuck_threshold` frontmatter field (default 3)
- [ ] `--stuck-threshold <n>` flag added to `setup-ralph-loop.sh`
- [ ] `--stuck-threshold 0` disables stuck detection
- [ ] Existing tests and hook behavior unaffected for non-stuck scenarios

## Test Scenarios

### Acceptance Tests

- Given a ralph loop with stuck_threshold=3 and 3 consecutive empty responses, when the stop hook runs, then it terminates the loop and removes the state file
- Given a ralph loop with stuck_threshold=3 and 2 consecutive empty responses followed by a substantive response, when the stop hook runs, then the counter resets and the loop continues
- Given a ralph loop with stuck_threshold=0, when empty responses occur, then stuck detection is disabled and the loop continues normally
- Given a ralph loop producing substantive output every iteration, when the stop hook runs, then stuck_count stays at 0 and the loop is unaffected
- Given a ralph loop with both stuck_threshold=3 and max_iterations=10, when stuck detection triggers at iteration 5 (3 consecutive empty responses), then stuck detection wins (fires before iteration limit check) and terminates the loop

### Edge Cases

- Given a response that is exactly 20 characters after whitespace stripping, when the stop hook runs, then it counts as substantive (>= 20, not > 20)
- Given a state file without `stuck_count` or `stuck_threshold` fields (pre-existing state files from before this feature), when the stop hook runs, then defaults apply (stuck_count=0, stuck_threshold=3) and the hook does not error
- Given a corrupted `stuck_count` value (non-numeric), when the stop hook runs, then it resets to 0 and logs a warning
- Given a response that is entirely tool_use blocks (no text content), when the stop hook runs, then LAST_OUTPUT is empty, length is 0, and it counts as minimal

### Regression Tests

- Given the production crash scenario (crash recovery, task already complete, assistant outputs minimal "nothing to do" text), when the stop hook runs 3 times, then the loop terminates instead of cycling 31+ times

## MVP

### `plugins/soleur/hooks/stop-hook.sh` (key additions)

```bash
# --- Stuck Detection ---
# Parse stuck detection fields from frontmatter
# CRITICAL: || true guards prevent grep exit 1 from aborting under set -euo pipefail
# when fields are missing (pre-existing state files without stuck_count/stuck_threshold)
STUCK_COUNT=$(echo "$FRONTMATTER" | grep '^stuck_count:' | sed 's/stuck_count: *//' || true)
STUCK_THRESHOLD=$(echo "$FRONTMATTER" | grep '^stuck_threshold:' | sed 's/stuck_threshold: *//' || true)

# Default values for backward compatibility with pre-existing state files
if [[ ! "$STUCK_COUNT" =~ ^[0-9]+$ ]]; then
  STUCK_COUNT=0
fi
if [[ ! "$STUCK_THRESHOLD" =~ ^[0-9]+$ ]]; then
  STUCK_THRESHOLD=3
fi

# Measure response substantiveness
# Note: LAST_OUTPUT may be empty for tool-use-only responses (jq text extraction
# yields nothing when all content blocks are type "tool_use"). This is fine --
# empty string has length 0, which counts as minimal.
STRIPPED_OUTPUT=$(echo "$LAST_OUTPUT" | tr -d '[:space:]')
RESPONSE_LENGTH=${#STRIPPED_OUTPUT}

# Update stuck counter
if [[ $RESPONSE_LENGTH -lt 20 ]]; then
  STUCK_COUNT=$((STUCK_COUNT + 1))
else
  STUCK_COUNT=0
fi

# Check stuck threshold (0 = disabled)
if [[ $STUCK_THRESHOLD -gt 0 ]] && [[ $STUCK_COUNT -ge $STUCK_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $STUCK_COUNT consecutive empty responses (stuck detection)" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi
```

Note: The existing iteration `sed` update and the new `stuck_count` update must be combined into a single `sed` pass:

```bash
# Combined frontmatter update (iteration + stuck_count in one pass)
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed -e "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
    -e "s/^stuck_count: .*/stuck_count: $STUCK_COUNT/" \
    "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"
```

### `plugins/soleur/scripts/setup-ralph-loop.sh` (key additions)

```bash
# In argument parsing while loop:
    --stuck-threshold)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --stuck-threshold requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --stuck-threshold must be a non-negative integer, got: $2" >&2
        exit 1
      fi
      STUCK_THRESHOLD="$2"
      shift 2
      ;;

# In state file cat block:
stuck_count: 0
stuck_threshold: $STUCK_THRESHOLD
```

## References

- Issue: #453
- State file: `.claude/ralph-loop.local.md`
- Hook: `plugins/soleur/hooks/stop-hook.sh`
- Setup: `plugins/soleur/scripts/setup-ralph-loop.sh`
- One-shot skill: `plugins/soleur/skills/one-shot/SKILL.md`
- Bundling learning: `knowledge-base/learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md`
- Permission learning: `knowledge-base/learnings/2026-02-22-skill-code-fence-permission-flow.md`
- Pipefail learning: `knowledge-base/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
