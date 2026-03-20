---
title: "fix(sec): audit LS and NotebookRead tools for path validation bypass"
type: fix
date: 2026-03-20
semver: patch
---

# fix(sec): audit LS and NotebookRead tools for path validation bypass

## Overview

`LS` and `NotebookRead` are in the `SAFE_TOOLS` allowlist in `apps/web-platform/server/agent-runner.ts:270-277`. They bypass `canUseTool`'s `isPathInWorkspace` check entirely. If either tool accepts a user-controlled path argument, an agent could use them to list directories or read notebooks outside the workspace boundary -- including through symlinks.

This gap was identified during the architecture review of PR #884 (symlink escape defense-in-depth) and filed as issue #891.

## Problem Statement / Motivation

The `canUseTool` callback in `agent-runner.ts` enforces workspace containment for five tools (`Read`, `Write`, `Edit`, `Glob`, `Grep`) by extracting `file_path` or `path` from `toolInput` and checking `isPathInWorkspace()`. Six other tools are in `SAFE_TOOLS` and auto-allowed without any path check:

```typescript
const SAFE_TOOLS = [
  "Agent",    // No path input
  "Skill",    // No path input
  "TodoRead", // No path input
  "TodoWrite",// No path input
  "LS",       // <-- accepts path?
  "NotebookRead", // <-- accepts path?
];
```

`Agent`, `Skill`, `TodoRead`, and `TodoWrite` are genuinely safe -- they don't accept filesystem path arguments. But `LS` and `NotebookRead` need verification:

1. **LS**: A directory listing tool. In Claude Code's built-in tools, the Glob tool has a `path` parameter ("The directory to search in"). LS likely accepts a similar directory path parameter.

2. **NotebookRead**: The sibling write tool (NotebookEdit) has `notebook_path: string` ("The absolute path to the Jupyter notebook file"). NotebookRead almost certainly accepts a `file_path` parameter for the notebook to read, consistent with the Read tool's `file_path` parameter.

Both tools are built into the Claude Code runtime (compiled into the `@anthropic-ai/claude-agent-sdk` binary) -- their schemas are not exposed in the SDK's TypeScript type definitions. The `canUseTool` callback receives `toolInput: Record<string, unknown>`, so the path arguments pass through regardless.

## Proposed Solution

### Option A: Move LS and NotebookRead into the checked tools block (recommended)

Add `LS` and `NotebookRead` to the existing file-tool check alongside `Read`, `Write`, `Edit`, `Glob`, and `Grep`:

```typescript
// apps/web-platform/server/agent-runner.ts
if (
  ["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead"].includes(toolName)
) {
  const filePath =
    (toolInput.file_path as string) ||
    (toolInput.path as string) ||
    (toolInput.notebook_path as string) ||  // NotebookRead/NotebookEdit
    "";
  if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
    return {
      behavior: "deny" as const,
      message: "Access denied: outside workspace",
    };
  }
}
```

Remove `LS` and `NotebookRead` from `SAFE_TOOLS` and add a comment documenting why the remaining tools are safe:

```typescript
// Safe SDK tools: no filesystem path inputs, allowed without checks.
// Agent/Skill: orchestration tools, no path args.
// TodoRead/TodoWrite: in-memory task list, no path args.
// NOTE: LS and NotebookRead removed (#891) -- they accept path inputs
// and must go through isPathInWorkspace.
const SAFE_TOOLS = ["Agent", "Skill", "TodoRead", "TodoWrite"];
```

### Option B: Document safety if tools are CWD-scoped

If investigation reveals that LS and NotebookRead are scoped to the `cwd` option by the SDK runtime (ignoring any path parameter), document this with a code comment:

```typescript
// LS and NotebookRead: path arguments are resolved relative to cwd
// by the SDK runtime. Since cwd is set to workspacePath (line 182),
// these tools cannot access files outside the workspace even with
// absolute path arguments. Verified: [link to SDK source/docs].
// Re-audit if SDK version changes path resolution behavior.
const SAFE_TOOLS = ["Agent", "Skill", "TodoRead", "TodoWrite", "LS", "NotebookRead"];
```

**Recommendation: Option A.** Defense-in-depth favors explicit checks over assumptions about SDK internal behavior. Even if the SDK scopes to CWD today, a future SDK version could change that behavior silently. The `isPathInWorkspace` check is cheap and provides an independent layer of protection.

## Technical Considerations

### Attack Surface Enumeration

All code paths for file access through `canUseTool`:

| Tool | Path Parameter | Currently Checked | Status |
|------|---------------|-------------------|--------|
| Read | `file_path` | Yes | Safe |
| Write | `file_path` | Yes | Safe |
| Edit | `file_path` | Yes | Safe |
| Glob | `path` | Yes | Safe |
| Grep | `path` | Yes | Safe |
| **LS** | `path` (probable) | **No** | **Gap** |
| **NotebookRead** | `file_path` (probable) | **No** | **Gap** |
| Bash | `command` | Separate check (containsSensitiveEnvAccess) | N/A (OS sandbox) |
| Agent | None | N/A | Safe |
| Skill | None | N/A | Safe |
| TodoRead | None | N/A | Safe |
| TodoWrite | None | N/A | Safe |

### Path parameter discovery

The `canUseTool` callback receives `toolInput: Record<string, unknown>`. The path parameter name varies by tool:
- `file_path`: Read, Write, Edit, NotebookRead (probable), NotebookEdit (confirmed)
- `path`: Glob, Grep, LS (probable)
- `notebook_path`: NotebookEdit (confirmed as alias)

The fix must check all three parameter names: `file_path`, `path`, and `notebook_path`.

### SDK version coupling

The tool schemas are compiled into the Claude Code binary (`@anthropic-ai/claude-agent-sdk`). Parameter names could change between SDK versions. The current approach (checking multiple parameter names with `||` fallback) is resilient to additions but not to renames. This is acceptable -- a rename would break the existing Read/Write/Edit/Glob/Grep checks too, forcing an update.

### Bubblewrap sandbox interaction

The bubblewrap sandbox (layer 1) independently restricts filesystem access via Linux namespaces configured through the `sandbox.filesystem` option:
```typescript
filesystem: {
  allowWrite: [workspacePath],
  denyRead: ["/workspaces"],
}
```
The `isPathInWorkspace` check is layer 2 (application-level). Even if layer 2 is bypassed, layer 1 should block access. But defense-in-depth requires both layers to be correct independently.

### Performance impact

`isPathInWorkspace` calls `fs.realpathSync()` which is a synchronous filesystem operation. For LS and NotebookRead, this adds ~1ms per invocation. Since these tools are I/O-bound (listing directories, reading notebooks), the overhead is negligible.

## Non-goals

- Auditing Bash tool path validation (Bash has OS-level sandbox isolation, separate from `isPathInWorkspace`)
- Modifying the SDK to change LS/NotebookRead tool schemas
- Adding path validation for MCP tools (separate security surface with its own controls)
- Verifying the bubblewrap sandbox configuration (layer 1 audit is out of scope for this issue)

## Acceptance Criteria

- [ ] Determine the actual parameter names for LS and NotebookRead by inspecting `toolInput` at runtime or SDK source
- [ ] Move LS and NotebookRead out of `SAFE_TOOLS` into the `isPathInWorkspace` check block in `agent-runner.ts`
- [ ] Check `file_path`, `path`, and `notebook_path` parameter names in the path extraction logic
- [ ] Add code comment documenting why remaining SAFE_TOOLS members are safe (no path inputs)
- [ ] Add unit tests for LS and NotebookRead path validation in `canusertool-sandbox.test.ts`
- [ ] Add a negative-space test that enumerates all tools with path args and asserts they route through `isPathInWorkspace`
- [ ] All existing sandbox tests continue to pass

## Test Scenarios

### Acceptance Tests

- Given an LS tool call with `path: "/etc"`, when `canUseTool` is invoked, then it returns `behavior: "deny"` with "outside workspace" message
- Given an LS tool call with `path: "<workspacePath>/subdir"`, when `canUseTool` is invoked, then it returns `behavior: "allow"`
- Given a NotebookRead tool call with `file_path: "/etc/shadow"`, when `canUseTool` is invoked, then it returns `behavior: "deny"`
- Given a NotebookRead tool call with `file_path: "<workspacePath>/notebook.ipynb"`, when `canUseTool` is invoked, then it returns `behavior: "allow"`
- Given an LS tool call with `path: "<workspacePath>/../other-user/dir"`, when `canUseTool` is invoked, then it returns `behavior: "deny"` (path traversal)

### Regression Tests

- Given a Read tool call with `file_path` outside workspace, when `canUseTool` is invoked, then it still returns `behavior: "deny"` (existing behavior preserved)
- Given a symlink inside workspace pointing to `/etc`, when LS is called on the symlink path, then `isPathInWorkspace` resolves the symlink and denies access

### Negative-Space Test

- Given the full list of tools with path arguments `["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead"]`, when checking which tools route through `isPathInWorkspace`, then all tools in the list are either in the checked block or have a documented exemption

## Dependencies and Risks

- **SDK parameter name uncertainty**: The actual parameter names for LS and NotebookRead are not publicly documented. Risk mitigation: add runtime logging (debug-only) to capture actual `toolInput` keys on first invocation, or inspect the SDK binary strings.
- **SDK version changes**: A future `@anthropic-ai/claude-agent-sdk` update could rename parameters or add new file-accessing tools. Risk mitigation: the negative-space test will fail if a new tool is added to `SAFE_TOOLS` without updating the test.

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:270-277` -- SAFE_TOOLS definition
- `apps/web-platform/server/agent-runner.ts:209-222` -- existing file-tool path check
- `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace` implementation
- `apps/web-platform/test/canusertool-sandbox.test.ts` -- existing sandbox tests
- `knowledge-base/project/learnings/2026-03-20-security-fix-attack-surface-enumeration.md` -- learning from PR #884 review

### Related Issues and PRs

- Issue #891 (this issue)
- PR #884 (symlink escape defense-in-depth -- where this gap was found)
- Issue #877 (original symlink escape report)
- Issue #725 (original path traversal via `../`)
- CWE-22: Path Traversal (https://cwe.mitre.org/data/definitions/22.html)
- CWE-59: Improper Link Resolution (https://cwe.mitre.org/data/definitions/59.html)
