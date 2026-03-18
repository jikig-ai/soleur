---
title: "fix: guard jq call in stop-hook.sh against invalid JSON input"
type: fix
date: 2026-03-18
---

# fix: Guard jq call in stop-hook.sh against invalid JSON input

## Overview

Line 118 of `plugins/soleur/hooks/stop-hook.sh` passes `HOOK_INPUT` (raw stdin from the Claude Code hook API) to `jq` without guarding against malformed or empty input. Under `set -euo pipefail`, if `jq` receives invalid JSON, it exits non-zero and aborts the script -- potentially trapping the user's session (every exit attempt would fail with the hook error).

Closes #713.

## Problem Statement

```bash
# plugins/soleur/hooks/stop-hook.sh:118
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
```

The `// ""` alternative operator handles a missing `.last_assistant_message` key, but does **not** handle invalid JSON input. If the hook API sends empty stdin, a truncated response, or any non-JSON payload, `jq` exits with code 2 or 5, and `set -e` kills the script before `exit 0` runs.

This is a pre-existing issue identified during code review of PR #710 (TOCTOU race fix). The same class of vulnerability (`|| true` missing under `set -euo pipefail`) was already addressed for `grep` pipelines in the same file (see learning: `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md`), but the `jq` call was missed.

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

- `2>/dev/null` suppresses jq's stderr parse error messages (e.g., `parse error (invalid json)`) so they don't leak to the user's terminal. This matches the pattern used on `awk` calls at lines 30, 55, 203, and 223.
- `|| true` absorbs the non-zero exit code so `set -e` does not abort.
- `LAST_OUTPUT` becomes empty string on failure, which is a safe value -- the stuck detection counter handles repeated empty outputs gracefully (already documented in the comment on lines 120-121).

### Second `jq` call analysis (line 240)

```bash
jq -n --arg prompt "$PROMPT_TEXT" --arg msg "$SYSTEM_MSG" '{...}'
```

This call uses `jq -n` (null input) and `--arg` for all inputs. It constructs JSON from string arguments, not from stdin parsing. There is no invalid-input vector -- `jq -n` ignores stdin entirely, and `--arg` escapes any special characters. No guard needed.

## Acceptance Criteria

- [ ] Line 118 jq call guarded with `2>/dev/null || true`
- [ ] New test: invalid JSON input to stop hook exits 0 (does not abort)
- [ ] New test: empty stdin to stop hook exits 0 (does not abort)
- [ ] Existing tests pass (39/39 in `plugins/soleur/test/ralph-loop.test.sh`)

## Test Scenarios

- Given the hook API sends valid JSON with `last_assistant_message`, when the stop hook runs, then `LAST_OUTPUT` contains the message (existing behavior, no regression).
- Given the hook API sends `{}` (valid JSON, missing key), when the stop hook runs, then `LAST_OUTPUT` is empty string (existing behavior via `// ""`).
- Given the hook API sends `not json at all` (invalid JSON), when the stop hook runs, then `LAST_OUTPUT` is empty string and the hook exits 0.
- Given the hook API sends empty stdin, when the stop hook runs, then `LAST_OUTPUT` is empty string and the hook exits 0.
- Given invalid JSON input with an active ralph loop, when the stop hook runs, then the loop continues (block decision emitted) with `LAST_OUTPUT` treated as empty.

## Context

### Related files

- `plugins/soleur/hooks/stop-hook.sh` -- the file to fix (line 118)
- `plugins/soleur/test/ralph-loop.test.sh` -- test suite (39 existing tests)
- `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md` -- prior learning documenting the same pattern class

### Related issues

- #710 -- PR where this issue was identified during code review
- #713 -- this issue

## References

- [jq exit codes](https://jqlang.github.io/jq/manual/#invocation): exit 2 = usage error, exit 5 = system error (invalid input falls under these)
- Constitution rule: "Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail` at the top"
- Learning: `set -euo pipefail` upgrade pitfalls -- every pipeline that can legitimately produce no output or fail needs `|| true`
