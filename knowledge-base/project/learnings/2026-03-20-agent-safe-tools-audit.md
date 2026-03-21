# Learning: Agent tool in SAFE_TOOLS -- implicit trust without auditability

## Problem

The `Agent` tool was included in the `SAFE_TOOLS` array in `apps/web-platform/server/tool-path-checker.ts`. This meant subagent spawning was auto-allowed by the same code path as genuinely inert tools (Skill, TodoRead, TodoWrite), with no logging, no documented rationale, and no differentiation from tools that truly have zero security surface.

The Agent tool spawns subagents that use path-bearing tools (Read, Write, Edit, Glob, Grep, etc.). While the SDK's three defense layers -- PreToolUse hooks (layer 1), canUseTool callback (layer 2), and bubblewrap sandbox (layer 3) -- all fire for subagent tool calls (confirmed by the `agentID?: string` field in the SDK's `CanUseTool` TypeScript type), the implicit allowance meant:

1. **No audit trail** -- subagent spawns were invisible in server logs.
2. **No documented rationale** -- future maintainers could not verify why Agent was considered safe without re-doing the SDK analysis.
3. **Fragile assumption** -- if a future SDK version stopped routing subagent tool calls through canUseTool, the silent auto-allow would become a real security bypass.

This was **not** a security gap -- all three defense layers were confirmed operational for subagents. It was a code hygiene and auditability issue.

## Solution

1. Removed `"Agent"` from `SAFE_TOOLS`. The array now contains only genuinely inert tools: `["Skill", "TodoRead", "TodoWrite"]`.
2. Added explicit `if (toolName === "Agent")` handler in canUseTool with documented rationale citing SDK type-level proof.
3. Added `SubagentStart` hook for audit logging with sanitized log values (newlines stripped, 200 char limit).
4. Added `options.agentID` to canUseTool signature for subagent context in deny messages.
5. Updated tests: completeness guards, negative Agent test, stale sandbox-hook.test.ts reference.

## Key Insight

When auditing allowlists, distinguish between three categories:

1. **Inert tools** -- no security-sensitive inputs, no side effects. These belong in SAFE_TOOLS (e.g., TodoRead).
2. **Multiplier tools** -- no direct security-sensitive inputs, but spawn contexts that use them. Agent falls here. These need explicit handlers with documented rationale, not silent auto-allow.
3. **Path-bearing tools** -- direct security-sensitive inputs requiring validation. Already handled by FILE_TOOLS.

The critical verification technique: **check the SDK's TypeScript types**. The `CanUseTool` type's `agentID?: string` field is definitive proof that canUseTool fires for subagent tool calls -- stronger evidence than runtime testing.

## Session Errors

1. `npx vitest` failed with rolldown native binding error -- worktree `node_modules` were missing. Fix: `npm install` in the app directory.
2. Pre-existing duplicate `settingSources` property in agent-runner.ts discovered by review agents (not introduced by this PR).

## Tags

category: security-issues
module: web-platform/agent-runner
