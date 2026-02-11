---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, simplicity, architecture]
dependencies: []
---

# Remove dead permission code (~152 lines)

## Problem Statement

`--dangerously-skip-permissions` is hardcoded, making the entire permission request/response UI dead code. ~152 lines including `PendingPermission` type, `pendingPermissions` map, `handlePermissionRequest()`, `sendPermissionResponse()`, `control_request` handler, callback query handler, `InlineKeyboard` import, `PERMISSION_TIMEOUT_MS`, and cleanup in `/new` and `shutdown()` are unreachable.

## Findings

- **code-simplicity-reviewer**: Identified 152 LOC of dead code across 10 locations
- **architecture-strategist**: Called it an "architectural contradiction" -- 80+ lines of unreachable code
- **pattern-recognition-specialist**: Permission system is "untested in production, may silently rot"
- **silent-failure-hunter**: `sendPermissionResponse` silently returns on null stdin, stale UI buttons remain

## Proposed Solutions

### Option A: Remove all permission code (Recommended)
- **Pros**: ~20% LOC reduction, eliminates cognitive load, removes misleading UI references
- **Cons**: Loses the implementation if permissions are ever needed again
- **Effort**: Small
- **Risk**: Low -- code is definitively unreachable with current flag

### Option B: Gate behind env var
- **Pros**: Keeps implementation available, configurable per deployment
- **Cons**: Maintaining untested code paths, complexity
- **Effort**: Medium
- **Risk**: Medium -- untested code rots

## Acceptance Criteria
- [ ] `InlineKeyboard` removed from imports
- [ ] `PERMISSION_TIMEOUT_MS`, `PendingPermission`, `pendingPermissions` removed
- [ ] `handlePermissionRequest`, `sendPermissionResponse` removed
- [ ] `control_request` case removed from switch
- [ ] Callback query handler (section 11) removed
- [ ] Permission cleanup removed from `/new` and `shutdown()`
- [ ] `/status` no longer shows "Pending permissions: 0"
- [ ] Section numbers renumbered

## Work Log
- 2026-02-11: Identified during /soleur:review by 4 agents
