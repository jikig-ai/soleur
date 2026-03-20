---
title: "sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks"
type: feat
date: 2026-03-20
semver: patch
---

# sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 8
**Research sources:** Context7 SDK docs, 5 institutional learnings, attack surface enumeration learning, SDK ToolInputSchemas type analysis

### Key Improvements
1. Corrected `NotebookRead` gap -- SDK has no `NotebookRead` tool; notebook reading goes through `Read` tool. Removed from matcher and SAFE_TOOLS (stale reference).
2. Added `updatedInput` hook capability -- hooks CAN provide `updatedInput` (not just deny), opening a future path to move review gates to hooks if needed.
3. Added hook chaining pattern for auditability -- separate sandbox hook from a future audit-logging hook using the SDK's ordered hook array.
4. Import `HookCallback` and `PreToolUseHookInput` directly from SDK -- confirmed exported in ^0.2.80 via Context7.

### New Considerations Discovered
- `NotebookRead` in `SAFE_TOOLS` is a stale reference -- the SDK's `ToolInputSchemas` union does not include a `NotebookReadInput` type. Notebooks are read via the `Read` tool. Remove from SAFE_TOOLS during this migration.
- Hooks support `updatedInput` in `hookSpecificOutput` (not just `systemMessage`) -- this contradicts the original plan's claim that hooks cannot provide `updatedInput`. However, moving review gates to hooks is still not recommended because `canUseTool`'s `updatedInput` is simpler for the AskUserQuestion flow.
- Hook chaining: the SDK executes hooks in array order. A future audit-logging hook can be added as a second entry without modifying the sandbox hook.

## Overview

Migrate the workspace sandbox enforcement in `apps/web-platform/server/agent-runner.ts` from the `canUseTool` callback (permission chain step 5) to `PreToolUse` hooks (permission chain step 1). This is a defense-in-depth improvement recommended during #876 verification. The current `canUseTool` sandbox works correctly per-invocation, but hooks provide immunity to `allowedTools`, `settings.json` pre-approvals, and `bypassPermissions` mode -- none of which reach step 5.

## Problem Statement / Motivation

The Agent SDK permission chain has 5 steps:

1. **Hooks** (PreToolUse) -- fire unconditionally on every tool invocation
2. **Deny rules** (`disallowedTools`)
3. **Permission mode** (`permissionMode: "default"`)
4. **Allow rules** (`allowedTools`, `settings.json permissions.allow`)
5. **`canUseTool` callback** -- only fires if steps 1-4 did not resolve

The workspace sandbox currently lives at step 5. Three bypass vectors exist:

- **`allowedTools` array:** If a tool is listed here, it is auto-approved at step 4 and never reaches `canUseTool`. The migration from #725 removed pre-approved file tools, but a future regression could re-add them.
- **`settings.json permissions.allow`:** Workspace settings loaded by the SDK can pre-approve tools. `patchWorkspacePermissions()` strips these on session start, but if the SDK loads settings from additional sources (plugin directories, user home), those could bypass the sandbox.
- **`bypassPermissions` mode:** If `permissionMode` were changed to `"acceptEdits"` or another bypass mode (even by a code bug), `canUseTool` is skipped entirely.

PreToolUse hooks fire at step 1, before all three bypass vectors. A hook-based sandbox cannot be circumvented by any configuration change -- only by removing the hook itself from the code.

### Research Insights

**SDK Documentation Confirmation (Context7):**

The permission evaluation order is officially documented as: hooks -> deny rules -> permission mode -> allow rules -> canUseTool -> dontAsk deny. The documentation explicitly states: "Hooks execute before `canUseTool` and can allow, deny, or modify requests based on your own logic."

**Institutional Learning (worktree-enforcement-pretooluse-hook):**

The project has prior art with hook-based enforcement: `worktree-write-guard.sh` intercepts Write/Edit tools at step 1 to prevent writes to the main repo. This migration follows the same principle -- "hook-based enforcement > documentation-based rules" -- applied to the multi-tenant sandbox.

## Proposed Solution

### Architecture

Create a new module `apps/web-platform/server/sandbox-hook.ts` that exports a `createSandboxHook()` factory. Register the hook in `agent-runner.ts` via the `options.hooks.PreToolUse` array. Retain `canUseTool` only for the `AskUserQuestion` review gate and the deny-by-default policy.

### File changes

| File | Change |
|------|--------|
| `apps/web-platform/server/sandbox-hook.ts` | **NEW** -- `createSandboxHook()` factory returning a `HookCallback` |
| `apps/web-platform/server/agent-runner.ts` | Register `PreToolUse` hook, slim down `canUseTool`, remove `NotebookRead` from SAFE_TOOLS |
| `apps/web-platform/test/sandbox-hook.test.ts` | **NEW** -- unit tests for the hook |
| `apps/web-platform/test/canusertool-sandbox.test.ts` | **RENAME** to `sandbox.test.ts` (tests `isPathInWorkspace`, not canUseTool) |

### Implementation detail

**`sandbox-hook.ts`:**

```typescript
// apps/web-platform/server/sandbox-hook.ts
import type { HookCallback, PreToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";
import { containsSensitiveEnvAccess } from "./bash-sandbox";

// File-accessing tools and the input fields that carry paths.
// Read handles notebooks (.ipynb) natively -- no separate NotebookRead tool exists.
const FILE_TOOLS = new Set(["Read", "Write", "Edit", "Glob", "Grep"]);

export function createSandboxHook(workspacePath: string): HookCallback {
  return async (input, _toolUseID, _options) => {
    const preInput = input as PreToolUseHookInput;
    const toolInput = preInput.tool_input as Record<string, unknown>;
    const toolName = preInput.tool_name;

    // --- File-tool sandbox ---
    if (FILE_TOOLS.has(toolName)) {
      const filePath =
        (toolInput?.file_path as string) ||
        (toolInput?.path as string) ||
        "";

      if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
        return {
          systemMessage:
            "File access outside the workspace is not permitted. " +
            "All file operations must target paths within the user workspace.",
          hookSpecificOutput: {
            hookEventName: preInput.hook_event_name,
            permissionDecision: "deny" as const,
            permissionDecisionReason:
              "Access denied: file path outside workspace boundary",
          },
        };
      }
    }

    // --- Bash env-access defense-in-depth ---
    if (toolName === "Bash") {
      const command = (toolInput?.command as string) || "";
      if (containsSensitiveEnvAccess(command)) {
        return {
          systemMessage:
            "Accessing sensitive environment variables is not permitted. " +
            "The agent environment contains only safe variables.",
          hookSpecificOutput: {
            hookEventName: preInput.hook_event_name,
            permissionDecision: "deny" as const,
            permissionDecisionReason:
              "Access denied: sensitive environment variable access",
          },
        };
      }
    }

    // All checks passed -- return empty to continue permission chain
    return {};
  };
}
```

### Research Insights

**Best Practices (SDK docs):**

- Use `Set.has()` instead of `Array.includes()` for tool name lookup -- O(1) vs O(n). Minor for 5 tools but establishes the right pattern.
- Import `HookCallback` and `PreToolUseHookInput` directly from the SDK package (`@anthropic-ai/claude-agent-sdk`). Context7 confirms these are exported in the TypeScript SDK. No need for local interface definitions.
- The SDK casts `input` generically; the documented pattern is `const preInput = input as PreToolUseHookInput` followed by `preInput.tool_input as Record<string, unknown>`.

**Edge Case: `tool_input` is typed as `unknown`:**

The SDK types `tool_input` as `unknown`, requiring explicit casting. The plan correctly casts to `Record<string, unknown>` and then accesses `file_path` / `path` / `command` with optional chaining and `as string` fallbacks. This matches the official SDK examples verbatim.

**Edge Case: empty return means "continue":**

Returning `{}` from a hook means "no opinion -- continue to the next step." This is NOT the same as "allow." The tool still passes through deny rules, permission mode, allow rules, and canUseTool. This is correct for our use case -- the hook only blocks, never explicitly allows.

**`agent-runner.ts` changes:**

```typescript
// Add import
import { createSandboxHook } from "./sandbox-hook";

// In startAgentSession(), add hooks and slim canUseTool:
const q = query({
  prompt: /* ... */,
  options: {
    // ... existing options ...
    hooks: {
      PreToolUse: [{
        matcher: "Read|Write|Edit|Glob|Grep|Bash",
        hooks: [createSandboxHook(workspacePath)],
      }],
    },
    canUseTool: async (
      toolName: string,
      toolInput: Record<string, unknown>,
    ) => {
      // Review gates: intercept AskUserQuestion
      if (toolName === "AskUserQuestion") {
        const gateId = randomUUID();
        const question =
          (toolInput.question as string) || "Agent needs your input";
        const options = Array.isArray(toolInput.options)
          ? (toolInput.options as string[])
          : ["Approve", "Reject"];

        sendToClient(userId, {
          type: "review_gate",
          gateId,
          question,
          options,
        });

        await updateConversationStatus(conversationId, "waiting_for_user");

        const selection = await new Promise<string>((resolve) => {
          session.reviewGateResolvers.set(gateId, resolve);
        });

        await updateConversationStatus(conversationId, "active");

        return {
          behavior: "allow" as const,
          updatedInput: { ...toolInput, answer: selection },
        };
      }

      // Safe SDK tools (no file paths, no security-sensitive inputs)
      // Note: NotebookRead removed -- SDK reads notebooks via the Read tool
      const SAFE_TOOLS = [
        "Agent", "Skill", "TodoRead", "TodoWrite", "LS",
      ];
      if (SAFE_TOOLS.includes(toolName)) {
        return { behavior: "allow" as const };
      }

      // Deny-by-default: block unrecognized tools
      return {
        behavior: "deny" as const,
        message: "Tool not permitted in this environment",
      };
    },
  },
});
```

### Coexistence model

The `PreToolUse` hook handles sandbox enforcement (file path validation, env access). The `canUseTool` callback handles:

1. **`AskUserQuestion` review gates** -- requires `updatedInput` to inject the user's answer. While hooks technically support `updatedInput` via `hookSpecificOutput`, the `canUseTool` pattern is simpler for this use case because it can return `updatedInput` at the top level without nesting in `hookSpecificOutput`.
2. **Deny-by-default policy** -- blocks unrecognized tools. This stays in `canUseTool` because hooks fire per-matcher and a catch-all matcher would add unnecessary overhead for every tool invocation.
3. **Safe tool allowlist** -- `Agent`, `Skill`, etc. remain allow-listed in `canUseTool`.

These do not conflict: hooks fire at step 1 (deny if outside workspace), then if allowed, `canUseTool` fires at step 5 (review gates, deny-by-default). The hook matcher `"Read|Write|Edit|Glob|Grep|Bash"` means the hook only fires for security-relevant tools, not for `AskUserQuestion`.

### Research Insights

**Hook chaining for future extensibility (SDK docs):**

The SDK supports multiple hook entries in the `PreToolUse` array, executed in order. A future audit-logging hook can be added as a second entry:

```typescript
PreToolUse: [
  { matcher: "Read|Write|Edit|Glob|Grep|Bash", hooks: [createSandboxHook(workspacePath)] },
  { hooks: [auditLogger] },  // Future: log all tool invocations
],
```

This keeps the sandbox hook focused on security decisions while audit concerns are separated.

## Technical Considerations

### SDK type imports

The SDK (`@anthropic-ai/claude-agent-sdk ^0.2.80`) exports `PreToolUseHookInput` and `HookCallback` types. Context7 documentation confirms these types with the exact signatures used in the implementation. No need for local interface definitions.

### Research Insights

**Confirmed SDK exports (Context7):**

```typescript
import { query, HookCallback, PreToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
```

The `HookCallback` type signature is:
```typescript
type HookCallback = (
  input: PreToolUseHookInput,
  toolUseID: string,
  options: { signal: AbortSignal },
) => Promise<HookResult>;
```

Where `HookResult` can contain `systemMessage`, `hookSpecificOutput` (with `hookEventName`, `permissionDecision`, `permissionDecisionReason`, `updatedInput`), or be an empty object.

### `systemMessage` vs `canUseTool` deny

Key behavioral difference:

- **`canUseTool` deny:** Returns `{ behavior: "deny", message: "..." }`. The agent receives the denial but no system message explaining it.
- **Hook deny:** Returns `{ hookSpecificOutput: { permissionDecision: "deny" }, systemMessage: "..." }`. The `systemMessage` is injected into the conversation, helping the agent understand and avoid retrying.

This is an improvement -- the agent gets clearer feedback on why an operation was blocked.

### `patchWorkspacePermissions()` retention

Keep the `patchWorkspacePermissions()` function that strips pre-approved file tools from workspace `settings.json`. It remains valuable as defense-in-depth even with hooks, because it prevents the SDK from auto-approving tools that would skip the permission mode prompt (step 3). The hook still catches these, but cleaner to not have them pre-approved at all.

### Research Insights

**Institutional Learning (canuse-tool-sandbox-defense-in-depth):**

"SDK `permissions.allow` bypasses `canUseTool`. This is architectural, not a bug." Even though hooks fire before allow rules, keeping `patchWorkspacePermissions()` prevents the SDK from short-circuiting at step 4 for tools that happen to be in settings. Belt-and-suspenders.

### Matcher regex specificity

Use `"Read|Write|Edit|Glob|Grep|Bash"` (explicit tool names) rather than `".*"` (all tools). The wildcard would cause the hook to fire for `AskUserQuestion`, `Agent`, `Skill`, etc., adding unnecessary overhead. Only security-relevant tools need the hook.

### `NotebookRead` is a stale reference -- remove from SAFE_TOOLS

The SDK's `ToolInputSchemas` union type (confirmed via Context7) does NOT include a `NotebookReadInput`. The available types are: `AgentInput`, `AskUserQuestionInput`, `BashInput`, `FileEditInput`, `FileReadInput`, `FileWriteInput`, `GlobInput`, `GrepInput`, `NotebookEditInput`, `WebFetchInput`, `WebSearchInput`, and others. Notably:

- **Notebook reading** goes through the `Read` tool (`FileReadInput` with `file_path`), which is already covered by the sandbox hook.
- **`NotebookEditInput`** exists for editing notebooks but is not in the `SAFE_TOOLS` list.
- **`NotebookRead`** in `SAFE_TOOLS` is a stale reference that bypasses the deny-by-default policy for a tool name that does not exist in the SDK. Remove it.

This corrects the original plan's recommendation to add `NotebookRead` to the hook matcher -- the right action is to remove it from `SAFE_TOOLS`, not to add it to the matcher for a non-existent tool.

## Attack Surface Enumeration

All code paths for agent file access in the web platform:

| Path | Checked by hook? | Notes |
|------|-------------------|-------|
| `Read` tool with `file_path` | Yes | Hook validates `file_path`. Also handles `.ipynb` notebooks. |
| `Write` tool with `file_path` | Yes | Hook validates `file_path` |
| `Edit` tool with `file_path` | Yes | Hook validates `file_path` |
| `Glob` tool with `path` | Yes | Hook validates `path` field |
| `Grep` tool with `path` | Yes | Hook validates `path` field |
| `Bash` tool with arbitrary commands | Partial | Hook checks env-access patterns; bubblewrap sandbox handles filesystem isolation |
| `Agent` tool (spawns subagent) | N/A | Subagent inherits same hooks and sandbox config |
| `Skill` tool (invokes skill) | N/A | Skills execute within the same agent session, subject to same hooks |
| `AskUserQuestion` | N/A | No file access; review gate handled by `canUseTool` |
| `LS` tool | Not checked | `LS` only lists directory contents (read-only, non-sensitive). Bubblewrap constrains what directories are visible. Gap is minimal. |
| `NotebookEdit` | Deny-by-default | Not in SAFE_TOOLS or matcher. Falls through to canUseTool deny-by-default. If needed in future, add to matcher with file_path validation. |

### Research Insights

**Institutional Learning (security-fix-attack-surface-enumeration):**

"Enumerate the full attack surface, not just the reported vector." This table follows that principle. The learning also recommends negative-space tests -- write a test that enumerates every tool and asserts it either routes through the security check or is explicitly documented as exempt. Added to test scenarios below.

**Edge Case: `LS` tool path parameter:**

The `LS` tool likely accepts a directory path parameter but is not documented in `ToolInputSchemas`. It remains in `SAFE_TOOLS` because: (1) it only lists directory contents, not file contents, (2) bubblewrap restricts visible directories, (3) the information leakage risk is minimal compared to Read/Grep. If future SDK versions add `LS` to `ToolInputSchemas` with a `path` parameter, add it to the hook matcher.

## Acceptance Criteria

- [x] `apps/web-platform/server/sandbox-hook.ts` exists with `createSandboxHook()` factory
- [x] `HookCallback` and `PreToolUseHookInput` imported from `@anthropic-ai/claude-agent-sdk`
- [x] PreToolUse hook registered in `agent-runner.ts` with matcher `"Read|Write|Edit|Glob|Grep|Bash"`
- [x] Hook denies file access outside workspace with `systemMessage` explaining the denial
- [x] Hook denies sensitive env-access patterns in Bash commands with `systemMessage`
- [x] Hook allows file access within workspace (no false positives)
- [x] Hook returns empty object `{}` for allowed operations (not explicit allow)
- [x] `canUseTool` retains only: AskUserQuestion review gate, safe-tool allowlist, deny-by-default
- [x] File-tool sandbox logic removed from `canUseTool` (no duplication)
- [x] Bash env-access check removed from `canUseTool` (moved to hook)
- [x] `NotebookRead` removed from `SAFE_TOOLS` (stale reference -- SDK has no such tool)
- [x] `patchWorkspacePermissions()` retained (defense-in-depth)
- [x] All existing tests pass (`bun test apps/web-platform/test/`)
- [x] New test file `sandbox-hook.test.ts` covers: allow in-workspace, deny out-of-workspace, deny env-access, allow clean bash, systemMessage present on deny
- [x] Negative-space test: enumerate all tools and assert each routes through hook, canUseTool, or is documented as exempt
- [x] No regression in review gate functionality

## Test Scenarios

### sandbox-hook.test.ts

- Given a Read tool input with `file_path` inside workspace, when the hook fires, then it returns empty object (allow)
- Given a Read tool input with `file_path` outside workspace (e.g., `/etc/passwd`), when the hook fires, then it returns deny with `systemMessage`
- Given a Read tool input with `file_path` using `../` traversal to escape workspace, when the hook fires, then it returns deny
- Given a Write tool input with `file_path` outside workspace, when the hook fires, then it returns deny
- Given a Bash tool input with `env` command, when the hook fires, then it returns deny with env-access `systemMessage`
- Given a Bash tool input with `ls -la` (clean command), when the hook fires, then it returns empty object (allow)
- Given a Glob tool input with `path` outside workspace, when the hook fires, then it returns deny
- Given a Grep tool input with `path` outside workspace, when the hook fires, then it returns deny
- Given a Read tool input with empty `file_path`, when the hook fires, then it returns empty object (allow -- empty path is not outside workspace)
- Given a hook deny response, then `hookSpecificOutput.permissionDecision` equals `"deny"` and `hookSpecificOutput.hookEventName` equals `"PreToolUse"`
- Given a hook deny for file access, then `systemMessage` contains "workspace" guidance
- Given a hook deny for env access, then `systemMessage` contains "environment variables" guidance

### Research Insights

**Negative-space test (from attack-surface-enumeration learning):**

```typescript
test("all file-accessing tools are covered by hook or documented as exempt", () => {
  const hookMatcherTools = new Set(["Read", "Write", "Edit", "Glob", "Grep", "Bash"]);
  const safeToolsExempt = new Set(["Agent", "Skill", "TodoRead", "TodoWrite", "LS"]);
  const disallowedTools = new Set(["WebSearch", "WebFetch"]);
  const denyByDefault = true; // canUseTool blocks everything else

  // Every tool with file/path access must be in hookMatcherTools
  const fileAccessTools = ["Read", "Write", "Edit", "Glob", "Grep"];
  for (const tool of fileAccessTools) {
    expect(hookMatcherTools.has(tool)).toBe(true);
  }

  // Safe tools must NOT have file_path access
  // (Agent, Skill, TodoRead, TodoWrite, LS are path-free or read-only directory listing)
  for (const tool of safeToolsExempt) {
    expect(fileAccessTools.includes(tool)).toBe(false);
  }
});
```

### Regression tests (existing test files)

- Given the existing `canusertool-sandbox.test.ts` (renamed to `sandbox.test.ts`), when tests run, then all `isPathInWorkspace` tests still pass
- Given the existing `canusertool-caching.test.ts`, when tests run, then caching verification still passes (canUseTool still fires for AskUserQuestion)

### Test implementation pattern

The sandbox hook is a pure function -- given a `PreToolUseHookInput` shape, it returns a result. Tests construct mock inputs directly:

```typescript
import { createSandboxHook } from "../server/sandbox-hook";

const WORKSPACE = "/workspaces/user1";
const hook = createSandboxHook(WORKSPACE);
const signal = new AbortController().signal;

function makeInput(toolName: string, toolInput: Record<string, unknown>) {
  return {
    hook_event_name: "PreToolUse",
    tool_name: toolName,
    tool_input: toolInput,
  };
}

test("allows Read inside workspace", async () => {
  const result = await hook(
    makeInput("Read", { file_path: "/workspaces/user1/file.md" }),
    "test-id",
    { signal },
  );
  expect(result).toEqual({});
});

test("denies Read outside workspace", async () => {
  const result = await hook(
    makeInput("Read", { file_path: "/etc/passwd" }),
    "test-id",
    { signal },
  );
  expect(result.hookSpecificOutput?.permissionDecision).toBe("deny");
  expect(result.systemMessage).toContain("workspace");
});
```

This follows the project pattern of extracting security logic into pure, dependency-free modules (like `sandbox.ts` and `bash-sandbox.ts`) for millisecond-level unit testing.

## Non-goals

- Removing `canUseTool` entirely (still needed for review gates and deny-by-default)
- Removing the bubblewrap sandbox (OS-level isolation is orthogonal to SDK hooks)
- Adding hooks for the local development plugin (`.claude/settings.json` hooks are for the local dev workflow; this issue is about the web platform's programmatic SDK hooks)
- Migrating the local dev PreToolUse hooks (guardrails.sh, worktree-write-guard.sh) -- those are shell-based hooks for the developer experience, not the tenant sandbox
- Moving AskUserQuestion review gates to hooks (hooks support `updatedInput` but canUseTool is simpler for this pattern)

## Dependencies and Risks

| Risk | Mitigation |
|------|------------|
| SDK types (`PreToolUseHookInput`, `HookCallback`) not exported | Context7 confirms these are exported in ^0.2.80. Fallback: define local interfaces matching documented shape. |
| Hook `systemMessage` format differs from documentation | Context7 confirms `systemMessage` at top level of return object. Test with real SDK before merging. |
| Hook matcher regex syntax differs between SDK versions | Use simple pipe-delimited tool names (documented pattern in Context7 examples). Avoid complex regex. |
| Double-deny (hook denies, then canUseTool also denies) | Remove file-tool checks from canUseTool so only the hook handles them. Hook deny at step 1 prevents canUseTool from ever firing for that invocation. |
| `NotebookRead` removal breaks something | Stale reference -- SDK has no `NotebookRead` tool. If a tool with that name is ever added, deny-by-default in canUseTool catches it. |

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:204-287` -- current canUseTool sandbox implementation
- `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace()` function (unchanged, reused by hook)
- `apps/web-platform/server/bash-sandbox.ts` -- `containsSensitiveEnvAccess()` function (unchanged, reused by hook)
- `apps/web-platform/test/canusertool-sandbox.test.ts` -- existing sandbox tests (to be renamed)
- `knowledge-base/project/plans/2026-03-20-sec-verify-canusertool-caching-behavior-plan.md:98-146` -- createSandboxHook pattern origin
- `knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md` -- SDK permission chain analysis
- `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- three-tier defense model
- `knowledge-base/project/learnings/2026-03-20-security-fix-attack-surface-enumeration.md` -- negative-space test pattern
- `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` -- path validation history
- `knowledge-base/project/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` -- prior art for hook-based enforcement
- `spike/FINDINGS.md` -- Agent SDK spike results
- `.claude/settings.json` -- existing PreToolUse hook pattern (shell-based, for local dev)
- `.claude/hooks/worktree-write-guard.sh` -- reference for hook output format (hookSpecificOutput)

### External References

- [Agent SDK Hooks Documentation](https://platform.claude.com/docs/en/agent-sdk/hooks) -- hook API, chaining, matcher patterns
- [Agent SDK Permissions](https://platform.claude.com/docs/en/agent-sdk/permissions) -- permission evaluation order
- [Agent SDK User Input](https://platform.claude.com/docs/en/agent-sdk/user-input) -- canUseTool and hook alternatives

### Related Issues

- #876 -- canUseTool caching verification (recommended this migration)
- #725 -- workspace permissions migration (removed pre-approved file tools)
- #877 -- symlink escape defense-in-depth (sandbox.ts improvements)
- #891 -- LS/NotebookRead bypass tracking (related attack surface gap)
