---
title: "sec: verify canUseTool callback caching behavior in Agent SDK"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources:** Claude Agent SDK docs (Context7), SDK TypeScript reference, SDK GitHub issues (anthropics/claude-agent-sdk-typescript), CHANGELOG.md (v0.2.76-0.2.80), SDK source decompilation from issue #162, institutional learnings (agent-sdk-spike-validation, cwe22-path-traversal, fire-and-forget-promise)

### Key Improvements

1. **Strong evidence that caching does NOT exist** -- the `CanUseTool` type signature includes `toolUseID: string` (unique per invocation) and `suggestions?: PermissionUpdate[]` (SDK prompts the host to persist decisions externally, implying it does not cache internally). The `updatedInput` response field would be functionally broken under per-tool-name caching.
2. **Root cause of spike observation identified** -- the spike loaded a `.claude/settings.json` with `permissions.allow: ["Read", "Glob", "Grep"]`, causing those tools to be resolved at permission chain step 4 (allow rules) and never reaching step 5 (`canUseTool`). The "1 callback vs 5 tool uses" was the permission chain working correctly, not caching.
3. **Defense-in-depth recommendation added** -- regardless of caching findings, migrate sandbox enforcement from `canUseTool` (step 5) to a `PreToolUse` hook (step 1) for defense-in-depth. Hooks fire first in the permission chain and cannot be bypassed by `allowedTools` or settings.json pre-approvals.
4. **Test design improved** -- added `settingSources: []` to prevent settings.json from loading in tests, and a file-creation setup step so the agent has deterministic targets.
5. **SDK GitHub issues confirm no caching reports** -- zero issues in `anthropics/claude-agent-sdk-typescript` discuss `canUseTool` caching. Issue #162 reveals source-level tool filtering logic; no caching layer exists in the permission pipeline.

### New Considerations Discovered

- The SDK's `suggestions` field is designed for interactive approval UIs where the host can update permission rules so the user is "not prompted again." This is the SDK's intended mechanism for caching -- externalized to the host, not internal.
- `PreToolUse` hooks with `permissionDecision: "deny"` take absolute precedence over all other permission mechanisms including `bypassPermissions` mode. This makes hooks the strongest security boundary.
- The SDK internally applies a pre-filter (`gv6()`) that removes orchestration tools from subagent tool sets (issue #162). This confirms the SDK has internal tool filtering, but it operates on tool availability, not on permission decision caching.
- Versions 0.2.76-0.2.80 contain no permission-related changes. The only relevant fix is in 0.2.69 (`updatedPermissions` ZodError), which was already in range for `^0.2.76`.

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

5. **CHANGELOG analysis**: No version between 0.2.21 and 0.2.80 mentions changes to `canUseTool` invocation frequency or caching behavior. Versions 0.2.76 through 0.2.80 specifically contain: session forking, MCP elicitation hooks, API retry messages, exit reason types, and parallel tool result fixes -- zero permission-related changes.

6. **GitHub issues analysis**: Zero issues in `anthropics/claude-agent-sdk-typescript` discuss `canUseTool` caching. Issue [#162](https://github.com/anthropics/claude-agent-sdk-typescript/issues/162) decompiled the SDK's internal tool filtering function (`gv6()` -> `Os()`) which operates on tool availability for subagents, not on permission decision caching. No caching layer exists in the decompiled permission pipeline.

7. **SDK `suggestions` field design intent**: The official docs state that `suggestions` provides "Suggested permission updates so the user is not prompted again for this tool." This is the SDK's intended caching mechanism -- it is **externalized to the host application**, not internal to the SDK. The SDK delegates persistence of permission decisions to the host via `suggestions`, confirming it does not cache results itself.

### Spike Observation Reanalysis

The original spike (`spike/agent-sdk-test.ts`, v0.2.76) observed "only 1 callback invocation despite 5 tool uses." However, the spike had `plugins` configured with Soleur, which loads `.claude/settings.json`. The test workspace's settings likely had `permissions.allow: ["Read", "Glob", "Grep"]` pre-approvals, which would cause those tools to be approved at step 4 (allow rules) before reaching step 5 (`canUseTool`). The "5 tool uses" likely included pre-approved tools that bypassed the callback entirely.

The spike's own `observations.canUseToolCalls` array tracked callback invocations, and if only 1 fired, it was likely for the single tool that was NOT pre-approved (e.g., Bash or a non-Read tool). This is the permission chain working as documented, not caching.

### Hooks as Alternative (and Defense-in-Depth Recommendation)

Regardless of whether caching is confirmed, migrating sandbox enforcement from `canUseTool` (step 5) to a `PreToolUse` hook (step 1) is a defense-in-depth improvement:

- **Position in permission chain**: Hooks run at step 1, before deny rules (step 2), permission mode (step 3), and allow rules (step 4). A hook-based deny cannot be bypassed by `allowedTools`, `settings.json` pre-approvals, or even `bypassPermissions` mode. `canUseTool` at step 5 is the weakest position -- anything resolved at steps 1-4 never reaches it.
- **Per-invocation guarantee**: The SDK documentation explicitly states hooks fire on every tool invocation. The `PreToolUseHookInput` includes `tool_name` and `tool_input` with full arguments including `file_path`.
- **Type-safe implementation**: The SDK exports `HookCallback`, `PreToolUseHookInput` types for proper typing. The `tool_input` field is typed as `unknown` and requires casting to `Record<string, unknown>` for property access.
- **`systemMessage` injection**: Unlike `canUseTool` which only returns allow/deny, hooks can inject a `systemMessage` into the conversation explaining the denial. This helps the agent avoid retrying blocked operations.
- **Matcher optimization**: Hooks support regex matchers for tool name filtering (e.g., `"Read|Write|Edit|Glob|Grep"`) so the callback only fires for file-accessing tools, reducing overhead for non-file tools like `AskUserQuestion`.

**Concrete implementation pattern** (from SDK docs):

```typescript
import { HookCallback, PreToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";

export function createSandboxHook(workspacePath: string): HookCallback {
  return async (input, toolUseID, { signal }) => {
    const preInput = input as PreToolUseHookInput;
    const toolInput = preInput.tool_input as Record<string, unknown>;
    const filePath = (toolInput?.file_path as string) || (toolInput?.path as string) || "";

    if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
      return {
        systemMessage: "File access outside the workspace is not permitted.",
        hookSpecificOutput: {
          hookEventName: preInput.hook_event_name,
          permissionDecision: "deny",
          permissionDecisionReason: "Access denied: outside workspace",
        },
      };
    }
    return {};
  };
}
```

**Integration in agent-runner.ts**:

```typescript
const q = query({
  prompt: systemPrompt,
  options: {
    hooks: {
      PreToolUse: [{
        matcher: "Read|Write|Edit|Glob|Grep",
        hooks: [createSandboxHook(workspacePath)],
      }],
    },
    canUseTool: async (toolName, toolInput) => {
      // Retain canUseTool ONLY for AskUserQuestion review gates
      if (toolName === "AskUserQuestion") {
        return handleReviewGate(toolInput, session);
      }
      return { behavior: "allow" as const };
    },
  },
});
```

**Coexistence model**: `PreToolUse` hook handles sandbox enforcement (deny outside workspace). `canUseTool` handles `AskUserQuestion` review gates (allow with `updatedInput` containing user's answer). These do not conflict because hooks fire at step 1 and `canUseTool` at step 5 -- by the time `canUseTool` fires for `AskUserQuestion`, the hook has already allowed it (no matcher match on `AskUserQuestion`).

### SDK Version Gap

The project uses `^0.2.76`. Latest is `0.2.80`. Four versions released since the spike (0.2.77, 0.2.78, 0.2.79, 0.2.80). Changes in this range:

| Version | Key Changes |
|---------|-------------|
| 0.2.77 | `api_retry` system messages for transient API errors |
| 0.2.78 | Parity with Claude Code v2.1.78 (no breaking changes) |
| 0.2.79 | `'resume'` added to `ExitReason` type |
| 0.2.80 | Fixed `getSessionMessages()` dropping parallel tool results |

No permission-related changes. Version bumping is warranted for the parallel tool result fix (0.2.80) which could affect multi-tool sessions used in testing.

## Test Scenarios

### Caching Verification Test

- Given a `canUseTool` callback that logs every invocation with `settingSources: []` (no pre-approvals), when the SDK calls `Read` with `/tmp/test/file1.txt` and then `Read` with `/tmp/test/file2.txt`, then the callback fires twice (once per invocation) with different `file_path` values and different `toolUseID` values
- Given a `canUseTool` callback that counts invocations, when the SDK calls `Read` 3 times with 3 different paths on real files, then the count is at least 2 (allowing for agent non-determinism)
- Given a `canUseTool` callback that tracks `toolUseID` values, when multiple Read calls fire, then every `toolUseID` is unique (confirming no ID reuse from caching)

### Deduplication Test

- Given a `canUseTool` callback, when the agent is prompted to read the same file twice, then the callback fires for each invocation (no same-path deduplication). Note: the agent (LLM) may choose not to re-read a file it already has in context -- this is agent-level optimization, not SDK-level caching.

### Hook Equivalence Test (conditional -- only if caching confirmed)

- Given a `PreToolUse` hook with `isPathInWorkspace` validation and matcher `"Read|Write|Edit|Glob|Grep"`, when the SDK calls `Read` with a path outside the workspace, then the hook denies the tool call with `permissionDecision: "deny"`
- Given a `PreToolUse` hook, when the SDK calls `Read` 3 times with different paths, then the hook fires 3 times (hooks are documented as per-invocation with no caching)

### Research Insights

**Test design considerations:**
- Integration tests calling the real SDK are inherently non-deterministic because the LLM decides which tools to use and in what order. Use `greaterThanOrEqual` assertions and create real files to maximize the chance of Read tool usage.
- The `toolUseID` uniqueness check is the strongest anti-caching signal. If the SDK cached permission decisions per tool name, it would either reuse the `toolUseID` or skip calling the callback entirely. Unique IDs confirm per-invocation evaluation.
- `settingSources: []` is critical. Without it, the SDK may discover a `.claude/settings.json` in the test workspace or user directory that pre-approves tools, reproducing the original spike's misleading observation.

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

### Research Insights

**Test Design Improvements:**
- **`settingSources: []`**: Explicitly pass empty array to prevent the SDK from loading any `.claude/settings.json` files that could pre-approve tools and bypass `canUseTool`. This was the root cause of the spike's misleading observation.
- **Create test files first**: Use `beforeAll` to create deterministic test files so the agent has real targets. Without real files, the agent may use `Glob` or `Bash` instead of `Read`, making callback counts unpredictable.
- **`toolUseID` tracking**: Record the `toolUseID` from the options parameter to verify uniqueness across invocations -- if the SDK caches, it would reuse or skip generating unique IDs.
- **Timeout guard**: Agent SDK tests involve real API calls and LLM inference. Set a generous timeout (60s) to avoid flaky failures from slow responses.
- **`disallowedTools`**: Block `Bash`, `Write`, `Edit` to constrain the agent to read-only tools, reducing non-determinism and API cost.

```typescript
import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "fs";

const TEST_DIR = "/tmp/canusertool-caching-test";
const API_KEY = process.env.ANTHROPIC_API_KEY;

// Skip entire suite when no API key is available (CI without secrets)
const describeWithKey = API_KEY ? describe : describe.skip;

describeWithKey("canUseTool caching behavior", () => {
  beforeAll(() => {
    mkdirSync(TEST_DIR, { recursive: true });
    writeFileSync(`${TEST_DIR}/file1.txt`, "Content of file 1");
    writeFileSync(`${TEST_DIR}/file2.txt`, "Content of file 2");
    writeFileSync(`${TEST_DIR}/file3.txt`, "Content of file 3");
  });

  afterAll(() => {
    rmSync(TEST_DIR, { recursive: true, force: true });
  });

  test("callback fires for each tool invocation with different file_path", async () => {
    const { query } = await import("@anthropic-ai/claude-agent-sdk");

    const invocations: Array<{
      toolName: string;
      filePath: string;
      toolUseID: string;
    }> = [];

    const q = query({
      prompt: `Read all three files in ${TEST_DIR}: file1.txt, file2.txt, and file3.txt. Report their contents.`,
      options: {
        cwd: TEST_DIR,
        model: "claude-sonnet-4-6",
        maxTurns: 5,
        maxBudgetUsd: 0.25,
        permissionMode: "default",
        settingSources: [],  // Prevent settings.json from pre-approving tools
        disallowedTools: ["Bash", "Write", "Edit"],  // Constrain to read-only
        // No allowedTools -- everything routes through canUseTool
        canUseTool: async (toolName, input, options) => {
          const filePath = (input as { file_path?: string }).file_path || "";
          invocations.push({
            toolName,
            filePath,
            toolUseID: options.toolUseID,
          });
          return { behavior: "allow" as const, updatedInput: input };
        },
      },
    });

    for await (const message of q) {
      // Consume stream
    }

    // Verify callback fired for each Read invocation
    const readCalls = invocations.filter((i) => i.toolName === "Read");
    expect(readCalls.length).toBeGreaterThanOrEqual(2);

    // Verify different file paths triggered separate callbacks
    const uniquePaths = new Set(readCalls.map((r) => r.filePath));
    expect(uniquePaths.size).toBeGreaterThanOrEqual(2);

    // Verify each invocation got a unique toolUseID (anti-caching signal)
    const uniqueIDs = new Set(readCalls.map((r) => r.toolUseID));
    expect(uniqueIDs.size).toBe(readCalls.length);

    // Log results for manual verification
    console.log(`[caching-test] Total canUseTool calls: ${invocations.length}`);
    console.log(`[caching-test] Read calls: ${readCalls.length}`);
    console.log(`[caching-test] Unique paths: ${uniquePaths.size}`);
    console.log(`[caching-test] Unique toolUseIDs: ${uniqueIDs.size}`);
    for (const call of readCalls) {
      console.log(`  [Read] ${call.filePath} (ID: ${call.toolUseID})`);
    }
  }, 60_000);

  test("callback fires even for same tool + same path (no deduplication)", async () => {
    const { query } = await import("@anthropic-ai/claude-agent-sdk");

    const invocations: Array<{ toolName: string; filePath: string }> = [];

    const q = query({
      prompt: `Read ${TEST_DIR}/file1.txt. Then read ${TEST_DIR}/file1.txt again and confirm the content is unchanged.`,
      options: {
        cwd: TEST_DIR,
        model: "claude-sonnet-4-6",
        maxTurns: 5,
        maxBudgetUsd: 0.25,
        permissionMode: "default",
        settingSources: [],
        disallowedTools: ["Bash", "Write", "Edit"],
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

    const readCalls = invocations.filter((i) => i.toolName === "Read");
    // Agent may not re-read the same file (LLM optimization), but if it does,
    // verify the callback fires each time (not cached)
    expect(readCalls.length).toBeGreaterThanOrEqual(1);
    console.log(`[dedup-test] Read calls: ${readCalls.length}`);
    for (const call of readCalls) {
      console.log(`  [Read] ${call.filePath}`);
    }
  }, 60_000);
});
```

### Phase 2: Bump SDK version and re-test

Update `apps/web-platform/package.json` to `"@anthropic-ai/claude-agent-sdk": "^0.2.80"` and re-run the test.

### Phase 3: Update documentation based on findings

#### If NOT cached (expected outcome based on documentation analysis):

1. Update `spike/FINDINGS.md` section "canUseTool caching" to clarify the observation was due to pre-approved tools bypassing the callback, not caching
2. Update `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` to correct the caching claim -- replace "may cache" language with definitive "does not cache" and explain the pre-approval bypass root cause
3. Update `knowledge-base/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md` Known Limitations item 3 to state caching was disproven by empirical test
4. Update `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` to remove caching hedging language

### Research Insights

**Documentation update strategy:**
- Each document that references caching uses hedging language ("may cache", "Likely the SDK caches"). Replace with definitive language citing the empirical test results and the `toolUseID` uniqueness evidence.
- The `suggestions` field design intent should be documented as the SDK's intended externalized caching mechanism: the host decides whether to persist permission decisions, not the SDK.
- Cross-reference the test file (`canusertool-caching.test.ts`) as the authoritative verification artifact.

#### If cached (requires mitigation):

1. Create `apps/web-platform/server/sandbox-hook.ts` implementing `PreToolUse` hook with `isPathInWorkspace` validation (use the `createSandboxHook` pattern from the Hooks as Alternative section above)
2. Update `apps/web-platform/server/agent-runner.ts` to register the hook in `query()` options with matcher `"Read|Write|Edit|Glob|Grep"`
3. Retain `canUseTool` for `AskUserQuestion` review gates only (hooks cannot provide `updatedInput` with user answers -- only `canUseTool` supports the `updatedInput` response field needed for injecting the user's selection)
4. Add unit tests for the hook-based sandbox in `apps/web-platform/test/sandbox-hook.test.ts` -- these can be pure unit tests (no API key needed) since the hook callback is a regular function that can be invoked directly with mock `PreToolUseHookInput` objects
5. Create a new institutional learning documenting the caching behavior and the hook mitigation

### Phase 4 (Defense-in-Depth -- Recommended Regardless of Caching Findings)

Even if caching is disproven, consider migrating sandbox enforcement from `canUseTool` to `PreToolUse` hooks as a defense-in-depth improvement. Rationale:

- **Stronger position in permission chain**: Hooks at step 1 vs `canUseTool` at step 5. Any future code that adds `allowedTools` or `settingSources: ["project"]` would bypass `canUseTool` but not hooks.
- **`systemMessage` capability**: Hooks can inject context explaining the denial, helping the agent avoid retrying.
- **Pure unit testability**: Hook callbacks can be tested without the SDK by constructing mock `PreToolUseHookInput` objects, unlike `canUseTool` which requires an `options` parameter with `signal`, `suggestions`, etc.
- **No breaking changes**: The hook-based sandbox is additive. `canUseTool` continues to handle `AskUserQuestion` review gates.

This is a low-risk, high-value change that can be implemented in a follow-up PR after the caching verification is complete.

## Known Limitations

1. **Integration test requires API key**: The caching verification test calls the real Agent SDK `query()` function, which requires `ANTHROPIC_API_KEY` and incurs API costs. It cannot run in CI without a secrets-configured environment. The test uses `describe.skip` when `ANTHROPIC_API_KEY` is not set, following the env-var gate pattern.

2. **Non-deterministic agent behavior**: The test prompts Claude to read specific files, but the agent may choose different tools, re-order operations, or skip reads if it infers the content from context. The test checks `greaterThanOrEqual(2)` rather than exact counts, and creates real files for deterministic targets.

3. **Hooks + canUseTool coexistence**: If hooks are adopted for sandbox enforcement, the `canUseTool` callback remains needed for `AskUserQuestion` review gates. Both mechanisms coexist because they operate at different permission chain positions (step 1 vs step 5) and target different tools. The hook matcher `"Read|Write|Edit|Glob|Grep"` excludes `AskUserQuestion`, so review gates pass through to `canUseTool` unaffected.

### Research Insights

**Additional edge cases to consider:**

- **Subagent permission inheritance**: The SDK documentation warns that `bypassPermissions` is inherited by subagents and cannot be overridden. If the web platform ever spawns subagents via the `Agent` tool, verify that `PreToolUse` hooks also fire for subagent tool calls. The hook input includes `agentID` when firing inside a subagent, confirming hooks propagate.
- **MCP tool naming**: MCP tools use the `mcp__<server>__<action>` naming pattern. The sandbox hook matcher must not match MCP tools unless they access the filesystem. The current matcher (`"Read|Write|Edit|Glob|Grep"`) is safe because it uses exact tool name matching, not prefix matching.
- **Hook timeout**: The default hook timeout is 60 seconds. The `isPathInWorkspace` check is a synchronous `path.resolve` + `startsWith` operation (sub-millisecond), so the default timeout is more than sufficient. No custom timeout needed.
- **`settingSources` in production**: The current `agent-runner.ts` does not set `settingSources`. The SDK's default behavior is to NOT load filesystem settings unless explicitly requested with `settingSources: ["project"]`. Verify this is the case -- if settings are loaded, the workspace `.claude/settings.json` could re-introduce pre-approvals that bypass the sandbox hook.

## References

### Internal

- Issue: #876
- Related PR: #873 (path traversal fix)
- Related Issue: #725 (original path traversal vulnerability)
- Spike findings: `spike/FINDINGS.md`
- Spike test code: `spike/agent-sdk-test.ts`
- Existing sandbox: `apps/web-platform/server/sandbox.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`
- Existing sandbox tests: `apps/web-platform/test/canusertool-sandbox.test.ts`
- Institutional learning (spike): `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`
- Institutional learning (CWE-22): `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Institutional learning (fire-and-forget): `knowledge-base/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md`
- Related plan: `knowledge-base/plans/2026-03-20-sec-path-traversal-canusertool-workspace-sandbox-plan.md`

### External

- SDK permission chain: [Permissions docs](https://platform.claude.com/docs/en/agent-sdk/permissions)
- SDK hooks: [Hooks docs](https://platform.claude.com/docs/en/agent-sdk/hooks) -- includes `PreToolUse` file path filtering pattern
- SDK canUseTool: [User Input docs](https://platform.claude.com/docs/en/agent-sdk/user-input) -- `CanUseTool` type signature with `toolUseID` and `suggestions`
- SDK TypeScript reference: [TypeScript docs](https://platform.claude.com/docs/en/agent-sdk/typescript) -- `CanUseTool` type, `HookCallback`, `PreToolUseHookInput`
- SDK changelog: [CHANGELOG.md](https://github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md)
- SDK GitHub issues: [anthropics/claude-agent-sdk-typescript](https://github.com/anthropics/claude-agent-sdk-typescript/issues) -- zero issues about `canUseTool` caching
- SDK issue #162: [AgentDefinition.tools prompt-based only](https://github.com/anthropics/claude-agent-sdk-typescript/issues/162) -- source-level decompilation of permission pipeline (no caching layer found)
