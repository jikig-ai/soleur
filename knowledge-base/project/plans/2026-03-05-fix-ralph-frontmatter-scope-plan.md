---
title: "fix: scope Ralph Loop frontmatter parser and sed substitution to YAML block"
type: fix
date: 2026-03-05
semver: patch
deepened: 2026-03-05
---

# fix: scope Ralph Loop frontmatter parser and sed substitution to YAML block

Closes #455

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Context)
**Research performed:** awk edge-case verification, POSIX compatibility audit, pipefail safety analysis, variable naming consistency review

### Key Improvements

1. Verified awk fix against 8 edge cases including empty frontmatter, unclosed blocks, multiple `---` in prompt, and no-frontmatter files
2. Identified variable naming inconsistency: proposed fix uses `c` but existing prompt extraction (line 133) uses `i` -- recommend normalizing to same variable for readability
3. Confirmed awk always exits 0 (unlike grep which exits 1 on no match) -- eliminates a class of pipefail issues
4. Added concrete test code for the new test scenarios based on existing test harness patterns

## Problem

Two bugs in `plugins/soleur/hooks/stop-hook.sh` where sed operations are not scoped to the first YAML frontmatter block:

### Bug 1: Frontmatter parser reads beyond first `---` block (line 24)

```bash
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
```

This sed range matches ALL `---`-delimited blocks in the file. If the user's prompt contains `---` on its own line (common in markdown), content after it leaks into the FRONTMATTER variable, corrupting field extraction.

### Bug 2: sed substitution mutates prompt body (lines 146-148)

```bash
sed -e "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
    -e "s/^stuck_count: .*/stuck_count: $STUCK_COUNT/" \
    "$RALPH_STATE_FILE" > "$TEMP_FILE"
```

This replaces `iteration:` and `stuck_count:` patterns anywhere in the file. A prompt containing `iteration: check status` or `stuck_count: reset to zero` would be silently rewritten.

## Proposed Solution

Replace both sed operations with `awk` scoped to the first frontmatter block (lines between the first and second `---`). The prompt extraction on line 133 already uses the correct awk pattern (`awk '/^---$/{i++; next} i>=2'`).

### Frontmatter parser (replace line 24)

```bash
FRONTMATTER=$(awk '/^---$/{c++; next} c==1' "$RALPH_STATE_FILE")
```

Counter `c` increments on each `---` line. Only lines where `c==1` (between first and second `---`) are printed.

### Frontmatter update (replace lines 146-148)

```bash
awk -v iter="$NEXT_ITERATION" -v sc="$STUCK_COUNT" '
  /^---$/ { c++; print; next }
  c==1 && /^iteration:/ { print "iteration: " iter; next }
  c==1 && /^stuck_count:/ { print "stuck_count: " sc; next }
  { print }
' "$RALPH_STATE_FILE" > "$TEMP_FILE"
```

Only substitutes fields when `c==1` (inside frontmatter). All other lines pass through unchanged.

### Research Insights: awk Pattern Analysis

**Variable naming consistency:** The existing prompt extraction on line 133 uses variable `i`:

```bash
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")
```

The proposed parser uses `c`. For readability, normalize both the new parser and the new updater to use the same variable name. Recommend `c` (counter) for both new awk blocks since they are paired operations. Do not rename the existing `i` on line 133 -- it is not part of this fix scope.

**POSIX compatibility:** The proposed awk uses only POSIX features: `/regex/`, `{c++}`, `next`, `print`, `-v` variable passing. No gawk extensions. Safe on macOS (which ships BSD awk) and Linux.

**pipefail safety:** Unlike `grep` (which exits 1 on no match and requires `|| true` guards under `set -euo pipefail`), `awk` always exits 0. This is a safety improvement -- the current grep-based field extraction on lines 25-35 still needs `|| true` guards, but the new awk blocks do not.

**Edge cases verified:**

| Scenario | awk parser result | awk updater result |
|----------|------------------|-------------------|
| Normal frontmatter + prompt | Correct: only YAML fields | Correct: only frontmatter updated |
| Prompt contains `---` on own line | Correct: stops at second `---` | Correct: prompt `---` passed through |
| Prompt contains `iteration: text` | N/A (parser only) | Correct: prompt text unchanged |
| Empty frontmatter (`---` then `---`) | Empty string (triggers validation) | Pass-through (no fields to match) |
| No frontmatter at all | Empty string (triggers validation) | Pass-through (c never reaches 1) |
| Only opening `---` (malformed) | All content after `---` (c stays 1) | Same as current behavior |
| Multiple `---` in prompt body | Stops at second `---` only | Only first block's fields substituted |

## Acceptance Criteria

- [x] Frontmatter parser (`FRONTMATTER=...`) only reads lines between the first and second `---` markers in `plugins/soleur/hooks/stop-hook.sh`
- [x] sed update pass is replaced with awk that only substitutes `iteration:` and `stuck_count:` inside the first frontmatter block in `plugins/soleur/hooks/stop-hook.sh`
- [x] Prompt text containing `---`, `iteration:`, or `stuck_count:` is preserved verbatim through a loop iteration
- [x] All existing tests in `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` continue to pass
- [x] New test cases cover the two bug scenarios (prompt with `---`, prompt with `iteration:` text)
- [x] Comments on the changed lines updated to reflect awk usage

## Test Scenarios

- Given a state file whose prompt body contains `---` on its own line, when the stop hook parses frontmatter, then FRONTMATTER contains only the YAML block (not prompt content after `---`)
- Given a state file whose prompt body contains `iteration: check status`, when the stop hook updates the iteration counter, then the prompt text is unchanged and only the frontmatter `iteration:` field is updated
- Given a state file whose prompt body contains `stuck_count: reset`, when the stop hook updates stuck_count, then the prompt text is unchanged and only the frontmatter `stuck_count:` field is updated
- Given a state file with normal frontmatter and prompt (no conflicting patterns), when the stop hook runs, then behavior is identical to the current implementation (regression test)
- Given a state file with empty frontmatter (two `---` lines with nothing between), when the stop hook runs, then it correctly reports corrupted state and exits

### Research Insights: Concrete Test Code

Based on the existing test harness in `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`, the new tests should follow the same `create_state_file` / `run_hook` / `assert` pattern. However, the standard `create_state_file` helper cannot create prompts with `---` or `iteration:` text, so tests should use inline `cat` to build state files directly (same pattern as Test 7 and Test 12 in the existing file).

**Test for Bug 1 (prompt with `---`):**

```bash
# State file with --- in prompt body
cat > "$TEST_DIR/.claude/ralph-loop.local.md" <<'EOF'
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "2026-03-05T00:00:00Z"
---

Build a REST API with proper error handling.
---
Use standard HTTP status codes.
EOF
```

After running the hook with a substantive response, verify the state file's `iteration:` is updated to 2 and the prompt body (including `---` and text after it) is preserved verbatim.

**Test for Bug 2 (prompt with `iteration:` text):**

```bash
cat > "$TEST_DIR/.claude/ralph-loop.local.md" <<'EOF'
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "2026-03-05T00:00:00Z"
---

Check iteration: current status of deployment.
Monitor stuck_count: should be zero.
EOF
```

After running the hook, verify the prompt body contains `iteration: current status` and `stuck_count: should be zero` unchanged, while frontmatter `iteration:` is updated to 2.

## Context

Discovered during review of #453 / PR #454. These are pre-existing bugs, not regressions from stuck detection. The stuck detection PR (#454) added the combined sed pass on lines 146-148, which inherits the same scoping issue that existed for the `iteration:` substitution alone.

### Files to modify

| File | Change |
|------|--------|
| `plugins/soleur/hooks/stop-hook.sh` | Replace sed frontmatter parser (line 24) and sed update pass (lines 146-148) with scoped awk |
| `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` | Add test cases for prompt-body collision scenarios |

### Research Insights: Related Learnings

**From `2026-03-05-ralph-loop-stuck-detection-shell-counter.md`:** The `|| true` guards on grep (lines 34-35) exist because `grep` exits 1 under `set -euo pipefail` when a field is missing. The new awk-based parser does not have this issue (awk exits 0 regardless), but the individual field extraction lines 25-35 still use `echo "$FRONTMATTER" | grep ...` which retains the `|| true` requirement. This is acceptable -- refactoring field extraction to awk is out of scope per Non-goals.

**From `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`:** Confirms that Python/PyYAML is preferred for complex YAML transformations, but awk is appropriate for simple key-value frontmatter with known field names. The ralph loop state file has a fixed schema (7 fields, no nesting, no multi-line values), making awk the right tool. No over-engineering needed.

### Non-goals

- Refactoring other parts of `stop-hook.sh` beyond the two identified bugs
- Refactoring the grep-based field extraction (lines 25-35) to awk -- these work correctly with `|| true` guards
- Changing the state file format or `setup-ralph-loop.sh`
- Adding a YAML parsing library -- awk is sufficient for this simple key-value frontmatter

## References

- Issue: #455
- Related PR: #454 (stuck detection, introduced the combined sed pass)
- Learning: `knowledge-base/project/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- State file created by: `plugins/soleur/scripts/setup-ralph-loop.sh` (lines 129-141)
