# Tasks — fix: Recent Conversations rail shows freshly-started conversation immediately

Plan: `knowledge-base/project/plans/2026-06-16-fix-recent-conversations-rail-optimistic-insert-plan.md`
Lane: single-domain. Brand-survival threshold: single-user incident (CPO signed off).

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-confirm two `useConversations` instances: `git grep -n "useConversations(" apps/web-platform` (rail `conversations-rail.tsx:88` + dashboard `page.tsx:117`; chat surface none).
- [ ] 0.2 Confirm rail mount boundary `chat/layout.tsx:71` (mounts for `/dashboard/chat/*` only; not `/dashboard`).
- [ ] 0.3 Re-read `use-conversations.ts:288-404`; confirm `SUBSCRIBED` backfill (`:373-375`) + `shouldDropForScope` (`:102-118`) shapes unchanged.
- [ ] 0.4 Note latent active-repo self-heal divergence (`active-repo/route.ts:48-65` vs `ws-handler.ts:865,:892`) — out of scope unless deepen-plan elevates.

## Phase 1 — RED (failing tests)

- [ ] 1.1 Extend `test/conversations-rail-insert.test.tsx` harness so `active-repo` resolves AFTER the INSERT and `workspaceId` starts `null` (the existing harness resolves scope synchronously).
- [ ] 1.2 AC1: render real `ConversationsRail`; INSERT during connect window; assert row in rail DOM before completion (both sub-races).
- [ ] 1.3 AC2/AC3: `workspaceId` null→id transition → recovery backfill returns row; assert row lands in `conversations`; backfill bounded (fires once).
- [ ] 1.4 AC4: out-of-scope INSERT dropped; second workspace's rail does NOT show the row (F3 isolation).
- [ ] 1.5 AC5: completion UPDATE for a row NOT present does not resurrect it (map-only preserved).

## Phase 2 — GREEN (hook fix in `hooks/use-conversations.ts`)

- [ ] 2.1 Re-run bounded backfill when `workspaceId` resolves (`null → id`); transition-gate via guard ref (not per-render).
- [ ] 2.2 On own-channel INSERT with unresolved scope, schedule bounded recovery refetch instead of silent drop; if a drop with no recovery is taken, mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).

## Phase 3 — REFACTOR

- [ ] 3.1 Collapse backfill triggers (SUBSCRIBED + scope-resolve + null-scope-recovery) behind one bounded helper; keep `shouldDropForScope`/`deriveRailTitle` as single guard/title source.

## Phase 4 — Verify

- [ ] 4.1 AC6 hook-source-swap sweep: `git grep -l 'useConversations' apps/web-platform/test/` minus `git grep -l 'vi.mock("@/hooks/use-conversations"' apps/web-platform/test/`; paste both in PR body.
- [ ] 4.2 AC7: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exit 0; `./node_modules/.bin/vitest run test/conversations-rail-insert.test.tsx test/conversations-rail.test.tsx test/use-conversations-limit.test.tsx` green; `scripts/test-all.sh` exit 0.
- [ ] 4.3 AC8 (post-deploy): Playwright MCP from `/dashboard` → new conversation → assert row appears before completion + scope isolation. Do not punt to manual.

## Deferral

- [ ] D.1 File GitHub issue (labels `domain/engineering`, `priority/p3-low`) for the deferred zero-latency cross-instance optimistic insert (shared-store/Context refactor), with re-evaluation criteria and roadmap pointer.
