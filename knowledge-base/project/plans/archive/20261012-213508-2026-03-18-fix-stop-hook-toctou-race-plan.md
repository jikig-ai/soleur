---
title: "fix: suppress stop-hook.sh awk stderr noise from TOCTOU race"
type: fix
date: 2026-03-18
semver: patch
---

# fix: suppress stop-hook.sh awk stderr noise from TOCTOU race (#709)

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Acceptance Criteria, Test Scenarios)
**Analysis methods:** SpecFlow trace of all file I/O paths, `set -euo pipefail` exit-code audit, concurrent-invocation state machine analysis

### Key Improvements

1. Discovered 8 unguarded `rm` calls (lines 80, 86, 93, 103, 121, 174, 182, 194) that also race under concurrent invocations -- under `set -e`, these abort with exit 1 instead of the intended exit 0
2. Identified the `mv` after the final awk (line 211) as a race vector -- it overwrites a potentially-deleted file with an empty temp file if awk fails silently
3. Added Strategy D (guard all `rm` calls with `|| true`) to prevent exit-code corruption from concurrent deletions

### New Considerations Discovered

- The `rm` race is arguably more impactful than the `awk` stderr noise: a non-zero exit from the stop hook could signal an error to Claude Code's hook runner, whereas the awk stderr is purely cosmetic
- The temp file on line 202 (`${RALPH_STATE_FILE}.tmp.$$`) should be cleaned up on failure to avoid orphaned `.tmp.*` files

## Overview

`stop-hook.sh` has a TOCTOU (time-of-check-time-of-use) race condition where the ralph-loop state file can be deleted between an existence check and a subsequent `awk` read. This produces cosmetic `awk: cannot open` stderr noise. The hook exits correctly, but the error message is confusing.

## Problem Statement

When the Ralph Loop completion promise is detected, the state file is deleted by `rm "$RALPH_STATE_FILE"` (lines 80, 86, 93, 103, 121, 174, 182, 194). If a concurrent stop-hook invocation passes the existence check on line 42 before the file is removed, the `awk` call on line 51 fails with:

```
awk: cannot open ".claude/ralph-loop.local.md" (No such file or directory)
```

Four race windows exist in the file I/O path:

1. **TTL cleanup loop (line 29 -> line 30):** `[[ -f "$state_file" ]]` passes, then the file is deleted before `awk` on line 30.
2. **Main frontmatter parse (line 42 -> line 51):** `[[ ! -f "$RALPH_STATE_FILE" ]]` passes on line 42, stdin is consumed on line 48, then the file is deleted before `awk` on line 51.
3. **Prompt extraction (line 190):** `awk` reads `$RALPH_STATE_FILE` for prompt text after the file may have been deleted by a concurrent invocation.
4. **State update (line 210 -> line 211):** `awk` reads `$RALPH_STATE_FILE` and writes to a temp file. If the state file vanishes, the temp file is empty, and `mv` on line 211 either overwrites a now-deleted path (no-op) or creates an empty state file (corruption).

### Research Insights

**Additional race vector -- `rm` exit codes:**

Eight `rm "$RALPH_STATE_FILE"` calls (lines 80, 86, 93, 103, 121, 174, 182, 194) lack `|| true` guards. Under `set -euo pipefail`, if a concurrent invocation already deleted the file, `rm` exits non-zero and aborts the script before the following `exit 0` runs. The stop hook then returns exit code 1 to Claude Code's hook runner, which may interpret this as an error. Only line 36 (`rm "$state_file" || true`) is properly guarded.

**Temp file orphan risk:**

Line 202 creates `${RALPH_STATE_FILE}.tmp.$$`. If the awk on line 210 fails (file deleted) and `mv` on line 211 also fails, the temp file is orphaned in `.claude/`. While harmless, it accumulates over time. Adding a trap or guarding the mv addresses this.

## Proposed Solution

Apply defense-in-depth with four complementary strategies:

### Strategy A: Suppress stderr on awk calls

Add `2>/dev/null` to all `awk` calls that read the state file. This is the minimal fix that directly addresses the cosmetic symptom.

**Affected lines in `plugins/soleur/hooks/stop-hook.sh`:**

- Line 30: `awk ... "$state_file" 2>/dev/null` (TTL loop -- already has `|| true` downstream)
- Line 51: `FRONTMATTER=$(awk ... "$RALPH_STATE_FILE" 2>/dev/null)` (main parse)
- Line 190: `PROMPT_TEXT=$(awk ... "$RALPH_STATE_FILE" 2>/dev/null)` (prompt extraction)
- Line 210: `awk ... "$RALPH_STATE_FILE" > "$TEMP_FILE" 2>/dev/null` (state update)

### Strategy B: Re-check file existence before critical sections

Add a second file existence check immediately before the frontmatter parsing block (after line 48, before line 51) to narrow the race window:

```bash
# Re-check after potential race -- file may have been removed
# between the guard on line 42 and here (stdin read on line 48 is blocking)
[[ -f "$RALPH_STATE_FILE" ]] || exit 0
```

Also add a re-check before the prompt extraction section (before line 190):

```bash
[[ -f "$RALPH_STATE_FILE" ]] || exit 0
```

### Strategy C: Guard empty FRONTMATTER

After extracting FRONTMATTER on line 51, add an early exit if the variable is empty (which happens when awk cannot read the file):

```bash
if [[ -z "$FRONTMATTER" ]]; then
  # State file vanished between check and read (race condition)
  exit 0
fi
```

This is the final safety net -- it catches the case where Strategy B's re-check passes but the file is deleted in the gap before awk runs. It also handles partial truncation.

### Strategy D: Guard all `rm` calls

Add `|| true` to all 8 unguarded `rm "$RALPH_STATE_FILE"` calls (lines 80, 86, 93, 103, 121, 174, 182, 194). This prevents `set -e` from aborting with exit 1 when a concurrent invocation already deleted the file.

```bash
# Before (8 occurrences):
rm "$RALPH_STATE_FILE"

# After:
rm -f "$RALPH_STATE_FILE"
```

Using `rm -f` is the idiomatic approach -- it suppresses "No such file" errors without needing `|| true`, and is shorter.

### Strategy E: Guard the mv and clean up temp file

After the state update awk (line 210), guard the mv and clean up:

```bash
if [[ -s "$TEMP_FILE" ]]; then
  mv "$TEMP_FILE" "$RALPH_STATE_FILE"
else
  # awk produced empty output (file vanished) -- clean up and exit
  rm -f "$TEMP_FILE"
  exit 0
fi
```

The `-s` test ensures we never overwrite the state file with empty content.

**Recommendation:** Apply all five strategies. Strategy A handles the stderr noise (the reported symptom). Strategy B narrows the race window. Strategy C provides a clean exit path when the race is lost. Strategy D prevents exit-code corruption from concurrent `rm`. Strategy E prevents state file corruption and temp file orphans.

## Acceptance Criteria

- [x] `awk` calls on lines 30, 51, 190, and 210 of `stop-hook.sh` redirect stderr to `/dev/null`
- [x] A re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` is added before the frontmatter parse (between lines 48-51)
- [x] A re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` is added before the prompt extraction (before line 190)
- [x] An empty-FRONTMATTER guard exits cleanly after line 51
- [x] All 8 bare `rm "$RALPH_STATE_FILE"` calls are changed to `rm -f "$RALPH_STATE_FILE"` (lines 80, 86, 93, 103, 121, 174, 182, 194)
- [x] The `mv` on line 211 is guarded with a `-s` (non-empty) check on the temp file
- [x] Orphaned temp files are cleaned up on early exit
- [x] No behavioral change: hook still exits 0 when file is missing, still blocks when active
- [x] `set -euo pipefail` compatibility verified -- no unguarded commands that can exit non-zero

## Test Scenarios

- Given a stop-hook invocation where `$RALPH_STATE_FILE` exists at line 42 but is deleted before line 51, when the hook runs, then no stderr output is produced and the hook exits 0.
- Given a stop-hook invocation where the state file exists throughout, when the hook runs, then behavior is identical to current (loop continues or blocks exit).
- Given a TTL cleanup loop where `$state_file` passes the existence check but is deleted before the awk call, when the loop iterates, then no stderr output is produced and the loop continues to the next file.
- Given two concurrent stop-hook invocations racing on the same state file, when one deletes the file via promise detection, then the other exits cleanly with exit code 0 (not 1).
- Given a state file that vanishes between the frontmatter awk and the state-update awk, when the update awk produces an empty temp file, then the temp file is cleaned up and the hook exits 0 without overwriting the (now-missing) state file.
- Given a concurrent deletion during `rm "$RALPH_STATE_FILE"` on any of the 8 deletion points, when `rm -f` is used, then the script continues to `exit 0` without aborting.

## Non-goals

- Preventing concurrent stop-hook invocations (that would require a lockfile mechanism, which is overkill for a cosmetic fix)
- Changing the Ralph Loop lifecycle or state file format
- Adding integration tests for the race condition (timing-dependent races are inherently difficult to test deterministically)

## Context

- **Priority:** P3 (low) -- cosmetic stderr noise, no behavioral impact (upgraded to also fix potential exit-code corruption)
- **Semver:** patch
- **File:** `plugins/soleur/hooks/stop-hook.sh`
- **Related:** #709, commit f455f34 (similar error guard in welcome-hook.sh)

## References

- Issue: #709
- File: `plugins/soleur/hooks/stop-hook.sh`
- Similar pattern: `plugins/soleur/hooks/welcome-hook.sh` (uses `|| { exit 0; }` guard)
- Convention: constitution.md shell scripts section -- `set -euo pipefail`, `rm -f` idiom
- Best practice: `rm -f` is preferred over `rm ... || true` for idempotent file deletion in bash scripts with `set -e`
