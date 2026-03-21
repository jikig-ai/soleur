---
title: "path.resolve does not follow symlinks -- use realpathSync for containment checks"
category: security-issues
date: 2026-03-20
trigger: "Any path containment check (isPathInWorkspace, chroot guard, sandbox boundary) that uses path.resolve without fs.realpathSync"
---

# Learning: Symlink escape via path.resolve in workspace containment (CWE-59)

## Problem

`isPathInWorkspace` in `sandbox.ts` used `path.resolve()` to canonicalize file paths before checking workspace containment. `path.resolve()` normalizes `../` segments and dot-paths at the **string level** but does **not follow symlinks**. A symlink inside the workspace pointing to a location outside it would resolve to a path that lexically starts with the workspace prefix, passing the containment check while the actual filesystem target is outside the boundary.

Attack scenario: an agent creates a symlink `/workspaces/user1/escape -> /etc`, then reads `/workspaces/user1/escape/shadow`. `path.resolve()` returns `/workspaces/user1/escape/shadow` (passes `startsWith` check), but the real target is `/etc/shadow`.

This is CWE-59 (Improper Link Resolution Before File Access), the same class as CVE-2025-55130 in Node.js's Permissions Model. The prior CWE-22 fix (#873) addressed path traversal via `../` but left the symlink vector open because `path.resolve()` was assumed sufficient.

## Solution

Replaced `path.resolve()` with `fs.realpathSync()` for all path canonicalization in `sandbox.ts`. Three functions handle the full matrix of path states:

### 1. `resolveRealPath(filePath)` -- entry point for file paths

- Calls `fs.realpathSync()` to resolve the full symlink chain to the canonical path.
- On `ENOENT` (file does not exist yet -- Write/Edit targets), delegates to `resolveParentRealPath`.
- On all other errors (`ELOOP`, `EACCES`, `ENOTDIR`), returns `null` to deny. Fail-closed: if the path cannot be verified safe, reject it.

### 2. `resolveParentRealPath(filePath)` -- ancestor walk for non-existent paths

- Walks up the directory tree, stripping path components into a `segments` array, calling `realpathSync` on each ancestor until one resolves.
- Re-appends the non-existent tail segments to the resolved ancestor: `path.join(realParent, ...segments.toReversed())`.
- **Dangling symlink guard**: when an ancestor returns `ENOENT`, calls `fs.lstatSync()` on it. If `lstat` succeeds and `isSymbolicLink()` is true, the component is a dangling symlink (exists as a link but its target does not). Returns `null` to deny -- a dangling symlink pointing outside the workspace cannot be verified safe by walking past it.
- Uses `toReversed()` instead of `segments.reverse()` to avoid mutating the array in place.

### 3. `resolveWorkspacePath(workspacePath)` -- workspace root resolution

- Resolves the workspace path itself with `realpathSync`, so a workspace accessed through a symlink alias resolves to the same canonical root.
- Falls back to `path.resolve()` **only on `ENOENT`** (test environments with mock paths). Originally fell back on all errors, which would silently accept a workspace path with `ELOOP` or `EACCES` -- tightened to ENOENT-only after code quality review.

### Containment check (unchanged structure)

```typescript
const realPath = resolveRealPath(filePath);
if (realPath === null) return false; // fail-closed

const resolvedWorkspace = resolveWorkspacePath(workspacePath);
if (resolvedWorkspace === null) return false; // fail-closed

return realPath === resolvedWorkspace || realPath.startsWith(resolvedWorkspace + "/");
```

## Key Insight

**`path.resolve()` is a string operation, not a filesystem operation.** This is a fundamental distinction that is easy to miss because `path.resolve()` produces absolute, normalized paths that *look* canonical. But canonicalization without following symlinks is incomplete -- it handles CWE-22 (path traversal) but not CWE-59 (symlink following). Any containment check must use `fs.realpathSync()` (or equivalent) to resolve the actual filesystem target.

The harder sub-problem is non-existent paths. Write and Edit targets may not exist yet, so `realpathSync` throws `ENOENT`. The naive fix -- "on ENOENT, fall back to `path.resolve()`" -- reintroduces the original vulnerability for any path with a symlink component above the non-existent leaf. The correct approach is to walk up the directory tree, resolve the deepest existing ancestor with `realpathSync`, and re-append the non-existent tail. But this walk itself creates a new attack surface: a dangling symlink (symlink exists, target does not) at an intermediate component produces `ENOENT` from `realpathSync`, which looks identical to "directory does not exist". Without the `lstatSync` check, the walk steps past the dangling symlink and resolves its parent -- effectively ignoring a symlink that could point anywhere.

**Layered defense matters.** This fix is layer 2 (application-level path validation). Layer 1 (bubblewrap OS sandbox) independently restricts filesystem access via Linux namespaces. Neither layer alone is sufficient: bubblewrap has known bypass vectors in certain configurations, and application-level checks have TOCTOU race conditions. Together, an attacker must defeat both layers simultaneously.

**Audit the workspace path too, not just the file path.** The initial implementation resolved the file path with `realpathSync` but left the workspace path resolved with `path.resolve()`. If the workspace root itself is accessed through a symlink, the canonical paths won't match even for legitimate files. `resolveWorkspacePath` ensures both sides of the containment comparison use the same canonical form.

## Session Errors

1. **`soleur:plan_review` skill not found** -- the skill referenced in the workflow does not exist (or was renamed). Had to skip plan review and proceed directly. Track skill inventory drift with a CI check that validates skill references against `plugins/soleur/skills/`.

2. **`npx vitest` failed with rolldown native binding error** -- recurring issue where `npx` resolves to a stale or incompatible global vitest binary. Fix: use `./node_modules/.bin/vitest run` to force project-local resolution. This is the third session to hit this (see CWE-22 and canUseTool learnings).

3. **`package.json` accidentally deleted in prior commit f72e723** -- a prior security fix commit removed `apps/web-platform/package.json` from the tree. Had to restore it from git history (`git show HEAD~1:apps/web-platform/package.json > package.json`). Root cause: likely a bad `git add` that staged a deletion. Lesson: always run `git diff --stat` before committing to verify no unintended file removals.

4. **`beforeEach`/`afterEach` not imported from vitest** -- test file used these hooks without importing them. Vitest does not inject globals by default (unlike Jest). The fix is explicit: `import { describe, test, expect, beforeEach, afterEach } from "vitest"`.

5. **`segments.reverse()` mutation risk** -- the initial implementation used `Array.prototype.reverse()` which mutates the array in place. While functionally correct in this case (the array is not reused), mutation of local arrays is a latent bug source. Changed to `toReversed()` (ES2023) which returns a new array. Ensure the TypeScript target/lib includes ES2023.

## References

- Issue #877 (original symlink escape report)
- PR #884 (this fix)
- Issue #891 (LS/NotebookRead bypass `isPathInWorkspace` -- filed during architecture review)
- CWE-59: <https://cwe.mitre.org/data/definitions/59.html>
- CVE-2025-55130: Node.js Permissions Model symlink bypass (same vulnerability class)
- Prior fix: PR #873 (CWE-22 path traversal -- `path.resolve` + trailing separator)

## Tags

category: security-issues
module: web-platform/server
cwe: CWE-59
related: CWE-22, CVE-2025-55130
