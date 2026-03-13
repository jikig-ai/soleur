---
title: "fix: ralph loop stuck detection fails on substantive-but-idle responses"
type: fix
date: 2026-03-13
semver: patch
---

# fix: ralph loop stuck detection fails on substantive-but-idle responses

## Overview

The ralph loop's stuck detection uses a naive character-length threshold (`< 20 chars = minimal`). When a crashed session leaves an orphan state file, the stop hook re-injects "finish all slash commands" on every turn. The agent responds with substantive-but-idle text like "All slash commands are finished" (>20 chars), which resets the stuck counter every time. This creates an infinite loop that only terminates when the 1-hour TTL expires -- observed at 15+ consecutive idle turns.

This fix adds content-based idle detection, repetition detection, and worktree-scoped state files to close three related gaps.

Closes #580

## Problem Statement

Three interrelated problems:

1. **Naive stuck detection**: The `< 20 chars` threshold was designed for truly empty or tool-use-only responses. Semantically idle responses ("All slash commands are finished", "No active commands to complete", "Session is already complete") exceed 20 chars and reset the counter, defeating the purpose.

2. **No repetition detection**: When the agent produces the same idle response across consecutive turns, the hook has no memory of prior responses to detect the pattern.

3. **Shared state file path**: The state file lives at `${PROJECT_ROOT}/.claude/ralph-loop.local.md`. In a worktree, `git rev-parse --show-toplevel` resolves to the worktree root (e.g., `.worktrees/feat-x/`), which is correct. But crashes in one worktree don't affect others because the path is already worktree-scoped by git's toplevel resolution. However, when running outside a worktree (bare repo root), a crash orphan affects all sessions. The real fix is ensuring `setup-ralph-loop.sh` writes to the same path the stop hook reads from -- both already use `git rev-parse --show-toplevel`, so this is already consistent. No path change needed.

**Re-evaluation of fix #3**: After tracing the code, both `setup-ralph-loop.sh` (line 12-13) and `stop-hook.sh` (line 12-14) use `git rev-parse --show-toplevel` for path resolution. In a worktree, `--show-toplevel` returns the worktree root, not the bare repo root. The state file is already worktree-scoped. The issue description's assumption that the state file lives at the project root `.claude/` is incorrect for worktree contexts. **No path change is needed.** The fix focuses on idle detection and repetition detection only.

## Proposed Solution

### 1. Content-based idle pattern detection

Add regex matching against known "nothing to do" patterns. If the response matches an idle pattern, treat it as minimal regardless of length.

**Idle patterns** (case-insensitive, applied to whitespace-normalized text):

```
all (done|complete|finished|commands? (are |have been )?(done|complete|finished))
nothing (left|pending|remaining|to do|to complete|to run)
no (active|running|pending) (commands?|tasks?|slash commands?)
session (complete|finished|done|already complete)
already (done|complete|finished)
```

**Threshold**: 2 consecutive idle-pattern matches triggers termination (lower than the 3-response threshold for truly empty responses, because idle patterns are a stronger signal).

**Implementation**: After extracting `LAST_OUTPUT`, normalize whitespace and check against patterns using `grep -iE`. If any pattern matches, increment `STUCK_COUNT` (same counter as empty detection). If no pattern matches AND response is >= 20 chars, reset to 0.

### 2. Repetition detection

Track the last response hash in the state file frontmatter. If 3 consecutive responses produce the same hash, terminate.

**Implementation**:
- Add `last_response_hash` field to state file frontmatter (default: empty)
- Add `repeat_count` field (default: 0)
- Compute hash: `echo "$STRIPPED_OUTPUT" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1`
- If current hash matches `last_response_hash`: increment `repeat_count`
- If different: reset `repeat_count` to 0, update `last_response_hash`
- If `repeat_count >= 3`: terminate (same as stuck detection)

**Why md5sum, not exact match?** The frontmatter field would need to store the full response text, which complicates YAML parsing and could contain characters that break the frontmatter format. A hash is fixed-width and safe for YAML.

### 3. State file path (NO CHANGE NEEDED)

After code analysis, both scripts already use `git rev-parse --show-toplevel` which returns the worktree root in worktree contexts. The state file is already worktree-scoped. No change required.

## Technical Approach

### Files Modified

#### `plugins/soleur/hooks/stop-hook.sh`

**Changes:**

1. **Add idle pattern detection** (after line 119, where `STRIPPED_OUTPUT` is computed):

```bash
# --- Idle Pattern Detection ---
# Responses that say "nothing to do" in >20 chars fool the length check.
# Normalize and check against known idle patterns.
NORMALIZED_OUTPUT=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
IS_IDLE=false
if echo "$NORMALIZED_OUTPUT" | grep -iqE '(all (done|complete|finished)|all (slash )?commands? (are |have been )?(done|complete|finished|already)|nothing (left|pending|remaining|to do|to complete|to run)|no (active|running|pending) (commands?|tasks?|slash commands?)|session (complete|finished|done|already)|already (done|complete|finished))'; then
  IS_IDLE=true
fi
```

2. **Add repetition detection fields** (after parsing `STUCK_THRESHOLD`, around line 54):

```bash
LAST_RESPONSE_HASH=$(echo "$FRONTMATTER" | grep '^last_response_hash:' | sed 's/last_response_hash: *//' || true)
REPEAT_COUNT=$(echo "$FRONTMATTER" | grep '^repeat_count:' | sed 's/repeat_count: *//' || true)
if [[ ! "$REPEAT_COUNT" =~ ^[0-9]+$ ]]; then
  REPEAT_COUNT=0
fi
```

3. **Compute response hash and update repeat counter** (after idle detection):

```bash
# --- Repetition Detection ---
CURRENT_HASH=""
if [[ -n "$STRIPPED_OUTPUT" ]]; then
  CURRENT_HASH=$(echo "$STRIPPED_OUTPUT" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
fi

if [[ -n "$CURRENT_HASH" ]] && [[ "$CURRENT_HASH" == "$LAST_RESPONSE_HASH" ]]; then
  REPEAT_COUNT=$((REPEAT_COUNT + 1))
else
  REPEAT_COUNT=0
fi
LAST_RESPONSE_HASH="$CURRENT_HASH"
```

4. **Update stuck counter logic** (replace lines 122-126):

```bash
# Update stuck counter: idle patterns OR short responses increment, substantive resets
if [[ "$IS_IDLE" == "true" ]] || [[ $RESPONSE_LENGTH -lt 20 ]]; then
  STUCK_COUNT=$((STUCK_COUNT + 1))
else
  STUCK_COUNT=0
fi
```

5. **Add repetition threshold check** (after stuck threshold check, around line 133):

```bash
# Check repetition threshold (3 identical consecutive responses)
REPEAT_THRESHOLD=3
if [[ $REPEAT_COUNT -ge $REPEAT_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $REPEAT_COUNT consecutive identical responses (repetition detection)" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi
```

6. **Update frontmatter persistence** (update the awk block at lines 152-158 to include new fields):

```bash
awk -v iter="$NEXT_ITERATION" -v sc="$STUCK_COUNT" -v lrh="$LAST_RESPONSE_HASH" -v rc="$REPEAT_COUNT" '
  /^---$/ { c++; print; next }
  c==1 && /^iteration:/ { print "iteration: " iter; next }
  c==1 && /^stuck_count:/ { print "stuck_count: " sc; next }
  c==1 && /^last_response_hash:/ { print "last_response_hash: " lrh; next }
  c==1 && /^repeat_count:/ { print "repeat_count: " rc; next }
  { print }
' "$RALPH_STATE_FILE" > "$TEMP_FILE"
```

**Edge case**: Pre-existing state files without `last_response_hash` / `repeat_count` -- the grep `|| true` handles missing fields, and the awk substitution is a no-op for missing lines. The counter will not persist but won't crash either (same pattern as stuck_count backward compatibility).

#### `plugins/soleur/scripts/setup-ralph-loop.sh`

**Changes:**

1. **Add new fields to state file frontmatter** (in the `cat` block at line 132):

Add after `stuck_threshold:` line:
```yaml
last_response_hash:
repeat_count: 0
```

2. **Update help text** to document idle pattern detection and repetition detection in DESCRIPTION section.

#### `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

**New tests:**

- Test: Idle pattern "All slash commands are finished" (>20 chars) increments stuck counter
- Test: Idle pattern "Nothing left to do" increments stuck counter
- Test: Idle pattern "Session already complete" increments stuck counter
- Test: Non-idle substantive response resets stuck counter (existing behavior preserved)
- Test: 2 consecutive idle-pattern responses trigger termination (stuck_threshold=2 default still 3, but idle patterns count toward it)
- Test: 3 identical responses trigger repetition detection termination
- Test: 2 identical responses followed by different response resets repeat counter
- Test: Pre-existing state file without `last_response_hash` / `repeat_count` works (backward compatibility)
- Test: Empty response still counts as minimal (existing behavior preserved)

**Update `create_state_file` helper** to include `last_response_hash` and `repeat_count` fields.

### Non-goals

- **Semantic NLP analysis** -- regex patterns cover the observed failure modes; shell hooks are not the place for ML inference
- **Configurable idle patterns** -- hardcoded patterns are sufficient; if users need custom patterns, that is a separate feature
- **Configurable repeat threshold** -- hardcode at 3; aligns with stuck_threshold default
- **State file path changes** -- already worktree-scoped via `git rev-parse --show-toplevel`

## Acceptance Criteria

- [ ] Stop hook detects idle-pattern responses (e.g., "All slash commands are finished") and increments stuck counter regardless of length
- [ ] 3 consecutive idle-pattern or short responses trigger termination (existing stuck_threshold behavior, now applied to idle patterns too)
- [ ] Stop hook detects 3 consecutive identical responses and terminates (repetition detection)
- [ ] Repetition detection is independent of stuck detection (either can trigger termination)
- [ ] Pre-existing state files without `last_response_hash` / `repeat_count` fields work without errors
- [ ] Normal loops with substantive, varied output are unaffected
- [ ] State file frontmatter includes `last_response_hash` and `repeat_count` fields
- [ ] Help text updated to document idle pattern and repetition detection
- [ ] All existing tests pass (backward compatibility)
- [ ] New tests cover idle patterns, repetition detection, and backward compatibility

## Test Scenarios

### Acceptance Tests

- Given a ralph loop with stuck_threshold=3 and a response "All slash commands are finished", when the stop hook runs 3 times with this response, then the loop terminates after the 3rd response (idle pattern detected + stuck counter)
- Given a ralph loop with stuck_threshold=3 and a response "Nothing left to do", when the stop hook runs 3 times, then the loop terminates (idle pattern match)
- Given a ralph loop with 3 consecutive identical responses of "I've reviewed the codebase and everything looks good", when the stop hook runs 3 times, then the loop terminates (repetition detection)
- Given a ralph loop with 2 consecutive identical responses followed by a different response, when the stop hook runs, then the repeat counter resets to 0
- Given a ralph loop with substantive, varied responses on each turn, when the stop hook runs, then both stuck_count and repeat_count stay at 0

### Edge Cases

- Given a response that matches an idle pattern but also contains substantive content (e.g., "All done. Here's the summary: [500 chars of real work]"), when the stop hook runs, then it should still match the idle pattern and increment -- false positives are acceptable here because the stuck_threshold requires 3 consecutive matches
- Given an empty response, when the stop hook runs, then it counts as minimal (existing behavior) AND the hash is empty (repeat counter resets since empty hash does not match prior hash)
- Given a pre-existing state file without `last_response_hash` or `repeat_count`, when the stop hook runs, then defaults apply and no errors occur

### Regression Tests

- Given the production crash scenario (15+ turns of "finish all slash commands" with idle responses), when the stop hook runs 3 times, then the loop terminates instead of cycling until TTL expires
- Given the original stuck detection scenario (31+ empty responses), then the loop still terminates after 3 empty responses (existing behavior preserved)

## References

- Issue: #580
- Prior plan: `knowledge-base/features/plans/2026-03-05-fix-ralph-loop-stuck-detection-plan.md`
- Learning: `knowledge-base/features/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md`
- Learning: `knowledge-base/features/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- Learning: `knowledge-base/features/learnings/2026-03-09-stop-hook-path-resolution-and-api-simplification.md`
- Hook: `plugins/soleur/hooks/stop-hook.sh`
- Setup: `plugins/soleur/scripts/setup-ralph-loop.sh`
- Tests: `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`
