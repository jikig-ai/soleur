---
title: "fix(sec): audit LS and NotebookRead tools for path validation bypass"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research sources:** SDK TypeScript API reference (ToolInputSchemas), CWE-22/CWE-59 MITRE documentation, OWASP Path Traversal guidance, 4 project security learnings, PR #884/#725 analysis

### Key Improvements
1. Resolved parameter name uncertainty -- SDK ToolInputSchemas confirm LS and NotebookRead are NOT in the exported type union, meaning they are internal/undocumented tools whose schemas must be discovered at runtime
2. Added NotebookEdit path validation as a third tool to address (it has `notebook_path` and is also missing from the checked-tools block)
3. Added concrete test implementation patterns with extractable `canUseTool` logic for unit testing without SDK dependency
4. Added OWASP-aligned mitigation strategy: canonicalize-then-allowlist pattern

### New Considerations Discovered
- The SDK exports `ToolInputSchemas` union type with 24 tool schemas -- `LS` and `NotebookRead` are absent, confirming they are internal tools without exported type definitions
- `NotebookEdit` (has `notebook_path: string`) is also NOT in the file-tool check block and NOT in SAFE_TOOLS -- it would be denied by the catch-all deny-by-default, but should be explicitly checked for defense-in-depth
- `TodoRead` is not in the SDK's `ToolInputSchemas` either (only `TodoWriteInput` exists), confirming it has no path parameters
- The `canUseTool` callback receives `toolInput: Record<string, unknown>` -- type information is lost at the boundary, so parameter name checking is the only viable approach

---

# fix(sec): audit LS and NotebookRead tools for path validation bypass

## Overview

`LS` and `NotebookRead` are in the `SAFE_TOOLS` allowlist in `apps/web-platform/server/agent-runner.ts:270-277`. They bypass `canUseTool`'s `isPathInWorkspace` check entirely. If either tool accepts a user-controlled path argument, an agent could use them to list directories or read notebooks outside the workspace boundary -- including through symlinks.

This gap was identified during the architecture review of PR #884 (symlink escape defense-in-depth) and filed as issue #891.

## Problem Statement / Motivation

The `canUseTool` callback in `agent-runner.ts` enforces workspace containment for five tools (`Read`, `Write`, `Edit`, `Glob`, `Grep`) by extracting `file_path` or `path` from `toolInput` and checking `isPathInWorkspace()`. Six other tools are in `SAFE_TOOLS` and auto-allowed without any path check:

```typescript
const SAFE_TOOLS = [
  "Agent",    // No path input -- confirmed: AgentInput has description/prompt/subagent_type
  "Skill",    // No path input -- not in SDK ToolInputSchemas (plugin-level tool)
  "TodoRead", // No path input -- not in SDK ToolInputSchemas (no exported type)
  "TodoWrite",// No path input -- confirmed: TodoWriteInput has todos[] array only
  "LS",       // <-- NOT in SDK ToolInputSchemas -- internal tool, parameter names unknown
  "NotebookRead", // <-- NOT in SDK ToolInputSchemas -- internal tool, parameter names unknown
];
```

### Research Insights: SDK Tool Schema Analysis

The Claude Agent SDK (v0.2.80) exports a `ToolInputSchemas` union type with 24 tool input types. Neither `LS` nor `NotebookRead` appears in this union:

```typescript
// From @anthropic-ai/claude-agent-sdk -- complete ToolInputSchemas union:
type ToolInputSchemas =
  | AgentInput | AskUserQuestionInput | BashInput | TaskOutputInput
  | ConfigInput | EnterWorktreeInput | ExitPlanModeInput | FileEditInput
  | FileReadInput | FileWriteInput | GlobInput | GrepInput
  | ListMcpResourcesInput | McpInput | NotebookEditInput | ReadMcpResourceInput
  | SubscribeMcpResourceInput | SubscribePollingInput | TaskStopInput
  | TodoWriteInput | UnsubscribeMcpResourceInput | UnsubscribePollingInput
  | WebFetchInput | WebSearchInput;
// Notable absences: NO LSInput, NO NotebookReadInput, NO TodoReadInput, NO SkillInput
```

This confirms:
- **LS** and **NotebookRead** are internal Claude Code tools without exported schema types
- Their parameter structures must be discovered empirically (runtime logging or binary inspection)
- The `canUseTool` callback receives `toolInput: Record<string, unknown>` -- all type information is erased at this boundary

**Known parameter patterns from related tools:**
- `FileReadInput` (Read tool): `{ file_path: string, offset?: number, limit?: number }`
- `GlobInput` (Glob tool): `{ pattern: string, path?: string }`
- `NotebookEditInput`: `{ notebook_path: string, cell_id?: string, new_source: string }`

**Probable LS parameters:** `{ path?: string }` (directory to list, optional, defaults to cwd)
**Probable NotebookRead parameters:** `{ file_path: string }` (consistent with Read tool) or `{ notebook_path: string }` (consistent with NotebookEdit)

### Additional gap: NotebookEdit

`NotebookEdit` has a confirmed `notebook_path: string` parameter and is NOT in the file-tool check block. It is also NOT in SAFE_TOOLS, so it hits the deny-by-default catch-all at the bottom of `canUseTool`. This is functionally safe (denied), but the denial message is generic ("Tool not permitted in this environment") rather than the specific path-based denial. For defense-in-depth, NotebookEdit should be added to the file-tool check block alongside LS and NotebookRead.

## Proposed Solution

### Option A: Move LS, NotebookRead, and NotebookEdit into the checked tools block (recommended)

Add all three tools to the existing file-tool check alongside `Read`, `Write`, `Edit`, `Glob`, and `Grep`:

```typescript
// apps/web-platform/server/agent-runner.ts
//
// File-accessing tools: validate path is inside workspace.
// Parameter names vary by tool -- check all known variants.
// See #891 for the audit that added LS/NotebookRead/NotebookEdit.
if (
  ["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead", "NotebookEdit"].includes(toolName)
) {
  const filePath =
    (toolInput.file_path as string) ||
    (toolInput.path as string) ||
    (toolInput.notebook_path as string) ||
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
// Agent/Skill: orchestration tools with no path args (Agent: description/prompt/subagent_type;
//   Skill: plugin-level tool, no exported schema).
// TodoRead/TodoWrite: in-memory task list (TodoWrite: todos[] array only).
// NOTE: LS and NotebookRead removed (#891) -- they accept path inputs
// and must go through isPathInWorkspace. NotebookEdit also added to
// the checked block for defense-in-depth.
const SAFE_TOOLS = ["Agent", "Skill", "TodoRead", "TodoWrite"];
```

### Research Insights: Defense-in-Depth Pattern

**OWASP Path Traversal prevention** recommends a three-layer approach that matches the existing architecture:

1. **Canonicalize** (resolveRealPath/resolveParentRealPath in sandbox.ts) -- resolve all symlinks and `../` segments to canonical form
2. **Allowlist** (isPathInWorkspace) -- check canonical path against workspace boundary
3. **OS sandbox** (bubblewrap) -- independent filesystem namespace restriction

The current fix adds LS/NotebookRead to layer 2. Layer 1 (canonicalization) and layer 3 (bubblewrap) already cover these tools. The gap is specifically in the application-level allowlist check.

**CWE-22 MITRE guidance** specifically recommends: "Use an 'accept known good' input validation strategy. If you cannot, use a canonicalization function to resolve all directory traversal." The `isPathInWorkspace` function already implements both -- the fix is ensuring all file-accessing tools route through it.

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

**Learning applied:** From `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- "SDK `permissions.allow` bypasses `canUseTool`. An overly permissive allowlist silently disables your entire `canUseTool` security layer for those tools." The same principle applies to SAFE_TOOLS: each tool in the allowlist is an explicit bypass of the security check.

## Technical Considerations

### Attack Surface Enumeration

All code paths for file access through `canUseTool`:

| Tool | Path Parameter | Currently Checked | Status |
|------|---------------|-------------------|--------|
| Read | `file_path` (confirmed: FileReadInput) | Yes | Safe |
| Write | `file_path` (confirmed: FileWriteInput) | Yes | Safe |
| Edit | `file_path` (confirmed: FileEditInput) | Yes | Safe |
| Glob | `path` (confirmed: GlobInput) | Yes | Safe |
| Grep | `path` (confirmed: GrepInput) | Yes | Safe |
| **LS** | `path` (probable -- no exported type) | **No -- in SAFE_TOOLS** | **Gap** |
| **NotebookRead** | `file_path` (probable -- no exported type) | **No -- in SAFE_TOOLS** | **Gap** |
| **NotebookEdit** | `notebook_path` (confirmed: NotebookEditInput) | **No -- hits deny-by-default** | **Functional but not explicit** |
| Bash | `command` (confirmed: BashInput) | Separate check (containsSensitiveEnvAccess) | N/A (OS sandbox) |
| Agent | No path args (confirmed: AgentInput) | N/A | Safe |
| Skill | No path args (not in ToolInputSchemas) | N/A | Safe |
| TodoRead | No path args (not in ToolInputSchemas) | N/A | Safe |
| TodoWrite | No path args (confirmed: TodoWriteInput) | N/A | Safe |

### Research Insights: Complete Tool Inventory

The SDK's ToolInputSchemas union lists 24 tool types. Cross-referencing against the `canUseTool` handler:

| SDK Type | Tool Name | Has Path Arg | In canUseTool Check | In SAFE_TOOLS | Status |
|----------|-----------|-------------|--------------------|----|--------|
| FileReadInput | Read | `file_path` | Yes | No | Covered |
| FileWriteInput | Write | `file_path` | Yes | No | Covered |
| FileEditInput | Edit | `file_path` | Yes | No | Covered |
| GlobInput | Glob | `path` | Yes | No | Covered |
| GrepInput | Grep | `path` | Yes | No | Covered |
| NotebookEditInput | NotebookEdit | `notebook_path` | No | No | Hits deny-by-default |
| AgentInput | Agent | None | No | Yes | Safe |
| TodoWriteInput | TodoWrite | None | No | Yes | Safe |
| BashInput | Bash | `command` | Yes (env check) | No | Covered |
| AskUserQuestionInput | AskUserQuestion | None | Yes (review gate) | No | Covered |
| WebFetchInput | WebFetch | `url` (not fs) | No | No | disallowedTools |
| WebSearchInput | WebSearch | `query` (not fs) | No | No | disallowedTools |
| N/A (internal) | LS | Unknown | No | Yes | **GAP** |
| N/A (internal) | NotebookRead | Unknown | No | Yes | **GAP** |
| N/A (internal) | Skill | None | No | Yes | Safe |
| N/A (internal) | TodoRead | None | No | Yes | Safe |

### Path parameter discovery

The `canUseTool` callback receives `toolInput: Record<string, unknown>`. The path parameter name varies by tool:
- `file_path`: Read, Write, Edit, NotebookRead (probable), NotebookEdit (confirmed)
- `path`: Glob, Grep, LS (probable)
- `notebook_path`: NotebookEdit (confirmed)

The fix must check all three parameter names: `file_path`, `path`, and `notebook_path`.

### Research Insights: Runtime Parameter Discovery

Since LS and NotebookRead have no exported type definitions, use this approach to confirm parameter names:

```typescript
// Temporary diagnostic: log tool input keys for unknown tools
// Add inside canUseTool, before the SAFE_TOOLS check:
if (["LS", "NotebookRead"].includes(toolName)) {
  console.log(`[sec-audit] ${toolName} toolInput keys:`, Object.keys(toolInput));
  console.log(`[sec-audit] ${toolName} toolInput:`, JSON.stringify(toolInput));
}
```

Trigger with a test prompt: "List the files in this directory" (for LS) and "Read notebook.ipynb" (for NotebookRead). Remove diagnostic logging before shipping.

### SDK version coupling

The tool schemas are compiled into the Claude Code binary (`@anthropic-ai/claude-agent-sdk`). Parameter names could change between SDK versions. The current approach (checking multiple parameter names with `||` fallback) is resilient to additions but not to renames. This is acceptable -- a rename would break the existing Read/Write/Edit/Glob/Grep checks too, forcing an update.

### Research Insights: SDK Version Risk Mitigation

The SDK changelog (v0.2.80) shows tool schema changes are rare -- no tool renames in the visible changelog history. The `ToolInputSchemas` export provides a compile-time safety net for typed tools. For untyped tools (LS, NotebookRead), add a runtime assertion:

```typescript
// Fail-safe: if a "LS" or "NotebookRead" tool call has no recognized path parameter,
// log a warning but still allow (the deny-by-default fallback would block it anyway
// if it's not in SAFE_TOOLS, but this catches silent schema changes).
if (["LS", "NotebookRead"].includes(toolName) && !filePath) {
  console.warn(`[sec] ${toolName} invoked without recognized path parameter. ` +
    `Keys: ${Object.keys(toolInput).join(", ")}. ` +
    `SDK version may have changed parameter names. See #891.`);
}
```

### Bubblewrap sandbox interaction

The bubblewrap sandbox (layer 1) independently restricts filesystem access via Linux namespaces configured through the `sandbox.filesystem` option:
```typescript
filesystem: {
  allowWrite: [workspacePath],
  denyRead: ["/workspaces"],
}
```
The `isPathInWorkspace` check is layer 2 (application-level). Even if layer 2 is bypassed, layer 1 should block access. But defense-in-depth requires both layers to be correct independently.

### Research Insights: Layer Independence

From learning `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`: "Defense-in-depth failures are multiplicative, not additive." The bubblewrap sandbox has `denyRead: ["/workspaces"]` which blocks cross-tenant reads, but does NOT block reads to system paths like `/etc/passwd` (only `allowWrite` restricts writes). The `isPathInWorkspace` check is the only layer that blocks reads to arbitrary non-workspace, non-denyRead paths via LS and NotebookRead.

### Performance impact

`isPathInWorkspace` calls `fs.realpathSync()` which is a synchronous filesystem operation. For LS and NotebookRead, this adds ~1ms per invocation. Since these tools are I/O-bound (listing directories, reading notebooks), the overhead is negligible.

## Non-goals

- Auditing Bash tool path validation (Bash has OS-level sandbox isolation, separate from `isPathInWorkspace`)
- Modifying the SDK to change LS/NotebookRead tool schemas
- Adding path validation for MCP tools (separate security surface with its own controls)
- Verifying the bubblewrap sandbox configuration (layer 1 audit is out of scope for this issue)
- Exporting or publishing tool schema types (SDK-level concern)

## Acceptance Criteria

- [x] Determine the actual parameter names for LS and NotebookRead by inspecting `toolInput` at runtime or SDK source
- [x] Move LS and NotebookRead out of `SAFE_TOOLS` into the `isPathInWorkspace` check block in `agent-runner.ts`
- [x] Add NotebookEdit to the `isPathInWorkspace` check block (defense-in-depth -- it currently hits deny-by-default)
- [x] Check `file_path`, `path`, and `notebook_path` parameter names in the path extraction logic
- [x] Add code comment documenting why remaining SAFE_TOOLS members are safe (no path inputs)
- [x] Add unit tests for LS and NotebookRead path validation in `tool-path-checker.test.ts` (extracted for testability)
- [x] Add a negative-space test that enumerates all tools with path args and asserts they route through `isPathInWorkspace`
- [x] Add a runtime warning for unrecognized parameter names on LS/NotebookRead (SDK version safety net)
- [x] All existing sandbox tests continue to pass

## Test Scenarios

### Acceptance Tests

- Given an LS tool call with `path: "/etc"`, when `canUseTool` is invoked, then it returns `behavior: "deny"` with "outside workspace" message
- Given an LS tool call with `path: "<workspacePath>/subdir"`, when `canUseTool` is invoked, then it returns `behavior: "allow"`
- Given a NotebookRead tool call with `file_path: "/etc/shadow"`, when `canUseTool` is invoked, then it returns `behavior: "deny"`
- Given a NotebookRead tool call with `file_path: "<workspacePath>/notebook.ipynb"`, when `canUseTool` is invoked, then it returns `behavior: "allow"`
- Given an LS tool call with `path: "<workspacePath>/../other-user/dir"`, when `canUseTool` is invoked, then it returns `behavior: "deny"` (path traversal)
- Given a NotebookEdit tool call with `notebook_path: "/tmp/evil.ipynb"`, when `canUseTool` is invoked, then it returns `behavior: "deny"` (outside workspace)
- Given a NotebookEdit tool call with `notebook_path: "<workspacePath>/notebook.ipynb"`, when `canUseTool` is invoked, then it returns `behavior: "allow"`

### Research Insights: Testable Implementation Pattern

Extract the `canUseTool` path-checking logic into a pure function for unit testing without SDK dependencies (following the sandbox.ts extraction pattern from the CWE-22 fix):

```typescript
// apps/web-platform/server/tool-path-checker.ts
export function extractToolPath(toolName: string, toolInput: Record<string, unknown>): string {
  return (
    (toolInput.file_path as string) ||
    (toolInput.path as string) ||
    (toolInput.notebook_path as string) ||
    ""
  );
}

export const FILE_TOOLS = ["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead", "NotebookEdit"];

export function isFileToolOutsideWorkspace(
  toolName: string,
  toolInput: Record<string, unknown>,
  workspacePath: string,
): boolean {
  if (!FILE_TOOLS.includes(toolName)) return false;
  const filePath = extractToolPath(toolName, toolInput);
  return filePath !== "" && !isPathInWorkspace(filePath, workspacePath);
}
```

This is testable without mocking the Anthropic SDK, Supabase, or WebSocket dependencies -- following the same pattern used for `sandbox.ts` and `error-sanitizer.ts`.

### Regression Tests

- Given a Read tool call with `file_path` outside workspace, when `canUseTool` is invoked, then it still returns `behavior: "deny"` (existing behavior preserved)
- Given a symlink inside workspace pointing to `/etc`, when LS is called on the symlink path, then `isPathInWorkspace` resolves the symlink and denies access
- Given a tool NOT in FILE_TOOLS (e.g., "Agent"), when `canUseTool` is invoked, then it is NOT subject to path checking

### Negative-Space Test

- Given the full list of tools with path arguments `["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead", "NotebookEdit"]`, when checking which tools route through `isPathInWorkspace`, then all tools in the list are either in the checked block or have a documented exemption
- Given SAFE_TOOLS `["Agent", "Skill", "TodoRead", "TodoWrite"]`, when checking each for path parameters against SDK ToolInputSchemas, then none have `file_path`, `path`, or `notebook_path` fields

### Edge Cases

- Given an LS tool call with NO path parameter (empty toolInput), when `canUseTool` is invoked, then it returns `behavior: "allow"` (tool defaults to cwd which is workspace)
- Given a NotebookRead tool call with an empty string path, when `canUseTool` is invoked, then it returns `behavior: "allow"` (empty path guard: `if (filePath && ...)` short-circuits)

## Dependencies and Risks

- **SDK parameter name uncertainty**: The actual parameter names for LS and NotebookRead are not publicly documented and not in the SDK's exported TypeScript types. Risk mitigation: add runtime logging to capture actual `toolInput` keys on first invocation. The fix defensively checks all three known parameter names (`file_path`, `path`, `notebook_path`).
- **SDK version changes**: A future `@anthropic-ai/claude-agent-sdk` update could rename parameters or add new file-accessing tools. Risk mitigation: the negative-space test will fail if a new tool is added to `SAFE_TOOLS` without updating the test. The runtime warning logs unexpected parameter patterns.
- **NotebookEdit behavior change**: Moving NotebookEdit from deny-by-default to explicit path checking changes its behavior -- previously any NotebookEdit was denied; now NotebookEdit within the workspace would be allowed. Verify this is the intended behavior before implementation.

### Research Insights: Learning Applications

From `2026-03-20-security-fix-attack-surface-enumeration.md`:
> "Any time you make a security boundary stricter, ask: 'What bypasses this boundary?' Allowlists (SAFE_TOOLS, permissions.allow, env var allowlists) are explicit bypass mechanisms."

Applied: This audit is the direct result of that learning. The fix removes the bypass.

From `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`:
> "Extracting security-critical logic into pure, dependency-free modules makes it unit-testable without mocking heavy dependencies."

Applied: The proposed `tool-path-checker.ts` extraction follows this pattern.

From `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`:
> "Regex command filtering is defense-in-depth, not a security boundary."

Applied: The path parameter name checking is similarly defense-in-depth -- the bubblewrap sandbox is the true security boundary. But application-level checks catch attacks before they reach the OS sandbox, reducing attack surface exposure.

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:270-277` -- SAFE_TOOLS definition
- `apps/web-platform/server/agent-runner.ts:209-222` -- existing file-tool path check
- `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace` implementation
- `apps/web-platform/test/canusertool-sandbox.test.ts` -- existing sandbox tests (21 tests)
- `knowledge-base/project/learnings/2026-03-20-security-fix-attack-surface-enumeration.md` -- learning from PR #884 review
- `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` -- CWE-22 fix learning
- `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- defense-in-depth learning
- `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md` -- CWE-59 fix learning

### External References

- Claude Agent SDK TypeScript v0.2.80 -- ToolInputSchemas type (https://platform.claude.com/docs/en/agent-sdk/typescript#tool-input-types)
- CWE-22: Improper Limitation of a Pathname to a Restricted Directory (https://cwe.mitre.org/data/definitions/22.html)
- CWE-59: Improper Link Resolution Before File Access (https://cwe.mitre.org/data/definitions/59.html)
- OWASP Path Traversal (https://owasp.org/www-community/attacks/Path_Traversal)

### Related Issues and PRs

- Issue #891 (this issue)
- PR #884 (symlink escape defense-in-depth -- where this gap was found)
- Issue #877 (original symlink escape report)
- Issue #725 (original path traversal via `../`)
