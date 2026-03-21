---
title: Ralph Loop idle detection and repetition guard
date: 2026-03-13
category: bug-fixes
tags: [ralph-loop, stuck-detection, idle-detection, repetition-detection, stop-hook]
module: plugins/soleur/hooks
issue: 580
---

# Learning: Ralph Loop idle detection and repetition guard

## Problem

After a crashed session left an orphan state file (see 2026-03-09 learning), the stop hook re-injected prompts on every turn. The agent responded with messages like "All slash commands are finished" -- syntactically substantive (>20 chars) but semantically idle. The existing stuck counter only incremented on responses under 20 stripped characters, so it reset to 0 on every iteration. The loop ran indefinitely until the 4-hour TTL expired, burning tokens on responses that conveyed no progress.

Reported as GitHub issue #580.

## Investigation

1. Reproduced the scenario: orphan state file with a completed task prompt, agent responding with "nothing to do" variants
2. Measured response lengths -- "All slash commands are finished." is 33 stripped chars, well above the 20-char minimal threshold
3. Confirmed stuck counter reset on every iteration because the response was classified as substantive
4. Identified two independent failure modes: (a) idle-but-long responses bypassing stuck detection, (b) identical responses repeating without triggering any guard

## Root Cause

The stuck detection used a single length threshold (20 chars) to classify responses as minimal vs. substantive. This binary heuristic fails when responses are syntactically long but semantically empty -- the agent politely says "nothing to do" in enough words to exceed the threshold. Length alone cannot distinguish idle responses from genuinely substantive ones.

## Solution

Three changes to `plugins/soleur/hooks/stop-hook.sh`:

1. **Idle pattern detection**: Regex matching against known "nothing to do" patterns (case-insensitive): "nothing to do", "no .*to", "all .* finished", "already completed", "no remaining", "no pending", "no outstanding". Applied only when the stripped response is under 200 chars (length gate prevents false positives on substantive responses that happen to contain an idle phrase mid-paragraph).

2. **Repetition detection**: md5sum hash of each response stored in state file frontmatter (`last_response_hash`). If 3 consecutive responses produce the same hash (`repeat_count` >= 3), the loop terminates regardless of length or content. Independent of stuck detection -- catches any degenerate loop, not just idle ones.

3. **Three-tier stuck counter**: `< 20 chars` = minimal (existing behavior, increments counter). `20-199 chars + idle pattern match` = semantically idle (new, increments counter). `>= 200 chars` = always substantive (resets counter). The 200-char gate is the key design choice: it allows idle pattern matching on short responses without risking false positives on long ones.

Also updated `plugins/soleur/scripts/setup-ralph-loop.sh` to initialize `last_response_hash` and `repeat_count` in state file frontmatter.

## Session Errors

1. **setup-ralph-loop.sh path error** -- Tried editing `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` instead of `./plugins/soleur/scripts/setup-ralph-loop.sh`. The script lives outside the skills directory.
2. **cleanup-merged failed with exit 128** -- Ran `cleanup-merged` from the bare repo root instead of a worktree. The script requires a git context with a valid HEAD.
3. **Test hash computation mismatch** -- md5sum in a pipeline (`echo "$response" | md5sum`) includes a trailing newline from echo, while command substitution (`$(echo ...)`) does not. Tests had to match the exact pipeline used in the hook.
4. **Test 26 false positive** -- A test response under 200 stripped chars contained an idle pattern and was incorrectly classified as substantive. Required adjusting the test expectation to match the new three-tier logic.
5. **Test 2 assertion string not updated** -- Changed error message wording in the hook but forgot to update the corresponding assertion string in the test file.
6. **Test 32 boundary response** -- A response crafted to be exactly 200 stripped chars was actually 165 chars. Required recounting and padding to hit the boundary precisely.

## Key Insight

Length-based "is this response meaningful?" heuristics break when responses can be syntactically long but semantically empty. Content-based pattern matching with a length gate is more robust than either pure length checks or pure pattern matching alone. The length gate is critical: without it, pattern matching produces false positives on substantive responses that happen to mention "nothing to do" in passing. The combination -- apply content patterns only to short responses, trust length for long ones -- covers both failure modes with minimal complexity.

The repetition guard is orthogonal and catches degenerate loops that no heuristic can predict. If an agent says the exact same thing three times in a row, the loop is stuck regardless of what it is saying.

## Prevention

- When designing stuck/idle detection, test with responses that are long but semantically empty. The 20-char threshold was correct for tool-use-only responses but failed for polite refusals.
- Repetition detection (hash-based) is a universal backstop that requires no domain knowledge about what "idle" looks like. Consider adding it alongside any heuristic-based detection.
- Boundary tests for length gates must verify the actual stripped length, not the raw length. Whitespace stripping can change the count significantly.

## Cross-References

- `knowledge-base/features/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md` -- original stuck detection implementation
- `knowledge-base/features/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md` -- orphan state file TTL fix that surfaces the idle-loop scenario
- `knowledge-base/features/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` -- frontmatter parsing patterns used in the stop hook

## Tags

category: bug-fixes
module: plugins/soleur/hooks
