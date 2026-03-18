---
title: "fix: guard jq call in stop-hook.sh against invalid JSON input"
type: fix
date: 2026-03-18
deepened: 2026-03-18
---

# fix: Guard jq call in stop-hook.sh against invalid JSON input

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Test Scenarios, Acceptance Criteria)
**Research performed:** jq exit code verification, pipefail interaction testing, empty-stdin edge case discovery, test helper pattern analysis

### Key Improvements
1. Corrected false assumption: empty stdin is actually safe (jq exits 0), narrowing the vulnerability to malformed text/JSON only
2. Added concrete jq exit code matrix from empirical testing
3. Refined test strategy: new tests must bypass `run_hook` helper (which always constructs valid JSON) and pipe raw input directly
4. Identified test pattern precedent in existing tests 16, 20, 36-37 (raw `'{}'` piped directly)

### New Considerations Discovered
- The output `jq -n` call (line 240) is confirmed safe via empirical testing -- `--arg` properly escapes all content including multiline strings, quotes, and special characters
- Empty stdin to jq is a non-issue (exits 0 with no output), so the "empty stdin" acceptance criterion can be simplified

---

## Overview

Line 118 of `plugins/soleur/hooks/stop-hook.sh` passes `HOOK_INPUT` (raw stdin from the Claude Code hook API) to `jq` without guarding against malformed or empty input. Under `set -euo pipefail`, if `jq` receives invalid JSON, it exits non-zero and aborts the script -- potentially trapping the user's session (every exit attempt would fail with the hook error).

Closes #713.

## Problem Statement

```bash
# plugins/soleur/hooks/stop-hook.sh:118
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
```

The `// ""` alternative operator handles a missing `.last_assistant_message` key, but does **not** handle invalid JSON input. If the hook API sends a truncated response or any non-JSON payload, `jq` exits with code 5, and `set -e` kills the script before `exit 0` runs.

This is a pre-existing issue identified during code review of PR #710 (TOCTOU race fix). The same class of vulnerability (`|| true` missing under `set -euo pipefail`) was already addressed for `grep` pipelines in the same file (see learning: `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md`), but the `jq` call was missed.

### Research Insights: jq Exit Code Matrix

Empirical testing confirms which inputs are dangerous:

| Input | jq Exit Code | Dangerous? |
|-------|-------------|------------|
| Valid JSON with key | 0 | No |
| Valid JSON missing key (`{}`) | 0 | No (handled by `// ""`) |
| Empty string | 0 | No (jq treats as no input) |
| Binary null bytes (`\x00\x01\x02`) | 0 | No |
| Malformed text (`not json at all`) | 5 | **Yes** -- parse error aborts script |
| Truncated JSON (`{"last_assistant`) | 5 | **Yes** -- parse error aborts script |

**Only malformed text/JSON triggers the vulnerability.** Empty stdin is safe -- jq exits 0 with no output, which produces an empty `LAST_OUTPUT` string. The `echo "$HOOK_INPUT"` always provides at least an empty line, but even true empty piped input is handled.

### Impact

- **Low probability:** the hook API typically sends well-formed JSON.
- **High impact:** if triggered, every session exit attempt fails with a `jq` parse error, effectively trapping the user until they `kill` the process or delete the state file manually.

## Proposed Solution

Guard the `jq` call with `2>/dev/null || true`, matching the defensive pattern already applied throughout the file:

```bash
# plugins/soleur/hooks/stop-hook.sh:118
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)
```

**Why `2>/dev/null || true` (not just `|| true`):**

- `2>/dev/null` suppresses jq's stderr parse error messages (e.g., `parse error (Invalid numeric literal at line 1, column 4)`) so they don't leak to the user's terminal. This matches the pattern used on `awk` calls at lines 30, 55, 203, and 223.
- `|| true` absorbs the non-zero exit code so `set -e` does not abort.
- `LAST_OUTPUT` becomes empty string on failure, which is a safe value -- the stuck detection counter handles repeated empty outputs gracefully (already documented in the comment on lines 120-121).

### Research Insights: pipefail Interaction

Verified that `set -euo pipefail` propagates jq's exit 5 through the `echo ... | jq ...` pipeline:

```bash
# Without guard: script aborts
bash -c 'set -euo pipefail; X=$(echo "not json" | jq -r ".x // \"\""); echo "$X"'
# exit: 5

# With guard: script continues, X is empty
bash -c 'set -euo pipefail; X=$(echo "not json" | jq -r ".x // \"\"" 2>/dev/null || true); echo "[$X]"'
# output: []
# exit: 0
```

### Alternative Considered: Pre-validation

```bash
if echo "$HOOK_INPUT" | jq empty 2>/dev/null; then
  LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
else
  LAST_OUTPUT=""
fi
```

Rejected: this doubles the jq invocation (validation + extraction) for the common case (valid JSON), adding unnecessary overhead to every stop-hook invocation. The `|| true` pattern is simpler, cheaper, and consistent with the file's existing defensive coding style.

### Second `jq` call analysis (line 240)

```bash
jq -n --arg prompt "$PROMPT_TEXT" --arg msg "$SYSTEM_MSG" '{...}'
```

This call uses `jq -n` (null input) and `--arg` for all inputs. It constructs JSON from string arguments, not from stdin parsing. Empirically verified: `jq -n --arg` properly escapes multiline strings, embedded quotes, `---` delimiters, and all special characters. No guard needed.

## Acceptance Criteria

- [ ] Line 118 jq call guarded with `2>/dev/null || true`
- [ ] New test: malformed text input (`"not json"`) to stop hook exits 0 when no ralph loop is active
- [ ] New test: malformed text input with active ralph loop -- loop continues (block decision emitted), `LAST_OUTPUT` treated as empty
- [ ] Existing tests pass (39/39 in `plugins/soleur/test/ralph-loop.test.sh`)

## Test Scenarios

- Given the hook API sends valid JSON with `last_assistant_message`, when the stop hook runs, then `LAST_OUTPUT` contains the message (existing behavior, no regression).
- Given the hook API sends `{}` (valid JSON, missing key), when the stop hook runs, then `LAST_OUTPUT` is empty string (existing behavior via `// ""`).
- Given the hook API sends `not json at all` (malformed text), when the stop hook runs, then `LAST_OUTPUT` is empty string and the hook exits 0.
- Given malformed text input with an active ralph loop, when the stop hook runs, then the loop continues (block decision emitted) with `LAST_OUTPUT` treated as empty (stuck detection eventually terminates).

### Research Insights: Test Implementation Pattern

The existing `run_hook` and `run_hook_stderr` helpers always construct valid JSON via `jq -n --arg`. New tests for invalid input **must bypass these helpers** and pipe raw input directly, following the pattern already used in tests 16, 20, and 36-37:

```bash
# Pattern from test 16 (line 332) -- pipe raw input directly
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>&1) || true

# New test pattern for invalid JSON
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo 'not json' | bash "$HOOK" 2>&1) || true
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "hook exits 0 on invalid JSON input"
```

For the "active ralph loop + invalid JSON" test, create a state file first (via `create_state_file`), then pipe invalid JSON. The hook should emit a block decision JSON blob despite LAST_OUTPUT being empty.

### Research Insights: Test Numbering

New tests should continue the existing numbering (39 -> 40, 41). Group them under a new `=== Invalid JSON Input Tests ===` section header following the established pattern.

## Context

### Related files

- `plugins/soleur/hooks/stop-hook.sh` -- the file to fix (line 118)
- `plugins/soleur/test/ralph-loop.test.sh` -- test suite (39 existing tests)
- `plugins/soleur/test/test-helpers.sh` -- shared assertions (assert_eq, assert_contains, assert_file_exists, assert_file_not_exists)
- `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md` -- prior learning documenting the same pattern class

### Related issues

- #710 -- PR where this issue was identified during code review
- #713 -- this issue

## References

- [jq exit codes](https://jqlang.github.io/jq/manual/#invocation): exit 2 = usage error, exit 5 = system error (invalid input falls under these)
- Constitution rule: "Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail` at the top"
- Learning: `set -euo pipefail` upgrade pitfalls -- every pipeline that can legitimately produce no output or fail needs `|| true`
- Learning: TOCTOU race guards pattern -- `2>/dev/null` on reads + `|| true` on exit codes + output validation before acting
