---
status: complete
priority: p3
issue_id: 1047
tags: [code-review, security]
dependencies: []
---

# Add /sys to sandbox denyRead for consistency

## Problem Statement

The `/sys` pseudo-filesystem exposes kernel parameters and device information. While already blocked by the workspace path check (layers 2-3), it is not in the OS-level `denyRead` list. Adding it would be consistent with the defense-in-depth posture applied to `/proc`.

## Findings

- Source: security-sentinel review of PR #1282
- `/sys` exposes: MAC addresses (`/sys/class/net/*/address`), CPU topology, kernel parameters
- Already blocked by `isPathInWorkspace` (not in workspace) and bubblewrap defaults
- Lower risk than `/proc` (no per-process secrets)
- Explicitly scoped out of #1047

## Proposed Solutions

### Option A: Add /sys to denyRead (recommended)

Add `"/sys"` to the `denyRead` array alongside `/proc`.

- Pros: Consistent defense-in-depth, trivial change
- Cons: Out of scope for #1047
- Effort: Small
- Risk: None

## Technical Details

- File: `apps/web-platform/server/agent-runner.ts:346`

## Acceptance Criteria

- [ ] `/sys` added to `denyRead` array
- [ ] Existing tests pass
