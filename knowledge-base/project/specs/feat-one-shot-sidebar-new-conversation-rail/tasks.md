# Tasks — feat(chat): new-conversation rail affordance + deterministic appearance

lane: single-domain
Plan: `knowledge-base/project/plans/2026-06-16-feat-sidebar-new-conversation-rail-plan.md`
Wireframe: `knowledge-base/product/design/chat/new-conversation-rail-affordance.pen`

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-confirm rail header + empty-state CTA: `apps/web-platform/components/chat/conversations-rail.tsx:104-110` (header), `:133-139` (empty-state "Start one →"), `:101-102` (collapsed `return null`).
- [ ] 0.2 Re-confirm new-conversation route: `chat/page.tsx` → `/dashboard/chat/new`; `chat/[conversationId]/page.tsx` mounts `ChatSurface`; `chat-surface.tsx:349` branches `"new" → startSession`. The empty-state CTA already uses href `/dashboard/chat/new` (`:138`).
- [ ] 0.3 Re-confirm hook shapes: `SUBSCRIBED` backfill `use-conversations.ts:403-404` (unconditional, single-shot); scope-resolve backfill `:451-460` gated on `pendingScopeRecoveryRef` (`:456`); `fetchConversations` toggles `setLoading`/`setError` at `:157-158`; lazy row INSERT at `apps/web-platform/server/ws-handler.ts:2191`.
- [ ] 0.4 **Falsification gate (before writing any timer):** walk the three orderings and confirm "unconditional `null→id` backfill + `SUBSCRIBED` fetch + steady-state INSERT reducer (`:370-381`)" recovers the row in each. If no surviving drop ordering can be exhibited, NO timer ships.
- [ ] 0.5 Confirm the two `useConversations` call sites (rail `:88`, dashboard `page.tsx:117`); chat surface holds none.

## Phase 1 — RED (failing tests)

- [ ] 1.1 `test/conversations-rail.test.tsx`: non-empty-list render asserts "+ New conversation" link present in header (role `link`, name "New conversation", href `/dashboard/chat/new`) — AC1.
- [ ] 1.2 `test/conversations-rail.test.tsx`: collapsed render asserts affordance absent — AC2.
- [ ] 1.3 `test/conversations-rail-connect-race.test.tsx`: row absent at first fetch/`SUBSCRIBED`, `workspaceId` transitions `null→id`, NO INSERT dropped → row appears via unconditional backfill — AC3.
- [ ] 1.4 `test/conversations-rail-connect-race.test.tsx`: backfill fires exactly once per `null→id` (call-count) — AC4; quiet refetch never flashes empty/error branch with rows present — AC4b.

## Phase 2 — GREEN

- [ ] 2.1 `conversations-rail.tsx`: add `<Link href="/dashboard/chat/new">` "+ New conversation" to the header row (`:104-110`); reuse the empty-state CTA's href constant (`:138`); accessible name "New conversation"; expanded branch only (early-return `:102` precedes header). Token per wireframe.
- [ ] 2.2 `use-conversations.ts`: drop the `pendingScopeRecoveryRef.current` clause from the scope-resolve effect condition (`:456`) → `if (prev === null && workspaceId !== null)`.
- [ ] 2.3 `use-conversations.ts`: delete `pendingScopeRecoveryRef` entirely (declaration `:154`, arming branch + `own-insert-deferred-unresolved-workspace` Sentry mirror `:357-366`); sweep for dangling reads (`cq-ref-removal-sweep-cleanup-closures`).
- [ ] 2.4 `use-conversations.ts`: add a quiet-refetch path (`{ background }` arg or sibling fetch) that skips `setLoading(true)`/`setError(null)` (`:157-158`); the unconditional backfill uses it — AC4b.
- [ ] 2.5 Do NOT touch `shouldDropForScope`, the `SUBSCRIBED` backfill, the fill-only INSERT reducer, or the map-only UPDATE handler.
- [ ] 2.6 ONLY if 0.4 exhibited a surviving drop ordering: add a bounded self-cancelling retry — cancel on count-increase-vs-arm-time (NOT `length>0`, NOT new-id), `setTimeout` cleared in cleanup, transition-gated, re-introduce a one-shot bound-exhaustion Sentry mirror with a distinct slug.

## Phase 3 — REFACTOR

- [ ] 3.1 Minimal — two refetch triggers remain (`SUBSCRIBED` + unconditional scope-resolve), both pre-existing; no new helper unless a timer was added. Keep `shouldDropForScope`/`deriveRailTitle` single-source. Do NOT merge the triggers' gates (scope-drift risk).

## Phase 4 — Verify

- [ ] 4.1 AC5: scope+visibility isolation — out-of-scope INSERT dropped; second workspace's rail does not show the row; non-`workspace`-visibility peer not surfaced by the backfill. Existing isolation case (`conversations-rail-connect-race.test.tsx:362-381`) stays green.
- [ ] 4.2 AC6: map-only UPDATE cannot resurrect absent row; `pendingScopeRecoveryRef` fully removed; prior armed-drop test updated to the unconditional behavior.
- [ ] 4.3 AC8: hook-source-swap sweep — `git grep -l 'useConversations' apps/web-platform/test/` minus `git grep -l 'vi.mock("@/hooks/use-conversations"' apps/web-platform/test/`; paste both in PR body; all renderers green.
- [ ] 4.4 AC9: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0; `./node_modules/.bin/vitest run test/conversations-rail.test.tsx test/conversations-rail-connect-race.test.tsx test/conversations-rail-insert.test.tsx` green; full `scripts/test-all.sh` exits 0.
- [ ] 4.5 AC10 (post-merge): Playwright MCP live check from `/dashboard` — new conversation appears in rail within seconds before completion; affordance lands on composer; scope isolation. Do not punt to manual.
- [ ] 4.6 Deferral tracking: verify/file the cross-instance optimistic-insert issue (labels `domain/engineering`, `priority/p3-low`); no duplicate of #5421's deferral.
