---
title: "Tasks — fix kb-chat fresh-conversation history-fetch 404"
plan: knowledge-base/project/plans/2026-06-02-fix-kb-chat-fresh-conversation-history-404-plan.md
lane: single-domain
brand_survival_threshold: single-user incident
status: pending
---

# Tasks — kb-chat fresh-conversation history-fetch 404 (deferred-row race)

Derived from the finalized plan. Run vitest via `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT bun).

## Phase 0 — Preconditions

- [x] 0.1 Re-read `apps/web-platform/lib/ws-client.ts:791-822` (session_started/session_resumed handlers) and `:1198-1217` (mount + resume history effects) to confirm shapes unchanged since plan.
- [x] 0.2 Re-read `apps/web-platform/server/api-messages.ts:103-120` (404 site) and confirm `warnSilentFallback` import is available from `@/server/observability`.
- [x] 0.3 Confirm deferred-creation insert is still single-site at `apps/web-platform/server/ws-handler.ts:816` (TR1 invariant).

## Phase 1 — Failing tests (RED)

- [x] 1.1 (AC1/FR1) In `test/kb-chat-resume-hydration.test.tsx`: assert `fetchSpy` is NOT called after a `session_started` frame while `conversationId="new"`.
- [x] 1.2 (AC2/FR2) Assert `fetchSpy` IS called once after `session_resumed` (messageCount 0) while `conversationId="new"`; 200-empty hydrates zero messages, no error.
- [x] 1.3 (AC3/FR4) Assert `warnSilentFallback` invoked on `res.status === 404`; `reportSilentFallback` invoked on `res.status === 500`.
- [x] 1.4 (AC4/FR3) In `test/api-messages-handler.test.ts`: GET for non-existent conversation → HTTP 404 + `warnSilentFallback` called with `op: "history-fetch-404-not-owned-or-missing"`; `reportSilentFallback` NOT called for that op; body `{ error: "Conversation not found" }` unchanged.
- [x] 1.5 (AC9/FR5) In `test/ws-client-resume-history.test.tsx`: with `conversationId="<uuid>"` (non-"new") + mocked 404, hook settles `historyLoading===false`, `messages.length===0`, `lastError===null`.

## Phase 2 — Implementation (GREEN)

- [x] 2.1 (TR2a) Add `sessionKind: "fresh" | "resumed" | null` state to `useWebSocket`; set `"fresh"` in `session_started` handler, `"resumed"` in `session_resumed` handler.
- [x] 2.2 (FR1/FR2) Gate the resume-history effect (`ws-client.ts:1209-1217`) on `sessionKind === "resumed"` so a `session_started` deferred UUID does NOT fetch; `session_resumed` (any messageCount) still fetches.
- [x] 2.3 (FR4) In `fetchConversationHistory` non-OK branch (`ws-client.ts:1007-1014`): emit `warnSilentFallback` for `res.status === 404`, keep `reportSilentFallback` for other non-OK statuses.
- [x] 2.4 (FR3) In `api-messages.ts:112`: swap `reportSilentFallback` → `warnSilentFallback` at the `history-fetch-404-not-owned-or-missing` site; add/confirm import. Keep HTTP 404 and op string unchanged.
- [x] 2.5 (FR5) Verify ChatSurface empty-state renders for non-"new" id + 404 (empty composer, not error boundary). Only edit `chat-surface.tsx` if AC9 reveals a gap.

## Phase 3 — Verify

- [x] 3.1 (AC7) `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] 3.2 (AC5) `git grep -n 'from("conversations").insert' apps/web-platform/server/ws-handler.ts` → exactly one site (deferred model intact).
- [x] 3.3 (AC6) `grep -n 'sessionKind' apps/web-platform/lib/ws-client.ts` → set in both handler arms + read by the effect gate.
- [x] 3.4 (AC8) `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-chat-resume-hydration.test.tsx test/api-messages-handler.test.ts test/ws-client-resume-history.test.tsx` → all pass.

## Phase 4 — Post-merge (operator)

- [ ] 4.1 (AC10) After deploy, query Sentry issues API for op `history-fetch-404-not-owned-or-missing` over 24h; deterministic verdict: error-level count for that op == 0 (any residual occurrences are warning-level). Pull via API per `hr-no-dashboard-eyeball-pull-data-yourself`.

## Notes

- Open code-review overlaps acknowledged (not folded in): #3280 (history-fetch reducer refactor), #3374 (slot_reclaimed frame), #3289 (conversation_messages MCP tool). Carry the `sessionKind` gate into the reducer if #3280 lands.
- TR2(b) wire-level `deferred?` flag is a deferred follow-up only if an external agent client needs the signal — default to client-local TR2(a).
