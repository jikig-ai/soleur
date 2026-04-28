---
date: 2026-04-27
module: apps/web-platform
problem_type: design_decision
component: typescript_types
symptoms:
  - "51 TS errors after adding branded IDs to WSMessage discriminated union"
  - "string literals like 'p-1' fail assignment to PromptId / ConversationId / SpawnId"
  - "Producer code (soleur-go-runner.ts) and test fixtures hit cross-confusion friction"
root_cause: brand_at_wrong_boundary
severity: high
tags: [typescript, branded-types, wire-protocol, zod, websocket]
synced_to: []
related_pr: 2902
related_issues: [2885]
---

# Branded TypeScript IDs belong at internal API boundaries, not wire-protocol types

## Problem

Stage 3 of the Command Center WSMessage protocol extension (#2885) prescribed branded TypeScript IDs (`SpawnId`, `PromptId`, `ConversationId`) on the variants of the wire-protocol discriminated union (`WSMessage`):

```typescript
| { type: "subagent_spawn"; parentId: SpawnId; leaderId: DomainLeaderId; spawnId: SpawnId }
| { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; ... }
```

The intent (closing the cross-confusion gap from #2858 review) was sound. The implementation revealed a deeper design issue: putting the brand on the wire-type boundary produced **51 TypeScript errors** across server runtime (`soleur-go-runner.ts`) and 4 test files. Plain string literals like `"p-1"`, `"conv-1"`, `"nope"` cannot widen to `string & { readonly [PromptIdBrand]: true }` without an explicit mint helper or cast at every construction site.

## Root cause

Brands solve **cross-confusion at function boundaries** (a `register(promptId: PromptId, conversationId: ConversationId)` callsite cannot accidentally swap the args). They do **not** solve any wire-protocol concern because:

1. **JSON has no concept of brands.** `JSON.stringify({ promptId: x })` drops the brand into a plain string. The receiver's `JSON.parse` cannot recover it. So a brand on a wire-type variant provides zero protection across the network.
2. **The wire-type union is the boundary between untyped JSON and typed code.** Forcing every producer (server emit site, test fixture) to mint at the boundary inverts the cost: every call pays the friction tax to satisfy a type-system constraint that adds no runtime safety.
3. **The Zod parser is the actual boundary gate.** `parseWSMessage(rawJson)` validates shape and field types; if it accepts the frame, downstream code can branch on `msg.type` and read fields. Whether those fields are typed `PromptId` or `string` doesn't change runtime behavior — it only changes friction.

## Solution

WSMessage carries plain `string` for IDs:

```typescript
| { type: "subagent_spawn"; parentId: string; leaderId: DomainLeaderId; spawnId: string }
| { type: "interactive_prompt"; promptId: string; conversationId: string; ... }
```

Branded utility types remain available via `lib/branded-ids.ts` for use at **internal API boundaries** where cross-confusion is a real risk:

```typescript
// lib/branded-ids.ts — exported for use at internal boundaries
export type SpawnId = string & { readonly [SpawnIdBrand]: true };
export type PromptId = string & { readonly [PromptIdBrand]: true };
export type ConversationId = string & { readonly [ConversationIdBrand]: true };

// Producer site that benefits from the brand:
class PendingPromptRegistry {
  register(args: { promptId: PromptId; conversationId: ConversationId; ... }) { ... }
}
```

The Zod schema (`lib/ws-zod-schemas.ts`) parses incoming frames with `z.string()` — no `.transform(mintXxxId)` — so consumers don't pay a per-frame minting cost. If a downstream API genuinely requires a branded type, the call site mints once at that boundary.

## The heuristic

> Brands belong where the **type checker** can prevent a real cross-confusion bug. They do not belong where every value is going to round-trip through JSON anyway.

Concretely: brand at function-signature boundaries (registries, schedulers, ID minters), NOT at wire-protocol union variants.

## Prevention

- When a plan prescribes branded types on a discriminated union, ask: "Does any consumer of this union genuinely benefit from the brand, or does every consumer immediately read the field as a plain string?"
- If the union represents a wire format (WS frame, REST payload, JSON-RPC), default to plain `string` for IDs and lift the brand into named function-signature types where it discriminates between two same-shaped slots that must not be swapped.
- The Zod 4 caveat that surfaced this design question (non-generic `discriminatedUnion` discriminator) is a separate concern — the bidirectional `_SchemaCovers` compile-time assertion still pins schema/union drift even without branded fields.

## Session Errors

1. **Bash tool CWD non-persistence** — `cd apps/web-platform && rg ...` failed when a prior `cd` had moved CWD. **Recovery:** pwd verification + absolute paths. **Prevention:** Already covered by `cq-for-local-verification-of-apps-doppler` (single-Bash-call pattern). Apply the same pattern to grep/test invocations in worktrees.
2. **Map<string, number> inference broke 30+ tests** when `applyStreamEvent` signature tightened to `Map<DomainLeaderId, number>`. **Recovery:** introduced `makeStreams()` helper, bulk-replaced fixture Maps. **Prevention:** Already covered by `cq-raf-batching-sweep-test-helpers`'s analog — when tightening a parameter type that fixtures construct via untyped literals, sweep all fixture-construction sites in the same edit.
3. **Helper name self-shadowing (TS7022)** — first named the helper `streams()`; every test had `const streams = streams([...])`. **Recovery:** renamed helper to `makeStreams`. **Prevention:** When introducing a fixture-builder helper, grep the file for the chosen name as a local variable before committing.
4. **Branded IDs in WSMessage produced 51 TS errors** — see main learning above. **Recovery:** reverted brands from WSMessage, kept utility types. **Prevention:** Apply the heuristic in this learning at plan-deepen time, before brand annotations propagate to all variants.
5. **Duplicate `WSMessage` imports** in `cc-dispatcher.ts` and `ws-handler.ts` after adding `Extract<WSMessage,...>` aliases. **Recovery:** removed duplicate. **Prevention:** When adding a new `import type { WSMessage } from "@/lib/types"` line, grep the file first for existing imports.
6. **`KNOWN_WS_MESSAGE_TYPES` allowlist gap from Stage 2** — `interactive_prompt` and `interactive_prompt_response` were in `WSMessage` but not in the allowlist; the `_Exhaustive` proof did not catch it because the existing union shape was used as the inferred Set type. Surfaced via `ws-known-types-guard.test.ts` failure. **Recovery:** added all 6 new entries + updated test fixture. **Prevention:** Allowlist runtime tests must enumerate the expected set verbatim (not derive it from the union); test failures on PR diff are the gate.
7. **`next lint` interactive ESLint setup prompt** — no ESLint config in worktree, command hung. **Recovery:** noted as pre-existing, skipped. **Prevention:** N/A — pre-existing condition.

## See also

- `cq-raf-batching-sweep-test-helpers` (analog for type-tightening sweeps)
- `cq-write-failing-tests-before` (TDD gate this PR followed)
- `cq-union-widening-grep-three-patterns` (Stage 3.8 grep procedure)
- `lib/branded-ids.ts` (the surviving utility-type module)
- PR #2902 / Issue #2885 (Stage 3 WSMessage protocol extension)
