---
title: "sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks"
type: feat
date: 2026-03-20
semver: patch
---

# sec: migrate sandbox enforcement from canUseTool to PreToolUse hooks

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

## Proposed Solution

### Architecture

Create a new module `apps/web-platform/server/sandbox-hook.ts` that exports a `createSandboxHook()` factory. Register the hook in `agent-runner.ts` via the `options.hooks.PreToolUse` array. Retain `canUseTool` only for the `AskUserQuestion` review gate and the Bash env-access check (which requires `canUseTool`'s `behavior: "deny"` response type for proper UX).

### File changes

| File | Change |
|------|--------|
| `apps/web-platform/server/sandbox-hook.ts` | **NEW** -- `createSandboxHook()` factory returning a `HookCallback` |
| `apps/web-platform/server/agent-runner.ts` | Register `PreToolUse` hook, slim down `canUseTool` |
| `apps/web-platform/test/sandbox-hook.test.ts` | **NEW** -- unit tests for the hook |
| `apps/web-platform/test/canusertool-sandbox.test.ts` | **RENAME** to `sandbox.test.ts` (tests `isPathInWorkspace`, not canUseTool) |

### Implementation detail

**`sandbox-hook.ts`:**

```typescript
// apps/web-platform/server/sandbox-hook.ts
import type { PreToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";
import { containsSensitiveEnvAccess } from "./bash-sandbox";

interface HookResult {
  systemMessage?: string;
  hookSpecificOutput?: {
    hookEventName: string;
    permissionDecision: "deny" | "allow";
    permissionDecisionReason?: string;
  };
}

type HookCallback = (
  input: PreToolUseHookInput,
  toolUseID: string,
  options: { signal: AbortSignal },
) => Promise<HookResult>;

export function createSandboxHook(workspacePath: string): HookCallback {
  return async (input, _toolUseID, _options) => {
    const toolInput = input.tool_input as Record<string, unknown>;
    const toolName = input.tool_name;

    // --- File-tool sandbox ---
    if (["Read", "Write", "Edit", "Glob", "Grep"].includes(toolName)) {
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
            hookEventName: input.hook_event_name,
            permissionDecision: "deny",
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
            hookEventName: input.hook_event_name,
            permissionDecision: "deny",
            permissionDecisionReason:
              "Access denied: sensitive environment variable access",
          },
        };
      }
    }

    // All checks passed -- allow
    return {};
  };
}
```

**`agent-runner.ts` changes:**

```typescript
// Add import
import { createSandboxHook } from "./sandbox-hook";

// In startAgentSession(), replace the canUseTool block:
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
        // ... existing review gate logic (unchanged) ...
      }

      // Safe SDK tools
      const SAFE_TOOLS = [
        "Agent", "Skill", "TodoRead", "TodoWrite",
        "LS", "NotebookRead",
      ];
      if (SAFE_TOOLS.includes(toolName)) {
        return { behavior: "allow" as const };
      }

      // Deny-by-default for unrecognized tools
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

1. **`AskUserQuestion` review gates** -- requires `updatedInput` to inject the user's answer, which hooks cannot provide (hooks return `systemMessage`, not `updatedInput`).
2. **Deny-by-default policy** -- blocks unrecognized tools. This stays in `canUseTool` because hooks fire per-matcher and would need a "catch-all" matcher.
3. **Safe tool allowlist** -- `Agent`, `Skill`, etc. remain allow-listed in `canUseTool`.

These do not conflict: hooks fire at step 1 (deny if outside workspace), then if allowed, `canUseTool` fires at step 5 (review gates, deny-by-default). The hook matcher `"Read|Write|Edit|Glob|Grep|Bash"` means the hook only fires for security-relevant tools, not for `AskUserQuestion`.

## Technical Considerations

### SDK type imports

The SDK (`@anthropic-ai/claude-agent-sdk ^0.2.80`) exports `PreToolUseHookInput` and `HookCallback` types. If these types are not exported in the installed version, define local interfaces matching the documented shape (the hook receives JSON with `tool_name`, `tool_input`, `hook_event_name` fields).

### `systemMessage` vs `canUseTool` deny

Key behavioral difference:

- **`canUseTool` deny:** Returns `{ behavior: "deny", message: "..." }`. The agent receives the denial but no system message explaining it.
- **Hook deny:** Returns `{ hookSpecificOutput: { permissionDecision: "deny" }, systemMessage: "..." }`. The `systemMessage` is injected into the conversation, helping the agent understand and avoid retrying.

This is an improvement -- the agent gets clearer feedback on why an operation was blocked.

### `patchWorkspacePermissions()` retention

Keep the `patchWorkspacePermissions()` function that strips pre-approved file tools from workspace `settings.json`. It remains valuable as defense-in-depth even with hooks, because it prevents the SDK from auto-approving tools that would skip the permission mode prompt (step 3). The hook still catches these, but cleaner to not have them pre-approved at all.

### Matcher regex specificity

Use `"Read|Write|Edit|Glob|Grep|Bash"` (explicit tool names) rather than `".*"` (all tools). The wildcard would cause the hook to fire for `AskUserQuestion`, `Agent`, `Skill`, etc., adding unnecessary overhead. Only security-relevant tools need the hook.

## Attack Surface Enumeration

All code paths for agent file access in the web platform:

| Path | Checked by hook? | Notes |
|------|-------------------|-------|
| `Read` tool with `file_path` | Yes | Hook validates `file_path` |
| `Write` tool with `file_path` | Yes | Hook validates `file_path` |
| `Edit` tool with `file_path` | Yes | Hook validates `file_path` |
| `Glob` tool with `path` | Yes | Hook validates `path` field |
| `Grep` tool with `path` | Yes | Hook validates `path` field |
| `Bash` tool with arbitrary commands | Partial | Hook checks env-access patterns; bubblewrap sandbox handles filesystem isolation |
| `Agent` tool (spawns subagent) | N/A | Subagent inherits same hooks and sandbox config |
| `Skill` tool (invokes skill) | N/A | Skills execute within the same agent session, subject to same hooks |
| `AskUserQuestion` | N/A | No file access; review gate handled by `canUseTool` |
| `LS` tool | Not checked | `LS` only lists directory contents (read-only, non-sensitive). Bubblewrap constrains what directories are visible. Gap is minimal. |
| `NotebookRead` | Not checked | Similar to `Read` but for notebooks. **Should be added to matcher.** |

**Gap identified:** `NotebookRead` should be included in the hook matcher since it reads files. Update matcher to `"Read|Write|Edit|Glob|Grep|Bash|NotebookRead"`. Verify `NotebookRead` uses `file_path` in its input schema.

## Acceptance Criteria

- [ ] `apps/web-platform/server/sandbox-hook.ts` exists with `createSandboxHook()` factory
- [ ] PreToolUse hook registered in `agent-runner.ts` with matcher `"Read|Write|Edit|Glob|Grep|Bash|NotebookRead"`
- [ ] Hook denies file access outside workspace with `systemMessage` explaining the denial
- [ ] Hook denies sensitive env-access patterns in Bash commands
- [ ] Hook allows file access within workspace (no false positives)
- [ ] `canUseTool` retains only: AskUserQuestion review gate, safe-tool allowlist, deny-by-default
- [ ] File-tool sandbox logic removed from `canUseTool` (no duplication)
- [ ] Bash env-access check removed from `canUseTool` (moved to hook)
- [ ] `patchWorkspacePermissions()` retained (defense-in-depth)
- [ ] All existing tests pass (`bun test apps/web-platform/test/`)
- [ ] New test file `sandbox-hook.test.ts` covers: allow in-workspace, deny out-of-workspace, deny env-access, allow clean bash, systemMessage present on deny
- [ ] No regression in review gate functionality

## Test Scenarios

### sandbox-hook.test.ts

- Given a Read tool input with `file_path` inside workspace, when the hook fires, then it returns empty object (allow)
- Given a Read tool input with `file_path` outside workspace (e.g., `/etc/passwd`), when the hook fires, then it returns deny with `systemMessage`
- Given a Read tool input with `file_path` using `../` traversal to escape workspace, when the hook fires, then it returns deny
- Given a Write tool input with `file_path` outside workspace, when the hook fires, then it returns deny
- Given a Bash tool input with `env` command, when the hook fires, then it returns deny with env-access message
- Given a Bash tool input with `ls -la` (clean command), when the hook fires, then it returns empty object (allow)
- Given a Glob tool input with `path` outside workspace, when the hook fires, then it returns deny
- Given a Read tool input with empty `file_path`, when the hook fires, then it returns empty object (allow -- empty path is not outside workspace)
- Given a tool not in the matcher (e.g., `AskUserQuestion`), when the agent session runs, then the hook does not fire for that tool

### Regression tests (existing test files)

- Given the existing `canusertool-sandbox.test.ts` (renamed to `sandbox.test.ts`), when tests run, then all `isPathInWorkspace` tests still pass
- Given the existing `canusertool-caching.test.ts`, when tests run, then caching verification still passes (canUseTool still fires for AskUserQuestion)

## Non-goals

- Removing `canUseTool` entirely (still needed for review gates and deny-by-default)
- Removing the bubblewrap sandbox (OS-level isolation is orthogonal to SDK hooks)
- Adding hooks for the local development plugin (`.claude/settings.json` hooks are for the local dev workflow; this issue is about the web platform's programmatic SDK hooks)
- Migrating the local dev PreToolUse hooks (guardrails.sh, worktree-write-guard.sh) -- those are shell-based hooks for the developer experience, not the tenant sandbox

## Dependencies and Risks

| Risk | Mitigation |
|------|------------|
| SDK types (`PreToolUseHookInput`, `HookCallback`) not exported | Define local interfaces matching documented shape; SDK ^0.2.80 should export them |
| Hook `systemMessage` format differs from documentation | Test with real SDK before merging; fall back to `hookSpecificOutput` only |
| Hook matcher regex syntax differs between SDK versions | Use simple pipe-delimited tool names (documented pattern); avoid complex regex |
| Double-deny (hook denies, then canUseTool also denies) | Remove file-tool checks from canUseTool so only the hook handles them |

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts` -- current canUseTool sandbox implementation
- `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace()` function (unchanged, reused by hook)
- `apps/web-platform/server/bash-sandbox.ts` -- `containsSensitiveEnvAccess()` function (unchanged, reused by hook)
- `knowledge-base/project/plans/2026-03-20-sec-verify-canusertool-caching-behavior-plan.md:98-146` -- createSandboxHook pattern origin
- `knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md` -- SDK permission chain analysis
- `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- three-tier defense model
- `spike/FINDINGS.md` -- Agent SDK spike results
- `.claude/settings.json` -- existing PreToolUse hook pattern (shell-based, for local dev)
- `.claude/hooks/worktree-write-guard.sh` -- reference for hook output format (hookSpecificOutput)

### Related Issues

- #876 -- canUseTool caching verification (recommended this migration)
- #725 -- workspace permissions migration (removed pre-approved file tools)
- #877 -- symlink escape defense-in-depth (sandbox.ts improvements)
