---
date: 2026-04-27
issue: 2885
parent_issue: 2853
parent_pr: 2858
parent_plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
branch: feat-one-shot-2885-stage-3-wsmessage
type: feature
classification: refactor + protocol-extension
deepened: 2026-04-27
---

# Stage 3 — WSMessage protocol extension (branded IDs + Zod parsing)

## Deepen-Plan Enhancement Summary

**Deepened on:** 2026-04-27 (same session as initial draft)
**Sections enhanced:** Research Reconciliation, Hypotheses, Phase 1, Phase 3, Phase 5, Test Strategy, Risks
**Verification methods used:** direct codebase grep, `node_modules` inspection, WebSearch (Zod 4 API)

### Critical findings folded back into the plan

1. **`zod` is already at v4.3.6 in `apps/web-platform/node_modules/`**, pulled transitively via a peer dep. NOT in `apps/web-platform/package.json` direct deps. Plan corrected: promote to direct dep (still a `package.json` change to make the dependency explicit and protect against transitive removal on lockfile regen). Plan now targets **Zod 4 API**, not Zod 3. Zod 4 changes that matter:
   - `.brand<"PromptId">()` works, with optional `<"PromptId", "in" | "out" | "inout">` modes (Zod 4.2+).
   - `z.discriminatedUnion("type", [...])` discriminator parameter is **no longer generic** in Zod 4 — TypeScript cannot pull the discriminator value to determine variant options the way Zod 3 did. Implication: bidirectional exhaustiveness check (`_SchemaCovers`) becomes load-bearing for catching schema/union drift; we cannot rely on TS inference alone the way the Zod 3 version of this plan would.
   - Source: <https://github.com/colinhacks/zod/issues/5024>, Zod 4 docs at <https://zod.dev/api>.
2. **Wire-field convention is camelCase, not snake_case.** The original draft prescribed renaming `promptId` → `prompt_id` etc. to match a snake_case pattern. Direct grep of `lib/types.ts` shows the existing `WSMessage` convention is **camelCase for fields, snake_case for the `type` discriminator**: `resume_session.conversationId`, `session_started.conversationId`, `session_resumed.resumedFromTimestamp`, `usage_update.totalCostUsd`. Corrected: new variants keep camelCase (`promptId`, `conversationId`, `parentId`, `spawnId`, `leaderId`). **This is a major delta from the source plan** (`2026-04-23-...-plan.md` Stage 3 used `parent_id` / `spawn_id` / `prompt_id` / `conversation_id` snake_case). The source plan is wrong; this plan corrects.
3. **`activeLeaderIds` is already a `useMemo`** (verified `ws-client.ts:181`) — only fix needed is dropping the `as DomainLeaderId[]` cast on line 182. Source plan task 3.9 ("REFACTOR: derive `activeLeaderIds` via `useMemo`") is already done; only the cast removal remains. Plan narrowed accordingly.
4. **Test rename surface is large but localized.** `test/cc-interactive-prompt-response.test.ts` has 44 references to `promptId`/`conversationId`; `test/cc-dispatcher.test.ts` has 12; `test/soleur-go-runner-interactive-prompt.test.ts` has 7. Since wire fields stay camelCase (per #2), these references DO NOT need to be renamed — the snake_case rename burden disappears. Phase 5 simplified.
5. **Reconciliation table line-count drift.** The original draft cited specific line ranges (`lib/types.ts:84-115`, `ws-client.ts:329-440`, `chat-state-machine.ts:42-216`) which are stale vs. worktree HEAD. Per `cq-code-comments-symbol-anchors-not-line-numbers`, all references converted to symbol anchors.

### New considerations discovered

- **Zod 4 `discriminatedUnion` cannot infer per-variant types from a tuple of schemas the way Zod 3 did.** Mitigation: write the schema as `z.discriminatedUnion("type", [interactivePromptAskUserSchema, interactivePromptPlanPreviewSchema, ...])` with each branch as a named `z.object({...})` exported individually. This survives the Zod 4 inference change and stays grep-able.
- **Test mocks of `Map<string, number>`.** Sweep for `new Map<string,` and `Map<string, number>` in `test/chat-state-machine.test.ts` and `test/ws-client.test.ts` before the Phase 4.2 type tightening — single-edit pass per `cq-raf-batching-sweep-test-helpers`.

## Overview

Extend the Command Center WebSocket protocol with the new event variants designed in PR #2858 and document-only deferred to a follow-through. Specifically:

1. Inline the discriminated `interactive_prompt` / `interactive_prompt_response` sub-union (currently a feature-local shim at `apps/web-platform/server/cc-interactive-prompt-types.ts`) into the canonical `WSMessage` discriminated union in `apps/web-platform/lib/types.ts`.
2. Add four additional variants the source plan calls for: `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`.
3. Introduce **branded ID** types (`SpawnId`, `PromptId`, `ConversationId`) so identifier provenance is enforced by the type system at producer/consumer sites (closes the lift-everything-to-strings vs. cross-confusion gap from #2858 review).
4. Introduce **Zod parsing at the WS boundary** in `ws-client.ts:onmessage` — replace the `JSON.parse(...) as WSMessage` cast with a strict, fail-closed schema parse; report Sentry on rejection (extends the current `isKnownWSMessageType` runtime guard with full payload validation).
5. Extend `chat-state-machine.ts:applyStreamEvent` and `ws-client.ts:chatReducer` with reducer cases + `: never` exhaustiveness rails for the new variants.
6. **Fold in #2225** — re-key `activeStreams` from a stringly-keyed `Map<string, number>` to a typed composite-key form, derive `activeLeaderIds` via `useMemo`, and remove `as DomainLeaderId[]` casts.
7. **Delete** `apps/web-platform/server/cc-interactive-prompt-types.ts` — the shim's reason-to-exist disappears once `WSMessage` carries the structured variants natively. Update the 7 importers (4 server, 3 test) to use canonical types from `lib/types.ts`.

This is a typed-protocol refactor: the wire format already exists (Stage 2 ships `interactive_prompt` / `interactive_prompt_response` with `payload: unknown` + `response: unknown`); Stage 3 strips the `unknown` and replaces it with discriminated payload sub-unions plus runtime parsing.

**Non-goals (deferred):**

- Server-side text-delta coalescing (rAF batching at 16-32ms intervals) — source plan task 3.10. Folded into a separate follow-through (will be filed as part of this PR if not already tracked) since it's a server-emit perf change orthogonal to the type refactor.
- Chat-UI bubble components (Stage 4 of the source plan) — separate issue, separate PR.
- Server-side emission of `subagent_spawn` / `subagent_complete` / `workflow_started` / `workflow_ended` from `soleur-go-runner.ts` — Stage 3 lands the types and client reducers; the runner emit sites are wired in Stage 4 / Stage 5 work since they need the corresponding chat-UI surfaces to do anything visible.

  **Rationale for shipping types ahead of producers:** the type extensions are zero-cost when the server doesn't emit them (the reducer `case` is dead code until producers fire). Landing them now (a) unblocks the cc-interactive-prompt-types.ts deletion which #2858 review explicitly called for, (b) lets Stage 4 component work proceed with strict types instead of `unknown`, (c) makes the V2 MCP-tool counterparts (filed as deferrals from #2858 review) easier to reason about. The `: never` rail catches missing reducer cases at compile time the moment a producer is wired.

## Research Reconciliation — Spec vs. Codebase

| Source-plan / spec claim | Codebase reality (worktree HEAD) | Plan response |
|---|---|---|
| Stage 3.4: "implement `branded-ids.ts` + `ws-zod-schemas.ts` (new files)". | Neither file exists. `zod` is **transitively installed at v4.3.6** in `apps/web-platform/node_modules/` (peer dep of another package), but **NOT in `apps/web-platform/package.json` direct deps**. No source file imports zod yet. | Promote `zod` to a direct dep in `apps/web-platform/package.json` (pinned to `4.3.6` exact, no `^`). Both new files created under `apps/web-platform/lib/` using the **Zod 4 API** (`.brand()` modes, schema-side `_SchemaCovers` exhaustiveness because v4 discriminator is non-generic — see "Zod 4 caveats" in Risks). |
| Stage 3.5: "extend `WSMessage` and `ChatMessage` unions with discriminated sub-unions" — references `lib/types.ts:84-115`. | `WSMessage` lives at `lib/types.ts:85-147`; the Stage 2 shim variants (`interactive_prompt` / `interactive_prompt_response` with `payload: unknown` / `response: unknown`) are already inlined at L133-146. | Replace the two `unknown`-shape lines with the discriminated sub-union. Add four new variants. Per `cq-code-comments-symbol-anchors-not-line-numbers`, every plan reference uses symbol anchors (`WSMessage`, `applyStreamEvent`, `chatReducer`), not line numbers. |
| Stage 3.6: "add reducer cases + activeStreams re-key (folds in #2225)". | `chat-state-machine.ts:ChatMessage` is a 2-variant union (`text` \| `review_gate`); `activeStreams: Map<string, number>` keyed by `DomainLeaderId` (string). The hook in `ws-client.ts` currently derives `activeLeaderIds` via `useMemo(() => Array.from(chatState.activeStreams.keys()) as DomainLeaderId[], ...)` — already a `useMemo` BUT with an unsafe cast. | (a) Tighten key type to `DomainLeaderId` (the simple win #2225 calls for). (b) Stage 3 does NOT yet need a composite `${parent_id}:${leader_id}` key — that becomes load-bearing only when Stage 4 renders nested children. Defer the composite re-key until Stage 4 actually needs it (carry the simpler `DomainLeaderId` keying through Stage 3). (c) Drop the `as DomainLeaderId[]` cast. **This narrows the source plan's "Stage 3.6 + #2225" — composite keying moves to Stage 4.** |
| Stage 3.7: "replace WS `onmessage` cast with Zod parse" — references `ws-client.ts:329-440`. | `onmessage` lives at `ws-client.ts:317-467`; existing runtime guard is `isKnownWSMessageType` (allowlist over `type` only — payload not validated). Sentry breadcrumb already wired via `reportSilentFallback`. | Replace the per-`type` allowlist with a full `wsMessageSchema.safeParse(parsed)`. On failure: same `reportSilentFallback` Sentry breadcrumb (compatible signal). Keep the `isKnownWSMessageType` allowlist as a redundant fast-path check to preserve the existing observability shape during rollout. |
| Stage 3.8: "grep three patterns to find consumer if-ladders". | Plan-time grep across `apps/web-platform/{lib,server,components}/`: `\.kind === "` matches 3 sites (`server/kb-reader.ts:384-385` for `KBSearchResult.kind` — unrelated; `server/soleur-go-runner.ts:711` for `ConversationRouting.kind === "soleur_go_active"` — unrelated). `\?\.kind === "` matches 0 sites. **No `interactive_prompt.kind` if-ladder in client/server consumer code.** The consumer pattern for the `kind` discriminator is `switch (event.kind)` inside `handleInteractivePromptResponse` (`server/cc-interactive-prompt-response.ts`) — already exhaustive, no widening risk. | Stage 3.8 grep result is "no widening required". Document the grep output in §Test Strategy so the implementer doesn't repeat the search. |
| Source plan Stage 3 references "delete `cc-interactive-prompt-types.ts`" implicitly (its TODO comment). | 7 importers exist (verified by `grep "cc-interactive-prompt-types"`): `server/cc-dispatcher.ts`, `server/ws-handler.ts`, `server/cc-interactive-prompt-response.ts`, `server/soleur-go-runner.ts`, `test/cc-dispatcher.test.ts`, `test/cc-interactive-prompt-response.test.ts`, `test/soleur-go-runner-interactive-prompt.test.ts`. The exhaustiveness check `_AssertKindsMatch` in the shim (lines 59-66) is load-bearing — must be ported to the canonical types or replaced with an equivalent in `pending-prompt-registry.ts`. | Each importer rewritten to import from `@/lib/types`. The `_AssertKindsMatch` exhaustiveness check is **ported into `lib/types.ts`** alongside the new discriminated union (compile-time enforcement that `WSMessage` `interactive_prompt.kind` matches `InteractivePromptKind` from `pending-prompt-registry.ts`). File deleted in the same commit. |
| Stage 3.10: "server-side text-delta coalescing 16-32ms rAF". | `agent-runner.ts` and `soleur-go-runner.ts` emit `stream` events directly per SDK delta. No coalescing layer. | **Deferred — see Non-goals.** Filing tracking issue if not already covered by an existing perf issue (verify at plan time). The reasoning: stream coalescing is an emission-side concern; this PR is a typed-protocol concern. Mixing them invites rollback complexity. |
| `WorkflowEndStatus` enum: `"completed" \| "user_aborted" \| "cost_ceiling" \| "idle_timeout" \| "plugin_load_failure" \| "sandbox_denial" \| "runner_crash" \| "runner_runaway" \| "internal_error"`. | `soleur-go-runner.ts` and `cc-dispatcher.ts` already use these specific status strings in comments and emit logic but have no shared enum type — they're stringly typed today. | New `WorkflowEndStatus` exported from `lib/types.ts`; producers in `soleur-go-runner.ts` adopt the type (PR-touch limited to the emit sites). |
| `WorkflowName`. | Already exists in `apps/web-platform/server/conversation-routing.ts:26` as a TS union, exported. Used by `cc-dispatcher.ts`, `ws-handler.ts`. | Re-export from `lib/types.ts` so client types don't depend on `server/*`. (Move the type or re-export — pick the lower-risk option at implementation time; see Stage 3 Files to Edit.) |

## Open Code-Review Overlap

- **#2225** — `refactor(chat): tighten activeStreams key type and derive activeLeaderIds via useMemo` → **Fold in.** This plan re-keys `activeStreams` to `Map<DomainLeaderId, number>` and removes the `as DomainLeaderId[]` cast. Add `Closes #2225` to the PR body.
- **#2191** — `refactor(ws): introduce clearSessionTimers helper + add refresh-timer jitter and consecutive-failure close` → **Acknowledge, defer.** Touches `server/ws-handler.ts` but is a session-lifecycle refactor orthogonal to type-protocol changes. Stays open. Annotate via `gh issue comment` with cross-link to this plan.

## Hypotheses

The plan rests on three load-bearing assumptions verified at plan/deepen time:

1. **`zod` v4.3.6 (already in `node_modules` transitively) parses discriminated unions with branded-string fields.** Verified via Zod 4 docs (<https://zod.dev/api>) — `z.discriminatedUnion("type", [z.object({...}), ...])` is supported; `z.string().brand<"PromptId">()` produces the branded `string & {[Symbol]: "PromptId"}` shape this plan needs. **Caveat:** Zod 4 discriminator parameter is non-generic (<https://github.com/colinhacks/zod/issues/5024>), so per-variant inference at the schema-tuple level is weaker than Zod 3 — the bidirectional `_SchemaCovers` compile-time assertion is load-bearing here, not optional. **Verification at implementation time:** Stage 3 RED test (Phase 1.3) round-trips a malformed frame through the parser and asserts rejection; Phase 3.6 schema implementation passes the assertion.
2. **The existing wire-protocol convention is camelCase for field names, snake_case for `type` discriminator.** Verified by direct grep of `lib/types.ts` against worktree HEAD: `resume_session.conversationId`, `session_started.conversationId`, `session_resumed.resumedFromTimestamp`, `usage_update.totalCostUsd`. New variants conform: `promptId`, `conversationId`, `parentId`, `spawnId`, `leaderId`. **The source plan (Stage 3 of `2026-04-23-...-plan.md`) prescribed snake_case; this plan deliberately overrides** to maintain protocol consistency. The Stage 2 shim already uses camelCase, so this also minimizes the rename surface in Phase 5.
3. **No `interactive_prompt`-related `.kind === "..."` if-ladders exist in client/server consumer code.** Verified at plan time via the three Stage 3.8 greps (output recorded in §Test Strategy). The only `.kind === ` matches are on `KBSearchResult.kind` (kb-reader.ts) and `ConversationRouting.kind` (soleur-go-runner.ts) — both unrelated unions. **Verification at implementation time:** re-run the greps in Phase 6.1.

## Implementation Phases

### Phase 0 — Preflight (non-blocking, ~5 min)

**Goal:** Confirm dependency landscape.

- [x] 0.1 — Verified at deepen time: `zod` v4.3.6 already in `apps/web-platform/node_modules/` (transitive). Pin exact `4.3.6` in `apps/web-platform/package.json` direct deps (no `^`). Use Zod 4 API throughout.
- [ ] 0.2 — Run `command -v rg` to confirm ripgrep is available (used in Stage 3.8 grep documentation).
- [x] 0.3 — Stage 3.8 greps run at plan time (see Research Reconciliation table + Test Strategy). Implementer copies the recorded result; re-runs in Phase 6.1.

### Phase 1 — RED (write failing tests first per `cq-write-failing-tests-before`)

**Goal:** Lock the contract before writing code.

**Files to edit:**

- `apps/web-platform/test/ws-protocol.test.ts` — extend with:
  - Round-trip Zod parse for every new `WSMessage` variant (`subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`, every `interactive_prompt` kind, every `interactive_prompt_response` kind).
  - Reject malformed frames: missing `type`, wrong `kind`, branded-ID type mismatch (e.g., a `PromptId` slot fed a non-string), unknown `WorkflowEndStatus`.
  - Assert the parser produces the correctly-typed `WSMessage` (TS-level — uses the `Expect<Equal<...>>` pattern or compile-time `satisfies`).
- `apps/web-platform/test/chat-state-machine.test.ts` — extend with:
  - One `it` per new variant that affects the reducer (initial Stage 3 list: none directly mutate `messages` — they mutate sibling state in the hook). Until Stage 4 wires bubble rendering, the reducer cases are **inert pass-throughs** that update `pendingTimerAction` only when relevant. Test the inert pass-through: assert no message mutation, no `activeStreams` mutation.
  - Critical: an `_exhaustive: never` compile-time assertion at the bottom of `applyStreamEvent`'s `switch` so a future variant fails `tsc --noEmit`. Test by writing a temporary `// @ts-expect-error` line that gets removed once the reducer cases are added.
- `apps/web-platform/test/branded-ids.test.ts` (new) — assert `mintSpawnId` / `mintPromptId` / `mintConversationId` produce branded values; assert plain string assignment fails compile (via `// @ts-expect-error` markers — a runtime test cannot verify a type-only invariant, so the gate is the markers + `tsc --noEmit` in CI).
- `apps/web-platform/test/ws-zod-schemas.test.ts` (new) — schema-level tests independent of the WS plumbing:
  - `wsMessageSchema.safeParse({ type: "interactive_prompt", promptId: "x", conversationId: "y", kind: "ask_user", payload: { question: "Q?", options: ["a","b"], multiSelect: false } })` succeeds with branded fields.
  - Same with `kind: "diff"` and a malformed `payload` (e.g., `additions: "not-a-number"`) → fails with structured error.
  - Discriminated union exhaustiveness: `z.discriminatedUnion("type", [...])` rejects an `interactive_prompt` with no `kind`.

**Tasks:**

- [ ] 1.1 — Add `"zod": "4.3.6"` to `apps/web-platform/package.json` `dependencies` (exact pin, no `^`). Run `cd apps/web-platform && npm install` to regenerate `package-lock.json` (Dockerfile uses `npm ci` — see `cq-before-pushing-package-json-changes`). The transitive entry already pins 4.3.6 so the install is a no-op at the lock level except for promotion from peer to direct.
- [ ] 1.2 — Write `branded-ids.test.ts` first (smallest unit). Run via `cd apps/web-platform && ./node_modules/.bin/vitest run test/branded-ids.test.ts` — RED.
- [ ] 1.3 — Write `ws-zod-schemas.test.ts` (still no implementation). Imports from `@/lib/ws-zod-schemas` will fail to resolve — that's the RED state.
- [ ] 1.4 — Extend `ws-protocol.test.ts` with new variant round-trips (RED — variants don't exist on `WSMessage` yet).
- [ ] 1.5 — Extend `chat-state-machine.test.ts` with inert pass-through cases for new event types (RED — `applyStreamEvent` switch isn't exhaustive yet).

### Phase 2 — GREEN: branded IDs + Zod schemas (foundation)

**Files to create:**

- `apps/web-platform/lib/branded-ids.ts` — branded string types + mint helpers. Comment block calls out the `string & { __brand }` pattern reason (provenance check at compile time, zero runtime cost).
  ```typescript
  // illustrative — final implementation may use Zod's .brand() helper
  // when the value flows through a schema, and the manual __brand pattern
  // when minted directly in code.
  declare const SpawnIdBrand: unique symbol;
  declare const PromptIdBrand: unique symbol;
  declare const ConversationIdBrand: unique symbol;

  export type SpawnId = string & { readonly [SpawnIdBrand]: true };
  export type PromptId = string & { readonly [PromptIdBrand]: true };
  export type ConversationId = string & { readonly [ConversationIdBrand]: true };

  export const mintSpawnId = (s: string): SpawnId => s as SpawnId;
  export const mintPromptId = (s: string): PromptId => s as PromptId;
  export const mintConversationId = (s: string): ConversationId => s as ConversationId;
  ```

- `apps/web-platform/lib/ws-zod-schemas.ts` — Zod schemas for every `WSMessage` variant. Exports:
  - `wsMessageSchema: z.ZodType<WSMessage>` — discriminated union over `type`.
  - `interactivePromptPayloadSchema` — discriminated union over `kind` (per-`kind` typed `payload`).
  - `interactivePromptResponseSchema` — discriminated union over `kind` (per-`kind` typed `response`).
  - `parseWSMessage(raw: unknown): { ok: true; msg: WSMessage } | { ok: false; error: ZodError }` — convenience wrapper used by `ws-client.ts:onmessage`.
  - **Bidirectional exhaustiveness** between the schema and the TS union (same pattern as `ws-known-types.ts:_Exhaustive`): a TS `_SchemaCovers` type assertion fails compilation if a `WSMessage` variant exists without a schema branch, or vice versa.

**Tasks:**

- [ ] 2.1 — Implement `branded-ids.ts`. Run `vitest run test/branded-ids.test.ts` — GREEN.
- [ ] 2.2 — Implement `ws-zod-schemas.ts` against the **current** `WSMessage` union (Stage 2 shape — `payload: unknown`, `response: unknown`). This intermediate state passes `ws-zod-schemas.test.ts` for the existing variants and fails for the new ones. Commit checkpoint.
- [ ] 2.3 — Verify `tsc --noEmit` passes in worktree before extending the union (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`).

### Phase 3 — GREEN: extend `WSMessage` discriminated union

**Files to edit:**

- `apps/web-platform/lib/types.ts` — replace `WSMessage` `interactive_prompt` / `interactive_prompt_response` with the discriminated sub-union; add four new variants.

  Per source plan Stage 3 (with **field-name correction to camelCase** — see deepen-pass note below):
  ```typescript
  // illustrative — final shape lives in lib/types.ts
  | { type: "subagent_spawn"; parentId: SpawnId; leaderId: DomainLeaderId; spawnId: SpawnId }
  | { type: "subagent_complete"; spawnId: SpawnId; status: "success" | "error" | "timeout" }
  | { type: "workflow_started"; workflow: WorkflowName; conversationId: ConversationId }
  | { type: "workflow_ended"; workflow: WorkflowName; status: WorkflowEndStatus; summary?: string }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "ask_user"; payload: { question: string; options: string[]; multiSelect: boolean } }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "plan_preview"; payload: { markdown: string } }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "diff"; payload: { path: string; additions: number; deletions: number } }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "bash_approval"; payload: { command: string; cwd: string; gated: boolean } }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "todo_write"; payload: { items: TodoItem[] } }
  | { type: "interactive_prompt"; promptId: PromptId; conversationId: ConversationId; kind: "notebook_edit"; payload: { notebookPath: string; cellIds: string[] } }
  | { type: "interactive_prompt_response"; promptId: PromptId; conversationId: ConversationId; kind: "ask_user"; response: string | string[] }
  | { type: "interactive_prompt_response"; promptId: PromptId; conversationId: ConversationId; kind: "plan_preview"; response: "accept" | "iterate" }
  | { type: "interactive_prompt_response"; promptId: PromptId; conversationId: ConversationId; kind: "bash_approval"; response: "approve" | "deny" }
  | { type: "interactive_prompt_response"; promptId: PromptId; conversationId: ConversationId; kind: "diff" | "todo_write" | "notebook_edit"; response: "ack" }
  ```

  **Field-naming correction (deepen-pass):** the source plan in `2026-04-23-feat-cc-route-via-soleur-go-plan.md` Stage 3 uses snake_case (`parent_id`, `spawn_id`, `prompt_id`, `conversation_id`). Direct grep of `lib/types.ts` against worktree HEAD shows the existing `WSMessage` convention is **camelCase for fields, snake_case only for the `type` discriminator** (e.g., `resume_session.conversationId`, `session_started.conversationId`, `session_resumed.resumedFromTimestamp`, `usage_update.totalCostUsd`). The Stage 2 shim already uses camelCase. **This plan corrects the source plan** — all new variants use camelCase to stay consistent with the existing 14 `WSMessage` variants. Phase 5 importer rewrite carries fewer diffs as a result (no field rename in the 7 importers).

- `apps/web-platform/lib/types.ts` — also add:
  - `export type WorkflowEndStatus = "completed" | "user_aborted" | "cost_ceiling" | "idle_timeout" | "plugin_load_failure" | "sandbox_denial" | "runner_crash" | "runner_runaway" | "internal_error";` (no bare `"error"`).
  - `export type { TodoItem } from "@/server/cc-interactive-prompt-types";` ← **delete this re-export source path** in Phase 5 (file is being deleted). Inline the `TodoItem` interface verbatim into `lib/types.ts` instead. (`TodoItem` is a wire-protocol concern — it belongs in `lib/types.ts`, not `server/*`.)
  - Re-export of `WorkflowName` from `@/server/conversation-routing`. (Alternative: move `WorkflowName` itself to `lib/types.ts`. Pick the lower-risk option at implementation — re-export is safer because `conversation-routing.ts` has its own `ConversationRouting` ADT machinery that should stay server-side.)
  - Port the `_AssertKindsMatch` exhaustiveness check from the shim, retargeting `InteractivePromptPayload["kind"]` against the `interactive_prompt` variants in `WSMessage`.

- `apps/web-platform/lib/ws-known-types.ts` — extend `KNOWN_WS_MESSAGE_TYPES` with four new entries (`subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`). The existing `_Exhaustive` proof catches misses at `tsc --noEmit`.

- `apps/web-platform/lib/ws-zod-schemas.ts` — extend the schema union with the four new variants and the per-`kind` discriminated payloads. The bidirectional exhaustiveness assertion ensures schema-side and type-side stay in sync.

**Tasks:**

- [ ] 3.1 — Inline `TodoItem` into `lib/types.ts`.
- [ ] 3.2 — Replace the two `unknown`-shape `WSMessage` variants with the 14-variant discriminated union (6 `interactive_prompt` kinds + 4 `interactive_prompt_response` shapes + 4 new event types).
- [ ] 3.3 — Add `WorkflowEndStatus` + `WorkflowName` re-export to `lib/types.ts`.
- [ ] 3.4 — Port `_AssertKindsMatch` from the shim (retargeted at the new `WSMessage` `interactive_prompt` variants).
- [ ] 3.5 — Extend `KNOWN_WS_MESSAGE_TYPES` set + `_Exhaustive` proof in `ws-known-types.ts`.
- [ ] 3.6 — Extend `ws-zod-schemas.ts` with the new variants. Run `vitest run test/ws-zod-schemas.test.ts test/ws-protocol.test.ts` — GREEN.
- [ ] 3.7 — Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — must pass with new union (importer edits in Phase 5 will resolve any consumer-side breakage; until then expect breakage at the 7 importer sites — that's expected RED, fixed in Phase 5).

### Phase 4 — GREEN: extend `chat-state-machine.ts` reducer + `: never` rail

**Files to edit:**

- `apps/web-platform/lib/chat-state-machine.ts` — extend `applyStreamEvent` switch:
  - Add `case "subagent_spawn"`, `case "subagent_complete"`, `case "workflow_started"`, `case "workflow_ended"`, `case "interactive_prompt"` — **all inert pass-throughs** in Stage 3 (return `{ messages: prev, activeStreams }` with no timer action). Stage 4 wires the actual rendering.
  - Append `default: { const _exhaustive: never = event; void _exhaustive; return { messages: prev, activeStreams }; }` so `tsc --noEmit` fails when a new variant is added without a case.
  - Tighten `activeStreams` parameter type and return type from `Map<string, number>` to `Map<DomainLeaderId, number>` (folds in #2225 part 1).
  - Update `StreamEvent` type alias to include the new event types so the switch types correctly. **Note:** `interactive_prompt_response` is client→server; do not include it in `StreamEvent` (it's never produced by the server).

- `apps/web-platform/lib/ws-client.ts`:
  - `chatReducer` (the `useReducer` wrapper) — propagate the typed `Map<DomainLeaderId, number>` through `ChatState.activeStreams`.
  - `useMemo`-derived `activeLeaderIds` — drop the `as DomainLeaderId[]` cast (folds in #2225 part 2).
  - `onmessage` — replace the existing flow:
    ```ts
    // current: parsed = JSON.parse(event.data); ... isKnownWSMessageType(rawType) ... msg as WSMessage
    // new:
    const parseResult = parseWSMessage(parsed);
    if (!parseResult.ok) {
      reportSilentFallback(parseResult.error, {
        feature: "command-center",
        op: "ws-zod-parse-failure",
        extra: { rawType: typeof rawType === "string" ? rawType : String(rawType) },
      });
      return;
    }
    const msg = parseResult.msg; // strictly typed WSMessage, no cast
    ```
    Keep `isKnownWSMessageType` as a fast-path before the Zod parse (so cheap rejections stay cheap; Zod parse is the strict gate).
  - Add `case "interactive_prompt"` branch in the outer `switch (msg.type)` that dispatches to the reducer (`dispatch({ type: "stream_event", msg })`) — Stage 4 wires the actual rendering. Without this, `interactive_prompt` falls through to `default: break` and the reducer never sees it (which is fine for Stage 3's inert behaviour but fails the `chat-state-machine.test.ts` assertion that the reducer received the event).
  - Same for `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended` — inert dispatch.

**Tasks:**

- [ ] 4.1 — Extend `applyStreamEvent` switch with inert cases + `_exhaustive: never` rail.
- [ ] 4.2 — Re-key `activeStreams` to `Map<DomainLeaderId, number>` end-to-end. Drop `as DomainLeaderId[]` cast.
- [ ] 4.3 — Wire Zod parser at `ws-client.ts:onmessage`. Preserve `reportSilentFallback` on failure.
- [ ] 4.4 — Run `vitest run test/chat-state-machine.test.ts test/ws-client.test.ts test/ws-protocol.test.ts` — GREEN.
- [ ] 4.5 — Run `tsc --noEmit` from `apps/web-platform` — must pass.

### Phase 5 — Delete the shim + rewrite importers

**Files to delete:**

- `apps/web-platform/server/cc-interactive-prompt-types.ts` (66 lines).

**Files to edit (7 importers):**

| File | Current import | Replacement |
|---|---|---|
| `server/cc-dispatcher.ts` | `import { ... } from "./cc-interactive-prompt-types"` (`InteractivePromptEvent`, `InteractivePromptResponse`, `WorkflowName`-adjacent types) | `import type { Extract } from "@/lib/types"` — narrow `WSMessage` via `Extract<WSMessage, { type: "interactive_prompt" }>` etc. |
| `server/ws-handler.ts` | `import type { InteractivePromptResponse } from "./cc-interactive-prompt-types"` | `import type { WSMessage } from "@/lib/types"` + alias `type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>` |
| `server/cc-interactive-prompt-response.ts` | same as above | same as above |
| `server/soleur-go-runner.ts` | `import { ... } from "./cc-interactive-prompt-types"` | same approach; `emitInteractivePrompt` callback signature changes from `InteractivePromptEvent` to the equivalent `Extract<WSMessage, { type: "interactive_prompt" }>` |
| `test/cc-dispatcher.test.ts` | `import type { InteractivePromptResponse } from "@/server/cc-interactive-prompt-types"` | `import type { WSMessage } from "@/lib/types"` + same alias |
| `test/cc-interactive-prompt-response.test.ts` | same | same |
| `test/soleur-go-runner-interactive-prompt.test.ts` | `import type { InteractivePromptEvent } from "@/server/cc-interactive-prompt-types"` | `import type { WSMessage } from "@/lib/types"` + same alias |

**No field renames** (deepen-pass correction): the new `WSMessage` variants keep camelCase (`promptId`, `conversationId`, etc.) to match the existing `WSMessage` convention. The 44 references in `test/cc-interactive-prompt-response.test.ts`, 12 in `test/cc-dispatcher.test.ts`, and 7 in `test/soleur-go-runner-interactive-prompt.test.ts` (counts verified at deepen time via direct grep) DO NOT need to be renamed. Importer changes are limited to: (a) replacing the `import` source path (`./cc-interactive-prompt-types` → `@/lib/types` + `Extract<...>` aliases), (b) ensuring the existing camelCase usage flows through the new types unchanged. Per `cq-union-widening-grep-three-patterns`, the three greps were run at plan time (recorded in §Test Strategy); no consumer-side widening is required.

**Tasks:**

- [ ] 5.1 — Rewrite each importer (in order: tests first, then production code, since tests are leaf nodes). Run the affected vitest after each rewrite to localize breakage.
- [ ] 5.2 — `git rm apps/web-platform/server/cc-interactive-prompt-types.ts`.
- [ ] 5.3 — `tsc --noEmit` from `apps/web-platform` — must pass.
- [ ] 5.4 — Full `vitest run` from `apps/web-platform` — must pass (or surface only pre-existing failures).
- [ ] 5.5 — `rg "cc-interactive-prompt-types" apps/web-platform/` — must return zero hits.
- [ ] 5.6 — `rg "InteractivePromptEvent\|InteractivePromptResponse" apps/web-platform/server/` — must show no remaining type-imports from the deleted file (aliases via `Extract<WSMessage, ...>` are fine).

### Phase 6 — REFACTOR / Sweep

**Tasks:**

- [ ] 6.1 — Run the three Stage 3.8 greps and record results in PR description (already known to be empty; document for the reviewer):
  ```bash
  rg "\.kind === " apps/web-platform/{lib,server,components}/
  rg "\?\.kind === " apps/web-platform/{lib,server,components}/
  rg 'case "[a-z_]+":' apps/web-platform/{lib,server}/
  ```
- [ ] 6.2 — Verify `lib/ws-known-types.ts` `_Exhaustive` proof still holds (`tsc --noEmit`).
- [ ] 6.3 — Verify `lib/types.ts` ported `_AssertKindsMatch` still holds.
- [ ] 6.4 — Run `vitest run` once more to confirm no regression.
- [ ] 6.5 — `cd apps/web-platform && ./node_modules/.bin/next lint` — must pass.

### Phase 7 — Lifecycle artifacts

**Tasks:**

- [ ] 7.1 — Update `apps/web-platform/server/cc-interactive-prompt-response.ts` header comment: remove the "Stage 2.14" marker now that Stage 3 has landed; reference Stage 3 PR.
- [ ] 7.2 — File **two follow-through tracking issues** (per `wg-when-deferring-a-capability-create-a`):
  - **Server-side text-delta coalescing** (source plan task 3.10) — milestone `Post-MVP / Later` or the active engineering phase per `roadmap.md`. Body: scope (rAF batching at 16-32ms in `agent-runner.ts` / `soleur-go-runner.ts` `stream` emit sites), why deferred (orthogonal to type refactor), re-evaluation criteria (>200 React renders/turn measured in production).
  - **Composite `(parent_id, leader_id)` re-keying of `activeStreams`** — Stage 4 dependency. Body: needed when nested-children rendering lands (Stage 4 of source plan).
- [ ] 7.3 — Comment on #2191 with a cross-link to this PR explaining the acknowledge-not-fold disposition.
- [ ] 7.4 — PR body uses `Closes #2885` and `Closes #2225` (per `wg-use-closes-n-in-pr-body-not-title-to`). Both close on merge.

## Files to Edit (consolidated)

- `apps/web-platform/package.json` — add `zod` dep (Phase 1.1).
- `apps/web-platform/package-lock.json` — regenerate.
- `apps/web-platform/lib/types.ts` — replace `WSMessage` `interactive_prompt` / `interactive_prompt_response` shim shapes with 14-variant discriminated sub-union; add 4 new event variants; add `WorkflowEndStatus`; re-export `WorkflowName`; inline `TodoItem`; port `_AssertKindsMatch`.
- `apps/web-platform/lib/ws-known-types.ts` — extend `KNOWN_WS_MESSAGE_TYPES` set with 4 new entries.
- `apps/web-platform/lib/chat-state-machine.ts` — extend `applyStreamEvent` switch with inert cases + `_exhaustive: never` rail; tighten `activeStreams` key to `DomainLeaderId`.
- `apps/web-platform/lib/ws-client.ts` — replace `JSON.parse(...) as WSMessage` cast with `parseWSMessage()`; drop `as DomainLeaderId[]` cast on `useMemo` derivation; add inert `dispatch` cases for new event types.
- `apps/web-platform/server/cc-dispatcher.ts` — rewrite imports from deleted shim → `Extract<WSMessage, ...>` aliases.
- `apps/web-platform/server/ws-handler.ts` — same rewrite.
- `apps/web-platform/server/cc-interactive-prompt-response.ts` — same rewrite + Stage 2.14 → Stage 3 marker.
- `apps/web-platform/server/soleur-go-runner.ts` — same rewrite.
- `apps/web-platform/test/cc-dispatcher.test.ts` — rewrite imports only; existing camelCase usage is preserved (deepen-pass field-naming correction).
- `apps/web-platform/test/cc-interactive-prompt-response.test.ts` — same; the 44 `promptId`/`conversationId` references stay as-is.
- `apps/web-platform/test/soleur-go-runner-interactive-prompt.test.ts` — same; the 7 references stay as-is.
- `apps/web-platform/test/ws-protocol.test.ts` — extend with new variant round-trips + Zod rejection cases.
- `apps/web-platform/test/chat-state-machine.test.ts` — extend with inert pass-through cases + `_exhaustive: never` assertion test.

## Files to Create

- `apps/web-platform/lib/branded-ids.ts` — `SpawnId`, `PromptId`, `ConversationId` branded types + mint helpers.
- `apps/web-platform/lib/ws-zod-schemas.ts` — Zod schemas for every `WSMessage` variant + `parseWSMessage` wrapper + bidirectional exhaustiveness assertion.
- `apps/web-platform/test/branded-ids.test.ts` — branded-type unit tests + `// @ts-expect-error` markers.
- `apps/web-platform/test/ws-zod-schemas.test.ts` — schema-level round-trip + rejection tests.

## Files to Delete

- `apps/web-platform/server/cc-interactive-prompt-types.ts` — shim sunset (its TODO comment explicitly calls out this PR; close the loop).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `WSMessage` discriminated union in `lib/types.ts` carries the 14 new variants with branded `PromptId` / `ConversationId` / `SpawnId` IDs (no `unknown`).
- [ ] `WorkflowEndStatus` exported from `lib/types.ts` with the 9-status enum from the source plan.
- [ ] `wsMessageSchema` in `lib/ws-zod-schemas.ts` covers every variant; `_SchemaCovers` (or equivalent) compile-time assertion enforces parity with the TS union.
- [ ] `ws-client.ts:onmessage` parses via `parseWSMessage(...)`. The `as WSMessage` cast is removed. Sentry breadcrumb fires on parse failure via `reportSilentFallback` with `op: "ws-zod-parse-failure"`.
- [ ] `applyStreamEvent` switch in `chat-state-machine.ts` has a `default: const _exhaustive: never = event` rail. Adding a new `WSMessage` variant without a reducer case fails `tsc --noEmit`.
- [ ] `activeStreams` is typed `Map<DomainLeaderId, number>` end-to-end. No `as DomainLeaderId[]` cast remains in `ws-client.ts`.
- [ ] `apps/web-platform/server/cc-interactive-prompt-types.ts` is deleted. `rg "cc-interactive-prompt-types" apps/web-platform/` returns zero hits.
- [ ] All 7 importers updated to import from `@/lib/types` (with `Extract<WSMessage, ...>` aliases): `server/cc-dispatcher.ts`, `server/ws-handler.ts`, `server/cc-interactive-prompt-response.ts`, `server/soleur-go-runner.ts`, `test/cc-dispatcher.test.ts`, `test/cc-interactive-prompt-response.test.ts`, `test/soleur-go-runner-interactive-prompt.test.ts`.
- [ ] Wire-protocol fields stay **camelCase** (matching existing `WSMessage` convention): `promptId`, `conversationId`, `parentId`, `spawnId`, `leaderId`. No snake_case field rename per deepen-pass field-naming correction.
- [ ] `tsc --noEmit` passes from `apps/web-platform/`.
- [ ] `vitest run` from `apps/web-platform/` shows green for all Stage 3 tests; pre-existing failures (if any) tracked per `wg-when-tests-fail-and-are-confirmed-pre`.
- [ ] `next lint` passes.
- [ ] Stage 3.8 grep results documented in PR body (matches `\.kind === "` + `\?\.kind === "` + `case "[a-z_]+":` patterns; current state: no widening required, all existing matches are unrelated unions).
- [ ] PR body contains `Closes #2885` and `Closes #2225`.
- [ ] Two follow-through issues filed (delta coalescing + composite key re-keying).
- [ ] `#2191` cross-linked via comment.

### Post-merge (operator / automation)

- [ ] CI deploy webhook triggers prod build on merge (no operator action — pipeline runs automatically; verify success per `wg-after-a-pr-merges-to-main-verify-all`).
- [ ] No new Sentry events with `op: "ws-zod-parse-failure"` in the first 24h of soak (a spike would indicate server emitting frames the client schema rejects — a server/client skew bug).
- [ ] `gh issue close 2885` (auto-closes via `Closes`).
- [ ] `gh issue close 2225` (auto-closes via `Closes`).

## Test Strategy

**Test runner:** `vitest` (already configured per `apps/web-platform/package.json`). Run via `cd apps/web-platform && ./node_modules/.bin/vitest run` per `cq-in-worktrees-run-vitest-via-node-node`.

**Test layers:**

1. **Unit — branded IDs** (`test/branded-ids.test.ts`): mint helpers + `// @ts-expect-error` markers ensuring plain string assignment fails compile.
2. **Unit — Zod schemas** (`test/ws-zod-schemas.test.ts`): round-trip happy path for every variant + rejection for malformed payloads + bidirectional exhaustiveness compile-time assertion.
3. **Unit — protocol round-trip** (`test/ws-protocol.test.ts`): JSON.stringify → JSON.parse → `parseWSMessage` round-trip per variant.
4. **Unit — reducer** (`test/chat-state-machine.test.ts`): inert pass-through for every new event type + `_exhaustive: never` enforcement (tested via temporary `// @ts-expect-error` marker that gets removed).
5. **Type-only — exhaustiveness rails** (`tsc --noEmit` in CI): catches any future variant added without a corresponding schema branch / reducer case / known-types entry.
6. **Integration — existing suites** (`test/cc-dispatcher.test.ts`, `test/cc-interactive-prompt-response.test.ts`, `test/soleur-go-runner-interactive-prompt.test.ts`): updated to use `Extract<WSMessage, ...>` aliases + snake_case wire fields. Must still pass.

**Stage 3.8 grep documentation (run at plan time, recorded for reviewer):**

```bash
$ rg "\.kind === " apps/web-platform/{lib,server,components}/
apps/web-platform/server/kb-reader.ts:384:    if (a.kind !== b.kind) return a.kind === "content" ? -1 : 1;
apps/web-platform/server/kb-reader.ts:385:    if (a.kind === "content") return b.matches.length - a.matches.length;
apps/web-platform/server/soleur-go-runner.ts:711:        args.currentRouting.kind === "soleur_go_active"

$ rg "\?\.kind === " apps/web-platform/{lib,server,components}/
# (no matches)

$ rg 'case "[a-z_]+":' apps/web-platform/{lib,server}/  # filtered to relevant files
# kb-reader.ts kind is on KBSearchResult union (unrelated).
# soleur-go-runner.ts kind is on ConversationRouting ADT (unrelated).
# No interactive_prompt.kind if-ladder in client/server consumer code.
# Consumer pattern is `switch (event.kind)` inside handleInteractivePromptResponse — already exhaustive.
```

**Conclusion:** No widening required for the Stage 3 union expansion at consumer if-ladder sites. The `cq-union-widening-grep-three-patterns` rule's three patterns are all clear.

## Risks

- **`zod` is a runtime dep on a security-sensitive boundary (WS deserialization).** Already at v4.3.6 in `node_modules` transitively; promotion to direct dep makes it explicit. Mitigation: pin exact version (no `^`); minimal-reproducer test in `test/ws-zod-schemas.test.ts` covers the patterns we use (discriminated union + branded types + per-`kind` payload validation).
- **Zod 4 caveats.** Two Zod 4 differences from Zod 3 affect this design: (a) `.brand()` works (with optional `<"PromptId", "in" | "out" | "inout">` modes) — the default is "out" branding, sufficient for our use case; (b) `z.discriminatedUnion("type", [...])` discriminator parameter is **non-generic** in Zod 4 (<https://github.com/colinhacks/zod/issues/5024>), so per-variant inference at the schema-tuple level is weaker than Zod 3 — TS may type the parsed result as a wider union than expected. Mitigation: write each branch as a named exported `z.object({...})` constant (so the schema is grep-able); enforce TS-side parity via the bidirectional `_SchemaCovers` compile-time assertion (modeled after `lib/ws-known-types.ts:_Exhaustive`). The schema/union drift gate is the assertion, not Zod inference.
- **`activeStreams` typing may break peer consumers.** `chat-state-machine.test.ts` and `ws-client.test.ts` mock `Map<string, number>` directly. Mitigation: at Phase 4.2 entry, run `rg "Map<string,\s*number>|new Map<string," apps/web-platform/` to enumerate every mock and sweep all in the same edit per `cq-raf-batching-sweep-test-helpers` (the analogous "sweep helpers" pattern for type tightenings).
- **Bidirectional schema/union drift.** A new variant on the TS union without a Zod branch (or vice versa) is the silent-skew failure mode. Mitigation: `_SchemaCovers` compile-time assertion in `ws-zod-schemas.ts` matches the existing `_Exhaustive` proof in `ws-known-types.ts`.
- **Inert Stage 3 reducer cases create dead code briefly.** Until Stage 4 wires actual rendering, `case "subagent_spawn"` etc. return the unchanged state. This is intentional (lands the type rail without UI surface) but a reviewer could flag as YAGNI. Mitigation: comment block at each inert case explicitly references the Stage 4 follow-up + the corresponding tracking issue.
- **`reportSilentFallback` on Zod failure** could spam Sentry on a server/client version skew during phased rollout. Mitigation: rate-limit at the Sentry side (existing infra) + the existing `isKnownWSMessageType` fast-path stays in place to filter known-unknown types before Zod parse fires.

## Domain Review

**Domains relevant:** Engineering (CTO)

**Brainstorm carry-forward:** Yes. The brainstorm `2026-04-23-cc-single-leader-routing-brainstorm.md` ran a full domain sweep (8 domains assessed). Engineering and Product flagged inline (per `pdr-do-not-route-on-trivial-messages-yes` exception — the brainstorm was about routing/leader architecture). Marketing, Legal, Sales, Support, Finance, Operations had no signal (internal operator tooling, no external surface). Stage 3 of the source plan is a **subset** of the brainstorm's scope — pure-TS protocol type extension on `apps/web-platform/`. No new domain signals appear at the Stage 3 level.

### Engineering (CTO, brainstorm carry-forward)

**Status:** reviewed (carry-forward)

**Assessment:** Stage 3 is the minimal type-protocol extension that the source plan's Stages 4-5 depend on. Risk surface is small: the `: never` rail + Zod schema's bidirectional exhaustiveness + the existing `ws-known-types.ts:_Exhaustive` proof form a redundant three-layer drift guard. The new dep (`zod`) is widely adopted, low-risk. Branded IDs introduce zero runtime cost. The biggest implementation hazard is the snake_case wire-field rename in the 7 importers — `tsc --noEmit` catches it deterministically.

### Product/UX Gate

**Tier:** none — Stage 3 ships zero user-visible UI. No new pages, no new components, no new flows. The reducer cases are inert. UI surfaces land in Stage 4.

**Decision:** N/A — no Product/UX Gate needed for a type-protocol-only PR.

## Stage 3 Sequencing Note

The 12 source-plan tasks (3.1-3.12) map onto this plan's 7 phases as follows:

| Source plan | This plan |
|---|---|
| 3.1 — Read `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` and document REPLACE-not-APPEND in runner header. | Out of scope — runner is touched in Stage 4/5 of source plan; this PR's `lib/` changes don't add new emit sites. |
| 3.2 — RED: extend `test/ws-protocol.test.ts`. | Phase 1.4. |
| 3.3 — RED: extend `test/chat-state-machine.test.ts`. | Phase 1.5. |
| 3.4 — GREEN: implement `branded-ids.ts` + `ws-zod-schemas.ts`. | Phase 2 (split into 2.1 + 2.2). |
| 3.5 — GREEN: extend `WSMessage` and `ChatMessage` unions. | Phase 3 (`WSMessage`) + Phase 4.1 (reducer cases — `ChatMessage` itself doesn't need new variants in Stage 3, only `applyStreamEvent` switch arms). |
| 3.6 — GREEN: add reducer cases + activeStreams re-key (folds in #2225). | Phase 4.1 + 4.2. **Narrowed:** keeps `Map<DomainLeaderId, number>` keying; defers composite `(parent_id, leader_id)` to Stage 4 of source plan. Tracking issue filed in Phase 7.2. |
| 3.7 — GREEN: replace WS `onmessage` cast with Zod parse. | Phase 4.3. |
| 3.8 — Run three greps to find consumer if-ladders. | **Done at plan time** (results in §Test Strategy). Re-run at Phase 6.1. |
| 3.9 — REFACTOR: derive `activeLeaderIds` via `useMemo`. | Already a `useMemo`. Phase 4.2 just drops the unsafe cast. |
| 3.10 — Server-side text-delta coalescing. | **Deferred — Phase 7.2 files tracking issue.** Server emit-side concern, orthogonal to type refactor. |
| 3.11 / 3.12 (if any in numbering — source plan stops at 3.10). | N/A. |

Plus Stage 3 issue body explicitly: **delete `cc-interactive-prompt-types.ts`** — Phase 5 (the shim sunset).

## References

- Source plan: `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md` Stage 3 (`git show main:...` to retrieve in worktree).
- Source spec: `knowledge-base/project/specs/feat-cc-single-leader-routing/spec.md` (`git show main:...`).
- Source PR: #2858 (Stage 1 + Stage 2 SDK-as-router foundation, merged 2026-04-26).
- Tracked issue: #2885 (this work).
- Folded-in issue: #2225 (`activeStreams` key tightening + `useMemo` derivation).
- Acknowledged issue: #2191 (orthogonal session-lifecycle refactor).
- Learning references:
  - `cq-union-widening-grep-three-patterns` — Stage 3.8 grep procedure.
  - `cq-write-failing-tests-before` — Phase 1 RED gate.
  - `cq-code-comments-symbol-anchors-not-line-numbers` — symbol-anchor references throughout.
  - `cq-in-worktrees-run-vitest-via-node-node` — vitest invocation pattern.
  - `cq-before-pushing-package-json-changes` — `zod` dep + lockfile regen.
  - `cq-test-mocked-module-constant-import` — relevant if any test fully `vi.mock()`s `lib/types.ts` (verify at implementation time before extracting any new exported constant).
  - `wg-use-closes-n-in-pr-body-not-title-to` — PR body `Closes #2885` + `Closes #2225`.
  - `wg-when-deferring-a-capability-create-a` — Phase 7.2 follow-through issues.
