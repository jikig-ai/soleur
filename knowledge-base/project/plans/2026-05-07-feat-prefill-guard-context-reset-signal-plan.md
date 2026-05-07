---
title: Surface prefill-guard fires to model + user (context-reset signal)
date: 2026-05-07
type: feature
issue: "#3269"
parent_pr: "#3263"
draft_pr: "#3419"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-07-prefill-guard-context-reset-signal-brainstorm.md
spec: knowledge-base/project/specs/feat-prefill-guard-context-reset-signal/spec.md
adr: ADR-025
---

# Plan: Surface prefill-guard fires to model + user (context-reset signal)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Files-to-Edit (added 2 sites), Phases 3, 4, 6 (verification rails), Sharp Edges, Risks
**Research agents used:** Explore × 2 (SDK retry + Zod proof shape; chat-surface render), learnings-researcher (3-pattern grep precedent + WS variant family), agent-native-reviewer (MCP parity gap)

### Key Improvements

1. **Found 2 missing exhaustiveness rails:** plan listed 3 sites; codebase has 4. Added `lib/ws-known-types.ts` (`KNOWN_WS_MESSAGE_TYPES` Set + `_forward`/`_backward` rails at lines 76-77) and `lib/chat-state-machine.ts` (`applyStreamEvent` reducer at line 277, where the discriminated-union exhaustive switch actually lives — `ws-client.ts` is dispatcher only).
2. **`_SchemaCovers` proof is bidirectional.** `_SchemaCoversForward` AND `_SchemaCoversBackward` (ws-zod-schemas.ts:472-479). One-way update fails `tsc --noEmit`. Plan now spells this out.
3. **`Promise.all([...])` wraps applyPrefillGuard at cc-dispatcher.ts:477-486.** Implementer must thread the new return fields through the array destructure, not a sequential await.
4. **`conversationId` empty-string fallback was dead code.** Verified always-present at agent-runner.ts:1157 (required `startAgentSession` parameter). Plan simplified — no runtime fallback, no `prefill-guard-conversationid-missing` Sentry op.
5. **Added `cq-union-widening-grep-three-patterns` verification step** (Phase 6.1a) — three-pattern grep + `vi.mock("../server/observability")` sweep. Compiler does NOT catch if-ladder consumers.
6. **Sentry op-naming constraint sharpened** — if future WS-path Sentry emit added, MUST use distinct op (`context-reset-signal-sent`), never `prefill-guard`, to preserve #3269's >10/7d threshold accuracy.
7. **Agent-native parity gap acknowledged** — WS event is browser-bound; future `get_session_state` MCP tool needs write-side persistence. Tracked in **#3423** (close before option (c) enters build).

### New Considerations Discovered

- SDK `query()` retries are internal to the returned `Query` AsyncGenerator (`sdk.d.ts:1678-1681` + `api_retry` subtype 1769-1776). `applyPrefillGuard` is genuinely re-entered per dispatcher call only — `wsEmitted` boolean is purely defensive (kept for clarity, not correctness).
- The `fanout_truncated` schema at `ws-zod-schemas.ts:286-290` is the verbatim shape precedent — `z.strictObject` (not `z.object`), included in `flatTypeSchema` at line 431.
- `chat-state-machine.ts:277 applyStreamEvent` is the single reducer site where TS exhaustiveness will fail compilation if `context_reset` is missing from the `switch (msg.type)`.

## Overview

PR #3263 landed a prefill-guard at the SDK call boundary in `apps/web-platform/server/agent-prefill-guard.ts`. When the persisted Claude Agent SDK session ends with `assistant`, the guard drops `resume:` so the SDK starts a fresh server-side session — preventing an HTTP 400 ("model does not support assistant message prefill") from reaching the user. Trade-off: the model has zero memory of prior turns, the user has no UI signal.

This plan implements **(a) system-prompt notice + (b) WS `context_reset` event** in one PR, with the `tool_use` orphan branch handled via a `reason: "tool_use_orphan"` discriminator on the new WS variant. Defer **(c) MCP `get_session_state`** behind issue #3269's >10/7d Sentry trigger — no native MCP server exists today.

ADR-025 (committed in the brainstorm phase, before this plan was written) documents the WS lifecycle-notice event family invariants for forward-compat. This plan adds **one** variant (`context_reset`) — the family abstraction is reference-only here; future variants justify themselves on arrival.

**Brand-survival threshold:** `single-user incident` (carried from brainstorm). CPO sign-off required at plan time before `/work`. `user-impact-reviewer` will be invoked at review-time per the standard threshold gate.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality | Plan response |
|---|---|---|
| `cc-dispatcher.ts:619` is the systemPrompt assembly site | Correct site is `cc-dispatcher.ts:597` (`systemPrompt: args.systemPrompt`); guard call is at `cc-dispatcher.ts:479` | Plan uses verified line numbers (479 + 597) |
| `agent-runner.ts:584-590` | Actual systemPrompt assembly is `agent-runner.ts:883-1047` (multi-source `+=` accumulator); guard call is `agent-runner.ts:1157` | Plan appends notice after services-list section (~line 1170 area) so it is not overwritten by later accumulator branches |
| MCP server exists at `apps/web-platform/server/mcp/` | Directory does NOT exist; only Playwright's vendored copy | Confirms (c) MCP self-observability is greenfield (1-week+); deferral correct |
| Client renderer location TBD | Client WS dispatch at `lib/ws-client.ts:512-651`; inline notice render at `components/chat/chat-surface.tsx:505-599` mirroring `workflow_ended` pattern (lines 563-587) | Use inline render in `chat-surface.tsx` (no new component file); pattern precedent is single-shot informational badge |
| `fanout_truncated` is a working precedent for one-shot lifecycle-notice WS variants | Currently a NO-OP in `ws-client.ts:650-651` (case break, no render) | Use `workflow_ended` (chat-surface.tsx:563-587) as the render-side precedent instead. `context_reset` becomes the **first** lifecycle-notice variant to actually render — ADR-025 invariant #6 (Zod-parsed and `_SchemaCovers`-proven) still holds |
| Per-conversation routing | Single active WS per user; `conversationId` carried for forward-compat but no multi-thread demux | `context_reset` carries `conversationId` for forward-compat (matches FR2) |

## User-Brand Impact

**If this lands broken, the user experiences:** Soleur Concierge confidently producing wrong-but-plausible answers in the turn after a context-reset, OR executing the wrong action / no action when the user replies "yes do that" referencing a tool the new session never proposed. Either case erodes paid-trust contract — user does not retry, they churn.

**If this leaks, the user's workflow is exposed via:** Authorization-audit-trail ambiguity — the platform cannot prove what tool action the user authorized when their "yes do that" referenced a phantom tool_use the model no longer remembers (CLO-flagged in brainstorm).

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time (this plan). `user-impact-reviewer` invoked at review-time. `requires_cpo_signoff: true` set in frontmatter.

## Files to Edit

- `apps/web-platform/server/agent-prefill-guard.ts` — extend `ApplyPrefillGuardResult` with `contextResetNotice?: string`; add tool_use detection (`last.message.content[].type === "tool_use"`); return tool-aware notice variant.
- `apps/web-platform/server/cc-dispatcher.ts` — at line 477-486 the `applyPrefillGuard` call is wrapped in `Promise.all([...])` with other prep tasks; the destructure of `safeResumeSessionId / contextResetNotice / reason` lands in the same `Promise.all` result-array. At line 597 append the notice to `args.systemPrompt`. Emit WS `context_reset` via `sendToClient` exactly once between guard-result and the SDK call. **`sendToClient` signature** (verified): `sendToClient(userId: string, message: WSMessage): boolean` from `apps/web-platform/server/ws-handler.ts:419` — return `false` indicates delivery failed (treat as no-op; do NOT retry).
- `apps/web-platform/server/agent-runner.ts` — at line 1157 consume notice; append to `systemPrompt` accumulator **after all conditional accumulator branches finish (last `+=` is at ~line 1047 inside the `installationId && repoUrl && owner && repo` GitHub-read-access block) and BEFORE the `query({` call at ~line 1166**. Verify exact insertion point at work time — line 1170 is inside the `query({})` object literal, NOT in the accumulator. Emit WS `context_reset` via `sendToClient` exactly once. The `wsEmitted` boolean is defensive only — `applyPrefillGuard` is awaited before `sdkQuery({...})` and SDK retries re-enter `query()` (not the guard), so the helper is naturally per-fire.
- `apps/web-platform/lib/types.ts` — at line 189 add `ContextReset` variant to `WSMessage` discriminated union: `{ type: "context_reset"; reason: "prefill-guard" | "tool_use_orphan"; conversationId: string }`.
- `apps/web-platform/lib/ws-zod-schemas.ts` — at the discriminated union add `contextResetSchema = z.strictObject({ type: z.literal("context_reset"), reason: z.union([z.literal("prefill-guard"), z.literal("tool_use_orphan")]), conversationId: z.string() })` (mirror `fanoutTruncatedSchema` at lines 286-290 verbatim shape). Add to `flatTypeSchema` at line 431. The `_SchemaCovers` proof at lines 472-479 is **bidirectional** (`_SchemaCoversForward` + `_SchemaCoversBackward`); a one-way update is insufficient — the new variant must satisfy both directions or `tsc --noEmit` fails.
- `apps/web-platform/lib/ws-known-types.ts` — add `"context_reset"` to the `KNOWN_WS_MESSAGE_TYPES` Set literal (~line 26). The `_forward`/`_backward` exhaustiveness rails at lines 76-77 enforce parity with `AllowedWSMessageType`.
- `apps/web-platform/lib/chat-state-machine.ts` — extend `applyStreamEvent` (`function` declaration at line 277) to accept the new `context_reset` variant. This is the reducer site that `ws-client.ts:175` calls into; the `WSMessage` discriminated-union exhaustive switch lives here, not in `ws-client.ts`.
- `apps/web-platform/lib/ws-client.ts` — in the `onmessage` switch (lines 512-651) add a `case "context_reset":` that forwards to the client store / chat-surface props (mirrors `workflow_ended` ingestion path, NOT the no-op `fanout_truncated` path).
- `apps/web-platform/components/chat/chat-surface.tsx` — in the message-type dispatcher switch (lines 505-599) add a `context_reset` case that renders an inline rounded badge using the `workflow_ended` pattern at lines 563-587. Render reads from a new `CONTEXT_RESET_COPY` const (Phase 4.5) keyed by `message.reason`. Both copy strings live in the const, not inline at the render site.
- `apps/web-platform/test/agent-prefill-guard.test.ts` — add scenarios for `contextResetNotice` populated/empty across all branches; tool-aware variant on `tool_use` trailing.
- `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — add scenarios: `args.systemPrompt` receives notice exactly when guard fires; not appended otherwise; WS emit fires exactly once per guard fire.
- `apps/web-platform/test/ws-known-types-guard.test.ts` — add `context_reset` to the known types list with both reason variants.
- `apps/web-platform/test/ws-protocol.test.ts` (or sibling Zod-schema test if `ws-protocol.test.ts` does not exist) — add `context_reset` Zod round-trip scenarios for both reason variants. **Do not create a new file — fold into the existing WS schema test file.**

## Files to Create

- `apps/web-platform/test/agent-runner-prefill-guard.test.ts` — new test file mirroring `cc-dispatcher-prefill-guard.test.ts` for the legacy path. Distinct accumulator semantics warrant isolation. Asserts notice append + single WS emit.
- `apps/web-platform/test/chat-surface-context-reset.test.tsx` — new RTL render test asserting `chat-surface.tsx` renders both `reason` variants with the verbatim `CONTEXT_RESET_COPY` strings and the `data-message-type="context_reset"` attribute. Closes the FR3 coverage gap.

## Implementation Phases

### Phase 1 — Helper extension (`agent-prefill-guard.ts`)

1.1. Extend `ApplyPrefillGuardResult`: add `contextResetNotice?: string` (optional). When `safeResumeSessionId === undefined` because of assistant-terminated history, populate it; in all other branches (cold start, user-final, empty history, probe failure), leave `undefined`.

1.2. Add tool_use detection via a typed runtime guard `isToolUseTrailing(message: unknown): boolean`. Per `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2563`, `SessionMessage.message` is typed `unknown` — the guard MUST narrow at runtime. Required predicate chain:

```
typeof message === "object" && message !== null
  && "content" in message
  && (
       (typeof message.content === "string" && /* tool_use never appears in string form, return false */ false)
       || (Array.isArray(message.content)
           && message.content.some(
                (block) => typeof block === "object" && block !== null
                  && "type" in block && block.type === "tool_use"
              ))
     )
```

Any non-object / null / undefined / unrecognized shape returns `false` (degrades to generic notice — never throws).

1.3. Build the notice text in two variants. Trim to model directive only — no jargon ("thread-shape constraint", "Note:", "due to"):
- Generic: `"Prior conversation context was reset. Treat the user's next message as standalone; ask for clarification if it references earlier turns."`
- Tool-aware: `"Prior conversation context was reset. The previous turn proposed a tool action you no longer have context on. Do NOT execute any action without explicit re-confirmation by name — ask the user to restate which action they want to run."`

1.4. Add a returned `reason` field on the result so callers can pass it directly to the WS emit: `{ safeResumeSessionId: undefined, contextResetNotice: <text>, reason: "prefill-guard" | "tool_use_orphan" }`.

1.5. JSDoc updates: document that `contextResetNotice` is single-turn (caller MUST NOT persist it across turns) and that `reason` discriminator is the source of truth for the WS event.

### Phase 2 — Wire `cc-dispatcher.ts` call site

2.1. At line 479 (the `applyPrefillGuard` call), destructure the new fields: `const { safeResumeSessionId, contextResetNotice, reason } = await applyPrefillGuard({...})`.

2.2. At line 597 (where `systemPrompt: args.systemPrompt` is passed to the SDK), append the notice when present: `systemPrompt: contextResetNotice ? \`${args.systemPrompt}\n\n${contextResetNotice}\` : args.systemPrompt`. Single-turn — never persisted.

2.3. After the guard call (line 479 area) and before the SDK call, when `contextResetNotice && reason`, emit the WS event exactly once via `sendToClient(userId, { type: "context_reset", reason, conversationId })`. Use a local boolean `wsEmitted` flag scoped to the dispatcher call so SDK retries do not re-emit.

2.4. Existing Sentry op (`op: "prefill-guard"`) remains unchanged. Do NOT add a second Sentry emit for the WS event — the WS emission is the user-side signal; Sentry is the operator-side signal. Avoids double-counting in #3269's >10/7d threshold.

### Phase 3 — Wire `agent-runner.ts` call site

3.1. At line 1157 (the `applyPrefillGuard` call), destructure the same three fields.

3.2. Locate the systemPrompt accumulator's terminal append point. **Verified at plan time:** the last conditional `+=` lands at line 1047 inside the `installationId && repoUrl && owner && repo` GitHub-read-access block; the `query({...})` call begins at line 1166. The notice append MUST land **after all conditional accumulator branches finish AND BEFORE line 1166** — line 1170 is inside the `query({})` object literal and cannot accept a statement. Insert at the first column-0 line after line 1047's branch closes and before the `query({` site. Append shape: `if (contextResetNotice) systemPrompt += \`\n\n${contextResetNotice}\`;`. Verify the exact insertion point at work time by re-reading lines 1040-1170 — accumulator structure may have drifted.

3.3. WS emit identical to dispatcher path: `if (reason) sendToClient(userId, { type: "context_reset", reason, conversationId })`. **`conversationId` is verified always-present at agent-runner.ts:1157** (required parameter to `startAgentSession`, threaded through to the guard call). The empty-string fallback prescription has been dropped — it was guarding against an impossible code path. If a future refactor makes `conversationId` optional, surface the gap via TypeScript (declare it required at the call site), not via runtime fallback.

### Phase 4 — WS taxonomy + Zod parser

4.1. `lib/types.ts` — add the `ContextReset` variant to `WSMessage`. Place lexically near `session_resumed` / `session_ended` (the closest semantic neighbors).

4.2. `lib/ws-zod-schemas.ts` — define `contextResetSchema = z.object({ type: z.literal("context_reset"), reason: z.union([z.literal("prefill-guard"), z.literal("tool_use_orphan")]), conversationId: z.string() })`. Add to the discriminated-union in `wsMessageSchema`. Update the `_SchemaCovers` proof.

4.3. `lib/ws-client.ts` — in the `onmessage` switch (lines 512-651), add `case "context_reset":` that forwards via `applyStreamEvent(prev, conversationId, msg)` (line 175 pattern). The actual reducer logic for the variant lives in `chat-state-machine.ts` (Phase 4.3a below); `ws-client.ts` is purely the dispatcher.

4.3a. `lib/chat-state-machine.ts` — extend `applyStreamEvent` (line 277) to handle `context_reset`. The function returns the new state; for a one-shot lifecycle notice, append the message to the conversation's message stream (no other state mutation). Mirror `workflow_ended` reducer path. This is where the exhaustive `switch (msg.type)` lives — TypeScript will fail compilation if `context_reset` is missing from the switch, since `WSMessage` widens here.

4.3b. `lib/ws-known-types.ts` — add `"context_reset"` to the `KNOWN_WS_MESSAGE_TYPES` Set (line 26). The `_forward`/`_backward` exhaustiveness rails at lines 76-77 will fail compilation if omitted.

4.4. `components/chat/chat-surface.tsx` — in the message-type switch (lines 505-599), add a `case "context_reset":` rendering an inline rounded badge mirroring the `workflow_ended` pattern at lines 563-587. Use `data-message-type="context_reset"`. Tailwind classes: `rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3` (verify against the `workflow_ended` line's exact classes at work time). Branch on `message.reason` to render the appropriate copy variant.

4.5. **Single source of truth for copy.** Export a typed const `CONTEXT_RESET_COPY` from `chat-surface.tsx` (or a sibling `apps/web-platform/components/chat/chat-copy.ts`):

```ts
export const CONTEXT_RESET_COPY = {
  "prefill-guard": "Context was lost. Re-state your request if it built on earlier turns.",
  "tool_use_orphan": "Context was lost before the last proposed action ran — name the action and re-state it to continue.",
} as const;
```

The render in 4.4 reads `CONTEXT_RESET_COPY[message.reason]`. Tests (Phase 5) import the const, never inline string literals — prevents copywriter / test divergence at zero abstraction cost (one const, two consumers).

### Phase 5 — Tests (RED before code per `cq-write-failing-tests-before`)

5.1. **`agent-prefill-guard.test.ts`** — extend with:
- "returns `contextResetNotice` populated and `reason: 'prefill-guard'` when last message is plain assistant"
- "returns tool-aware notice and `reason: 'tool_use_orphan'` when last assistant message contains a `tool_use` content block in `content: array` shape"
- "returns generic notice (not tool-aware) when `content: string` (tool_use never appears in string form)"
- "returns generic notice (not tool-aware) when `message` is null, undefined, or non-object — no crash"
- "returns `contextResetNotice: undefined` and `reason: undefined` on cold start, user-final, empty history, probe failure"

5.2. **`cc-dispatcher-prefill-guard.test.ts`** — extend with:
- "appends `contextResetNotice` to `args.systemPrompt` exactly when guard fires (assistant-final)"
- "does not mutate `args.systemPrompt` when guard does not fire"
- "emits one `context_reset` WS event per guard fire (single-call SDK retry does not re-emit)"
- "emits `reason: 'tool_use_orphan'` when trailing message had `tool_use` content"
- "does not emit `context_reset` on probe failure"
- "does not emit `context_reset` on empty history"
- "subsequent dispatcher calls in the same session, where the guard does NOT fire, do NOT carry the notice forward (multi-turn non-accumulation per spec AC6b)"

5.3. **`agent-runner-prefill-guard.test.ts`** (new file) — same scenario list as 5.2 for the legacy path.

5.4. **`ws-protocol.test.ts` (extend, do not create new file)** — add Zod round-trip scenarios:
- "parses `{ type: 'context_reset', reason: 'prefill-guard', conversationId: '<uuid>' }`"
- "parses `{ type: 'context_reset', reason: 'tool_use_orphan', conversationId: '<uuid>' }`"
- "rejects unknown `reason` values"
- "rejects missing `conversationId`"

5.5. **`ws-known-types-guard.test.ts`** — add `context_reset` to the known-types allowlist.

5.6. **`chat-surface-context-reset.test.tsx`** (new file) — RTL render tests asserting:
- "renders the `prefill-guard` copy from `CONTEXT_RESET_COPY['prefill-guard']` when `reason: 'prefill-guard'`"
- "renders the `tool_use_orphan` copy from `CONTEXT_RESET_COPY['tool_use_orphan']` when `reason: 'tool_use_orphan'`"
- "renders with `data-message-type=\"context_reset\"` attribute"
- Tests import `CONTEXT_RESET_COPY` directly — never inline string literals.

### Phase 6 — Verification + ship

6.1. Run `npm run test` (or the verified test command from `package.json scripts.test`) for the web-platform package. All new + existing prefill-guard tests pass.

6.1a. **Three-pattern grep per `cq-union-widening-grep-three-patterns`** — after `WSMessage` widens with `context_reset`, run all three consumer patterns and document zero hits in the PR body:

```bash
rg "const _exhaustive: never" apps/web-platform/{lib,server,components}/
rg '\.type === "' apps/web-platform/{lib,server,components}/ | grep -v node_modules
rg '\?\.type === "' apps/web-platform/{lib,server,components}/ | grep -v node_modules
```

Any if-ladder hit not covered by an exhaustive switch must be widened in the same PR. Compiler does NOT flag if-ladders.

6.1b. **`vi.mock("../server/observability")` sweep** — if Phase 2/3 introduces new imports from `@/server/observability` (e.g., `reportSilentFallback`), grep `apps/web-platform/test/` for `vi.mock("../server/observability")` factories and update each to export the new symbols. Test stubs that omit the new export crash with "is not a function" at first run.

6.2. Manual QA via `apps/web-platform` dev: simulate a guard fire by injecting an assistant-final persisted session in `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, then send a follow-up message. Verify (i) chat strip renders with the prefill-guard copy, (ii) model response acknowledges context loss, (iii) Sentry shows one `op:prefill-guard` warn (no double-count). Capture screenshot for PR.

6.3. Repeat 6.2 with a tool_use-trailing fixture; verify the tool-aware copy renders and model refuses any "yes do that" follow-up.

6.4. Update PR #3419 from draft to ready. `Closes #3269` in PR body. CPO sign-off + `user-impact-reviewer` per single-user-incident threshold.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: Guard fires on assistant-terminated history → `contextResetNotice` populated, system-prompt receives notice, WS `context_reset` event emitted exactly once with `reason: "prefill-guard"`.
- [x] AC2: Guard fires on tool_use-trailing history → notice contains "do not execute without re-confirmation" directive; WS event emits with `reason: "tool_use_orphan"`.
- [x] AC3: Guard does NOT fire (user-final history) → no system-prompt mutation, no WS event.
- [x] AC4: Probe failure → no system-prompt mutation, no WS event, existing `prefill-guard-probe-failed` Sentry op fires.
- [x] AC5: Empty history → no system-prompt mutation, no WS event, existing `prefill-guard-empty-history` Sentry op fires.
- [x] AC6a: SDK retry inside one runner call does not re-emit `context_reset` (idempotent per fire).
- [x] AC6b: A subsequent dispatcher/runner call in the same session, where the guard does NOT fire, does NOT carry the notice forward (multi-turn non-accumulation; the notice is single-turn signal only — per spec AC6).
- [x] AC7: WS `context_reset` Zod-parses both `reason` variants; round-trips through `ws-known-types-guard.test.ts`.
- [x] AC8: Inline notice renders in `chat-surface.tsx` for both `reason` variants with the copywriter-approved strings (verbatim).
- [x] AC9: New + existing prefill-guard tests pass; no regression in `agent-prefill-guard.test.ts` existing scenarios.
- [x] AC10: `_SchemaCovers` proof in `ws-zod-schemas.ts` accepts the new variant; `tsc --noEmit` clean.
- [ ] AC11: Manual QA screenshots captured for both `reason` variants (PR comment).
- [ ] AC12: CPO sign-off recorded on PR; `user-impact-reviewer` review pass.

### Post-merge (operator)

- [ ] PM1: Verify production deploy via `web-platform-release` workflow succeeds.
- [ ] PM2: 7-day watch on Sentry `op:prefill-guard` count (per #3269 re-evaluation criteria for option (c)).

## Test Scenarios

See Phase 5 above. All scenarios written RED before implementation per `cq-write-failing-tests-before` (Test Scenarios present in this plan → TDD gate applies). Infrastructure-only carve-out does NOT apply (this is product code).

## Open Code-Review Overlap

7 open `code-review` issues touch files this plan modifies:

- **#3392** (PR-B deferrals — denied_jti, timer pair, /proc test, mock DRY, allowlist tightening) on cc-dispatcher.ts + agent-runner.ts. **Acknowledge** — separate concern (BYOK lease hardening, unrelated to prefill-guard). Plan does not touch the affected lines.
- **#3369** (Extract `mirrorWithDebounce` from cc-dispatcher.ts to observability module) on cc-dispatcher.ts. **Acknowledge** — extraction refactor; this plan only adds new logic at the guard-call line, not in the observability mirroring path.
- **#3243** (decompose cc-dispatcher.ts into focused modules) on cc-dispatcher.ts. **Acknowledge** — large architectural refactor; folding in would balloon scope past the (a)+(b) brainstorm decision.
- **#3242** (tool_use WS event lacks raw `name` field for agent consumers) on cc-dispatcher.ts + agent-runner.ts + lib/types.ts + ws-zod-schemas.ts. **Acknowledge** — closest domain (same WS surface, agent-native parity concern), but distinct change (adding a field to existing variant vs. adding a new variant). ADR-025 establishes the lifecycle-notice family precedent that #3242's eventual fix can leverage.
- **#2955** (process-local state assumption needs ADR + startup guard) on cc-dispatcher.ts + agent-runner.ts. **Acknowledge** — architectural concern unaffected by this PR.
- **#3343** (case-insensitive `</document>` escape across cc + leader prompt builders) on agent-runner.ts. **Acknowledge** — prompt sanitization is upstream of our notice-append site; our `\n\n` separator does not introduce sanitization concerns.
- **#3374** (emit `slot_reclaimed` WS frame for ledger-divergence recovery) on ws-zod-schemas.ts + ws-protocol.test.ts. **Acknowledge** — independent WS variant in same family. Both follow ADR-025 invariants when implemented; no merge conflict expected (both add new entries to the discriminated union without modifying existing entries).

No fold-ins. All 7 remain open and their PRs proceed independently.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm Phase 0.5)

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** (a) alone insufficient at single-user-incident threshold; asymmetric notification fails the brand contract. Recommend (a) tool-aware + (b), defer (c) behind Sentry signal as the issue specifies. Threshold push-back-resistant: paid-trust product, hallucinated continuation = single-user incident even when no data leaks. **CPO sign-off required at PR time per `requires_cpo_signoff: true`.**

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** WS taxonomy precedent solid (`fanout_truncated`, `tier_changed`); (b) cost negligible. System-prompt mutation safe per-turn (SDK `system` field is per-request, never persisted to JSONL). Tool_use orphan branches off same call site — included in same PR. (c) is greenfield (no native MCP server in `apps/web-platform/server/mcp/`); 1-week+ effort, defer correct. ADR-025 created for the lifecycle-notice category.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** WS event + UI badge is the floor for an autonomous-agent product with destructive tools — model-only signal does not discharge the platform's authorization-audit-trail duty. Re-confirmation modal (#3417) and privacy-policy disclosure update (#3418) deferred to separate domain-scoped issues; this PR is not gated on legal-document review.

### Product/UX Gate

**Tier:** advisory (modifies existing chat surface; mechanical-escalation does not fire — no new file under `components/**/*.tsx` is created, the inline notice extends `chat-surface.tsx` mirroring the existing `workflow_ended` pattern at lines 563-587).
**Decision:** auto-accepted (pipeline) — operator routed plan from brainstorm directly; ADVISORY in pipeline auto-accepts.
**Agents invoked:** copywriter (final user-facing copy), brainstorm-carry-forward CPO/CTO/CLO.
**Skipped specialists:** ux-design-lead (no new component file; pattern precedent exists in `chat-surface.tsx`), spec-flow-analyzer (single inline notice, no flow gaps).
**Pencil available:** N/A (no wireframes needed).

#### Findings

Copywriter delivered final copy (verbatim in Files to Edit). Both `reason` variants land as declarative single-clause statements; alternatives recorded for PR-time fallback. Pattern-match against `workflow_ended` (chat-surface.tsx:563-587) gives exact Tailwind class precedent — no new design system tokens introduced.

**Brainstorm-recommended specialists:** copywriter (invoked at plan time, output recorded above).

## Sharp Edges

- **`SessionMessage.message` is typed `unknown`.** Per `sdk.d.ts:2563`, the SDK declines to constrain the message shape — Phase 1.2's `isToolUseTrailing` guard is the runtime contract. Any non-object / null / unrecognized shape returns `false` (degrades to generic notice; never throws). Tests 5.1 cover the null/undefined/non-object branch — do not skip them.
- **systemPrompt accumulator drift in `agent-runner.ts`.** Last `+=` is at line 1047 (verified at plan time, inside the GitHub-read-access conditional); the `query({...})` call is at line 1166. The notice must land between those two anchors, not at the prose-anchored "~1170" — line 1170 is inside the `query({})` object literal. Re-read 1040-1170 at work time before inserting; refactors to the accumulator may shift both anchors.
- **`conversationId` availability — do NOT empty-string fallback.** If `conversationId` is missing in scope at the WS emit site, **do NOT emit** the WS event and call `reportSilentFallback` with `op: "prefill-guard-conversationid-missing"`. Empty-string would either fail the Zod `z.string()` schema (silent client parse failure, no render) or pass while being semantically malformed. Both worse than no-emit + Sentry signal.
- **Sentry double-count avoidance.** Existing `op:prefill-guard` warn = operator-side signal; new WS event = user-side signal. Do not add a second Sentry emit on the WS path (TR7). If a future operator wants Sentry instrumentation on WS-emit success/failure, MUST use a distinct op (e.g., `op: "context-reset-signal-sent"`) — never `op: "prefill-guard"` — to keep #3269's >10/7d trigger threshold accurate.
- **Agent-native parity gap (acknowledged).** WS `context_reset` is browser-bound; an external MCP-driven agent cannot subscribe. Acceptable today (no `apps/web-platform/server/mcp/` exists), but the WS event is fire-and-forget — a future `get_session_state` MCP tool (option (c) from #3269) will only see resets that occurred AFTER (c) shipped unless write-side persistence lands first. **Tracked in #3423** — to close BEFORE (c) enters the build queue.

## Risks

- **(low) WS event renders on the wrong thread.** Per Explore: per-conversation routing is single-WS-per-user with `conversationId` carried for forward-compat. `context_reset` includes `conversationId`; client today demuxes correctly because there's only one active thread. If multi-conversation tabs land before this ships, ensure `chat-surface.tsx` filters by active `conversationId` — current pattern (workflow_ended) already does.
- **(low) Tool_use detection misses non-standard content shape.** The SDK's `SessionMessage.content` shape is documented as `string | ContentBlock[]`. If a future SDK variant adds a third shape (e.g., wrapped object), tool_use detection silently degrades to the generic notice. Mitigation: Phase 1.2 documents both current shapes; widening when a third shape lands is a one-line fix.
- **(low) Copywriter copy drift.** Mitigated by Phase 4.5: `CONTEXT_RESET_COPY` const is the single source of truth; render and tests both import it. Inline string literals in tests are explicitly disallowed.
- **(medium) Defense-relaxation lens.** Current behavior on guard fire: drop `resume:`, model has zero memory, user sees clean turn. Adding a system-prompt notice **changes** what the model "sees" — instead of zero memory, it sees a notice telling it to ask for clarification. This is not a defense relaxation (we're adding context, not removing a check), but reviewers may interrogate whether the notice could itself be a prompt-injection vector if a user's prior message was somehow embedded. The notice text is hard-coded server-side; user input never flows into it. Document explicitly.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| (a) system-prompt notice only | CPO + CLO + CTO converged: asymmetric notification (model knows, user doesn't) fails single-user-incident threshold for an autonomous-agent product. (a) alone leaves the user-side discoverability gap. |
| (a)+(b)+(c) full stack | (c) is greenfield — no native MCP server in `apps/web-platform/server/mcp/`. 1-week+ effort. Issue #3269's >10/7d Sentry trigger is the right gate for (c). Building it preemptively conflates two roadmap initiatives. |
| (a)+(b)+CLO re-confirmation modal | Touches tool-approval flow surface — larger scope than the brainstorm decision. CLO floor honored by (a)+(b)+inline notice; modal hardening tracked in #3417 for re-evaluation when guard-fire frequency justifies. |
| (a)+(b)+privacy-policy update | Cross-domain (engineering + legal-document). Separate ship cadence. Tracked in #3418 — to land in same release window per CLO recommendation. |
| Render via toast / modal instead of inline strip | `workflow_ended` precedent is inline strip. Toasts compete with attention; modals interrupt. The notice is informational, not blocking. Inline strip is the brand-correct render. |

All deferred items have tracking issues per `wg-when-deferring-a-capability-create-a` (#3417, #3418). #3269 itself remains open and `Closes #3269` lands in the PR body at ship time.

## Cross-references

- Issue: #3269
- Parent PR (the one that introduced the silent-reset trade-off): #3263
- Draft PR for this work: #3419
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-prefill-guard-context-reset-signal-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-prefill-guard-context-reset-signal/spec.md`
- ADR-025: WS lifecycle-notice event family — `knowledge-base/engineering/architecture/decisions/ADR-025-ws-lifecycle-notice-event-family.md`
- Deferred tracking issues: #3417 (CLO re-confirmation modal), #3418 (CLO privacy-policy disclosure)
- Open code-review overlap (all Acknowledge): #3392, #3369, #3243, #3242, #2955, #3343, #3374
- Related rule: `hr-weigh-every-decision-against-target-user-impact`
- Related learning: `knowledge-base/project/learnings/2026-05-07-bot-fix-single-file-constraint-not-a-signal-for-brainstorm-fix-shape.md`
