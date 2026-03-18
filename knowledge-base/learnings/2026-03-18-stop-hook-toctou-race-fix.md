---
title: "TOCTOU race guards in bash stop hooks under set -euo pipefail"
date: 2026-03-18
category: runtime-errors
tags: [toctou, race-condition, set-euo-pipefail, bash, defensive-coding, ralph-loop]
module: plugins/soleur/hooks/stop-hook.sh
---

# Learning: TOCTOU race guards in bash stop hooks under set -euo pipefail

## Problem

The Ralph Loop stop hook (`plugins/soleur/hooks/stop-hook.sh`) exhibited two symptoms from concurrent invocations racing on a shared state file:

1. **Cosmetic awk stderr noise.** When one invocation deleted the state file (via completion promise, max iterations, stuck detection, etc.), a concurrent invocation that had already passed the `[[ -f "$RALPH_STATE_FILE" ]]` guard would hit `awk: cannot open` on the subsequent read. The hook exited correctly, but the error message leaked to the user's terminal.

2. **Silent exit-code corruption.** Eight `rm "$RALPH_STATE_FILE"` calls lacked `-f`. Under `set -euo pipefail`, if a concurrent invocation already deleted the file, `rm` exited non-zero and `set -e` aborted the script before the following `exit 0`. The stop hook returned exit code 1 to Claude Code's hook runner -- potentially misinterpreted as an error condition.

Four distinct TOCTOU (time-of-check-time-of-use) race windows existed in the file I/O path:

- **TTL cleanup loop:** file existence check passes, file deleted before `awk` reads it.
- **Main frontmatter parse:** existence check on line 42, stdin consumed (blocking) on line 48, file deleted before `awk` on line 55.
- **Prompt extraction:** `awk` reads state file after it may have been deleted by a concurrent termination path.
- **State update:** `awk` reads state file into a temp file; if the source vanishes, `mv` overwrites a deleted path with empty content (corruption) or orphans the temp file.

Additionally, three `grep` pipelines parsing `ITERATION`, `MAX_ITERATIONS`, and `COMPLETION_PROMISE` from the frontmatter variable lacked `|| true` guards -- a pre-existing `set -e` vulnerability unrelated to the race but discovered during the audit.

## Solution

Defense-in-depth with five complementary strategies, applied to all affected code paths:

**Strategy A -- Suppress stderr on awk calls.** Added `2>/dev/null` to all four `awk` invocations that read the state file (TTL loop, frontmatter parse, prompt extraction, state update). This is the minimal fix for the cosmetic symptom.

**Strategy B -- Re-check file existence before critical sections.** Added `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` after stdin consumption (line 48 gap) and before prompt extraction. Narrows the race window, though cannot close it entirely without a lockfile.

**Strategy C -- Empty FRONTMATTER guard.** After extracting frontmatter via `awk`, check `[[ -z "$FRONTMATTER" ]]` and exit cleanly. This is the final safety net -- catches the case where Strategy B's re-check passes but the file is deleted in the microsecond gap before `awk` runs.

**Strategy D -- `rm` to `rm -f` on all deletion calls.** Changed all eight bare `rm "$RALPH_STATE_FILE"` calls to `rm -f`. The `-f` flag suppresses "No such file or directory" errors idiomatically, preventing `set -e` from aborting the script when a concurrent invocation already deleted the file. Also normalized the TTL loop's `rm` to `rm -f` for consistency.

**Strategy E -- Guard `mv` with `-s` check, clean up orphaned temp files.** After the state-update `awk`, check the temp file with `[[ -s "$TEMP_FILE" ]]` before `mv`. If awk produced empty output (file vanished), clean up the temp file and exit. Prevents both state file corruption and temp file accumulation.

**Bonus fixes:** Added `|| true` to three `grep` pipelines for `ITERATION`, `MAX_ITERATIONS`, and `COMPLETION_PROMISE` (pre-existing `set -e` vulnerability). Replaced a fragile line-number comment reference with a semantic description of the code location.

## Key Insight

In bash scripts under `set -euo pipefail`, any file operation on a shared resource is a potential TOCTOU race when the script can be invoked concurrently. The classic check-then-act pattern (`[[ -f "$file" ]] && awk ... "$file"`) is necessary but insufficient -- the file can vanish between the check and the act.

The defense-in-depth layering matters because no single strategy is complete:

- **Stderr suppression** (A) hides the symptom but does not prevent downstream logic from operating on empty data.
- **Re-checks** (B) narrow the window but cannot close it without mutual exclusion.
- **Output validation** (C) catches races that slip through re-checks but only works for read operations.
- **Idempotent deletion** (D) is orthogonal -- it addresses `rm` exit codes, not `awk` reads.
- **Write guards** (E) prevent the most dangerous outcome (state corruption from empty overwrites).

The generalizable rule: when a bash script (a) uses `set -euo pipefail`, (b) operates on a file that external processes can delete, and (c) can be invoked concurrently, every file I/O path needs three things: stderr suppression on reads, `-f` on deletes, and output validation before acting on results. A lockfile would close the race entirely but is overkill when the consequence is a clean exit vs. a noisy one.

A secondary lesson: `grep` in a pipeline under `set -euo pipefail` exits 1 on no match, which `pipefail` propagates. Every `grep` in a command substitution that might legitimately match nothing needs `|| true`. This was already documented in `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` and `knowledge-base/project/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`, but this session found three more instances in the same file -- proving the pattern recurs even after prior learnings.

## Session Errors

1. **`worktree-manager.sh draft-pr` failed 3 times.** The bare-repo detection logic in the worktree manager incorrectly identifies worktree CWD as the bare repo root, causing `draft-pr` to fail when invoked from inside a worktree. The fallback was to use `gh pr create` directly. This is a pre-existing bug in the worktree manager's CWD detection, not related to the stop-hook fix itself.

## Tags
category: runtime-errors
module: plugins/soleur/hooks/stop-hook.sh
