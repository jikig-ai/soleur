# Tasks — fix KB doc chat resume hydration + button label + Command Center empty body

Plan: `knowledge-base/project/plans/2026-05-05-fix-kb-doc-chat-resume-hydration-and-button-label-plan.md`

## Phase 0 — Reproduction + diagnosis

- [x] 0.1 — Reproduction deferred to post-deploy Sentry instrumentation (per plan: success breadcrumb + reportSilentFallback mirrors localize H1/H2/H4 from prod data alone).
- [x] 0.2 — Network-tab inspection covered by the new Sentry breadcrumb (`history-fetch-success`) + the four `op:history-fetch-*` mirrors.
- [x] 0.3 — Plan addresses H1/H2/H3/H4 in one fix: H1/H4 surface via Sentry post-deploy; H2 deterministically eliminated by `controller.signal.aborted` swap; H3 fixed in chat-surface + kb-chat-content.
- [x] 0.4 — Hypotheses + Sentry filter strings documented in plan §"Diagnostic Observability"; PR description carries the same.

## Phase 1 — Tests (RED)

- [x] 1.1 — `apps/web-platform/test/kb-chat-resume-hydration.test.tsx` — 5 tests covering historyLoading exposure, Command Center hydration, Sentry mirror on 5xx + thrown errors, AbortError filter.
- [x] 1.2 — `apps/web-platform/test/kb-chat-trigger.test.tsx` — 5 tests covering ctx-missing fallback, flag-disabled fallback, messageCount=0/N branches, label flips.
- [x] 1.3 — `apps/web-platform/test/api-messages-handler.test.ts` — 5 tests covering 401 missing-auth, 401 invalid-token, 404 not-owned, 200 success breadcrumb, 200 empty-messages breadcrumb.
- [x] 1.4 — Coverage of the non-`"new"` Command Center path is in `kb-chat-resume-hydration.test.tsx` ("hydrates Command Center history" + "exposes historyLoading=false"); existing `ws-client-resume-history.test.tsx` already covers the resume-by-context-path branch.

## Phase 2 — Implementation (GREEN)

- [x] 2.1 — `apps/web-platform/lib/ws-client.ts`: replaced `console.warn`/`console.error` in both history-fetch effects with `reportSilentFallback({ feature: "kb-chat", op: "history-fetch-failed" | "history-fetch-error" })`.
- [x] 2.2 — `apps/web-platform/lib/ws-client.ts`: introduced `historyLoading: boolean` state, set in both effects with try/finally, exposed on hook return type.
- [x] 2.3 — `apps/web-platform/lib/ws-client.ts`: code comment at the fetch-call site notes the endpoint lives in the Node custom server, not the App Router.
- [x] 2.4 — `apps/web-platform/components/chat/chat-surface.tsx`: empty-state guard extended to `!historyLoading`; `onMessageCountChange?.(0)` deferred while history is loading or `realConversationId` is set with empty messages.
- [x] 2.5 — `apps/web-platform/components/chat/kb-chat-content.tsx`: `handleMessageCountChange` ignores `count === 0` writes when `historicalCountRef.current > 0`.
- [x] 2.6 — `apps/web-platform/server/api-messages.ts`: `reportSilentFallback` on each non-200 branch (401 missing-auth, 401 invalid-token, 404 not-owned, 500 messages-load) + `Sentry.addBreadcrumb` on success path with `{ conversationId, count }`.
- [x] 2.7 — `apps/web-platform/components/kb/kb-chat-trigger.tsx`: comment pointing to `useKbLayoutState` thread-info prefetch as the source of truth for `messageCount` when the panel is closed.
- [x] 2.8 — H1 confirmation deferred to post-deploy Sentry; if `op:history-fetch-success` shows `count=0` paired with user reports, follow-up issue will address `lookupConversationForPath` row-mismatch.

## Phase 3 — Verification + REFACTOR

- [x] 3.1 — `vitest run` — 3200 passed, 18 skipped, 0 failed.
- [x] 3.2 — `tsc --noEmit` — passed (no output, exit 0).
- [ ] 3.3 — Manual smoke deferred to QA phase (`/soleur:qa`).
- [ ] 3.4 — Screenshot capture deferred to QA phase.

## Phase 4 — PR + post-merge

- [ ] 4.1 — Open PR with descriptive title under 70 chars.
- [ ] 4.2 — Run `/soleur:review` and resolve findings inline.
- [ ] 4.3 — Run `/soleur:qa` for both surfaces (KB sidebar + Command Center).
- [ ] 4.4 — `/soleur:ship` → squash-merge.
- [ ] 4.5 — Post-merge Sentry check: `feature:kb-chat op:history-fetch-failed` over 24h = 0.
