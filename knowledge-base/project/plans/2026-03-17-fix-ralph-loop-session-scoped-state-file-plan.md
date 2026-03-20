---
title: "fix: ralph loop stop hook blocks all parallel sessions on same repo"
type: fix
date: 2026-03-17
issue: "#650"
deepened: 2026-03-17
---

# fix: ralph loop stop hook blocks all parallel sessions on same repo

## Enhancement Summary

**Deepened on:** 2026-03-17
**Sections enhanced:** 5 (Proposed Solution, Affected Files, Edge Cases, Test Scenarios, new Implementation Details)
**Research sources:** Codebase analysis (stop-hook.sh, setup-ralph-loop.sh, test suite), 5 institutional learnings, engineering review patterns

### Key Improvements
1. Added concrete implementation snippets for the glob-based TTL cleanup loop in stop-hook.sh
2. Identified PPID stability risk with `bash -c` subshells and added mitigation (use `$$` fallback)
3. Added trap-based cleanup pattern for temp files in the TTL loop (from shell-script-defensive-patterns learning)
4. Added specific test harness design for PID isolation (from bash-arithmetic-and-test-sourcing patterns learning)
5. Identified that the test file uses `run_hook` via subshell `(cd "$dir" && ...)` which means `$PPID` inside the hook during tests will be the test shell's PID, not the subshell's -- tests need to account for this

### New Considerations Discovered
- The `run_hook` test helper wraps the hook in a subshell `(cd "$dir" && bash "$HOOK")`. The `bash "$HOOK"` creates a new bash process, so `$PPID` inside the hook will be the subshell's PID. This is different from the test script's `$$`. Tests must create state files using the PID that the hook will see, not `$$`.
- The `setup-ralph-loop.sh` help text includes hardcoded `ralph-loop.local.md` in examples -- these need updating too.

## Overview

The ralph loop state file (`$PROJECT_ROOT/.claude/ralph-loop.local.md`) is project-scoped. Since all worktrees in a bare repo share the same project root (resolved via `git rev-parse --git-common-dir`), a ralph loop active in one Claude Code session blocks exit in **all** parallel sessions on the same repo. Session B enters an infinite loop of stop hook rejections because it finds session A's state file.

## Root Cause

Both `stop-hook.sh` and `setup-ralph-loop.sh` resolve to a single state file path:

```bash
# plugins/soleur/hooks/stop-hook.sh:21
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# plugins/soleur/scripts/setup-ralph-loop.sh:143
cat > "${PROJECT_ROOT}/.claude/ralph-loop.local.md" <<EOF
```

There is no session identifier in the filename. Any session that shares the same `PROJECT_ROOT` sees the same state file.

## Proposed Solution: PPID-based session scoping

Use `$PPID` (parent process ID of the hook/script) to scope state files per session. Claude Code spawns each hook as a child process, so `$PPID` is the Claude Code process PID -- stable within a session, unique across parallel sessions.

### Why PPID over alternatives

| Approach | Pros | Cons |
|----------|------|------|
| `$PPID` | Available in all bash, stable per session, unique across parallel sessions | Orphaned files on crash (mitigated by existing TTL) |
| `$CLAUDE_SESSION_ID` | Semantically perfect | Does not exist in the hook environment (verified via `env` inspection) |
| Random UUID at setup time | Guaranteed unique | Requires passing the UUID from setup to stop hook via state file, circular |
| Worktree path hash | Scoped per worktree | Two sessions on the same worktree still collide |

PPID is the only reliable, environment-available, session-stable identifier. The existing TTL check (1-hour auto-remove) already handles orphaned state files from crashed sessions, so PID reuse is not a concern in practice.

### Research Insights

**PPID behavior in subshells and pipelines:**
- `$PPID` is set once when bash starts and never changes (unlike `$BASHPID` which reflects the current subshell). This is desirable -- subshells within the hook still see the Claude Code PID.
- `bash -c '...'` creates a new process with its own `$PPID` pointing to the invoking shell, not the Claude Code process. This does not affect us because Claude Code invokes hooks via `bash stop-hook.sh`, not `bash -c`.
- Pipelines: in `echo "$input" | bash stop-hook.sh`, the pipe creates a subshell for the right side. `$PPID` inside the hook still points to the Claude Code process (the pipe's parent).

**From learning: shell-script-defensive-patterns (2026-03-13):**
The glob-based TTL cleanup loop creates a temporary iteration pattern. Use `|| true` guards on the `for` loop and date parsing to prevent `set -euo pipefail` from aborting on empty globs or malformed timestamps.

### State file naming

```
# Before (project-scoped):
.claude/ralph-loop.local.md

# After (session-scoped):
.claude/ralph-loop.<PPID>.local.md
```

Example: `.claude/ralph-loop.12345.local.md`

### Gitignore

The existing `.claude/*.local.md` pattern in `.gitignore` already covers PID-suffixed files via the glob. No gitignore changes needed.

## Acceptance Criteria

- [x] `setup-ralph-loop.sh` creates session-scoped state file at `$PROJECT_ROOT/.claude/ralph-loop.<PPID>.local.md`
- [x] `stop-hook.sh` reads/writes only the state file matching its own `$PPID`
- [x] `stop-hook.sh` ignores state files from other sessions (does not block exit)
- [x] TTL glob cleanup iterates all `ralph-loop.*.local.md` files and removes stale ones
- [x] Cancel instructions in setup output reflect the new filename pattern (both specific and glob)
- [x] Help text in setup-ralph-loop.sh updated for new filename
- [x] Existing tests pass after adapting to new file path
- [x] New test: state file from foreign PID does not block exit
- [x] New test: TTL glob cleanup removes stale files from other PIDs
- [x] New test: TTL glob cleanup preserves fresh files from other PIDs

## Test Scenarios

- Given session A starts a ralph loop, when session B (different PPID) tries to exit, then session B exits cleanly (no block)
- Given session A starts a ralph loop, when session A tries to exit, then the stop hook blocks and feeds prompt back (existing behavior)
- Given a stale session-scoped state file (older than TTL), when any session's hook runs, then the stale file is auto-removed
- Given a fresh session-scoped state file from another PID, when this session's hook runs, then the fresh file is preserved (not removed by TTL)
- Given session A starts a ralph loop, when session A cancels (`rm .claude/ralph-loop.*.local.md`), then the loop stops
- Given a state file exists with PID 12345, when stop-hook runs with PPID 67890, then exit is allowed (file ignored)

## Implementation Details

### `plugins/soleur/hooks/stop-hook.sh` -- detailed changes

**Change 1: Session-scoped state file path (line 21)**

```bash
# Before:
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# After:
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"
```

**Change 2: Replace single-file TTL check with glob-based TTL cleanup (lines 29-44)**

The current TTL check only examines the single state file. Replace it with a loop that scans all session-scoped state files and removes stale ones. This handles orphaned files from any crashed session.

```bash
# --- TTL Check: Auto-remove stale state files from crashed sessions ---
TTL_HOURS=1
NOW_EPOCH=$(date +%s)
for state_file in "${PROJECT_ROOT}/.claude"/ralph-loop.*.local.md; do
  [[ -f "$state_file" ]] || continue
  STARTED_AT=$(awk '/^---$/{c++; next} c==1' "$state_file" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/^"\(.*\)"$/\1/' || true)
  if [[ -n "$STARTED_AT" ]]; then
    STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || true)
    if [[ -n "$STARTED_EPOCH" ]] && [[ $((NOW_EPOCH - STARTED_EPOCH)) -gt $((TTL_HOURS * 3600)) ]]; then
      AGE_MINS=$(( (NOW_EPOCH - STARTED_EPOCH) / 60 ))
      echo "Ralph loop: stale state file detected ($(basename "$state_file"), started ${AGE_MINS}m ago, TTL=${TTL_HOURS}h). Auto-removing." >&2
      rm "$state_file"
    fi
  fi
done
```

Key defensive patterns applied:
- `[[ -f "$state_file" ]] || continue` -- handles empty glob (no files match)
- `|| true` on grep/date commands -- prevents `set -euo pipefail` abort on missing fields
- `$(basename "$state_file")` in the log message -- shows which PID's file was removed

**Change 3: Own-file check remains at line 24 (after TTL cleanup)**

```bash
# Check if ralph-loop is active for THIS session
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop for this session - allow exit
  exit 0
fi
```

No change needed here -- `$RALPH_STATE_FILE` already points to the PPID-scoped file.

### `plugins/soleur/scripts/setup-ralph-loop.sh` -- detailed changes

**Change 1: State file path (line 143)**

```bash
# Before:
cat > "${PROJECT_ROOT}/.claude/ralph-loop.local.md" <<EOF

# After:
cat > "${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md" <<EOF
```

**Change 2: Update output messages (lines 171-172)**

```bash
# Before:
To monitor: head -10 .claude/ralph-loop.local.md
To cancel: rm .claude/ralph-loop.local.md

# After:
To monitor: head -10 .claude/ralph-loop.${PPID}.local.md
To cancel: rm .claude/ralph-loop.${PPID}.local.md
```

**Change 3: Update help text (lines 69, 73-76)**

Update the MONITORING and STOPPING sections in the `--help` output:

```bash
# Before:
STOPPING:
  ...Or manually remove the state file:
  rm .claude/ralph-loop.local.md

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/ralph-loop.local.md

  # View full state:
  head -10 .claude/ralph-loop.local.md

# After:
STOPPING:
  ...Or manually remove the state file:
  rm .claude/ralph-loop.*.local.md

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/ralph-loop.*.local.md

  # View full state:
  head -10 .claude/ralph-loop.*.local.md
```

Note: help text uses glob (`*.local.md`) because the user does not know their session's PID. Runtime output uses the specific PID.

### `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- detailed changes

**Critical insight from codebase analysis:** The test helper `run_hook` executes via `(cd "$dir" && bash "$HOOK" ...)`. The `bash "$HOOK"` spawns a new bash process. Inside that process, `$PPID` will be the PID of the subshell, not `$$` of the test script. The test must create state files using the PID that the hook will actually see.

**Approach:** Instead of trying to predict `$PPID` inside the hook (fragile), refactor the state file path computation into a function or variable that tests can override. However, the simplest approach is:

1. In `create_state_file`, accept an optional PID parameter (defaults to a known value)
2. In `run_hook`, have the hook discover its own `$PPID` naturally
3. For tests that need the hook to find the state file, determine the PID the hook will see by running a probe command first

**Simpler approach:** Create a helper that determines what PPID the hook will see when run from a given directory:

```bash
get_hook_ppid() {
  local dir="$1"
  (cd "$dir" && bash -c 'echo $PPID')
}
```

Then use that in `create_state_file`:

```bash
create_state_file() {
  local dir="$1"
  local iteration="${2:-1}"
  # ... existing params ...
  local pid
  pid=$(get_hook_ppid "$dir")
  cat > "$dir/.claude/ralph-loop.${pid}.local.md" <<EOF
  ...
  EOF
}
```

**New tests to add:**

Test N: State file from foreign PID does not block exit
```bash
# Create state file with a PID that is NOT what the hook will see
echo "Test N: Foreign PID state file does not block exit"
TEST_DIR=$(setup_test)
# Create state file for PID 99999 (guaranteed not to be our hook's PPID)
cat > "$TEST_DIR/.claude/ralph-loop.99999.local.md" <<EOF
---
active: true
iteration: 1
...
EOF
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>&1) || true
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "hook exits 0 when only foreign PID state file exists"
assert_eq "" "$HOOK_OUTPUT" "no output for foreign PID"
# Foreign file still exists (not our session to clean up, and it's fresh)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.99999.local.md" "foreign PID file preserved"
```

Test M: TTL glob cleanup removes stale file from other PID
```bash
echo "Test M: TTL glob cleanup removes stale file from other PID"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.99999.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$STALE_TS"
---

Stale prompt from other session
EOF
(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>/dev/null) || true
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.99999.local.md" "stale foreign PID file removed by TTL"
```

### `plugins/soleur/skills/one-shot/SKILL.md` -- detailed changes

Update line mentioning cancel:

```markdown
# Before:
To cancel: rm .claude/ralph-loop.local.md

# After:
To cancel: rm .claude/ralph-loop.*.local.md
```

## Affected Files

### `plugins/soleur/hooks/stop-hook.sh`

1. Change `RALPH_STATE_FILE` to include `$PPID`: `"${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"`
2. Replace single-file TTL check with glob-based TTL cleanup loop over all `ralph-loop.*.local.md` files
3. Keep all other logic unchanged -- the hook only reads/writes its own session's file

### `plugins/soleur/scripts/setup-ralph-loop.sh`

1. Change state file path to `"${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"`
2. Update the cancel instructions in the output message to show the specific PID file
3. Update the monitoring instructions similarly
4. Update `--help` text to show glob patterns (user does not know their PID)

### `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

1. Add `get_hook_ppid` helper to determine what `$PPID` the hook sees when invoked from a test directory
2. Update `create_state_file` to use PID-scoped filename
3. Update all direct references to `ralph-loop.local.md` in assertions
4. Add test: foreign PID state file does not block exit
5. Add test: TTL glob cleanup removes stale files from other PIDs
6. Add test: TTL glob cleanup preserves fresh files from other PIDs

### `plugins/soleur/skills/one-shot/SKILL.md`

1. Update the `rm .claude/ralph-loop.local.md` cancel instruction to use the glob pattern

## Edge Cases

### PID reuse after reboot
A new session could get the same PPID as a previously crashed session. The TTL check (1-hour) handles this: if the old file is stale, it gets auto-removed before the new session's setup creates a fresh one. Even if the PID is reused within the TTL window, setup-ralph-loop.sh overwrites the file with fresh state (iteration: 1, new started_at), so the new session gets a clean start.

### Multiple loops in same session
Not supported (existing limitation). Setup overwrites the previous state file for the same PPID. This is unchanged behavior.

### PPID stability across hook invocations
The stop hook is invoked as a child of the Claude Code process. `$PPID` in the hook is the Claude Code process PID, which is stable for the lifetime of the session. The setup script is also invoked as a child of the same Claude Code process. Both scripts see the same `$PPID`.

### Glob-based TTL cleanup performance
The `.claude/` directory is small (a handful of files). Iterating over `ralph-loop.*.local.md` with a for loop is negligible overhead. The `date -d` parsing per file is the most expensive operation, but with <10 files it is sub-millisecond.

### Empty glob with `set -euo pipefail`
In bash, `for f in pattern*; do` iterates once with the literal pattern if no files match. The `[[ -f "$state_file" ]] || continue` guard handles this. No `shopt -s nullglob` needed (and modifying shell options in a script with `set -euo pipefail` is risky -- per the bare-repo-helper-extraction-patterns learning).

### macOS `date` compatibility
The current TTL code uses `date -d "$STARTED_AT"` which is GNU date syntax. macOS uses BSD date (`date -j -f`). This is a pre-existing limitation -- the fix does not change the date parsing logic, just moves it into a loop. If macOS support is needed later, a `to_epoch()` helper function should be extracted (per bash-arithmetic-and-test-sourcing-patterns learning).

## References

- Issue: #650
- `plugins/soleur/hooks/stop-hook.sh` -- stop hook (main affected file)
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- loop setup script
- `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- test suite
- `plugins/soleur/skills/one-shot/SKILL.md` -- one-shot skill (cancel instruction)
- `knowledge-base/project/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md` -- bare repo root resolution
- `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md` -- defensive bash patterns (trap, validation)
- `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` -- test sourcing, `BASH_SOURCE` guard
- `knowledge-base/project/learnings/2026-03-14-bare-repo-helper-extraction-patterns.md` -- path arithmetic, sourceable helper design
