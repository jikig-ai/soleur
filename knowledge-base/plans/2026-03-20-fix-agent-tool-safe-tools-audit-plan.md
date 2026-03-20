---
title: "fix: remove Agent from SAFE_TOOLS and add subagent sandbox validation"
type: fix
date: 2026-03-20
semver: patch
---

# fix: remove Agent from SAFE_TOOLS and add subagent sandbox validation

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Problem Statement, Security Model, Proposed Solution, Technical Considerations, MVP)
**Research sources:** SDK TypeScript reference (type definitions), SDK subagents docs, SDK permissions docs, SDK hooks docs, SDK changelog (v0.2.80), codebase analysis

### Key Improvements

1. **Resolved the core unknown**: SDK TypeScript types confirm `canUseTool` IS called for subagent tool uses -- the `CanUseTool` callback receives `agentID?: string` ("If running within a sub-agent, the sub-agent's ID"). This eliminates the "unknown" status of layer 2 in the security model.
2. **Downgraded severity**: All 3 defense layers are confirmed active for subagents. The fix is now purely a code hygiene / auditability improvement, not a security gap closure.
3. **Added `agentID` logging**: The explicit Agent handler should log the `agentID` from the canUseTool options to correlate parent/subagent permission decisions.
4. **Identified `Skill` tool gap**: The `Skill` tool remains in SAFE_TOOLS but loads plugin-defined skills that could contain arbitrary instructions. This is acceptable because skills are developer-defined (not user-controlled), but worth documenting.

### New Considerations Discovered

- The SDK's `CanUseTool` type includes `agentID?: string` -- this is the definitive proof that canUseTool fires for subagent tool calls, not just parent calls
- `AgentDefinition` does NOT have a `canUseTool` field -- subagents always use the parent's callback
- `AgentDefinition` supports `disallowedTools?: string[]` for per-subagent tool restrictions
- The hooks documentation statement "Subagents do not automatically inherit parent agent permissions" refers to `allowedTools` / allow rules (step 4 in the permission chain), not to hooks or canUseTool
- SDK v0.2.63 fixed "MCP replacement tools being incorrectly denied in subagents" -- evidence the SDK actively manages subagent permissions through the same chain

## Overview

The `canUseTool` callback in `agent-runner.ts` classifies `Agent` as a safe tool (via `SAFE_TOOLS` in `tool-path-checker.ts`), auto-allowing it without any validation. The assumption is that subagents spawned via the Agent tool inherit the parent's sandbox configuration. SDK documentation and type definitions confirm this assumption is correct -- all 3 defense layers cover subagents. The fix is a code hygiene improvement for auditability, not a security gap closure.

## Problem Statement

### What the SDK documentation and types confirm

1. **Hooks DO fire for subagent tool calls.** The hooks documentation confirms `agent_id` and `agent_type` fields are populated on hook inputs when firing inside a subagent context. PreToolUse hooks registered on the parent `query()` call fire for tool uses within subagents. This means the `createSandboxHook(workspacePath)` PreToolUse hook correctly intercepts file tool calls from subagents.

2. **`canUseTool` DOES fire for subagent tool calls.** The SDK TypeScript type reference defines `CanUseTool` with an options parameter that includes `agentID?: string` -- documented as "If running within a sub-agent, the sub-agent's ID." This confirms the parent's `canUseTool` callback is invoked for every tool call in subagents, with the subagent's ID passed as context. The `AgentDefinition` type does NOT include a `canUseTool` field, confirming subagents always use the parent's callback.

3. **Subagents can inherit all parent tools by default.** When `tools` is omitted from `AgentDefinition`, the subagent "inherits all available tools." The agent-runner does not define any `agents` config, meaning the `general-purpose` built-in subagent gets all tools. However, `AgentDefinition` supports `disallowedTools` for per-subagent tool restrictions.

4. **Subagents cannot spawn their own subagents.** The SDK docs explicitly state "Don't include `Agent` in a subagent's `tools` array" and the SDK enforces this.

5. **`disallowedTools` applies to subagents.** The `disallowedTools: ["WebSearch", "WebFetch"]` config is enforced at the deny rule level (step 2 in the permission chain), which applies before both `permissionMode` and `canUseTool`.

### Research Insights

**SDK Permission Chain (confirmed via docs):**

```
Step 1: Hooks (PreToolUse) --> can allow, deny, or pass through
Step 2: Deny rules (disallowedTools) --> hard deny, even in bypassPermissions
Step 3: Permission mode --> bypassPermissions approves all; acceptEdits approves file ops
Step 4: Allow rules (allowedTools, settings.json) --> auto-approve listed tools
Step 5: canUseTool callback --> custom logic, receives agentID for subagent calls
```

All 5 steps apply to subagent tool calls. The hooks documentation statement "Subagents do not automatically inherit parent agent permissions" specifically refers to step 4 (allow rules / `allowedTools`) -- it does NOT mean hooks or canUseTool are bypassed.

**SDK Changelog Evidence (v0.2.63):** "Fixed MCP replacement tools being incorrectly denied in subagents" -- this fix demonstrates the SDK actively routes subagent tool calls through the same permission chain, including deny rules.

### Current security model (UPDATED)

The agent-runner has 3 defense layers, all confirmed active for subagents:

| Layer | Mechanism | Covers subagents? | Evidence |
|-------|-----------|-------------------|----------|
| 1 | PreToolUse hooks (`createSandboxHook`) | **Yes** | SDK docs: `agent_id`/`agent_type` populated on hook inputs |
| 2 | `canUseTool` callback (defense-in-depth) | **Yes** | SDK types: `CanUseTool` options include `agentID?: string` |
| 3 | SDK bubblewrap sandbox (`sandbox: {...}`) | **Yes** | Process-level; subagents run in same process tree |

### Why the fix is still valuable

Even though all layers are confirmed active, `Agent` being in `SAFE_TOOLS` has two issues:

1. **Implicit trust**: Auto-allowing Agent without documentation makes it hard to audit why it is allowed. Moving to an explicit handler with comments makes the security decision visible in code review.

2. **SAFE_TOOLS semantic mismatch**: The `SAFE_TOOLS` comment says "no filesystem path inputs" -- while Agent indeed has no path inputs, it spawns subagents that DO have path inputs. The "safe" classification is misleading for a tool that creates new execution contexts.

### Attack surface enumeration

All code paths that touch the Agent tool's security surface:

1. **Parent agent invokes Agent tool** -- hits `isSafeTool("Agent")` in `canUseTool`, auto-allowed (line 285). After fix: hits explicit Agent handler instead.
2. **Subagent invokes file tools (Read, Write, etc.)** -- hits PreToolUse hook (layer 1, confirmed) AND `canUseTool` `isFileTool` check (layer 2, confirmed via `agentID` in options).
3. **Subagent invokes Bash** -- hits PreToolUse hook for env access check (confirmed) AND SDK sandbox for filesystem/network (confirmed).
4. **Subagent invokes unrecognized tool** -- hits deny-by-default in `canUseTool` (confirmed: `canUseTool` fires for subagents).
5. **Subagent invokes Agent tool** -- SDK prevents this (subagents cannot spawn sub-subagents).
6. **Prompt injection via Agent tool prompt** -- subagent gets a fresh context with only its system prompt and the Agent tool's prompt string; no parent conversation history leaks.

**All paths are covered. No security gap exists.**

### Edge Cases

- **SDK version upgrade changes `canUseTool` behavior**: The `SubagentStart` hook provides ongoing visibility. If a future SDK version stops calling `canUseTool` for subagents, the hook logs would show subagent spawns without corresponding `canUseTool` calls in the audit log.
- **New tools added to SDK**: The deny-by-default case in `canUseTool` catches any tool not in `FILE_TOOLS`, not explicitly handled, and not in `SAFE_TOOLS`. This is confirmed to work for subagents.
- **`Skill` tool in SAFE_TOOLS**: Skill loads plugin-defined markdown instructions. This is acceptable because skills are developer-controlled (checked into the repo), not user-controlled. Documented here for audit trail.

## Proposed Solution

### Approach: Remove `Agent` from `SAFE_TOOLS`, add explicit validation

Make the Agent tool's security posture explicit and auditable:

1. **Remove `Agent` from `SAFE_TOOLS`** -- it no longer auto-allows via `isSafeTool()`
2. **Add an explicit Agent tool handler in `canUseTool`** before the deny-by-default return, with a comment documenting the SDK confirmation that canUseTool fires for subagents
3. **Add a `SubagentStart` hook** as defense-in-depth to log subagent spawning events for audit visibility
4. **Update SAFE_TOOLS JSDoc** to clarify the classification criteria
5. **Add tests** verifying Agent is not in SAFE_TOOLS (regression guard)

### Why not block Agent entirely?

The Agent tool is a core SDK feature used by the plugin system (domain leaders delegate to specialist agents via the Task/Agent tool). Blocking it would break the product. The goal is to move it from an implicit auto-allow to an explicit, documented allow with audit logging.

## Technical Considerations

### Architecture impacts

- `tool-path-checker.ts`: Remove `"Agent"` from `SAFE_TOOLS` array; `"Skill"`, `"TodoRead"`, `"TodoWrite"` remain. Update JSDoc to reference the SDK `CanUseTool` type confirmation.
- `agent-runner.ts`: Add explicit `Agent` handling block in `canUseTool` before deny-by-default. Add `SubagentStart` hook.
- `sandbox-hook.ts`: No changes needed -- hooks already fire for subagents.
- Tests: Update completeness guards in `tool-path-checker.test.ts`.

### Performance Considerations

- The explicit `if (toolName === "Agent")` check adds one string comparison per tool call. Negligible overhead.
- The `SubagentStart` hook is a single `console.log` call. No measurable impact.

### Security considerations

- **No regression in file tool protection**: All 3 defense layers are confirmed active for subagent tool calls.
- **Defense-in-depth improvement**: Moving Agent from auto-allow to explicit-allow with documentation makes the security decision auditable.
- **Future tool protection**: The deny-by-default case catches unknown tools for both parent and subagent calls (confirmed).
- **Audit visibility**: `SubagentStart` hook logs provide a runtime record of subagent spawning for incident investigation.

### SDK version dependency

The analysis is based on `@anthropic-ai/claude-agent-sdk` ^0.2.80. The `CanUseTool` type includes `agentID?: string` -- this is a typed API contract. If removed in a future version, TypeScript compilation would catch the change (if the callback uses the field). The `SubagentStart` hook provides additional runtime visibility.

## Acceptance Criteria

- [x] `Agent` is NOT in the `SAFE_TOOLS` array (`apps/web-platform/server/tool-path-checker.ts`)
- [x] `SAFE_TOOLS` JSDoc updated to reference SDK `CanUseTool` type and explain why Agent is handled explicitly
- [x] `canUseTool` has an explicit `Agent` handler with documented rationale (`apps/web-platform/server/agent-runner.ts`)
- [x] `SubagentStart` hook is registered in the `hooks` config to log subagent spawns
- [x] Test: `SAFE_TOOLS` completeness guard updated to `["Skill", "TodoRead", "TodoWrite"]` (`apps/web-platform/test/tool-path-checker.test.ts`)
- [x] Test: `Agent` is NOT a safe tool (explicit negative test)
- [x] Test: `Agent` is NOT a file tool (existing test, verify preserved)
- [x] All existing tests pass

## Test Scenarios

- Given Agent is removed from SAFE_TOOLS, when `isSafeTool("Agent")` is called, then it returns `false`
- Given the explicit Agent handler in canUseTool, when the Agent tool is invoked, then it returns `{ behavior: "allow" }`
- Given the canUseTool callback, when an unrecognized tool is invoked, then it returns `{ behavior: "deny" }` (unchanged)
- Given the SubagentStart hook, when a subagent is spawned, then a log entry is emitted with agent_id and agent_type
- Given the SAFE_TOOLS completeness guard, when SAFE_TOOLS is read, then it contains exactly `["Skill", "TodoRead", "TodoWrite"]`

## MVP

### apps/web-platform/server/tool-path-checker.ts

```typescript
/**
 * SDK tools with no filesystem path inputs -- allowed without path checks.
 *
 * - Skill: plugin-level tool (no exported SDK schema, no path args)
 * - TodoRead: in-memory task list (no exported SDK schema, no path args)
 * - TodoWrite: in-memory task list (TodoWriteInput: todos[] array only)
 *
 * Agent is NOT in this list despite having no path args. It spawns
 * subagents that DO use path-bearing tools. The parent's canUseTool
 * and PreToolUse hooks fire for subagent tool calls (confirmed via
 * SDK CanUseTool type: options.agentID is populated for subagent calls).
 * Agent is handled by an explicit block in canUseTool for auditability.
 * See #910.
 */
export const SAFE_TOOLS = ["Skill", "TodoRead", "TodoWrite"] as const;
```

### apps/web-platform/server/agent-runner.ts (canUseTool addition)

```typescript
// Agent tool: spawns subagents that run within the same SDK
// sandbox (bubblewrap, filesystem restrictions, network policy).
// Both PreToolUse hooks and this canUseTool callback fire for
// subagent tool calls (SDK CanUseTool type confirms via
// options.agentID). Explicit allow replaces the prior SAFE_TOOLS
// auto-allow for auditability. See #910.
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
      const subInput = input as Record<string, unknown>;
      console.log(
        `[sec] Subagent started: agent_id=${subInput.agent_id}, ` +
        `type=${subInput.agent_type}`
      );
      return {};
    }],
  }],
},
```

## References

- Issue: [#910](https://github.com/jikig-ai/soleur/issues/910)
- Related: [#895](https://github.com/jikig-ai/soleur/issues/895), [#876](https://github.com/jikig-ai/soleur/issues/876)
- **SDK TypeScript reference** (definitive): `CanUseTool` type includes `agentID?: string` -- [platform.claude.com/docs/en/agent-sdk/typescript#can-use-tool](https://platform.claude.com/docs/en/agent-sdk/typescript#can-use-tool)
- SDK subagents docs: [platform.claude.com/docs/en/agent-sdk/subagents](https://platform.claude.com/docs/en/agent-sdk/subagents)
- SDK permissions docs: [platform.claude.com/docs/en/agent-sdk/permissions](https://platform.claude.com/docs/en/agent-sdk/permissions)
- SDK hooks docs: [platform.claude.com/docs/en/agent-sdk/hooks](https://platform.claude.com/docs/en/agent-sdk/hooks)
- SDK changelog v0.2.63: "Fixed MCP replacement tools being incorrectly denied in subagents"
- File: `apps/web-platform/server/tool-path-checker.ts:49`
- File: `apps/web-platform/server/agent-runner.ts:285`
- Learning: `knowledge-base/learnings/2026-03-20-safe-tools-allowlist-bypass-audit.md`
