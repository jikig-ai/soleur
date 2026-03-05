---
title: "fix: scope Ralph Loop frontmatter parser and sed substitution to YAML block"
type: fix
date: 2026-03-05
semver: patch
---

# fix: scope Ralph Loop frontmatter parser and sed substitution to YAML block

Closes #455

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

## Acceptance Criteria

- [ ] Frontmatter parser (`FRONTMATTER=...`) only reads lines between the first and second `---` markers in `plugins/soleur/hooks/stop-hook.sh`
- [ ] sed update pass is replaced with awk that only substitutes `iteration:` and `stuck_count:` inside the first frontmatter block in `plugins/soleur/hooks/stop-hook.sh`
- [ ] Prompt text containing `---`, `iteration:`, or `stuck_count:` is preserved verbatim through a loop iteration
- [ ] All existing tests in `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` continue to pass
- [ ] New test cases cover the two bug scenarios (prompt with `---`, prompt with `iteration:` text)
- [ ] Comments on the changed lines updated to reflect awk usage

## Test Scenarios

- Given a state file whose prompt body contains `---` on its own line, when the stop hook parses frontmatter, then FRONTMATTER contains only the YAML block (not prompt content after `---`)
- Given a state file whose prompt body contains `iteration: check status`, when the stop hook updates the iteration counter, then the prompt text is unchanged and only the frontmatter `iteration:` field is updated
- Given a state file whose prompt body contains `stuck_count: reset`, when the stop hook updates stuck_count, then the prompt text is unchanged and only the frontmatter `stuck_count:` field is updated
- Given a state file with normal frontmatter and prompt (no conflicting patterns), when the stop hook runs, then behavior is identical to the current implementation (regression test)
- Given a state file with empty frontmatter (two `---` lines with nothing between), when the stop hook runs, then it correctly reports corrupted state and exits

## Context

Discovered during review of #453 / PR #454. These are pre-existing bugs, not regressions from stuck detection. The stuck detection PR (#454) added the combined sed pass on lines 146-148, which inherits the same scoping issue that existed for the `iteration:` substitution alone.

### Files to modify

| File | Change |
|------|--------|
| `plugins/soleur/hooks/stop-hook.sh` | Replace sed frontmatter parser (line 24) and sed update pass (lines 146-148) with scoped awk |
| `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` | Add test cases for prompt-body collision scenarios |

### Non-goals

- Refactoring other parts of `stop-hook.sh` beyond the two identified bugs
- Changing the state file format or `setup-ralph-loop.sh`
- Adding a YAML parsing library -- awk is sufficient for this simple key-value frontmatter

## References

- Issue: #455
- Related PR: #454 (stuck detection, introduced the combined sed pass)
- Learning: `knowledge-base/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- State file created by: `plugins/soleur/scripts/setup-ralph-loop.sh` (lines 129-141)
