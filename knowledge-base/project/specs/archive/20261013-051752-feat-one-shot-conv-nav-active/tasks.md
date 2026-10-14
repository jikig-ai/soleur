# Tasks — fix: conversations rail live status

Derived from `knowledge-base/project/plans/2026-09-30-fix-conversations-rail-live-status-plan.md` (post-review, incl. advisor P-findings).
Branch: `feat-one-shot-conv-nav-active`. Draft PR: #9270. Follow-up: #9293.

## Phase 1 — Tests first (failing) ✅ (5 RED → 8 GREEN)

- 1.1 Create `apps/web-platform/test/conversation-turn-start-status.test.ts`:
  - existing `completed` conversation + `chat` via `dispatchSoleurGo` →
    `updateConversationFor` invoked with `{ status: "active" }`.
  - legacy `sendUserMessage` → same assertion before `startAgentSession`.
  - `dispatchSoleurGo` setup throw after the write → guarded revert called
    with `{ status: "failed" }`, `onlyIfStatusIn: ["active"]`,
    `expectMatch: false`.
  - harness seams: reuse `ws-handler-cc-session-id-wiring.test.ts` /
    `agent-runner-result-branch-finalization.test.ts` mock shapes.
- 1.2 Create `apps/web-platform/test/conversations-rail-activity-event.test.tsx`:
  - mounted rail listing conversation C receives `CONVERSATION_ACTIVITY_EVENT`
    (`detail.conversationId = C`) → background `fetchConversations` runs again
    (no loading flash) and the row shows the updated status without remount.
  - negative: no dispatch happens on socket bind/resume alone.

## Phase 2 — Server: turn-start `status='active'` + guarded revert ✅

- 2.1 `apps/web-platform/server/cc-dispatcher.ts` — in `dispatchSoleurGo`, a
  dedicated `updateConversationFor(…, { status: "active" })` write immediately
  before `runner.dispatch` (~line 4229). [Shipped design refinement vs the
  original "add to the ownership write": the separate placement collapses the
  false-`active` window — setup throws above it leave the row untouched.]
- 2.2 `apps/web-platform/server/cc-dispatcher.ts` — in the `runner.dispatch`
  catch (~line 4286), revert via
  `updateConversationFor(…, { status: "failed" }, { onlyIfStatusIn: ["active"],
  expectMatch: false, feature: "cc-dispatcher", op: "turn-start-revert" })`
  — mirrors `agent-runner.ts` `updateConversationStatusIfActive` (#3463).
- 2.3 `apps/web-platform/server/agent-runner.ts` — in `sendUserMessage`, after
  the ownership probe, write `{ status: "active", last_active }` via
  `updateConversationFor` (`feature: "agent-runner"`, op `turn-start-active`,
  `expectMatch: true`). Both `ws-handler.ts` `chat` call sites covered.
- 2.4 Do NOT touch `resume_session` / `start_session` status — viewing is not a
  turn (plan Technical Considerations).

## Phase 3 — Client: deterministic rail refresh on derived state ✅

- 3.1 `apps/web-platform/hooks/use-conversations.ts` — export
  `CONVERSATION_ACTIVITY_EVENT = "soleur:conversation-activity"`; add a window
  listener that runs a debounced (~500 ms) `fetchConversations({ background:
  true })`; cleanup removes listener + clears the timer.
- 3.2 `apps/web-platform/components/chat/chat-surface.tsx` — dispatch the
  event (CustomEvent, `detail: { conversationId }`) when `streamState`
  enters/leaves `"streaming"` and on the `awaitingUserInput`/gate transition
  — derived state only; do NOT key on raw frames (`stream_start` is
  legacy-only; `session_started` fires on socket bind/resume — a forbidden
  false-positive per plan AC).

## Phase 4 — Verify

- 4.1 ✅ Run new tests + existing rail/handler suites — 8 new + 46 rail/handler
  + 116 dispatcher/agent-runner all green:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/conversation-turn-start-status.test.ts test/conversations-rail-activity-event.test.tsx test/conversations-rail.test.tsx test/conversations-rail-insert.test.tsx test/conversations-rail-connect-race.test.tsx test/conversations-active-repo-scope.test.tsx test/use-conversations-limit.test.tsx test/ws-handler-cc-session-id-wiring.test.ts`
- 4.2 ✅ Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (clean)
- 4.3 Browser QA — partial via CDP (Playwright's browser pipe dies ~30 s in
  under host memory pressure; a raw Chromium+CDP driver works): seeded QA
  conversation, live DOM verified `Done` → `In progress` in place on the
  `CONVERSATION_ACTIVITY_EVENT` with no navigation (screenshots
  /tmp/qa-event-*.png). The full WS send path could NOT run end-to-end —
  this dev env's tenant-JWT mint (`mintFounderJwt` → generateLink/verifyOtp)
  fails with RuntimeAuthError:jwt_mint on every WS chat op — pre-existing
  env defect, unrelated to the diff. Server-side write coverage rests on
  conversation-turn-start-status.test.ts.
- 4.4 Re-entry regression: navigate away and back — badge still correct.
  (Verified: status read is fresh on each mount; the badge showed the
  server-persisted value on re-entry.)
- 4.5 Review round (PR #9270): 4-agent panel (security / simplicity /
  test-design / architecture). Fixed: (a) P2 provenance-blind revert —
  `hasActiveCcQuery` guard + try/catch so a rejected-duplicate dispatch
  can't write `failed` onto a concurrent live turn or mask the primary
  error; (b) P1 emitter coverage — new chat-surface-activity-event.test.tsx
  (mount-no-emit inverse-lie AC + idle↔streaming + gate transitions);
  (c) quiet-contract vacuity — deferred-RPC mid-flight `loading===false`
  pin; (d) domain_leader:null tag-and-route branch coverage; (e) legacy
  flip moved per-branch (`markTurnStarted`) past `loadConversationHistory`;
  (f) success-path no-`failed` negatives + cc write option pins.
