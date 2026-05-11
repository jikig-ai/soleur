---
title: Wire conversations.session_id reader+writer for cc-soleur-go path
date: 2026-05-11
issue: 3266
related_issues: [3250, 3263, 3266, 3269, 3270]
related_prs: [3263]
type: bug
priority: p2-medium
branch: feat-one-shot-3266-cc-session-id-wiring
requires_cpo_signoff: true
status: draft
deepened_on: 2026-05-11
---

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Files to Edit, Implementation Phases 2-4, Risks (R7 added), Sharp Edges, Acceptance Criteria.
**Research artifacts verified:**

- SDK `SessionMessage` shape (`sdk.d.ts:2563-2569`): every transcript line carries `session_id: string`.
- SDK `getSessionMessages(sessionId, { dir })` (`sdk.d.ts:518`) is the helper the prefill guard already uses; no new SDK surface.
- SDK `resume?: string` on `Options` (`sdk.d.ts:1159-1161`): mutually exclusive with `forkSession` etc.; only consumed at cold-Query construction (not at warm-Query reuse). Threading is one-way; nothing in the SDK reads `args.sessionId` from a running Query.
- Migration `035_conversations_user_id_session_id_unique_total.sql` (`apps/web-platform/supabase/migrations/035_*.sql`): non-partial `unique(user_id, session_id)` with default `NULLS DISTINCT`. Confirmed live in dev/prd via prior `git log` and PR #3174 reference.
- Test pattern parity with `apps/web-platform/test/cc-dispatcher.test.ts:1-50` — `mockUpdateConversationFor` hoist + `vi.mock("@/server/conversation-writer", ...)` is the exact shape Phase 1 RED tests must use.

### Key Improvements

1. **Capture point refined.** The cc runner captures `session_id` only at `handleResultMessage` (line 1521), not at the first `system`/`assistant` message like legacy does (line 1468-1481). The plan now explicitly states this is **fine for the writer** (we persist after the SDK confirms a session) but adds a Phase 3 alternative considered (capture earlier on first non-result message bearing session_id) and explains why result-only is preferred (atomicity with `state.totalCostUsd` and `onResult` telemetry, which already commits cleanly).
2. **Stale-resume cleanup gap surfaced.** Legacy `agent-runner.ts:2211-2220` clears `session_id` when SDK resume fails. The cc path has no equivalent today — if the SDK rejects `resume` mid-stream (file deleted, schema drift), the next cold-Query will retry the same bad session_id. New R7 risk + a Phase 4.1 hook that clears `conversations.session_id` on a defined SDK-side failure class.
3. **`dispatchSoleurGo` parameter currently dead.** Verified via `grep -rn "dispatchSoleurGo({" apps/web-platform/ -A 20` that no production OR test call site passes `sessionId` today — making this plan's reader wiring activate a parameter that has been dormant since the cc-soleur-go cutover. Test invariant updates required: none of the 14 existing `dispatchSoleurGo` calls in `apps/web-platform/test/cc-dispatcher.test.ts` assert on `sessionId`, so no test rewrites needed.
4. **Mock pattern verified.** The hoisted `mockUpdateConversationFor` pattern at `cc-dispatcher.test.ts:1-23` is the canonical shape — Phase 1 RED tests reuse it verbatim. No new mock infrastructure needed.

### New Considerations Discovered

- **Realtime publication unaffected.** Migration 039 (`drop_messages_from_realtime_publication.sql`) and the conversation realtime invariant from migration 034 do not touch `session_id`. Writing this column does NOT propagate over realtime to clients — backend-only persistence, as intended.
- **Cross-tab determinism.** The SDK session_id is opaque to the client; two tabs viewing the same conversation never see this value directly. No client-side cache invalidation concern.
- **Sentry breadcrumb amplification.** The prefill guard's `op: "prefill-guard-empty-history"` breadcrumb (`agent-prefill-guard.ts:222-231`) will start firing on the cc path once this lands — it has been dormant. Phase 6 baseline expectation updated: a small non-zero rate is normal for empty-history cases (file rotation, ttl, etc.).

# Plan: Wire `conversations.session_id` reader + writer for cc-soleur-go path

## Overview

Issue #3266 is the **Approach C** carve-out from PR #3263. The shared `apps/web-platform/server/agent-prefill-guard.ts` helper is wired into both the legacy `startAgentSession` path (production-effective today) and the cc-soleur-go `realSdkQueryFactory` path (currently dormant). The cc path's guard is dormant because the upstream wiring from the WebSocket frame to the runner is broken on two ends:

1. **Reader gap** — `apps/web-platform/server/ws-handler.ts` `dispatchSoleurGoForConversation` (lines 820-944) does NOT thread `conversations.session_id` to `dispatchSoleurGo`. The SELECT at `ws-handler.ts:1468-1496` reads `session_id` from the row but only forwards `active_workflow` to `parseConversationRouting` and seeds `context_path` on `session.contextPath` — `session_id` is silently discarded.

2. **Writer gap** — there is no writer that persists the cc runner's `state.sessionId` (`apps/web-platform/server/soleur-go-runner.ts:1524`) back to `conversations.session_id`. The legacy `agent-runner.ts:1468-1481` writer fires from inside its own message loop on first message with `session_id`; the cc path has no equivalent.

Together: `args.resumeSessionId` reaches `realSdkQueryFactory` as `undefined` on every cold start, the prefill guard short-circuits at its first branch (`if (!args.resumeSessionId) return ...`), and the SDK starts a fresh server-side session. The cc path loses cross-restart conversation memory but is also immune to the prefill 400 by construction.

This plan closes both gaps so the cc path achieves parity with legacy: on cold-Query construction after a server reap or container restart, the runner resumes the SDK session using the persisted `session_id`, the prefill guard becomes production-effective, and conversation memory survives across restarts.

## User-Brand Impact

**If this lands broken, the user experiences:** A Concierge bubble that either (a) silently forgets prior conversation context across server restart / idle reap (regression of memory continuity), or (b) shows the raw Anthropic 400 "model does not support assistant message prefill" if the writer ships but the guard fails to fire — the exact failure mode #3263 was filed to prevent.

**If this leaks, the user's workflow is exposed via:** Two writer-side risk shapes. First, the (user_id, session_id) uniqueness contract on migration 035 (`uniq_conversations_user_id_session_id_total`) means a writer that races itself across two conversations OR across a tab-resume + new-conversation insert can trigger 23505 — visible to the user as a "Dashboard router is unavailable" message. Second, the cross-write invariant (a writer scoping by conversation_id but mis-attributing to another user) is currently the load-bearing protection against one user's session_id landing on another user's conversation row; we MUST keep the `eq("user_id", userId)` filter on every write per `wg-cross-tenant-write-via-foreign-key-update` and the `updateConversationFor` wrapper's `expectMatch: true` contract.

**Brand-survival threshold:** `single-user incident`.

Per the parent brainstorm (`knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`) the Concierge surface is the first-touch interactive surface for new users. A regression here — even a benign-looking "I don't remember our prior conversation" — collapses trust on the highest-blast-radius surface. CPO sign-off required at plan time (carry-forward from #3250 brainstorm `USER_BRAND_CRITICAL=true`); `user-impact-reviewer` agent invoked at review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body / brainstorm) | Reality (verified in worktree HEAD) | Plan response |
|---|---|---|
| `apps/web-platform/server/agent-prefill-guard.ts` is wired into both `realSdkQueryFactory` (cc) and `startAgentSession` (legacy). | Confirmed: `agent-prefill-guard.ts:184` exports `applyPrefillGuard`; cc call site at `cc-dispatcher.ts:480`; legacy call site at `agent-runner.ts:42` import + body usage. | No change to guard wiring — Approach C is upstream of the guard, not at it. |
| Reader gap at `ws-handler.ts:539-630`. | Adjusted line range: `dispatchSoleurGoForConversation` lives at `ws-handler.ts:820-944` (HEAD shifted vs issue body). SELECT discarding `session_id` is at `ws-handler.ts:1470` (column read), `1483-1487` (typedRow shape), `1488-1495` (seed step omits session_id). | Plan §Phase 2 prescribes adding `sessionId` to `ClientSession`, threading from typedRow, and forwarding into `dispatchSoleurGoForConversation`. |
| Writer gap; no cc-side equivalent of `agent-runner.ts:951-957`. | Adjusted: legacy writer lives at `agent-runner.ts:1468-1481` (HEAD shifted). The writer is invoked inside the message loop on first message bearing `session_id`. Runner state field `state.sessionId` is already captured by cc runner at `soleur-go-runner.ts:1524` inside `handleResultMessage`. | Plan §Phase 3 prescribes a new `DispatchEvents.onSessionIdCaptured(sessionId: string)` hook fired exactly once when the runner first observes a non-null `session_id`, wired from cc-dispatcher to a tenant-scoped `updateConversationFor` write. |
| Migration 035 uniqueness contract requires the cc path to satisfy a uniqueness invariant that doesn't currently exist. | Confirmed: `035_conversations_user_id_session_id_unique_total.sql` is a NON-partial unique on `(user_id, session_id)` with NULLs DISTINCT. Multiple (user_id, NULL) rows coexist; collision only on (same user, same non-null session_id). | Plan §R3 — handle 23505 on session_id write as "another conversation already owns this session_id"; this should never happen in practice (the SDK mints fresh session_ids per-Query) but defense-in-depth via the existing `updateConversationFor` error handling. |
| Open question: how to handle race with `active_workflow` writer. | The two writers target different columns (`session_id` vs `active_workflow`) on the same row; PostgreSQL serializes UPDATEs at row-lock level. No corruption risk; ordering observable to next-turn reader is the only concern. | Plan §R5 — session_id writer fires after first SDK message captured (`handleResultMessage` boundary); active_workflow writer fires from `persistActiveWorkflow`. They are serialized by the SDK message stream order, not by us. |

## Hypotheses

None — this is not an SSH / network outage. The Network-Outage Hypothesis Check (Phase 1.4) does not fire on this plan.

## Files to Edit

- `apps/web-platform/server/ws-handler.ts` — thread `session_id` from the SELECT through `ClientSession.sessionId` cache and into `dispatchSoleurGoForConversation` → `dispatchSoleurGo`. Touchpoints: `ClientSession` interface at line 105-147; SELECT at line 1468-1496; `dispatchSoleurGoForConversation` signature at line 820 and call sites at 1409 and 1507; `dispatchSoleurGo` invocation at line 933.
- `apps/web-platform/server/cc-dispatcher.ts` — wire `onSessionIdCaptured` event handler in the `events` object (line 972). Add `persistCcSessionId` and `clearCcSessionId` module-private helpers above `dispatchSoleurGo` (line 817). `sessionId` already passes through from `args` at line 825 and line 1070; no change to the dispatch arg spread.
- `apps/web-platform/server/soleur-go-runner.ts` — add `DispatchEvents.onSessionIdCaptured?: (sessionId: string) => void` (line 625-646 interface). Fire from `handleResultMessage` (line 1521) on the first transition from `state.sessionId === null` → non-null. Track via state field `sessionIdEverEmitted: boolean` to ensure the once-only contract. Capture point is `handleResultMessage` only (not `consumeStream`'s `system`/`user` branches) — see Phase 3 "Capture-point rationale".
- `apps/web-platform/server/agent-prefill-guard.ts` — no logic change; the guard's history-probe branch becomes production-effective on the cc path once Phase 2 lands.

## Files to Create

- `apps/web-platform/test/ws-handler-cc-session-id-wiring.test.ts` — read-side regression. SELECT row carries `session_id: "sess-X"`; assert `dispatchSoleurGoForConversation` invokes `dispatchSoleurGo` with `sessionId: "sess-X"`.
- `apps/web-platform/test/cc-dispatcher-session-id-writer.test.ts` — write-side regression. Stub runner fires `onSessionIdCaptured("sess-Y")`; assert `updateConversationFor` is called with `{ session_id: "sess-Y" }`, scoped by `(id, user_id)`, and that a second fire from the same state does NOT issue a second write (once-only contract).
- `apps/web-platform/test/soleur-go-runner-session-id-rebound.test.ts` — runner-side event emission. Feed a `result` message with `session_id: "sess-Z"`; assert `onSessionIdCaptured("sess-Z")` fires once. Feed a second `result` with the same `session_id`; assert no second fire.

## Open Code-Review Overlap

Three open code-review scope-outs touch files this plan modifies:

- **#3343 — case-insensitive `</document>` escape across cc + leader prompt builders** (`soleur-go-runner.ts`). **Acknowledge.** This is an unrelated prompt-builder concern in the same file; the session_id event hook lives in `handleResultMessage`, not the prompt-building path. The scope-out remains open.
- **#2955 — process-local state assumption needs ADR + startup guard** (`cc-dispatcher.ts`, `soleur-go-runner.ts`). **Acknowledge.** The cc runner's session-id capture and persistence is itself process-local (matches the existing pattern). This plan does not widen the process-local assumption; it inherits it. The scope-out remains open for the broader ADR.
- **#3243 — decompose cc-dispatcher.ts into focused modules** (`cc-dispatcher.ts`). **Acknowledge.** Adding a single `onSessionIdCaptured` handler does not materially worsen the decomposition problem. The scope-out remains open.

The remaining open scope-outs on these files (#3374, #3372, #3369, #3242, #2191, #2963) target unrelated surfaces (slot_reclaimed event, ledger-divergence tautology, mirrorWithDebounce extraction, tool_use raw name, session timers, ConversationPatch typegen) — none of these overlap.

## Implementation Phases

### Phase 0 — Pre-flight

1. Verify worktree is clean and on `feat-one-shot-3266-cc-session-id-wiring`.
2. Read the prior plan `2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §Phase 3 update to confirm the legacy fold-in shape.
3. Verify migration `035_conversations_user_id_session_id_unique_total.sql` is applied on dev (`doppler run -p soleur -c dev --silent -- psql "$DATABASE_URL" -c "\d+ public.conversations"` and inspect for `uniq_conversations_user_id_session_id_total`).

### Phase 1 — RED (writer-side tests)

Author the three failing tests before any production code change, per `cq-write-failing-tests-before`:

1. `soleur-go-runner-session-id-rebound.test.ts` — assert the runner emits `onSessionIdCaptured` exactly once per state on first non-null `session_id`. Verify duplicate / unchanged session_id messages do NOT re-fire. Verify a runner that never sees `session_id` does NOT fire.
2. `cc-dispatcher-session-id-writer.test.ts` — inject a stub runner that fires `onSessionIdCaptured("sess-Y")` mid-dispatch; assert exactly one call to `updateConversationFor(userId, conversationId, { session_id: "sess-Y" }, { feature: "cc-dispatcher", op: "persist-session-id", expectMatch: true })`. Assert a transient DB error mirrors to Sentry via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` and does NOT abort the dispatch (memory degradation only — does not block the user's current turn).
3. `ws-handler-cc-session-id-wiring.test.ts` — mock the supabase select to return `{ active_workflow: "brainstorm", session_id: "sess-X", context_path: null }`; invoke the chat-case branch; assert `dispatchSoleurGo` is invoked with `sessionId: "sess-X"`. Add a second scenario: warm session with `session.sessionId` already cached — assert no DB roundtrip and `sessionId: <cached>` is forwarded.

Run the suite; confirm all three fail.

### Phase 2 — GREEN reader (`ws-handler.ts`)

1. Add `sessionId?: string | null` to the `ClientSession` interface (`ws-handler.ts` — locate via the same diff block as `routing` and `contextPath`).
2. Extend the `session.routing && session.contextPath !== undefined` cache-check branch at `ws-handler.ts:1465` so the cache-hit path returns `session.sessionId ?? null` alongside routing. Cache miss reads `session.sessionId` from `typedRow.session_id` and seeds.
3. Extend `dispatchSoleurGoForConversation` to accept a `sessionId?: string | null` parameter and pass it through to `dispatchSoleurGo({ ...args, sessionId })`.
4. Update both call sites of `dispatchSoleurGoForConversation` (the chat-case deferred-materialization branch at `ws-handler.ts:1409` and the chat-case routed branch at `ws-handler.ts:1507`) to forward `sessionId`. For the deferred-materialization branch (first turn after start_session), `sessionId` is always `null` (the conversation was just inserted — see `createConversation`); explicitly pass `null`.

Re-run the reader test (`ws-handler-cc-session-id-wiring.test.ts`); confirm pass. Writer tests still fail (expected).

### Phase 3 — GREEN runner event (`soleur-go-runner.ts`)

1. Extend `DispatchEvents` (`soleur-go-runner.ts:625-646`) with an optional `onSessionIdCaptured?: (sessionId: string) => void;`. Optional so existing non-cc tests stay green.
2. Inside `handleResultMessage` (currently at line 1521), capture the prior value of `state.sessionId` before the assignment, then after the assignment check if `state.sessionId !== priorSessionId && state.sessionId !== null`. If so, invoke `state.events.onSessionIdCaptured?.(state.sessionId)` inside a try/catch that mirrors via `reportSilentFallback` with `feature: "soleur-go-runner", op: "onSessionIdCaptured"` per `cq-silent-fallback-must-mirror-to-sentry`.
3. Add a state field `sessionIdEverEmitted: boolean` (default `false`) so a runner that observes a session_id, then sees the same session_id again, does NOT re-fire. Re-fire only when the value changes (defensive — should not happen in practice; SDK session_id is stable for the lifetime of one Query).

**Capture-point rationale (alternatives considered).** The legacy `agent-runner.ts:1468-1481` writer captures `session_id` from the FIRST inbound message of any type (system, user, assistant — all carry `session_id` per `sdk.d.ts:2563-2569`). The cc runner currently ignores `system` and `user` messages entirely (`consumeStream` at `soleur-go-runner.ts:1570-1585`) and only inspects `assistant` / `result` / `user-tool-result`. We considered two capture strategies:

- **Strategy A — capture at first `result`** (chosen): fire `onSessionIdCaptured` from `handleResultMessage`. session_id is captured atomically with `state.totalCostUsd` and `onResult` telemetry, both of which already commit cleanly. The first turn must complete before we persist — acceptable because the prefill guard only needs session_id on the NEXT cold-Query construction (server restart, idle reap, container restart), not within the current turn.
- **Strategy B — widen `consumeStream` to inspect `system` / `user`** (rejected): more code paths, no observable user benefit. The persist could land seconds earlier, but no cold-Query construction happens within the active turn, so earlier persistence buys nothing.

Run the runner test; confirm pass.

### Phase 3.1 — Stale-resume cleanup hook

The legacy path clears `conversations.session_id` when `startAgentSession(... resumeSessionId)` rejects (`agent-runner.ts:2211-2220`). This handles the case where the persisted session file is deleted, schema-drifted, or unreadable for any reason that bypasses the prefill guard's history probe. The cc path has no equivalent today — if the SDK rejects `resume` mid-stream (post-probe, e.g., a race between probe and `query()` construction), the bad session_id stays in the DB and the next cold-Query retries the same failure.

1. In `cc-dispatcher.ts dispatchSoleurGo` catch block (currently at line 1082), extend the `KeyInvalidError`-and-generic branch with a new condition: when the error is NOT a `KeyInvalidError` AND the dispatch was called with a non-null `sessionId`, fire-and-forget `void clearCcSessionId({ userId, conversationId })` before sending the generic error to the client.
2. New module-private helper `clearCcSessionId` mirrors `persistCcSessionId` but writes `{ session_id: null }`:
   ```typescript
   async function clearCcSessionId(args: {
     userId: string;
     conversationId: string;
   }): Promise<void> {
     const { ok } = await updateConversationFor(
       args.userId,
       args.conversationId,
       { session_id: null },
       {
         feature: "cc-dispatcher",
         op: "clear-stale-session-id",
         expectMatch: true,
       },
     );
     if (!ok) {
       log.error({ conversationId: args.conversationId }, "cc-dispatcher: failed to clear stale session_id");
     }
   }
   ```
3. Test the cleanup branch: stub `runner.dispatch` to throw a generic `Error` with the runner having received a `sessionId`; assert `updateConversationFor` is invoked with `{ session_id: null }` and that the second dispatch with the same args fires the prefill guard's cold-start short-circuit (the cleared session_id surfaces as `args.resumeSessionId: undefined` in the runner). Add this scenario to `cc-dispatcher-session-id-writer.test.ts`.

### Phase 4 — GREEN writer (`cc-dispatcher.ts`)

1. In `dispatchSoleurGo` (currently at line 817), construct the `events` object (currently at line 972) with an `onSessionIdCaptured: (sessionId: string) => void` that calls `void persistCcSessionId({ userId, conversationId, sessionId })`. Fire-and-forget; the user's current turn does NOT depend on this write landing.
2. Extract `persistCcSessionId` as a new module-private helper above `dispatchSoleurGo`. Body:
   ```typescript
   async function persistCcSessionId(args: {
     userId: string;
     conversationId: string;
     sessionId: string;
   }): Promise<void> {
     const { ok, error } = await updateConversationFor(
       args.userId,
       args.conversationId,
       { session_id: args.sessionId },
       {
         feature: "cc-dispatcher",
         op: "persist-session-id",
         expectMatch: true,
       },
     );
     if (!ok) {
       // updateConversationFor already mirrors to Sentry on error;
       // log here only for cross-debugging with legacy `agent-runner.ts:1479`.
       log.error({ conversationId: args.conversationId, err: error }, "cc-dispatcher: failed to persist session_id");
     }
   }
   ```
3. The 23505 path (uniqueness violation on `(user_id, session_id)`): `updateConversationFor` already mirrors via `reportSilentFallback`. No special-casing here — the 23505 surface is theoretical (the SDK does not reuse session_ids across Queries), but if it ever fires the Sentry event lets us audit.

Run all three tests; confirm pass.

### Phase 5 — Integration check

1. Run `bun test apps/web-platform/test/` — full suite. No regressions expected; the new event field is optional.
2. Run `bun run tsc --noEmit` from `apps/web-platform/`. Verify no new type errors.
3. Manual smoke (local with `bun run dev` + Doppler dev): open Command Center, send a Concierge message, observe `state.sessionId` is captured in runner logs, restart the dev server, send a follow-up, verify `args.resumeSessionId` is non-null and `applyPrefillGuard` enters its history-probe branch (Sentry breadcrumb under `op: "prefill-guard"` if the probe finds a user-terminated thread, or `op: "prefill-guard-probe-failed"` if the session file is missing).

### Phase 6 — Sentry observability audit

Verify the writer's silent-fallback surfaces are observable:

- `cc-dispatcher` `op: "persist-session-id"` — mirrored by `updateConversationFor` on DB error. Search Sentry for this op after a 24h soak; baseline should be zero.
- `soleur-go-runner` `op: "onSessionIdCaptured"` — fires only if the user-supplied event callback throws (defensive; the cc-dispatcher's callback is `void persistCcSessionId(...)` which never throws synchronously).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `ws-handler-cc-session-id-wiring.test.ts` passes; `dispatchSoleurGo` receives `sessionId` from the typedRow SELECT and from the `session.sessionId` cache.
- [ ] `cc-dispatcher-session-id-writer.test.ts` passes; `onSessionIdCaptured` event triggers exactly one `updateConversationFor` call with `{ session_id }`, `expectMatch: true`, scoped to `(id, user_id)`.
- [ ] `cc-dispatcher-session-id-writer.test.ts` stale-resume scenario passes; a non-`KeyInvalidError` rejection from `runner.dispatch` with a non-null `sessionId` triggers exactly one `updateConversationFor` call with `{ session_id: null }`.
- [ ] `soleur-go-runner-session-id-rebound.test.ts` passes; runner fires `onSessionIdCaptured` exactly once per state on first non-null `session_id`.
- [ ] Full `apps/web-platform/test/` suite green: `bun test apps/web-platform/test/`.
- [ ] `bun run tsc --noEmit` from `apps/web-platform/` reports no new errors.
- [ ] PR body uses `Closes #3266` on its own line (not in a checkbox / code block) per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] PR includes `user-impact-reviewer` agent review per AGENTS.md `hr-weigh-every-decision-against-target-user-impact` (threshold: `single-user incident`).
- [ ] Labels applied: `priority/p2-medium`, `type/bug`, `domain/engineering` (each verified to exist via `gh label list --limit 200`).

### Post-merge (operator)

- [ ] Smoke-verify in prd: open Command Center, send Concierge message, force a server restart (or wait for idle reap), send follow-up. Confirm via Sentry breadcrumbs under `feature: "cc-concierge"` that the prefill guard is now production-effective (search for `op: "prefill-guard"` or `op: "prefill-guard-probe-failed"`). The pre-merge baseline is zero events; post-merge the baseline becomes non-zero for actual restart-and-resume flows.

## Test Strategy

Mirrors the existing test conventions for this surface:

- **Vitest** is the existing framework (`bun test` runs vitest under the hood per `apps/web-platform/package.json`). No new framework introduced.
- **Stub runner pattern** is the established shape: see `apps/web-platform/test/cc-dispatcher.test.ts` and `cc-dispatcher-bash-gate.test.ts` which both use `__setCcRunnerForTests` (exported test seam in `cc-dispatcher.ts:1186`) to inject a stub `SoleurGoRunner`.
- **Mock query pattern** in `soleur-go-runner-lifecycle.test.ts:63` (`createMockQuery`) provides the `emit(makeResult)` pattern for feeding `SDKResultMessage` to the runner. Reuse this; do not invent a new shape.
- **Supabase mock** for ws-handler tests follows the pattern in `ws-handler-context-path-23505.test.ts` and `ws-handler-cc-pdf-breadcrumb.test.ts`. Reuse the `mockSupabaseChainable` helper or its inline equivalent.

## Risks

- **R1 — Writer fires after user closes tab.** The runner emits `onSessionIdCaptured` from `handleResultMessage`, which can fire after the user's WS disconnects (the runner survives reconnects). The write is fire-and-forget and tenant-scoped via `updateConversationFor`'s `eq("user_id", userId)` invariant; the worst case is a Sentry event under `op: "persist-session-id"` if RLS rejects. **Mitigation:** the write goes to the conversation row, not a user-keyed table, so RLS / ownership reads consistently.
- **R2 — Once-only contract is per-state, not per-conversation.** A reap + new dispatch creates a fresh `state`; the new state's `sessionId` will fire `onSessionIdCaptured` again with the (likely) same session_id (since `resumeSessionId` is passed in and the SDK reuses it). The writer is idempotent at the DB level (`UPDATE ... SET session_id = X WHERE id = Y AND user_id = Z`); writing the same value twice is a no-op apart from `last_active` (which is not updated here — only the previously-stamped `cc-dispatcher op: "verify-conversation-ownership"` write at line 843 updates `last_active`). Acceptable.
- **R3 — 23505 on (user_id, session_id) uniqueness.** Theoretical only — the SDK mints fresh session_ids per-Query; no two conversations should ever own the same session_id. If it ever fires, the `updateConversationFor` wrapper mirrors to Sentry under `op: "persist-session-id"`; the user sees no visible failure (write was fire-and-forget). **Mitigation:** treat any Sentry event under this op + 23505 as a P1 page — it means an SDK invariant has shifted.
- **R4 — Reader cache stales after writer fires.** The writer updates `conversations.session_id`, but the `ClientSession.sessionId` cache in the ws-handler is not invalidated. On the same WS session's next turn, the cache returns the prior `null` and the runner re-resumes from `undefined`. **Mitigation:** when the runner state has `sessionId !== null` (warm Query path), the runner ignores the incoming `args.sessionId` and uses its existing `state.sessionId`. On cold-Query construction (after reap), the cache is correctly stale, but the next read from `typedRow.session_id` repopulates it. Acceptable.
- **R5 — Race between `session_id` writer and `active_workflow` writer.** Both target the same conversation row but different columns. PostgreSQL serializes the UPDATEs at the row-lock level; the writes are commutative for the (next-turn read, observability) pair we care about. No corruption risk.
- **R6 — Cross-tab session_id contamination.** If a user has two Command Center tabs open for the same conversation and the cc path is active in both, the runner is a process-singleton keyed by `conversationId`; both tabs would observe the same `state.sessionId`. The writer fires once per state. Multi-tab is not in scope for V1 (single-tab per conversation is the documented invariant). No additional mitigation.
- **R7 — Stale resume after non-prefill SDK failures.** The prefill guard catches assistant-terminated threads, but other SDK-side failures bypass it: missing session file (file-system rotated/cleared between probe and `query()`), schema drift between SDK versions, or an SDK internal that rejects `resume` at construction time. Without a cleanup writer, the next cold-Query construction retries the same bad session_id indefinitely. **Mitigation:** Phase 3.1 adds `clearCcSessionId` in the cc-dispatcher catch branch — only fires when (a) the dispatch was attempted with a non-null sessionId AND (b) the error is not `KeyInvalidError` (which has its own user-facing message). Behaviorally equivalent to the legacy `agent-runner.ts:2211-2220` stale clear.

## Sharp Edges

- The `onSessionIdCaptured` event is optional on `DispatchEvents`. Non-cc tests that omit it must continue to pass; the runner uses optional-chaining at the fire site. Drift-guard: add a comment on the field linking to this plan so a future refactor doesn't promote it to required without revisiting the no-op test cases.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here.
- When extending `ClientSession` with `sessionId`, grep for every other `ClientSession` consumer (`grep -rn "ClientSession" apps/web-platform/server/`) to confirm no other site reconstructs the type literal and silently drops the new field.
- The writer is fire-and-forget but the read at `conversations.session_id` is synchronous on the next cold-Query turn. If a user fires a follow-up turn within the few-millisecond window between `onSessionIdCaptured` and the DB write landing, the next-turn read returns the prior `null`. Acceptable: the runner's in-memory `state.sessionId` covers warm-Query case; cold-Query within that window is a one-turn memory regression, not a 400.
- `dispatchSoleurGo`'s existing `sessionId` parameter is documented at `cc-dispatcher.ts:757` and used at `cc-dispatcher.ts:1070`. The wiring change in Phase 2 / Phase 4 makes this parameter live — currently it is always `undefined`. Verified via `grep -rn "dispatchSoleurGo({" apps/web-platform/ -A 20`: none of the 14 existing call sites pass `sessionId`, so no test rewrites are required for this surface.
- The cc runner ignores SDK `system` and (non-tool-result) `user` messages in `consumeStream` (line 1570-1585). The SDK emits `session_id` on those types per `sdk.d.ts:1772-1789`, but the cc runner's capture is `result`-only. This is correct behavior for the writer (Phase 3 "Capture-point rationale") but the field of view is narrower than legacy — a future refactor that widens the runner's message inspection (e.g., for hook events) MUST NOT silently move `state.sessionId` capture to an earlier point without updating the once-only contract.
- SDK `resume?: string` (`sdk.d.ts:1159-1161`) is mutually exclusive with `forkSession` and the `continue` option. The cc path does not use `forkSession` or `continue`, so the only constraint relevant here is "`resume` is consumed at cold-Query construction only." Verified in `cc-dispatcher.ts:480-488` (`applyPrefillGuard` runs as part of the cold construction promise pair) and `soleur-go-runner.ts:1632` (`resumeSessionId = args.sessionId ?? undefined` only on the cold branch where `!state`).
- Labels prescribed in Acceptance Criteria (`priority/p2-medium`, `type/bug`, `domain/engineering`, `deferred-scope-out` already applied to #3266) — all four verified to exist via `gh label list --limit 200` on 2026-05-11.

## Test Scenarios

1. **Reader cold path** — supabase SELECT returns `{ active_workflow: "brainstorm", session_id: "sess-X", context_path: null }`; assert `dispatchSoleurGo` invoked with `sessionId: "sess-X"`.
2. **Reader warm path** — `session.sessionId = "sess-Y"` cached; assert no DB roundtrip and `sessionId: "sess-Y"` is forwarded.
3. **Reader cold path with NULL session_id** — fresh conversation; assert `sessionId: null` is forwarded.
4. **Runner event first-fire** — feed `result` with `session_id: "sess-Z"`; assert `onSessionIdCaptured("sess-Z")` fires exactly once.
5. **Runner event idempotent** — feed two `result` messages with same `session_id`; assert `onSessionIdCaptured` fires once.
6. **Runner event no-fire** — runner that never observes `session_id` (test stub messages without the field); assert `onSessionIdCaptured` never fires.
7. **Writer single fire** — stub runner fires `onSessionIdCaptured("sess-Y")`; assert single `updateConversationFor` call with `{ session_id: "sess-Y" }`.
8. **Writer DB error mirror** — `updateConversationFor` returns `{ ok: false, error: <PostgresError> }`; assert error is logged (Sentry mirror via `reportSilentFallback` already inside `updateConversationFor`); assert dispatch continues (no throw to user).
9. **Writer cross-tenant defense** — stub `updateConversationFor` to verify it is invoked with the correct `(userId, conversationId)` pair and `expectMatch: true`.
10. **End-to-end resume after reap** — (integration smoke, deferred to Phase 5 manual) cold conversation, capture session_id, force reap, send follow-up, observe `applyPrefillGuard` history-probe branch fires.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO).

### Engineering

**Status:** reviewed (carry-forward from `2026-05-05-cc-session-bugs-batch-brainstorm.md` §Domain Assessments → Engineering).
**Assessment:** The cc-runner's `state.sessionId` is already captured at the message-stream boundary; the gap is purely event-plumbing (runner → dispatcher → DB) and reader-plumbing (ws-handler SELECT → dispatch args). The right shape is an optional event field plus an `updateConversationFor` write — both established patterns in this module. No new architectural decisions.

### Product/UX Gate

**Tier:** none.
**Decision:** auto-accepted (pipeline) — no new user-facing UI, no new pages, no new components. Bug fix scoped to server-side session continuity. The user-facing artifact is the existing Concierge bubble; behavior preserved (memory continuity across restarts).
**Agents invoked:** none (correctly scoped out under tier=none).
**Skipped specialists:** ux-design-lead (no UI surface), copywriter (no copy change), spec-flow-analyzer (no flow change).
**Pencil available:** N/A.

## GDPR / Compliance Gate

`conversations.session_id` is an SDK-generated opaque identifier (random UUID-shape). It is not a regulated-data field (no PII, no auth payload, no Art. 9 special-category). The canonical regex in `plugins/soleur/skills/gdpr-gate/SKILL.md` does not match — this plan does NOT touch `auth/`, `users/`, schemas with PII fields, API routes accepting user data, or `.sql` files with personally-identifying columns. Migration 035 is read-only context, not modified by this plan.

Gate skipped silently per Phase 2.7 procedure.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`
- Prior plan (Approach C origin): `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §Phase 3 update
- PR #3263 (landed legacy fold-in; created this scope-out): see `git log --oneline | grep 3263`
- Learning: `knowledge-base/project/learnings/best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`
- Migration: `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql`
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — single-user incident threshold
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — observability contract for the writer error path
- AGENTS.md `cq-write-failing-tests-before` — Phase 1 RED-first sequencing
