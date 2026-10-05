# Tasks — feat-one-shot-session-completion-inline

Derived from `knowledge-base/project/plans/2026-10-05-fix-session-completion-inline-render-plan.md`.

## Phase 1 — Server seam (failing tests first)

- [ ] 1.1 `apps/web-platform/test/task-completed-suppression.test.ts` (RED): viewing → unread row + frame emitted + `notifyOfflineUser` NOT called; not-viewing → today's full path; viewing + `emit()` false → notify fires
- [ ] 1.2 `apps/web-platform/server/session-registry.ts`: add `isConversationViewed(userId, conversationId)` — `sessions.get` + `ws.readyState === OPEN` + `session.conversationId === conversationId`
- [ ] 1.3 `apps/web-platform/server/notifications.ts`: `notifyInboxItem` gains `dispatch?: boolean` opt-out and returns the inserted row id; `notifyTaskCompleted` gains required `emit` param + seam order (predicate → insert unread → emit → `shouldNotify = !(viewing && delivered)` → dispatch or `op=task-completed-suppressed` log)
- [ ] 1.4 `agent-runner.ts` + `cc-dispatcher.ts`: pass `emit: sendToClient` at both `notifyTaskCompleted` call sites; widen the cc-dispatcher opts `sendToClient` annotation from `=> void` to `=> boolean` (injected runtime value is `defaultSendToClient`); extend `test/task-completed-both-lineages.test.ts` to pin `emit:` wiring (GREEN)

## Phase 2 — Wire + render

- [ ] 2.1 `lib/types.ts` `WSMessage` += `task_completed` variant (`conversationId`, `inboxItemId`, `title`, `seq?`); `lib/ws-zod-schemas.ts` `taskCompletedSchema` (strictObject, mirrors `turnSummarySchema` incl. `seq`) + union member; `server/stream-replay-buffer.ts` `BufferedWSMessage` + `BUFFERED_FRAME_TYPE_MAP` += `task_completed`
- [ ] 2.2 `lib/chat-state-machine.ts`: `ChatTaskCompletedMessage` variant (`type: "task_completed"`, `inboxItemId`) + `ChatMessage` union + `case "task_completed"` reducer arm
- [ ] 2.3 `lib/ws-client.ts` `case "task_completed"`: drop when `msg.conversationId !== realConversationIdRef.current`; else `dispatch({type:"stream_event", msg})` + fire-and-forget `POST /api/inbox/{inboxItemId}/state {action:"read"}` + `mutate(swrKeys.inbox("active"))` (`mutate` via `useSWRConfig()` at hook top level; `swrKeys` from `lib/swr-config.ts`)
- [ ] 2.4 `components/chat/task-completed-card.tsx` (new): bordered card, emerald info dot, plain-text title, relative time, non-navigating, no markdown/dangerouslySetInnerHTML; `chat-surface.tsx` render `case "task_completed"` → `<TaskCompletedCard />`
- [ ] 2.5 `apps/web-platform/test/task-completed-inline.test.tsx` (RED → GREEN): convId-filter drop, message append, read-mark POST only on render

## Phase 3 — Verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean — every TS2322 `not assignable to never` is a rail to widen (compiler is the enumerator, not a fixed site list)
- [ ] 3.2 `./node_modules/.bin/vitest run test/task-completed-*.test.ts*` + touched suites (chat-reducer, ws-protocol)
- [ ] 3.3 Update `test/mocks/use-websocket.ts` if the mock surfaces need the new case
- [ ] 3.4 CPO sign-off confirmed before work begins (`requires_cpo_signoff: true` — planning recorded an in-process fallback; formal ack per plan §User-Brand Impact)
