---
title: "fix: suppress stop-hook.sh awk stderr noise from TOCTOU race"
type: fix
date: 2026-03-18
semver: patch
---

# fix: suppress stop-hook.sh awk stderr noise from TOCTOU race (#709)

## Overview

`stop-hook.sh` has a TOCTOU (time-of-check-time-of-use) race condition where the ralph-loop state file can be deleted between an existence check and a subsequent `awk` read. This produces cosmetic `awk: cannot open` stderr noise. The hook exits correctly, but the error message is confusing.

## Problem Statement

When the Ralph Loop completion promise is detected, the state file is deleted by `rm "$RALPH_STATE_FILE"` (lines 80, 86, 93, 103, 121, 175, 183). If a concurrent stop-hook invocation passes the existence check on line 42 before the file is removed, the `awk` call on line 51 fails with:

```
awk: cannot open ".claude/ralph-loop.local.md" (No such file or directory)
```

Three race windows exist:

1. **TTL cleanup loop (line 29-30):** `[[ -f "$state_file" ]]` passes, then the file is deleted before `awk` on line 30.
2. **Main frontmatter parse (line 42 -> line 51):** `[[ ! -f "$RALPH_STATE_FILE" ]]` passes, then the file is deleted before `awk` on line 51.
3. **Prompt extraction (line 190):** `awk` reads `$RALPH_STATE_FILE` for prompt text after the file may have been deleted by a concurrent invocation.
4. **State update (line 210):** `awk` writes updated frontmatter after the file may have disappeared.

## Proposed Solution

Apply defense-in-depth with two complementary strategies:

### Strategy A: Suppress stderr on awk calls

Add `2>/dev/null` to all `awk` calls that read the state file. This is the minimal fix that directly addresses the cosmetic symptom.

**Affected lines in `plugins/soleur/hooks/stop-hook.sh`:**

- Line 30: `awk ... "$state_file" 2>/dev/null` (TTL loop)
- Line 51: `FRONTMATTER=$(awk ... "$RALPH_STATE_FILE" 2>/dev/null)` (main parse)
- Line 190: `PROMPT_TEXT=$(awk ... "$RALPH_STATE_FILE" 2>/dev/null)` (prompt extraction)
- Line 210: `awk ... "$RALPH_STATE_FILE" > "$TEMP_FILE" 2>/dev/null` (state update)

### Strategy B: Re-check file existence before critical sections

Add a second file existence check immediately before the frontmatter parsing block (after line 48, before line 51) to narrow the race window:

```bash
# Re-check after potential race -- file may have been removed
# between the guard on line 42 and here
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

**Recommendation:** Apply all three strategies. Strategy A handles the stderr noise (the reported symptom). Strategy B narrows the race window. Strategy C provides a clean exit path when the race is lost.

## Acceptance Criteria

- [ ] `awk` calls on lines 30, 51, 190, and 210 of `stop-hook.sh` redirect stderr to `/dev/null`
- [ ] A re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` is added before the frontmatter parse (between lines 48-51)
- [ ] A re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` is added before the prompt extraction (before line 190)
- [ ] An empty-FRONTMATTER guard exits cleanly after line 51
- [ ] The TTL loop's awk call (line 30) also has `2>/dev/null` and a `continue` on failure
- [ ] No behavioral change: hook still exits 0 when file is missing, still blocks when active
- [ ] `set -euo pipefail` compatibility verified (awk failure with `2>/dev/null` does not abort the script due to existing `|| true` guards or the new `|| exit 0`/`|| continue` guards)

## Test Scenarios

- Given a stop-hook invocation where `$RALPH_STATE_FILE` exists at line 42 but is deleted before line 51, when the hook runs, then no stderr output is produced and the hook exits 0.
- Given a stop-hook invocation where the state file exists throughout, when the hook runs, then behavior is identical to current (loop continues or blocks exit).
- Given a TTL cleanup loop where `$state_file` passes the existence check but is deleted before the awk call, when the loop iterates, then no stderr output is produced and the loop continues to the next file.
- Given two concurrent stop-hook invocations racing on the same state file, when one deletes the file via promise detection, then the other exits cleanly without error output.

## Non-goals

- Preventing concurrent stop-hook invocations (that would require a lockfile mechanism, which is overkill for a cosmetic fix)
- Changing the Ralph Loop lifecycle or state file format
- Adding integration tests for the race condition (timing-dependent races are inherently difficult to test deterministically)

## Context

- **Priority:** P3 (low) -- cosmetic stderr noise, no behavioral impact
- **Semver:** patch
- **File:** `plugins/soleur/hooks/stop-hook.sh`
- **Related:** #709, commit f455f34 (similar error guard in welcome-hook.sh)

## References

- Issue: #709
- File: `plugins/soleur/hooks/stop-hook.sh`
- Similar pattern: `plugins/soleur/hooks/welcome-hook.sh` (uses `|| { exit 0; }` guard)
- Convention: constitution.md shell scripts section -- `set -euo pipefail`, `2>/dev/null` patterns
