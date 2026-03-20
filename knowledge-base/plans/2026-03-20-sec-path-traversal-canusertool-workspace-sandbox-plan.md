---
title: "sec: fix path traversal in canUseTool workspace sandbox"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources:** Claude Agent SDK docs (Context7), CWE-22 best practices (web search), Node.js CVE-2025-55130 symlink bypass, institutional learnings (agent-sdk-spike-validation, websocket-error-sanitization)

### Key Improvements

1. **Critical pre-approved tools bypass discovered** -- workspace `.claude/settings.json` pre-approves Read/Glob/Grep, which means `canUseTool` is never called for those tools per the SDK permission chain. The fix must remove those pre-approvals to close the vulnerability for read operations.
2. **Symlink escape vector identified** -- `path.resolve()` does not follow symlinks; `fs.realpathSync()` is needed for defense-in-depth against symlink-based sandbox escape (CVE-2025-55130 analogue).
3. **URL-encoded traversal test removed** -- `path.resolve()` does not decode `%2F`; the Agent SDK passes JSON-parsed strings, not URL-encoded paths, making `..%2F` a non-vector.
4. **Bash tool gap requires `cwd` enforcement** -- the SDK's `cwd` option restricts Bash to the workspace directory; document this as the intended Bash sandbox mechanism.

### New Considerations Discovered

- The SDK permission evaluation order is: hooks > deny rules > permission mode > allow rules (settings.json) > `canUseTool` callback. Pre-approved tools in settings.json never reach `canUseTool`.
- `canUseTool` may cache "allow" decisions per-tool-name within a session (spike finding) -- this means the callback must return consistent results; a stateful allowlist is unreliable.
- The workspace symlink (`plugins/soleur -> /app/shared/plugins/soleur`) is a read-only plugin path, not user-controlled. Symlink attack surface is low but should be documented.

---

# sec: fix path traversal in canUseTool workspace sandbox

The `canUseTool` callback in `apps/web-platform/server/agent-runner.ts` (line 172) validates file paths using `startsWith` without canonicalizing the path first. An agent-submitted path containing `../` segments (e.g., `/workspaces/user1/../user2/secret.md`) passes the `startsWith(workspacePath)` check but resolves to a directory outside the user's workspace.

This is CWE-22 (Path Traversal), labeled P0-critical. Pre-existing since the MVP commit (`5b8e242`).

Closes #725

## Acceptance Criteria

- [ ] All file paths in the `canUseTool` callback are canonicalized with `path.resolve()` before the `startsWith` check
- [ ] The `workspacePath` comparison target is also resolved (defense-in-depth -- it should already be absolute, but `path.resolve` is a no-op on absolute paths)
- [ ] A trailing-separator edge case is handled: `path.resolve("/workspaces/user1")` must not match `/workspaces/user10/file.txt` -- append `/` to the resolved workspace path before comparison
- [ ] The workspace `.claude/settings.json` pre-approved permissions (`Read`, `Glob`, `Grep`) are removed so that ALL file-accessing tools route through `canUseTool` for path validation
- [ ] The `Bash` tool gap is documented as a known limitation with mitigation: the SDK's `cwd` option restricts Bash execution to the workspace directory, and `canUseTool` receives Bash input as a `command` string (not a file path) -- shell-level sandbox escape requires the SDK's built-in `cwd` lock or a container-level chroot, not path prefix checks
- [ ] A dedicated unit test file `apps/web-platform/test/canusertool-sandbox.test.ts` covers:
  - Path with `../` segments is denied
  - Path exactly at workspace root is allowed
  - Subdirectory path is allowed
  - Path outside workspace is denied
  - Path that is a prefix collision (e.g., `/workspaces/user1` vs `/workspaces/user10`) is denied
  - Empty/missing `file_path` and `path` fields pass through (no false deny)
  - Deeply nested traversal (`/workspaces/user1/a/b/../../../../etc/passwd`) is denied

### Research Insights

**SDK Permission Chain (from [Claude Agent SDK docs](https://platform.claude.com/docs/en/agent-sdk/permissions)):**

The SDK evaluates permissions in this order:
1. Hooks (can allow, deny, or pass through)
2. Deny rules (`disallowed_tools` + settings.json deny)
3. Permission mode (`bypassPermissions` approves all; `acceptEdits` approves file ops)
4. Allow rules (`allowed_tools` + settings.json `permissions.allow`)
5. `canUseTool` callback (only reached if not resolved above)

The current workspace `.claude/settings.json` has `permissions.allow: ["Read", "Glob", "Grep"]`, which means these three tools are auto-approved at step 4 and **never reach** the `canUseTool` callback at step 5. The path traversal check in `canUseTool` only protects Write and Edit today. This is confirmed by the institutional learning in `knowledge-base/learnings/2026-03-16-agent-sdk-spike-validation.md`.

**Fix:** Remove `permissions.allow` from the workspace settings.json (or set it to an empty array). With `permissionMode: "default"` (already configured), unmatched tools fall through to `canUseTool`, which is the correct security boundary.

**Node.js Path Traversal Best Practices (CWE-22):**

The standard secure pattern is:
```typescript
const safePath = path.resolve(basePath, userInput);
if (!safePath.startsWith(path.resolve(basePath) + path.sep)) {
  throw new Error("Path traversal detected");
}
```

Key considerations:
- `path.resolve()` normalizes `..` segments and converts to absolute -- this is the primary defense
- Always append `path.sep` (or `/` on Linux) to the base path before `startsWith` to prevent prefix collisions
- URL-encoded traversal (`..%2F`) is NOT a vector here because the Agent SDK passes JSON-parsed strings, not URL-encoded paths; `path.resolve` does not decode percent-encoding
- `path.normalize()` alone is insufficient -- it normalizes but does not produce an absolute path

**Symlink Considerations (CVE-2025-55130):**

`path.resolve()` does not follow symlinks. If an attacker can create a symlink inside the workspace pointing outside it, `path.resolve` would approve the path but the actual file operation would follow the symlink to an external location. Mitigations:
- The workspace directory is server-provisioned (`workspace.ts`), not user-writable via the filesystem directly
- The only symlink is `plugins/soleur -> /app/shared/plugins/soleur` (read-only, server-controlled)
- Agent tool calls go through the SDK, which resolves paths relative to `cwd` -- the agent cannot create arbitrary symlinks without using Bash
- For defense-in-depth, a future hardening step could use `fs.realpathSync()` to resolve symlinks before the prefix check, but this requires the target file to exist (TOCTOU concern for Write/Edit operations targeting new files)
- Document symlink risk as a known limitation with low probability given the current architecture

## Test Scenarios

- Given a `file_path` of `/workspaces/user1/../user2/secret.md` and `workspacePath` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is denied with "Access denied: outside workspace"
- Given a `file_path` of `/workspaces/user10/file.txt` and `workspacePath` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is denied (prefix collision)
- Given a `file_path` of `/workspaces/user1/knowledge-base/plans/plan.md`, when `canUseTool` evaluates it, then the tool call is allowed
- Given a `file_path` of `/workspaces/user1`, when `canUseTool` evaluates it, then the tool call is allowed (workspace root itself)
- Given an empty `file_path` and empty `path`, when `canUseTool` evaluates it, then the tool call is allowed (no path to check)
- Given a `file_path` of `/workspaces/user1/a/b/../../../../etc/passwd`, when `canUseTool` evaluates it, then the tool call is denied (deep traversal resolves to `/etc/passwd`)

### Research Insights

**Test Design:**
- The `..%2F` (URL-encoded traversal) test case from the original plan should be removed. Verified experimentally: `path.resolve('/workspaces/user1/..%2F..%2Fetc/passwd')` returns `/workspaces/user1/..%2F..%2Fetc/passwd` -- the percent-encoded dots are treated as literal directory names, not traversal sequences. The Agent SDK delivers tool input as JSON-parsed objects, so URL encoding is not a relevant attack vector.
- Add a deeply nested traversal case (`/a/b/../../../../etc/passwd`) to verify `path.resolve` handles multiple `..` segments at varying depths.

## Context

- **Vulnerable code:** `apps/web-platform/server/agent-runner.ts:172` -- `filePath.startsWith(workspacePath)` without `path.resolve()`
- **CWE:** [CWE-22: Improper Limitation of a Pathname to a Restricted Directory](https://cwe.mitre.org/data/definitions/22.html)
- **Origin:** Discovered during code review of PR #721
- **Severity:** P0 -- any authenticated user's agent could read/write another user's workspace
- **Scope of fix:** Two changes: (1) extract the sandbox check into a pure function (`isPathInWorkspace`) with `path.resolve()` + trailing-separator guard, (2) remove pre-approved permissions from workspace `.claude/settings.json` so all file tools route through `canUseTool`

### Research Insights

**Related Institutional Learnings:**

1. **Agent SDK permission bypass** (`knowledge-base/learnings/2026-03-16-agent-sdk-spike-validation.md`): The `canUseTool` callback only fires for tools NOT pre-approved by `allowedTools` or `.claude/settings.json`. The current workspace settings pre-approve Read/Glob/Grep, completely bypassing the sandbox for read operations. This learning directly applies -- the fix must address the pre-approval gap.

2. **`canUseTool` may cache decisions** (spike/FINDINGS.md): "canUseTool may cache allow decisions per-tool-name within a session -- only 1 callback invocation was observed despite 5 tool uses." This means the callback must be deterministic and path-based, not stateful. The pure function design (`isPathInWorkspace`) is correct because it evaluates each path independently without session state.

3. **Error sanitization pattern** (`knowledge-base/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`): The deny message "Access denied: outside workspace" is already safe -- it does not leak the resolved path or the workspace boundary. Maintain this pattern.

## MVP

### apps/web-platform/server/agent-runner.ts

```typescript
// Extract sandbox check as a pure, testable function
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  const resolved = path.resolve(filePath);
  const resolvedWorkspace = path.resolve(workspacePath);
  return resolved === resolvedWorkspace || resolved.startsWith(resolvedWorkspace + "/");
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

### Research Insights

**Implementation refinements from research:**
- The `resolvedWorkspace + "/"` pattern is the Node.js standard for preventing prefix collisions (e.g., `/workspaces/user1` vs `/workspaces/user10`). Using `path.sep` instead of hardcoded `"/"` is unnecessary since the server runs on Linux (Docker), but for portability the constant `"/"` is acceptable since `path.resolve` produces POSIX paths on Linux.
- The original MVP used `resolvedWorkspace.slice(0, -1)` for the exact-match case -- simplified to direct equality check (`resolved === resolvedWorkspace`) for clarity.
- `path.resolve` handles all normalization: multiple slashes (`//`), dot segments (`.`), parent references (`..`), and trailing slashes. No additional sanitization is needed.

### apps/web-platform/server/workspace.ts

Remove pre-approved permissions that bypass `canUseTool`:

```typescript
const DEFAULT_SETTINGS = {
  permissions: {
    allow: [],
  },
};
```

This ensures Read, Glob, and Grep route through the `canUseTool` callback for path validation instead of being auto-approved by the SDK's permission chain.

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

  test("allows nested subdirectory", () => {
    expect(
      isPathInWorkspace("/workspaces/user1/knowledge-base/plans/plan.md", WORKSPACE),
    ).toBe(true);
  });

  test("denies path traversal via ../", () => {
    expect(
      isPathInWorkspace("/workspaces/user1/../user2/secret.md", WORKSPACE),
    ).toBe(false);
  });

  test("denies deeply nested traversal", () => {
    expect(
      isPathInWorkspace("/workspaces/user1/a/b/../../../../etc/passwd", WORKSPACE),
    ).toBe(false);
  });

  test("denies prefix collision (user1 vs user10)", () => {
    expect(isPathInWorkspace("/workspaces/user10/file.txt", WORKSPACE)).toBe(false);
  });

  test("denies path outside workspace", () => {
    expect(isPathInWorkspace("/etc/passwd", WORKSPACE)).toBe(false);
  });

  test("denies root path", () => {
    expect(isPathInWorkspace("/", WORKSPACE)).toBe(false);
  });
});
```

### apps/web-platform/test/workspace.test.ts

Update the existing workspace test to verify empty permissions:

```typescript
test("creates .claude/settings.json with empty permissions for canUseTool routing", async () => {
  const userId = randomUUID();
  const path = await provisionWorkspace(userId);

  const settingsPath = join(path, ".claude/settings.json");
  expect(existsSync(settingsPath)).toBe(true);

  const settings = JSON.parse(readFileSync(settingsPath, "utf8"));
  expect(settings.permissions.allow).toEqual([]);
});
```

## Known Limitations

1. **Bash tool**: `canUseTool` receives Bash input as `{ command: string }`, not a file path. The SDK's `cwd` option restricts the shell working directory to the workspace. A determined agent could attempt `cat /etc/passwd` via Bash -- this is mitigated by the container-level isolation (Docker) and the SDK's built-in Bash sandboxing. Full Bash command parsing is out of scope for this fix.

2. **Symlink escape**: `path.resolve()` does not follow symlinks. If a symlink inside the workspace points outside, the resolved path passes validation but the filesystem operation follows the symlink target. Current risk is LOW because workspace creation is server-controlled and agents cannot create symlinks without Bash. A future hardening step could add `fs.realpathSync()` for existing files, but this introduces a TOCTOU gap for new file creation (Write tool).

3. **`canUseTool` caching**: The SDK may cache `allow` decisions per tool name within a session. If caching occurs, only the first invocation per tool name reaches the callback. This means the path check runs on the first file access per tool, not every access. This is a known SDK behavior documented in the spike findings. The fix is still valuable because: (a) the first access is validated, (b) the `cwd` setting constrains the agent's working directory, and (c) the SDK's internal path resolution is relative to `cwd`.

## References

- Issue: #725
- Vulnerable file: `apps/web-platform/server/agent-runner.ts:172`
- Pre-approval bypass: `apps/web-platform/server/workspace.ts:20-24` (DEFAULT_SETTINGS)
- Existing test patterns: `apps/web-platform/test/error-sanitizer.test.ts`, `apps/web-platform/test/workspace.test.ts`
- Spike findings on `canUseTool`: `spike/FINDINGS.md`
- SDK permission docs: [Claude Agent SDK Permissions](https://platform.claude.com/docs/en/agent-sdk/permissions)
- CWE-22 reference: [MITRE CWE-22](https://cwe.mitre.org/data/definitions/22.html)
- Node.js path traversal guide: [StackHawk Node.js Path Traversal](https://www.stackhawk.com/blog/node-js-path-traversal-guide-examples-and-prevention/)
- Symlink bypass precedent: [CVE-2025-55130](https://www.cyberhub.blog/cves/CVE-2025-55130) (Node.js Permissions Model symlink bypass, CVSS 9.1)
- Institutional learning: `knowledge-base/learnings/2026-03-16-agent-sdk-spike-validation.md`
