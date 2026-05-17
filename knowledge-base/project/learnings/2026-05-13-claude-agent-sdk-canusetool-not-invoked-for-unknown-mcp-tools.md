---
title: Claude Agent SDK does NOT invoke canUseTool for unknown MCP tools — observability must hook the message iterator instead
date: 2026-05-13
category: best-practices
module: claude-agent-sdk
issue: 2909
plan: knowledge-base/project/plans/2026-05-13-feat-mcp-tier-classify-cc-soleur-go-phase-1-plan.md
tags: [claude-agent-sdk, mcp, canUseTool, silent-failure, observability, plan-review]
---

# Learning: `canUseTool` is not the right hook for "agent attempted unregistered MCP tool"

## Problem

During the V2-13 brainstorm (`#2909`), the CTO framing-time assessment recommended adding a Sentry-mirror branch at `permission-callback.ts createCanUseTool` to catch the case where a router-dispatched skill attempts a `mcp__soleur_platform__*` tool that isn't registered in `mcpServers`. The intent: close a silent-failure surface — today the SDK returns `unknown tool` to the model without any Sentry signal, and the user sees an unhelpful assistant response with no diagnostic trail.

The plan v1 wired FR2 to `createCanUseTool` accordingly. Plan-review (Kieran) caught it as **P0**: the entire branch would have shipped dead.

## Solution

Read the SDK type definitions before designating a guard site for SDK-mediated tool flows. From `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:122-140`:

```typescript
type CanUseTool = (
  toolName: string,
  input: ToolInput,
  options: { signal: AbortSignal; suggestions?: PermissionUpdate[] },
) => Promise<PermissionResult>;
```

`CanUseTool` is "called before each tool execution to determine if it should be allowed." When `mcpServers` is empty AND the model emits a `tool_use` block referencing `mcp__soleur_platform__kb_share_list`, the tool **does not exist** — there is nothing to execute. The SDK's model-validation loop rejects the call with a `tool_result` error (`tool not found`) and `canUseTool` is **never invoked** because there is no registered tool to gate.

Implication: a Sentry mirror at `permission-callback.ts:536` (the existing `if (ctx.platformToolNames.includes(toolName))` branch) is reachable only when at least one platform tool is registered. With cc-dispatcher.ts:977 passing `platformToolNames: []`, the branch is unreachable in the router path.

**The correct site** for the "unregistered tool attempted" observability is the SDK iterator hook in `cc-dispatcher.ts dispatchSoleurGo`'s `for await` loop. Each iteration yields message blocks; when a `tool_use` block names `mcp__soleur_platform__<unknown>`, fire `reportSilentFallback` from there. This sees the model's intent before the SDK's rejection swallows it.

## Key Insight

**`canUseTool` gates the execution of REGISTERED tools, not the model's INTENT to call any tool.** Two questions are easy to conflate:

- "Did the model TRY to call X?" — observable at the SDK message iterator (`tool_use` blocks).
- "Should X be allowed to execute?" — `canUseTool` (only fires after the SDK has accepted the tool registration).

When the framing question is "make silent-failure visible," the iterator is the right surface. When it is "deny an action that would otherwise succeed," `canUseTool` is correct.

This conflation is easy at framing time because both surfaces sit near "tool authorization" in the mental model. The fix is mechanical: **before prescribing a guard at a specific call-site for SDK-mediated tool flows, read the SDK's `.d.ts` types and trace the callback's invocation conditions.** Five minutes at plan-write time saves a P0 review finding (or worse, a dead branch shipping to prod).

This generalizes beyond MCP tools: any third-party SDK that wraps tool/function dispatch (OpenAI function calling, LangChain agent executors, Vercel AI SDK) will have a similar bifurcation between "model intent" and "execution authorization." Treat the SDK type file as the canonical source for "when does this callback fire?" — docs and READMEs typically describe the happy path and omit the negative-space cases.

## Session Errors

- **Sentry-mirror site initially planned at `permission-callback.ts createCanUseTool`** — caught by Kieran plan-review (P0). **Recovery:** flipped FR2 to Candidate B (SDK iterator hook in `dispatchSoleurGo`'s `for await` loop). **Prevention:** when prescribing a guard at a chosen call-site for SDK-mediated tool flows, read the SDK's `.d.ts` types and trace the callback's invocation conditions BEFORE designating the site. The plan skill's Sharp Edges already cover guard-tracing from entry-points (PR #3263); this is the SDK-callback-semantics complement: trace the callback's invocation conditions from the SDK source, not just from internal codebase threading.
- **Initial plan overengineered for a Phase 1 with zero behavioral delta** — separate `cc-mcp-allowlist.ts` file, custom `McpAllowlistError` class, hardcoded `KNOWN_PLATFORM_TOOLS` set, drift-guard test, 19 ACs. Three plan reviewers (DHH + Kieran + code-simplicity) converged on cuts. **Recovery:** rewrote inline (~10-LoC function in `cc-dispatcher.ts`), plain `Error`, denylist-only validation in Phase 1, 16 ACs. **Prevention:** apply "what does the smallest plan look like for a no-behavioral-delta Phase 1?" before drafting. Bias to inline single-file changes when the surface is tiny; new files earn their existence by passing a "would this be reused elsewhere?" test.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-13-feat-mcp-tier-classify-cc-soleur-go-phase-1-plan.md` §"Research Reconciliation" + Phase 2.2.4.
- SDK type definitions: `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:122-140` (CanUseTool signature).
- Related learning (guard-placement traceability from the OTHER direction — internal-codebase): `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md` (PR #3263). The two together form a complete picture: trace BOTH the codebase entry-points (where the value comes from) AND the SDK callback's invocation conditions (where the guard's hook can/cannot fire).
- `cc-dispatcher.ts:533-610` (the platform-tools `canUseTool` branch — correct for the legacy path, dead for the cc-router).
- `observability.ts:135 reportSilentFallback` (the canonical Sentry-mirror primitive).
