---
module: web-platform
date: 2026-04-05
problem_type: security_issue
component: tooling
symptoms:
  - "removeWorkspaceDir accepts arbitrary paths with no self-validation"
  - "Future callers could pass untrusted input enabling rm -rf outside workspace root"
root_cause: missing_validation
resolution_type: code_fix
severity: medium
tags: [path-traversal, defense-in-depth, cwe-22, workspace, rm-rf]
---

# Troubleshooting: Missing path validation on exported rm -rf function

## Problem

`removeWorkspaceDir` in `apps/web-platform/server/workspace.ts` was exported and accepted arbitrary string paths with no self-validation. While all current callers validated via UUID regex, a future caller could pass untrusted input, enabling `rm -rf` on arbitrary paths outside the workspace root.

## Environment

- Module: web-platform
- Affected Component: server/workspace.ts (`removeWorkspaceDir` function)
- Date: 2026-04-05

## Symptoms

- `removeWorkspaceDir` accepted any string path without boundary validation
- No protection against deleting the workspace root itself (which would delete all user workspaces)
- No protection against prefix collisions (e.g., `/workspaces-evil` matching `/workspaces`)

## What Didn't Work

**Direct solution:** The problem was identified during code review (PR #1540) and fixed on the first attempt. The fix was a 4-line guard clause using `path.resolve()` for canonicalization.

**Design alternative considered:** Reusing `isPathInWorkspace()` from `sandbox.ts` was evaluated but rejected because it uses `fs.realpathSync()` which throws on non-existent paths. The workspace cleanup function needs to validate paths that may not exist yet (the `existsSync` check comes after the guard).

## Session Errors

**Worktree creation appeared successful but wasn't registered in git worktree list**

- **Recovery:** Ran `worktree-manager.sh create` a second time, which succeeded
- **Prevention:** Verify worktree creation by checking `git worktree list` immediately after creation

**Draft PR creation failed due to no commits on new branch**

- **Recovery:** Deferred PR creation until after first commit, then created successfully
- **Prevention:** Expected behavior for new branches -- create PR after first commit, not immediately after branch creation

**Existing mock test used hardcoded path outside test root**

- **Recovery:** Updated mock test from `/workspaces/test-cleanup` to `TEST_ROOT + "/test-cleanup"` to work with the new path validation guard
- **Prevention:** When adding boundary validation to a function, check all existing tests that use hardcoded paths -- the validation may reject paths that were previously accepted

**CWD drifted to apps/web-platform after vitest run**

- **Recovery:** Used explicit `cd` back to worktree root before running git commands
- **Prevention:** Use absolute paths for git commands, or always verify CWD with `pwd` before git operations

## Solution

Added a `path.resolve()` guard at the top of `removeWorkspaceDir`, before the `existsSync` check:

**Code changes:**

```typescript
// Before (no validation):
export function removeWorkspaceDir(workspacePath: string): void {
  if (!existsSync(workspacePath)) return;
  // ... rm -rf logic

// After (with path prefix check):
export function removeWorkspaceDir(workspacePath: string): void {
  const root = resolve(getWorkspacesRoot());
  const resolved = resolve(workspacePath);
  if (resolved === root || !resolved.startsWith(root + "/")) {
    throw new Error("Refusing to remove path outside workspace root");
  }

  if (!existsSync(workspacePath)) return;
  // ... rm -rf logic
```

Added 6 test cases covering: outside root, root itself, prefix collision, path traversal, empty string, and valid subdirectory acceptance.

## Why This Works

1. **Root cause:** The function performed destructive operations (`rm -rf`) without validating its own input at the function boundary. Caller-side validation existed but was not enforced by the function contract.
2. **`path.resolve()` canonicalizes** both the workspace root and the input path, collapsing `..`, `.`, double slashes, and trailing slashes without filesystem I/O.
3. **The trailing slash in `root + "/"` prevents prefix collisions:** Without it, `/workspaces-evil` would match `startsWith("/workspaces")`. With the trailing slash, only paths that are actual children of the root directory match.
4. **The `resolved === root` check** prevents deleting the workspace root directory itself, which would destroy all user workspaces.
5. **Generic error message** does not leak the workspace root path, following the project's error sanitization pattern (CWE-209).

## Prevention

- Always add boundary validation to exported functions that perform destructive operations (rm -rf, DELETE, DROP)
- Use `path.resolve()` for string-level canonicalization when the path may not exist; use `fs.realpathSync()` only when symlink resolution is required
- Always include trailing separator in `startsWith` prefix checks to prevent prefix collisions
- When the threat model is programming errors (not adversarial input), `path.resolve()` is sufficient -- `realpathSync()` adds complexity without matching the threat model

## Related Issues

- See also: [CWE-22 path traversal in canUserTool sandbox](../2026-03-20-cwe22-path-traversal-canusertool-sandbox.md)
- See also: [Symlink escape CWE-59 workspace sandbox](../2026-03-20-symlink-escape-cwe59-workspace-sandbox.md)
- See also: [Defense-in-depth canuse tool sandbox](../2026-03-20-canuse-tool-sandbox-defense-in-depth.md)
