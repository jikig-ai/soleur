---
title: "fix: ralph loop stuck detection fails on substantive-but-idle responses"
type: fix
date: 2026-03-13
semver: patch
deepened: 2026-03-13
---

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 4 (Proposed Solution, Technical Approach, Test Scenarios, Acceptance Criteria)
**Research sources:** stop-hook.sh source analysis, set-euo-pipefail-upgrade-pitfalls learning, awk-scoping-yaml-frontmatter learning, shell-api-wrapper-hardening learning, live regex validation against 12 test phrases

### Key Improvements

1. **Fixed false positive risk in idle pattern regex**: Substring matching on `grep -iqE` catches "all done" embedded in substantive responses like "The authentication module is all done and tested." Added response length gate: only apply idle detection when response is under 200 chars (truly idle responses are short; substantive responses containing idle substrings are long)
2. **Identified `set -euo pipefail` safety requirement**: The `if echo ... | grep -iqE` wrapping is confirmed safe (the `if` statement absorbs grep's exit 1 on no match), but `md5sum` in a command substitution needs `|| true` guard for edge cases where input pipe fails
3. **Added macOS portability note**: `md5sum` is Linux-only; macOS uses `md5 -r`. Added cross-platform hash function using `cksum` as fallback
4. **Clarified backward-compatibility gap**: Pre-existing state files without `last_response_hash`/`repeat_count` fields will not persist these counters across iterations (awk substitution is a no-op for missing lines). Repetition detection is inert for the first iteration after upgrade but functional from iteration 2+ when setup-ralph-loop.sh creates new state files

# fix: ralph loop stuck detection fails on substantive-but-idle responses

## Overview

The ralph loop's stuck detection uses a naive character-length threshold (`< 20 chars = minimal`). When a crashed session leaves an orphan state file, the stop hook re-injects "finish all slash commands" on every turn. The agent responds with substantive-but-idle text like "All slash commands are finished" (>20 chars), which resets the stuck counter every time. This creates an infinite loop that only terminates when the 1-hour TTL expires -- observed at 15+ consecutive idle turns.

This fix adds content-based idle detection (with a response-length gate to prevent false positives) and repetition detection to close the gap. State file path changes were evaluated and found unnecessary -- the path is already worktree-scoped.

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

**Threshold**: Uses the same stuck_threshold (default 3) as empty response detection. Idle patterns count toward the same counter.

**Implementation**: After extracting `LAST_OUTPUT`, normalize whitespace and check against patterns using `grep -iE`. If any pattern matches, increment `STUCK_COUNT` (same counter as empty detection). If no pattern matches AND response is >= 20 chars, reset to 0.

### Research Insights: Idle Pattern False Positives

**Validated via live testing against 12 phrases.** The regex correctly identifies all target idle phrases. However, substring matching creates false positives on substantive responses that happen to contain idle phrases:

| Input | Expected | Actual |
|-------|----------|--------|
| "All slash commands are finished" | IDLE | IDLE |
| "Nothing left to do" | IDLE | IDLE |
| "Session already complete" | IDLE | IDLE |
| "I've updated all 5 files. The module is all done and tested." | WORK | **IDLE** (false positive) |
| "All done with the refactoring. Here's what changed: [list]" | WORK | **IDLE** (false positive) |
| "Not all done yet, still working on the tests" | WORK | **IDLE** (false positive) |

**Mitigation**: Add a response length gate. Truly idle responses are short (under ~100 chars). Substantive responses containing idle substrings are long. Apply idle pattern detection only when `RESPONSE_LENGTH < 200`. This eliminates false positives from long substantive responses while catching all observed failure-mode responses (which are all under 50 chars of stripped content).

This is a two-tier approach:

1. `RESPONSE_LENGTH < 20` -> definitely minimal (existing behavior)
2. `20 <= RESPONSE_LENGTH < 200` AND idle pattern match -> semantically idle (new)
3. `RESPONSE_LENGTH >= 200` -> always treated as substantive (too long to be idle)

The 200-char threshold is conservative. The longest observed idle response in the production incident was "All slash commands are finished. No active commands to complete." (65 chars stripped). A 200-char response with an idle substring embedded in real work is almost certainly not stuck.

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

### Research Insights: Hash Function Portability

**md5sum is Linux-only.** macOS ships `md5` (with `-r` flag for compatible output format), not `md5sum`. While this project currently runs on Linux (confirmed in environment), a portable hash function prevents future breakage:

```bash
# Cross-platform hash (works on both Linux and macOS)
compute_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    md5 -r | cut -d' ' -f1
  else
    # Fallback: cksum is POSIX and always available
    cksum | cut -d' ' -f1
  fi
}
```

**Recommendation**: Use `md5sum` directly (simpler, this is a Linux-only plugin). Add a comment noting the macOS alternative for future portability if needed. The hash is only used for same-session equality comparison, not for security or cross-system consistency.

**Verified**: md5 hash values are hex-only (`[0-9a-f]{32}`), safe for awk `-v` variable passing and YAML frontmatter storage. No quoting or escaping needed.

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
# Only apply to short-ish responses (< 200 chars stripped) to avoid false positives
# on substantive responses that contain idle phrases as substrings.
# Verified: the `if` statement absorbs grep exit 1 under set -euo pipefail.
IS_IDLE=false
if [[ $RESPONSE_LENGTH -lt 200 ]]; then
  NORMALIZED_OUTPUT=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
  if echo "$NORMALIZED_OUTPUT" | grep -iqE '(all (done|complete|finished)|all (slash )?commands? (are |have been )?(done|complete|finished|already)|nothing (left|pending|remaining|to do|to complete|to run)|no (active|running|pending) (commands?|tasks?|slash commands?)|session (complete|finished|done|already)|already (done|complete|finished))'; then
    IS_IDLE=true
  fi
fi
```

**Shell safety note**: The `if echo ... | grep -iqE` pattern is safe under `set -euo pipefail` because the `if` statement absorbs grep's exit 1 on no match (verified via live testing). This is the correct pattern -- do NOT use `grep ... || true` here as it would make the `if` condition always true. See learning: `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`.

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
# Three tiers:
#   < 20 chars: definitely minimal (existing behavior)
#   20-199 chars + idle pattern: semantically idle (new)
#   >= 200 chars: always substantive (long enough to contain real work)
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

### Research Insights: Backward Compatibility Gap with Pre-existing State Files

**Important behavioral difference from stuck_count backward compat**: When `stuck_count` was added (PR #454), pre-existing state files lacking the field defaulted to 0 on every iteration. This was acceptable because the counter still _accumulated_ within a single hook invocation -- it just reset to 0 on the next invocation because the awk update was a no-op.

The same gap applies to `last_response_hash` and `repeat_count`. For pre-existing state files (created before this fix), repetition detection is **completely inert** -- the hash and count are never persisted, so every iteration starts fresh. This is acceptable because:

1. Pre-existing state files come from `setup-ralph-loop.sh` runs before the fix
2. New `setup-ralph-loop.sh` runs will create state files WITH the new fields
3. The stuck-detection (idle pattern + length check) still works on pre-existing files
4. Only repetition detection is degraded, and only until the current loop ends

**No migration needed.** The worst case is a pre-existing orphan state file that doesn't benefit from repetition detection -- but idle pattern detection (which doesn't need frontmatter persistence) still catches it.

### Research Insights: awk Frontmatter Scoping

Per learning `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`, the `c==1 &&` guard in the awk block is critical for preventing prompt body mutations. The new `last_response_hash:` and `repeat_count:` substitutions MUST include the `c==1` guard to avoid corrupting prompt body text that happens to contain these strings. The code examples above already include this guard correctly.

### Research Insights: set -euo pipefail Safety Audit

Per learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`, all new code must be audited against three failure modes:

| New Code | `-e` risk | `-u` risk | `-o pipefail` risk |
|----------|-----------|-----------|-------------------|
| `grep '^last_response_hash:' \|\| true` | Handled by `\|\| true` | N/A | Handled by `\|\| true` |
| `grep '^repeat_count:' \|\| true` | Handled by `\|\| true` | N/A | Handled by `\|\| true` |
| `echo ... \| grep -iqE ...` (in `if`) | `if` absorbs exit 1 | N/A | `if` absorbs |
| `echo ... \| md5sum \| cut` | Always succeeds on valid input | N/A | Always succeeds |
| `NORMALIZED_OUTPUT=$(echo ...)` | Always succeeds | N/A | N/A |
| `$REPEAT_COUNT` | N/A | Safe: initialized to 0 if unset | N/A |
| `$LAST_RESPONSE_HASH` | N/A | Safe: grep `\|\| true` returns empty string | N/A |

All new code paths are safe under `set -euo pipefail`. No additional guards needed.

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

- Test: Idle pattern "All slash commands are finished" (>20 chars, <200 chars) increments stuck counter
- Test: Idle pattern "Nothing left to do" increments stuck counter
- Test: Idle pattern "Session already complete" increments stuck counter
- Test: Non-idle substantive response resets stuck counter (existing behavior preserved)
- Test: 3 consecutive idle-pattern responses trigger termination (stuck_threshold=3)
- Test: 3 identical responses trigger repetition detection termination
- Test: 2 identical responses followed by different response resets repeat counter
- Test: Pre-existing state file without `last_response_hash` / `repeat_count` works (backward compatibility)
- Test: Empty response still counts as minimal (existing behavior preserved)
- Test: Long response (>= 200 chars stripped) containing idle substring is NOT treated as idle (length gate)
- Test: Response of 199 chars stripped with idle pattern IS treated as idle (under length gate)

**Update `create_state_file` helper** to include `last_response_hash` and `repeat_count` fields.

### Non-goals

- **Semantic NLP analysis** -- regex patterns cover the observed failure modes; shell hooks are not the place for ML inference
- **Configurable idle patterns** -- hardcoded patterns are sufficient; if users need custom patterns, that is a separate feature
- **Configurable repeat threshold** -- hardcode at 3; aligns with stuck_threshold default
- **State file path changes** -- already worktree-scoped via `git rev-parse --show-toplevel`

## Acceptance Criteria

- [x] Stop hook detects idle-pattern responses (e.g., "All slash commands are finished") and increments stuck counter regardless of length
- [x] 3 consecutive idle-pattern or short responses trigger termination (existing stuck_threshold behavior, now applied to idle patterns too)
- [x] Stop hook detects 3 consecutive identical responses and terminates (repetition detection)
- [x] Repetition detection is independent of stuck detection (either can trigger termination)
- [x] Pre-existing state files without `last_response_hash` / `repeat_count` fields work without errors
- [x] Normal loops with substantive, varied output are unaffected
- [x] State file frontmatter includes `last_response_hash` and `repeat_count` fields
- [x] Help text updated to document idle pattern and repetition detection
- [x] All existing tests pass (backward compatibility)
- [x] New tests cover idle patterns, repetition detection, and backward compatibility

## Test Scenarios

### Acceptance Tests

- Given a ralph loop with stuck_threshold=3 and a response "All slash commands are finished", when the stop hook runs 3 times with this response, then the loop terminates after the 3rd response (idle pattern detected + stuck counter)
- Given a ralph loop with stuck_threshold=3 and a response "Nothing left to do", when the stop hook runs 3 times, then the loop terminates (idle pattern match)
- Given a ralph loop with 3 consecutive identical responses of "I've reviewed the codebase and everything looks good", when the stop hook runs 3 times, then the loop terminates (repetition detection)
- Given a ralph loop with 2 consecutive identical responses followed by a different response, when the stop hook runs, then the repeat counter resets to 0
- Given a ralph loop with substantive, varied responses on each turn, when the stop hook runs, then both stuck_count and repeat_count stay at 0

### Edge Cases

- Given a response that matches an idle pattern but is over 200 chars stripped (e.g., "All done. Here's the summary: [500 chars of real work]"), when the stop hook runs, then idle pattern detection is skipped (response length gate) and it counts as substantive -- the 200-char gate prevents false positives on long responses
- Given a short response (< 200 chars) that matches an idle pattern AND contains some useful content (e.g., "All done, moving to next task"), when the stop hook runs, then it counts as idle -- this is a tolerable false positive because 3 consecutive matches are required
- Given an empty response, when the stop hook runs, then it counts as minimal (existing behavior) AND the hash is empty (repeat counter resets since empty hash does not match prior hash)
- Given a pre-existing state file without `last_response_hash` or `repeat_count`, when the stop hook runs, then defaults apply and no errors occur
- Given a response of exactly 200 chars stripped that matches an idle pattern, when the stop hook runs, then idle detection is skipped (>= 200 is treated as substantive)
- Given a response of 199 chars stripped that matches an idle pattern, when the stop hook runs, then idle detection fires (< 200 qualifies for pattern check)

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
