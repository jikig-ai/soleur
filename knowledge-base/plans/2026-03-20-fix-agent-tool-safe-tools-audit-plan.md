---
title: "fix: remove Agent from SAFE_TOOLS and add subagent sandbox validation"
type: fix
date: 2026-03-20
semver: patch
---

# fix: remove Agent from SAFE_TOOLS and add subagent sandbox validation

## Overview

The `canUseTool` callback in `agent-runner.ts` classifies `Agent` as a safe tool (via `SAFE_TOOLS` in `tool-path-checker.ts`), auto-allowing it without any validation. The assumption is that subagents spawned via the Agent tool inherit the parent's sandbox configuration. SDK documentation reveals this assumption is partially correct but has important gaps that require explicit mitigation.

## Problem Statement

### What the SDK documentation says

1. **Hooks DO fire for subagent tool calls.** The hooks documentation confirms `agent_id` and `agent_type` fields are populated on hook inputs when firing inside a subagent context. PreToolUse hooks registered on the parent `query()` call fire for tool uses within subagents. This means the `createSandboxHook(workspacePath)` PreToolUse hook correctly intercepts file tool calls from subagents.

2. **`canUseTool` callback behavior for subagents is NOT documented.** The SDK documentation does not explicitly state whether the `canUseTool` callback fires for subagent tool calls. The hooks documentation states: "Subagents do not automatically inherit parent agent permissions." The permissions documentation says subagents inherit `bypassPermissions` mode, but is silent on `canUseTool` inheritance for other modes.

3. **Subagents can inherit all parent tools by default.** When `tools` is omitted from `AgentDefinition`, the subagent "inherits all available tools." The agent-runner does not define any `agents` config, meaning the `general-purpose` built-in subagent gets all tools.

4. **Subagents cannot spawn their own subagents.** The SDK docs explicitly state "Don't include `Agent` in a subagent's `tools` array" and the SDK enforces this.

### Current security model

The agent-runner has 3 defense layers:

| Layer | Mechanism | Covers subagents? |
|-------|-----------|-------------------|
| 1 | PreToolUse hooks (`createSandboxHook`) | **Yes** -- hooks fire for subagent tool calls (SDK confirmed) |
| 2 | `canUseTool` callback (defense-in-depth) | **Unknown** -- SDK docs do not confirm inheritance |
| 3 | SDK bubblewrap sandbox (`sandbox: {...}`) | **Likely yes** -- sandbox is process-level, subagents run in same process |

### The gap

If `canUseTool` does NOT fire for subagent tool calls, then layer 2 is inactive for subagents. This is not a critical vulnerability because layer 1 (PreToolUse hooks) is confirmed to cover subagents. However:

- The `Agent` tool itself bypasses the deny-by-default gate in `canUseTool` -- it is auto-allowed without reaching the bottom deny case
- If a subagent uses a tool NOT in `FILE_TOOLS` and NOT in `SAFE_TOOLS` (e.g., a future SDK tool), it would hit deny-by-default in the parent's `canUseTool` -- but only if `canUseTool` fires for subagents
- The `disallowedTools: ["WebSearch", "WebFetch"]` config is confirmed to be enforced by the SDK at the allow/deny rule level (step 2 in the permission chain), which applies before `canUseTool`

### Attack surface enumeration

All code paths that touch the Agent tool's security surface:

1. **Parent agent invokes Agent tool** -- hits `isSafeTool("Agent")` in `canUseTool`, auto-allowed (line 285)
2. **Subagent invokes file tools (Read, Write, etc.)** -- hits PreToolUse hook (layer 1, confirmed) and possibly `canUseTool` `isFileTool` check (layer 2, unconfirmed)
3. **Subagent invokes Bash** -- hits PreToolUse hook for env access check (confirmed) and SDK sandbox for filesystem/network (confirmed)
4. **Subagent invokes unrecognized tool** -- should hit deny-by-default in `canUseTool` IF `canUseTool` fires for subagents
5. **Subagent invokes Agent tool** -- SDK prevents this (subagents cannot spawn sub-subagents)
6. **Prompt injection via Agent tool prompt** -- subagent gets a fresh context with only its system prompt and the Agent tool's prompt string; no parent conversation history leaks

Path 4 is the residual risk: if `canUseTool` does not fire for subagents, an unrecognized future tool could bypass deny-by-default.

## Proposed Solution

### Approach: Remove `Agent` from `SAFE_TOOLS`, add explicit validation

Rather than trusting SDK behavior that is not documented, make the Agent tool's security posture explicit:

1. **Remove `Agent` from `SAFE_TOOLS`** -- it falls through to the deny-by-default case
2. **Add an explicit Agent tool handler in `canUseTool`** before the deny-by-default return, with a comment documenting the SDK inheritance assumptions and why it is allowed
3. **Add a `SubagentStart` hook** as defense-in-depth to log subagent spawning events for audit visibility
4. **Add a test** verifying that `Agent` is not in `SAFE_TOOLS` (regression guard)

### Why not block Agent entirely?

The Agent tool is a core SDK feature used by the plugin system (domain leaders delegate to specialist agents). Blocking it would break the product. The goal is to move it from an implicit auto-allow to an explicit, documented allow with audit logging.

## Technical Considerations

### Architecture impacts

- `tool-path-checker.ts`: Remove `"Agent"` from `SAFE_TOOLS` array, add `"Skill"`, `"TodoRead"`, `"TodoWrite"` remain
- `agent-runner.ts`: Add explicit `Agent` handling block in `canUseTool` before deny-by-default
- `sandbox-hook.ts`: No changes needed -- hooks already fire for subagents
- Tests: Update completeness guards in `tool-path-checker.test.ts`

### Security considerations

- **No regression in file tool protection**: PreToolUse hooks (layer 1) are confirmed to fire for subagent tool calls. File path validation remains intact.
- **Defense-in-depth improvement**: Moving Agent from auto-allow to explicit-allow with documentation makes the security decision auditable.
- **Future tool protection**: If `canUseTool` does fire for subagents, the deny-by-default case catches unknown tools. If it does not, the PreToolUse hook matcher should be expanded to cover any new file-like tools as they appear.

### SDK version dependency

The analysis is based on `@anthropic-ai/claude-agent-sdk` ^0.2.80. SDK behavior regarding subagent inheritance may change. The `SubagentStart` hook provides ongoing visibility.

## Acceptance Criteria

- [ ] `Agent` is NOT in the `SAFE_TOOLS` array (`apps/web-platform/server/tool-path-checker.ts`)
- [ ] `canUseTool` has an explicit `Agent` handler with documented rationale (`apps/web-platform/server/agent-runner.ts`)
- [ ] `SubagentStart` hook is registered in the `hooks` config to log subagent spawns
- [ ] Test: `SAFE_TOOLS` completeness guard updated to `["Skill", "TodoRead", "TodoWrite"]` (`apps/web-platform/test/tool-path-checker.test.ts`)
- [ ] Test: `Agent` is NOT a safe tool (explicit negative test)
- [ ] Test: `Agent` is NOT a file tool (existing test, verify preserved)
- [ ] All existing tests pass

## Test Scenarios

- Given Agent is removed from SAFE_TOOLS, when `isSafeTool("Agent")` is called, then it returns `false`
- Given the explicit Agent handler in canUseTool, when the Agent tool is invoked, then it returns `{ behavior: "allow" }`
- Given the canUseTool callback, when an unrecognized tool is invoked, then it returns `{ behavior: "deny" }` (unchanged)
- Given the SubagentStart hook, when a subagent is spawned, then a log entry is emitted
- Given the SAFE_TOOLS completeness guard, when SAFE_TOOLS is read, then it contains exactly `["Skill", "TodoRead", "TodoWrite"]`

## MVP

### apps/web-platform/server/tool-path-checker.ts

```typescript
// Remove "Agent" from SAFE_TOOLS
export const SAFE_TOOLS = ["Skill", "TodoRead", "TodoWrite"] as const;
```

### apps/web-platform/server/agent-runner.ts (canUseTool addition)

```typescript
// Agent tool: subagents run within the same SDK sandbox (bubblewrap,
// filesystem restrictions, network policy) and PreToolUse hooks fire
// for subagent tool calls (confirmed via SDK docs). canUseTool
// inheritance for subagents is undocumented -- this explicit allow
// replaces the SAFE_TOOLS auto-allow for auditability. See #910.
if (toolName === "Agent") {
  return { behavior: "allow" as const };
}
```

### apps/web-platform/server/agent-runner.ts (SubagentStart hook)

```typescript
hooks: {
  PreToolUse: [{
    matcher: "Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash",
    hooks: [createSandboxHook(workspacePath)],
  }],
  SubagentStart: [{
    hooks: [async (input, _toolUseID, _options) => {
      console.log(
        `[sec] Subagent started: agent_id=${(input as Record<string, unknown>).agent_id}, ` +
        `type=${(input as Record<string, unknown>).agent_type}`
      );
      return {};
    }],
  }],
},
```

## References

- Issue: [#910](https://github.com/jikig-ai/soleur/issues/910)
- Related: [#895](https://github.com/jikig-ai/soleur/issues/895), [#876](https://github.com/jikig-ai/soleur/issues/876)
- SDK subagents docs: [platform.claude.com/docs/en/agent-sdk/subagents](https://platform.claude.com/docs/en/agent-sdk/subagents)
- SDK permissions docs: [platform.claude.com/docs/en/agent-sdk/permissions](https://platform.claude.com/docs/en/agent-sdk/permissions)
- SDK hooks docs: [platform.claude.com/docs/en/agent-sdk/hooks](https://platform.claude.com/docs/en/agent-sdk/hooks)
- File: `apps/web-platform/server/tool-path-checker.ts:49`
- File: `apps/web-platform/server/agent-runner.ts:285`
- Learning: `knowledge-base/learnings/2026-03-20-safe-tools-allowlist-bypass-audit.md`
