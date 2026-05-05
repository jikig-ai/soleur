# Tasks — fix KB doc chat resume hydration + button label + Command Center empty body

Plan: `knowledge-base/project/plans/2026-05-05-fix-kb-doc-chat-resume-hydration-and-button-label-plan.md`

## Phase 0 — Reproduction + diagnosis

- [ ] 0.1 — Reproduce locally with `bun run dev` from `apps/web-platform/`.
- [ ] 0.2 — Inspect Network tab response for `/api/conversations/<id>/messages` (200/[]/404/etc.).
- [ ] 0.3 — Narrow root cause to H1, H2, H3, or H4 from the plan's Hypotheses section.
- [ ] 0.4 — Document the confirmed hypothesis in PR description.

## Phase 1 — Tests (RED)

- [ ] 1.1 — Create `apps/web-platform/test/kb-chat-resume-hydration.test.tsx` covering full mount → resume → hydrate flow. Confirm RED.
- [ ] 1.2 — Create `apps/web-platform/test/kb-chat-trigger.test.tsx` covering enabled/disabled + messageCount=0/N branches and the prefetch→mount→overwrite race. Confirm RED on the race case.
- [ ] 1.3 — Create `apps/web-platform/test/api-messages-handler.test.ts` covering 401 / 404 / 200-empty / 200-non-empty. Sentry-breadcrumb cases should be RED.
- [ ] 1.4 — Extend `apps/web-platform/test/ws-client-resume-history.test.tsx` with a non-`"new"` `conversationId` case (Command Center path).

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 — `apps/web-platform/lib/ws-client.ts`: replace `console.warn` in both history-fetch effects with `reportSilentFallback` (or `Sentry.captureException` if the helper is server-only).
- [ ] 2.2 — `apps/web-platform/lib/ws-client.ts`: introduce `historyLoading: boolean` state; expose from hook return value.
- [ ] 2.3 — `apps/web-platform/lib/ws-client.ts`: add code comment at line ~701 noting the endpoint lives in the Node custom server, not the App Router.
- [ ] 2.4 — `apps/web-platform/components/chat/chat-surface.tsx`: extend empty-state guard at line ~468 to include `!historyLoading`. Skip `onMessageCountChange?.(0)` while `realConversationId` is non-null and `messages.length === 0`.
- [ ] 2.5 — `apps/web-platform/components/chat/kb-chat-content.tsx`: `handleMessageCountChange` ignores `count === 0` writes when `historicalCountRef.current > 0`.
- [ ] 2.6 — `apps/web-platform/server/api-messages.ts`: add `reportSilentFallback` calls on each non-200 branch + a success breadcrumb with `{ conversationId, count }`.
- [ ] 2.7 — `apps/web-platform/components/kb/kb-chat-trigger.tsx`: add code comment pointing to `useKbLayoutState`'s thread-info prefetch as the source of truth for `messageCount` when the panel is closed.
- [ ] 2.8 — If H1 confirmed in Phase 0: add the additional fix in `lookupConversationForPath` or the WS handler's resume lookup (out of scope for this plan unless H1 is confirmed).

## Phase 3 — Verification + REFACTOR

- [ ] 3.1 — Run `bun test` from `apps/web-platform/` — all green.
- [ ] 3.2 — Run `bun run typecheck` — no new errors.
- [ ] 3.3 — Manual smoke: doc revisit → sidebar → messages render → trigger label is "Continue thread"; `/dashboard/chat/<id>` → messages render.
- [ ] 3.4 — Capture screenshots of both passing surfaces (KB sidebar + Command Center) for PR description.

## Phase 4 — PR + post-merge

- [ ] 4.1 — Open PR with `Closes #<issue>` (or `Ref` if scope-out tracked separately). Title under 70 chars: `fix(kb-chat): hydrate prior messages on resume + correct button label`.
- [ ] 4.2 — Run `/soleur:review` and resolve findings inline.
- [ ] 4.3 — Run `/soleur:qa` if UI-affecting (yes, both surfaces).
- [ ] 4.4 — `/soleur:ship` → squash-merge.
- [ ] 4.5 — Post-merge Sentry check: `feature:kb-chat op:history-fetch-failed` over 24h = 0.
