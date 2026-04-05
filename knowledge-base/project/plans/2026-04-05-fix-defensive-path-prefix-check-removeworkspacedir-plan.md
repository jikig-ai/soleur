---
title: "fix: add defensive path prefix check to removeWorkspaceDir"
type: fix
date: 2026-04-05
---

# fix: Add defensive path prefix check to removeWorkspaceDir

## Problem

`removeWorkspaceDir` in `apps/web-platform/server/workspace.ts:267` is exported and accepts an arbitrary string path with no self-validation. All current callers validate via UUID regex before constructing the path, but a future caller could pass untrusted input, enabling `rm -rf` on arbitrary paths outside the workspace root -- or on the workspace root itself (deleting all user workspaces).

**Source:** PR #1540 review finding. **Issue:** #1545.

## Proposed Fix

Add a defensive prefix check at the top of `removeWorkspaceDir`, before the `existsSync` guard:

1. Resolve both `workspacePath` and workspace root to canonical form using `path.resolve()`.
2. Reject if the resolved path does not start with `root + "/"` (path is outside workspace root).
3. Reject if the resolved path equals `root` exactly (prevents deleting the workspace root directory).

```typescript
// apps/web-platform/server/workspace.ts - removeWorkspaceDir
const root = path.resolve(getWorkspacesRoot());
const resolved = path.resolve(workspacePath);
if (resolved === root || !resolved.startsWith(root + "/")) {
  throw new Error("Refusing to remove path outside workspace root");
}
```

### Why `path.resolve()` and not `isPathInWorkspace` from sandbox.ts

The existing `isPathInWorkspace()` in `server/sandbox.ts` uses `fs.realpathSync()` to resolve symlinks, which is appropriate for the sandbox's tool-level containment check (it must follow symlinks to prevent CWE-59 escape). However, `removeWorkspaceDir` operates on workspace directories that may not yet exist (the `existsSync` check comes after this guard), and `realpathSync` throws `ENOENT` on non-existent paths. Using `path.resolve()` for string-level canonicalization is sufficient here because:

- The workspace path is always constructed internally from `getWorkspacesRoot() + "/" + userId` -- symlink escape is not a threat at this layer.
- The defense is against programming errors (wrong path passed to function), not against adversarial symlink manipulation.
- `sandbox.ts` has a `resolveParentRealPath` fallback for non-existent paths, but adding that complexity here would be over-engineering for the threat model.

### Error message

Use a generic error message that does not leak the workspace root path: `"Refusing to remove path outside workspace root"`.

## Acceptance Criteria

- [ ] `removeWorkspaceDir` rejects paths outside workspace root (throws Error)
- [ ] `removeWorkspaceDir` rejects the workspace root itself (throws Error)
- [ ] `removeWorkspaceDir` rejects paths that are string prefixes of the root but not children (e.g., `/workspaces-evil` when root is `/workspaces`)
- [ ] `removeWorkspaceDir` accepts valid workspace subdirectory paths (existing behavior preserved)
- [ ] Existing tests continue to pass

## Test Scenarios

- Given a path outside the workspace root (e.g., `/etc/passwd`), when `removeWorkspaceDir` is called, then it throws `"Refusing to remove path outside workspace root"`.
- Given the workspace root itself (e.g., `/workspaces`), when `removeWorkspaceDir` is called, then it throws `"Refusing to remove path outside workspace root"`.
- Given a path that is a string prefix collision (e.g., `/workspaces-evil`), when `removeWorkspaceDir` is called, then it throws because `"/workspaces-evil"` does not start with `"/workspaces/"`.
- Given a path with `../` traversal segments that resolve outside the root, when `removeWorkspaceDir` is called, then it throws (because `path.resolve()` canonicalizes the path first).
- Given a valid workspace subdirectory (e.g., `/workspaces/some-uuid`), when `removeWorkspaceDir` is called, then it proceeds to the existing removal logic.

## Implementation Notes

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/server/workspace.ts` | Add `import { resolve } from "path"` (or use existing `join` import pattern), add prefix check at top of `removeWorkspaceDir` |
| `apps/web-platform/test/workspace-cleanup.test.ts` | Add test cases for rejection scenarios |

### Existing test file

Tests live in `apps/web-platform/test/workspace-cleanup.test.ts`. The test file already imports `removeWorkspaceDir` and has helpers for creating test workspaces. The `WORKSPACES_ROOT` env var is set to `/tmp/soleur-test-workspaces-cleanup` before imports.

### Test approach

Add a new `describe` block for path validation tests. These tests do not need filesystem setup -- they verify that `removeWorkspaceDir` throws before reaching the `existsSync` check:

- Path outside root: `removeWorkspaceDir("/etc/passwd")` should throw
- Root itself: `removeWorkspaceDir(process.env.WORKSPACES_ROOT!)` should throw
- Prefix collision: `removeWorkspaceDir("/tmp/soleur-test-workspaces-cleanup-evil")` should throw
- Traversal: `removeWorkspaceDir("/tmp/soleur-test-workspaces-cleanup/user/../../../etc")` should throw

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/security hardening change.

## References

- Issue: [#1545](https://github.com/jikig-ai/soleur/issues/1545)
- Source PR: [#1540](https://github.com/jikig-ai/soleur/pull/1540)
- Related learning: `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Related learning: `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`
- Existing sandbox module: `apps/web-platform/server/sandbox.ts`
