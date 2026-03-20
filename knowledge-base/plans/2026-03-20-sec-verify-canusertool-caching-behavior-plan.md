---
title: "sec: verify canUseTool callback caching behavior in Agent SDK"
type: fix
date: 2026-03-20
---

# sec: verify canUseTool callback caching behavior in Agent SDK

The spike findings (`spike/FINDINGS.md`) observed that `canUseTool` may cache "allow" decisions per tool name within a session -- only 1 callback invocation was observed despite 5 tool uses. If confirmed, a user's agent could bypass the workspace sandbox by first accessing a legitimate file, then accessing files in another user's workspace, with the SDK serving the cached "allow" from the first invocation.

This verification task determines whether caching is real, and if so, evaluates SDK hooks (`PreToolUse`) as an alternative enforcement mechanism that fires on every invocation.

Closes #876

## Acceptance Criteria

- [ ] A dedicated integration test (`apps/web-platform/test/canusertool-caching.test.ts`) verifies callback invocation count when the same tool name is used with different `file_path` arguments
- [ ] The test covers: (a) same tool name + different paths triggers the callback for each invocation, (b) same tool name + same path still triggers the callback each time, (c) different tool names each trigger the callback
- [ ] If caching is confirmed: a `PreToolUse` hook-based sandbox implementation is written in `apps/web-platform/server/sandbox-hook.ts` as an alternative to the `canUseTool` callback, with equivalent path validation
- [ ] If caching is NOT confirmed: the spike finding is corrected, the institutional learning updated, and the `canUseTool`-based sandbox is documented as safe for per-invocation enforcement
- [ ] SDK version is bumped from `^0.2.76` to `^0.2.80` (latest) and the test re-run to check whether caching behavior changed between versions
- [ ] The known limitation in the existing plan (`2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md`, section "Known Limitations" item 3) is updated based on findings

## Research Findings

### SDK Documentation Analysis

The official SDK documentation at `platform.claude.com/docs/en/agent-sdk` does NOT mention any caching of `canUseTool` results. Key evidence against caching:

1. **`toolUseID` parameter**: The `CanUseTool` type signature includes a unique `toolUseID: string` per invocation, suggesting the SDK treats each call as distinct:
   ```typescript
   type CanUseTool = (
     toolName: string,
     input: Record<string, unknown>,
     options: {
       signal: AbortSignal;
       suggestions?: PermissionUpdate[];
       blockedPath?: string;
       decisionReason?: string;
       toolUseID: string;
       agentID?: string;
     }
   ) => Promise<PermissionResult>;
   ```

2. **`suggestions` parameter**: The callback receives `suggestions?: PermissionUpdate[]` -- the SDK provides suggestions for the host to update permission rules so the user is "not prompted again for this tool." This implies the SDK does NOT cache results itself; it expects the host to decide whether to persist the decision.

3. **`updatedInput` in response**: The callback can return `{ behavior: "allow", updatedInput: {...} }` which modifies the tool input. Caching would make `updatedInput` unreliable since the cached "allow" from a previous invocation would not carry the `updatedInput` for a different invocation.

4. **Hooks documentation**: The hooks page explicitly states that `PreToolUse` hooks fire on every tool call with the tool's `tool_input` including `file_path`. Matchers "only filter by tool name, not by file paths or other arguments." If `canUseTool` were cached per tool name, the documentation would likely mention this as a reason to prefer hooks for path-based filtering.

5. **CHANGELOG analysis**: No version between 0.2.21 and 0.2.80 mentions changes to `canUseTool` invocation frequency or caching behavior.

### Spike Observation Reanalysis

The original spike (`spike/agent-sdk-test.ts`, v0.2.76) observed "only 1 callback invocation despite 5 tool uses." However, the spike had `plugins` configured with Soleur, which loads `.claude/settings.json`. The test workspace's settings likely had `permissions.allow: ["Read", "Glob", "Grep"]` pre-approvals, which would cause those tools to be approved at step 4 (allow rules) before reaching step 5 (`canUseTool`). The "5 tool uses" likely included pre-approved tools that bypassed the callback entirely.

The spike's own `observations.canUseToolCalls` array tracked callback invocations, and if only 1 fired, it was likely for the single tool that was NOT pre-approved (e.g., Bash or a non-Read tool). This is the permission chain working as documented, not caching.

### Hooks as Alternative

If caching IS confirmed despite the documentation evidence, `PreToolUse` hooks are a viable alternative:

- Hooks run before `canUseTool` in the permission evaluation order (step 1 vs step 5)
- Hooks fire on every tool invocation with full `tool_input` including `file_path`
- Hooks can return `permissionDecision: "deny"` to block operations
- Hooks support matchers for tool name filtering and can inspect `tool_input.file_path` in the callback body
- The hook-based approach would match the existing `isPathInWorkspace` function from `sandbox.ts`

### SDK Version Gap

The project uses `^0.2.76`. Latest is `0.2.80`. Four versions released since the spike (0.2.77, 0.2.78, 0.2.79, 0.2.80). The changelog shows no explicit changes to `canUseTool` invocation behavior, but version bumping is warranted to pick up the `updatedPermissions` ZodError fix (0.2.69) and any unlisted internal changes.

## Test Scenarios

### Caching Verification Test

- Given a `canUseTool` callback that logs every invocation, when the SDK calls `Read` with `/workspaces/user1/file1.md` and then `Read` with `/workspaces/user1/file2.md`, then the callback fires twice (once per invocation) with different `file_path` values
- Given a `canUseTool` callback that counts invocations, when the SDK calls `Read` 5 times with 5 different paths, then the count equals 5
- Given a `canUseTool` callback that returns `allow` for workspace-internal paths, when the SDK calls `Read` with a workspace path followed by `Read` with an external path, then the callback fires for both calls and the second is denied

### Hook Equivalence Test (conditional -- only if caching confirmed)

- Given a `PreToolUse` hook with `isPathInWorkspace` validation, when the SDK calls `Read` with a path outside the workspace, then the hook denies the tool call
- Given a `PreToolUse` hook, when the SDK calls `Read` 5 times with different paths, then the hook fires 5 times

## Context

- **Spike findings**: `spike/FINDINGS.md` -- "canUseTool may cache allow decisions per-tool-name within a session"
- **Spike test**: `spike/agent-sdk-test.ts` -- original validation code
- **Existing sandbox**: `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace()` function
- **Agent runner**: `apps/web-platform/server/agent-runner.ts` -- `canUseTool` callback integration
- **Existing sandbox tests**: `apps/web-platform/test/canusertool-sandbox.test.ts`
- **Institutional learning**: `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`
- **Path traversal learning**: `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- **Related plan**: `knowledge-base/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md`
- **SDK docs**: [Permissions](https://platform.claude.com/docs/en/agent-sdk/permissions), [User Input](https://platform.claude.com/docs/en/agent-sdk/user-input), [Hooks](https://platform.claude.com/docs/en/agent-sdk/hooks)
- **SDK changelog**: [TypeScript CHANGELOG](https://github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md)
- **Issue**: #876
- **SDK version**: `^0.2.76` (latest: `0.2.80`)

## MVP

### Phase 1: Write caching verification test

#### apps/web-platform/test/canusertool-caching.test.ts

```typescript
import { describe, test, expect, vi } from "vitest";

// This test requires the Agent SDK installed and an API key.
// It validates whether canUseTool is called per-invocation or cached.
// Run with: ANTHROPIC_API_KEY=... vitest run canusertool-caching

describe("canUseTool caching behavior", () => {
  test("callback fires for each tool invocation with different file_path", async () => {
    const { query } = await import("@anthropic-ai/claude-agent-sdk");

    const invocations: Array<{ toolName: string; filePath: string }> = [];

    const q = query({
      prompt: "Read the files at /tmp/test1.txt and /tmp/test2.txt",
      options: {
        cwd: "/tmp",
        maxTurns: 3,
        maxBudgetUsd: 0.10,
        permissionMode: "default",
        // No allowedTools -- everything routes through canUseTool
        canUseTool: async (toolName, input) => {
          const filePath = (input as { file_path?: string }).file_path || "";
          invocations.push({ toolName, filePath });
          return { behavior: "allow" as const, updatedInput: input };
        },
      },
    });

    for await (const message of q) {
      // Consume stream
    }

    // Filter to Read invocations only
    const readCalls = invocations.filter((i) => i.toolName === "Read");
    expect(readCalls.length).toBeGreaterThanOrEqual(2);
    // Verify different file paths triggered separate callbacks
    const uniquePaths = new Set(readCalls.map((r) => r.filePath));
    expect(uniquePaths.size).toBeGreaterThanOrEqual(2);
  });
});
```

### Phase 2: Bump SDK version and re-test

Update `apps/web-platform/package.json` to `"@anthropic-ai/claude-agent-sdk": "^0.2.80"` and re-run the test.

### Phase 3: Update documentation based on findings

#### If NOT cached (expected outcome based on documentation analysis):

1. Update `spike/FINDINGS.md` section "canUseTool caching" to clarify the observation was due to pre-approved tools bypassing the callback, not caching
2. Update `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` to correct the caching claim
3. Update `knowledge-base/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md` Known Limitations item 3 to state caching was disproven
4. Update `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` if it references caching

#### If cached (requires mitigation):

1. Create `apps/web-platform/server/sandbox-hook.ts` implementing `PreToolUse` hook with `isPathInWorkspace` validation
2. Update `apps/web-platform/server/agent-runner.ts` to register the hook in `query()` options
3. Retain `canUseTool` for `AskUserQuestion` review gates (hooks cannot provide `updatedInput` with user answers)
4. Add tests for the hook-based sandbox in `apps/web-platform/test/sandbox-hook.test.ts`
5. Create a new institutional learning documenting the caching behavior and the hook mitigation

## Known Limitations

1. **Integration test requires API key**: The caching verification test calls the real Agent SDK `query()` function, which requires `ANTHROPIC_API_KEY` and incurs API costs. It cannot run in CI without a secrets-configured environment. Consider marking it as `test.skip` by default with an env-var gate.

2. **Non-deterministic agent behavior**: The test prompts Claude to "read two files," but the agent may choose different tools or paths. The test should be resilient to agent behavior variation by checking that the callback fires at least N times, not exactly N times.

3. **Hooks + canUseTool coexistence**: If hooks are adopted for sandbox enforcement, the `canUseTool` callback remains needed for `AskUserQuestion` review gates. Both mechanisms must coexist without conflicts. Hooks run at step 1 (before deny rules), while `canUseTool` runs at step 5 (after allow rules). A `PreToolUse` hook returning `permissionDecision: "deny"` takes precedence over any `canUseTool` "allow."

## References

- Issue: #876
- Related PR: #873 (path traversal fix)
- Related Issue: #725 (original path traversal vulnerability)
- SDK permission chain: [Permissions docs](https://platform.claude.com/docs/en/agent-sdk/permissions)
- SDK hooks: [Hooks docs](https://platform.claude.com/docs/en/agent-sdk/hooks)
- SDK canUseTool: [User Input docs](https://platform.claude.com/docs/en/agent-sdk/user-input)
- SDK TypeScript reference: [TypeScript docs](https://platform.claude.com/docs/en/agent-sdk/typescript)
- SDK changelog: [CHANGELOG.md](https://github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md)
- Spike findings: `spike/FINDINGS.md`
- Existing sandbox: `apps/web-platform/server/sandbox.ts`
- Institutional learning: `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`
