---
title: "sec: fix path traversal in canUseTool workspace sandbox"
type: fix
date: 2026-03-20
---

# sec: fix path traversal in canUseTool workspace sandbox

The `canUseTool` callback in `apps/web-platform/server/agent-runner.ts` (line 172) validates file paths using `startsWith` without canonicalizing the path first. An agent-submitted path containing `../` segments (e.g., `/workspaces/user1/../user2/secret.md`) passes the `startsWith(workspacePath)` check but resolves to a directory outside the user's workspace.

This is CWE-22 (Path Traversal), labeled P0-critical. Pre-existing since the MVP commit (`5b8e242`).

Closes #725

## Acceptance Criteria

- [ ] All file paths in the `canUseTool` callback are canonicalized with `path.resolve()` before the `startsWith` check
- [ ] The `workspacePath` comparison target is also resolved (defense-in-depth -- it should already be absolute, but `path.resolve` is a no-op on absolute paths)
- [ ] A trailing-separator edge case is handled: `path.resolve("/workspaces/user1")` must not match `/workspaces/user10/file.txt` -- append `/` to the resolved workspace path before comparison
- [ ] The `Bash` tool gap is documented as a known limitation (the Agent SDK's `canUseTool` fires for Bash but input is a `command` string, not a file path -- sandboxing Bash requires the SDK's `cwd` lock or a chroot, not path prefix checks)
- [ ] A dedicated unit test file `apps/web-platform/test/canusertool-sandbox.test.ts` covers:
  - Path with `../` segments is denied
  - Path with double-encoded traversal (`..%2F`) is denied (if the SDK decodes before delivering)
  - Path exactly at workspace root is allowed
  - Subdirectory path is allowed
  - Path outside workspace is denied
  - Path that is a prefix collision (e.g., `/workspaces/user1` vs `/workspaces/user10`) is denied
  - Empty/missing `file_path` and `path` fields pass through (no false deny)

## Test Scenarios

- Given a `file_path` of `/workspaces/user1/../user2/secret.md` and `workspacePath` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is denied with "Access denied: outside workspace"
- Given a `file_path` of `/workspaces/user10/file.txt` and `workspacePath` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is denied (prefix collision)
- Given a `file_path` of `/workspaces/user1/knowledge-base/plans/plan.md`, when `canUseTool` evaluates it, then the tool call is allowed
- Given a `file_path` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is allowed (workspace root itself)
- Given an empty `file_path` and empty `path`, when `canUseTool` evaluates it, then the tool call is allowed (no path to check)

## Context

- **Vulnerable code:** `apps/web-platform/server/agent-runner.ts:172` -- `filePath.startsWith(workspacePath)` without `path.resolve()`
- **CWE:** [CWE-22: Improper Limitation of a Pathname to a Restricted Directory](https://cwe.mitre.org/data/definitions/22.html)
- **Origin:** Discovered during code review of PR #721
- **Severity:** P0 -- any authenticated user's agent could read/write another user's workspace
- **Scope of fix:** Extract the sandbox check into a pure function (`isPathInWorkspace`) for testability, apply `path.resolve()` + trailing-separator guard

## MVP

### apps/web-platform/server/agent-runner.ts

```typescript
// Extract sandbox check as a pure, testable function
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  const resolved = path.resolve(filePath);
  const resolvedWorkspace = path.resolve(workspacePath) + "/";
  return resolved === resolvedWorkspace.slice(0, -1) || resolved.startsWith(resolvedWorkspace);
}
```

Replace the inline check at line 172 with:

```typescript
if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
  return {
    behavior: "deny" as const,
    message: "Access denied: outside workspace",
  };
}
```

### apps/web-platform/test/canusertool-sandbox.test.ts

```typescript
import { describe, test, expect } from "vitest";
import { isPathInWorkspace } from "../server/agent-runner";

const WORKSPACE = "/workspaces/user1";

describe("isPathInWorkspace", () => {
  test("allows path inside workspace", () => {
    expect(isPathInWorkspace("/workspaces/user1/file.md", WORKSPACE)).toBe(true);
  });

  test("allows workspace root itself", () => {
    expect(isPathInWorkspace("/workspaces/user1", WORKSPACE)).toBe(true);
  });

  test("denies path traversal via ../", () => {
    expect(isPathInWorkspace("/workspaces/user1/../user2/secret.md", WORKSPACE)).toBe(false);
  });

  test("denies prefix collision (user1 vs user10)", () => {
    expect(isPathInWorkspace("/workspaces/user10/file.txt", WORKSPACE)).toBe(false);
  });

  test("denies path outside workspace", () => {
    expect(isPathInWorkspace("/etc/passwd", WORKSPACE)).toBe(false);
  });
});
```

## References

- Issue: #725
- Vulnerable file: `apps/web-platform/server/agent-runner.ts:172`
- Existing test patterns: `apps/web-platform/test/error-sanitizer.test.ts`, `apps/web-platform/test/workspace.test.ts`
- Spike findings on `canUseTool`: `spike/FINDINGS.md`
