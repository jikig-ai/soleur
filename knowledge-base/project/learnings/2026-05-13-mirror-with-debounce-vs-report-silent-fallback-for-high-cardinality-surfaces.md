---
title: When to use mirrorWithDebounce vs raw reportSilentFallback for silent-failure mirrors
date: 2026-05-13
category: best-practices
module: observability
issue: 2909
pr: 3720
related_pr: 3639
tags: [observability, sentry, debounce, silent-failure, mirror, cc-router]
---

# Learning: Pick mirrorWithDebounce when the silent-failure surface is per-(user, event-class) high-cardinality

## Problem

PR #3720 (Phase 1 MCP tier-classify for cc-soleur-go) wired a Sentry mirror at `dispatchSoleurGo.onToolUse` to catch the silent-failure case where a router-dispatched skill attempts a `mcp__soleur_platform__*` tool not registered in `mcpServers`. The initial implementation used `reportSilentFallback` directly:

```typescript
if (shouldMirrorUnregisteredPlatformToolUse(block.name, [])) {
  reportSilentFallback(null, {
    feature: "cc-mcp-tier",
    op: "unregistered-tool-invoked",
    message: `cc-router skill attempted unregistered platform tool ${block.name}`,
    extra: { toolName: block.name, userId, conversationId, leaderId: CC_ROUTER_LEADER_ID },
  });
}
```

Plan-review (architecture-strategist) flagged it as P2: `reportSilentFallback` does NOT debounce — each invocation fires a new pino + Sentry event. If a misconfigured leader skill loops on the same unregistered tool (the model gets a `tool_result` error from the SDK, then the skill retries the same call rather than recovering), the mirror floods Sentry. 1 QPS sustained for 24 hours = 86,000 events per user per failure mode.

The fix: switch to `mirrorWithDebounce` (per-`(userId, errorClass)` 5-minute TTL).

## Solution

```typescript
if (shouldMirrorUnregisteredPlatformToolUse(block.name, CC_REGISTERED_PLATFORM_TOOL_NAMES)) {
  const safeToolName = sanitizeToolNameForLog(block.name);
  mirrorWithDebounce(
    null,
    {
      feature: "cc-mcp-tier",
      op: "unregistered-tool-invoked",
      message: `cc-router skill attempted unregistered platform tool ${safeToolName}`,
      extra: { toolName: safeToolName, toolUseId: block.toolUseId, userId, conversationId, leaderId: CC_ROUTER_LEADER_ID, mcpAllowlistConfigured: Boolean(process.env.CC_MCP_ALLOWLIST?.trim()) },
    },
    userId,
    "cc-mcp-tier:unregistered-tool",  // errorClass dedup key
  );
}
```

`mirrorWithDebounce(err, ctx, userId, errorClass)` lives at `apps/web-platform/server/observability.ts:328`. First call mirrors normally via `reportSilentFallback`; subsequent calls within 5 minutes for the same `(userId, errorClass)` key are no-ops. The application path (the SDK's tool_result error → model's recovery prose) is unaffected — only the observability event is deduplicated.

## Key Insight

`reportSilentFallback` and `mirrorWithDebounce` look interchangeable but encode different failure-mode assumptions:

| Primitive | Use when... |
|-----------|-------------|
| `reportSilentFallback` | The silent-failure condition is **bounded per invocation** — a one-off RPC retry exhaustion, a config-validation rejection on a single boot, an enum-out-of-range that the runtime path then aborts. Each event is meaningful and you want to see every one. |
| `mirrorWithDebounce` | The silent-failure condition is **high-cardinality per `(userId, errorClass)`** — a model-driven retry loop, a runaway per-frame iterator, a periodic-poll degraded path. You need to know IT happened, but not 10,000 times in 10 minutes. |
| `mirrorP0Deduped` | The silent-failure condition is **a security/compliance violation** — Art. 33 breach-notification clock anchor, cross-tenant write attempt, GDPR-category breach. Key includes `conversationId` so two cross-tenant attempts against different conversations from the same user are NOT coalesced; 1-hour TTL provides ~72 distinct samples for the same `(user, op, conv)` triple within the Art. 33 72-hour notification window. |

**The decision class:** look at the failure mode's natural emission cardinality, not the call-site frequency. A site that fires once per turn could still be 100 events per minute for a debugging-stuck user — that's where the per-`(userId, errorClass)` debounce belongs. **The iterator-hook test is the giveaway:** if the call site is inside a `for await` loop over model-emitted blocks, the natural cardinality is per-turn × per-tool-use-block — high. Default to `mirrorWithDebounce`.

The asymmetric cost of getting this wrong:

- **Wrong choice of `reportSilentFallback` on a high-cardinality surface:** Sentry rate-limits kick in; signal is buried; bill spikes; on-call gets paged for noise.
- **Wrong choice of `mirrorWithDebounce` on a low-cardinality surface:** you see one event instead of three within 5 minutes. Almost no information loss.

The cost is asymmetric → default to debounce for any uncertain surface and add per-invocation precision only when telemetry shows the throttle was too aggressive.

The `errorClass` key is load-bearing: a globally unique slug like `cc-mcp-tier:unregistered-tool` (NOT just `unregistered-tool`) so future features picking the same slug accidentally cannot collide TTL buckets across features for the same user. See `observability.ts:223-237` for the canonical registry of `errorClass` strings — extend it when adding a caller.

## Session Errors

- **TSC error on `block.id`** — added `toolUseId: block.id` to Sentry extras; the block shape is `{ name, input, toolUseId }` with no `id` field. **Recovery:** changed to `block.toolUseId`. **Prevention:** when extending a typed callback's payload, read the parameter type signature before referencing fields. Already covered by tsc-as-gate; no new rule needed.
- **Literal U+2028/U+2029 bytes in regex** — first Edit wrote the regex character class with raw Unicode bytes instead of `  ` escapes. **Recovery:** Python byte-replacement to escape form (`\\u2028\\u2029`). **Prevention:** `cq-regex-unicode-separators-escape-only` already covers this — should have started with escape syntax. The Edit tool's display flattens these to whitespace, so visual review post-edit cannot catch them; the byte-level check (`xxd`) or grepping for `\\u20` in the source is the only confirmation.

## Cross-references

- `apps/web-platform/server/observability.ts:135` — `reportSilentFallback` (one-shot mirror)
- `apps/web-platform/server/observability.ts:215-237` — `MIRROR_DEBOUNCE_MS` + errorClass registry
- `apps/web-platform/server/observability.ts:328` — `mirrorWithDebounce` (per-`(userId, errorClass)` 5-min TTL)
- `apps/web-platform/server/observability.ts:351+` — `mirrorP0Deduped` (per-`(userId, op, conversationId)` 1-hour TTL, fatal severity, Art. 33 clock anchor)
- PR #3639 — the F3 refactor that consolidated both wrappers onto a shared `TtlDedupMap`
- Related learning: `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md` — why this surface needs an observability hook AT ALL (the SDK doesn't fire canUseTool for unknown MCP tools, so iterator-hook is the only site)
