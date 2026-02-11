---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, silent-failures, reliability]
dependencies: []
---

# Fix silent failure paths that cause stuck/zombie states

## Problem Statement

Multiple error paths silently swallow errors, leaving the bridge in stuck states with no user notification. The most critical: (1) stdout reader empty catch can cause zombie bridge, (2) stdin write sync path doesn't call `drainQueue()`, (3) in-flight messages lost on CLI exit.

## Findings

- **silent-failure-hunter**: 14 distinct error handling defects, 9 bare catch blocks, 2 `.catch(() => {})`
- **performance-oracle**: `sendChunked` not awaited -- errors invisible to caller
- **pattern-recognition-specialist**: "Missing a reset in any error path would wedge the queue permanently"

## Proposed Solutions

### Fix all critical paths (Recommended)
1. **stdout reader catch (lines 431, 449)**: Log error, set `cliState = "error"`, notify user
2. **stdin write sync catch (line 518)**: Add `drainQueue()` call, notify user, null out `cliStdin`
3. **Tool notification `.catch(() => {})`**: Log 429 errors at minimum
4. **sendChunked outer catch**: Check error type, only retry on HTML parse errors
5. **sendChunked call site**: Add `.catch(console.error)`
6. **CLI exit handler**: Re-queue the in-flight message
7. **JSON parse catch**: Warn-level log after CLI initialization
8. **kill() catch in /new**: Log error, force cleanup if kill fails

- **Effort**: Medium
- **Risk**: Low -- all changes are additive error handling

## Acceptance Criteria
- [ ] No empty catch blocks without at minimum console.error logging
- [ ] stdin write failure notifies user and calls drainQueue()
- [ ] stdout reader failure sets cliState to error
- [ ] In-flight message re-queued on CLI exit
- [ ] kill() failure in /new triggers manual cleanup and spawnCli()
- [ ] Tool notification failures logged (not swallowed)

## Work Log
- 2026-02-11: Identified during /soleur:review
