---
title: "feat: Command Center conversation nav (in-chat switcher rail)"
date: 2026-04-29
issue: 3024
brainstorm: knowledge-base/project/brainstorms/2026-04-29-command-center-conversation-nav-brainstorm.md
spec: knowledge-base/project/specs/feat-command-center-conversation-nav/spec.md
branch: feat-command-center-conversation-nav
worktree: .worktrees/feat-command-center-conversation-nav
draft_pr: 3021
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# feat: Command Center conversation nav (in-chat switcher rail)

✨ Add a secondary navigation rail inside `/dashboard/chat/*` that lets users switch between recent conversations without round-tripping to `/dashboard`. Lives in a new nested layout `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` so the Realtime subscription persists across `[conversationId]` route changes (no remount, no resubscribe).

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** 3 (Risks, Phase 5a, Tasks Phase 1 + 5b)
**Research agents used:** Supabase realtime tier behavior, Next.js 15 nested-layout lifecycle, Playwright WebSocket assertion patterns

### Key Improvements

1. **Risks corrected.** The brainstorm/earlier plan claim "RLS doesn't gate Realtime broadcasts — only the snapshot" is wrong per Supabase docs ([Postgres Changes — Scaling](https://supabase.com/docs/guides/realtime/postgres-changes#scaling)): RLS gates every change event. Real load-bearing risk is narrower: **DELETE events bypass RLS** (Postgres can't verify access to a deleted row). Phase 5b integration test now exercises DELETE explicitly.
2. **Tier-divergence task added.** The hook comment "Free tier ignores server-side filter" contradicts current docs. Phase 1 sub-task verifies via `git blame` and either retires the comment or files a Supabase issue. Empirical integration test on the actual project tier remains source of truth.
3. **Playwright assertion pattern hardened.** Synchronous post-`waitForURL` snapshot would race CDP-side `close` events. Replaced with `expect.poll(() => [...openSet].filter(ws => !ws.isClosed()).length).toBe(0)` over a 5-second budget per the canonical pattern. Code sketch is now in the plan verbatim.
4. **Next.js premise confirmed.** Layout-above-dynamic-segment lifecycle is the canonical "subscribe once across a route segment" idiom; remount-bug exception (dynamic segment AT or ABOVE the layout) does not apply because `[conversationId]` is below `chat/layout.tsx`. Sharp Edge added to prevent future regressions.

### New Considerations Discovered

- **DELETE is the load-bearing leak vector**, not the previously-feared INSERT/UPDATE broadcast. Cross-tenant test must include all three events.
- **Issue #3028's framing for the AGENTS.md `cq-` rule needs revision.** The rule's original justification ("RLS doesn't gate broadcasts") is wrong; the correct justifications are (a) DELETE events bypass RLS, (b) per-event RLS check is a scaling concern, (c) explicit `filter:` documents intent. Update issued as a comment on #3028.

## Overview

USER_BRAND_CRITICAL feature; threshold = `single-user incident`. Reuses `useConversations` (with a new `limit?: number` option) and `useSidebarCollapse`. No fork of the per-user Realtime contract.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR8 says re-read `apps/web-platform/app/privacy/page.tsx` | That path does **not** exist. Privacy policy is rendered by Eleventy at `docs/legal/privacy-policy.md` (mirrored at `plugins/soleur/docs/pages/legal/privacy-policy.md`) | Phase 6 re-reads the correct path. Spec TR8 corrected in Phase 1 of this plan. |
| Spec implies `user_id` is the only filter | `useConversations` filters by **both** `user_id` AND `repo_url` (line 146); disconnected users (`repo_url IS NULL`) see an empty list by design | Rail inherits scoping for free. Empty-state is the disconnected-user state. |
| Spec TR5 e2e against `e2e/mock-supabase.ts` for cross-tenant Realtime payload isolation | The mock is single-tenant (`MOCK_USER.id = "test-user-id"`, hardcoded `MOCK_SESSION`) and rejects `/realtime/*` with `"realtime not supported in mock"` (line 147). Cross-tenant Realtime assertion CANNOT run against the mock. | Phase 5 splits into two tests: (a) Playwright UI test against mock (active-row + zero-open-WS-after-sign-out) + (b) integration test against Doppler `dev` Supabase project for cross-tenant Realtime payload isolation. |

## User-Brand Impact

**If this lands broken, the user experiences:** a logged-in user opens a conversation and sees another user's titles + status badges in the rail; or a user signs out on a shared device and the next user briefly sees the previous user's titles.

**If this leaks, the user's data is exposed via:** (a) Supabase Realtime `postgres_changes` channel without a per-user `filter:` (RLS does NOT enforce isolation on broadcasts — only the initial REST snapshot); (b) cache key not user-scoped; (c) Realtime channel not torn down on `signOut` before redirect.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time before `/work` (carry-forward from brainstorm). `user-impact-reviewer` and `security-sentinel` (focus: Realtime filter, cache scoping, logout teardown) invoked at review time.

## Goals

- Render a recent-conversations rail inside `/dashboard/chat/*`.
- Reuse `useConversations` (widen with `limit` option); do NOT fork the per-user Realtime contract.
- Persist sidebar collapse via `useSidebarCollapse("soleur:sidebar.chat-rail.collapsed")` + `Cmd/Ctrl+B`.
- Mobile: rail accessible via the existing dashboard drawer.
- Tear down the Realtime channel on `signOut` before redirect.
- Cross-tenant integration test (real Supabase) is the merge gate for Realtime isolation.

## Non-Goals

- Last-message snippets in v1 (deferred — #3025; needs server-side BYOK/PII redaction).
- Status / Domain filter dropdowns inside the rail.
- In-rail search.
- Cursor pagination + virtualization (deferred — #3026).
- Conversation pinning (deferred — #3027).
- Touching `apps/web-platform/app/(dashboard)/layout.tsx` beyond the single `handleSignOut` edit. #2194 stays untouched.
- Adding a new global keyboard shortcut beyond `Cmd/Ctrl+B`.
- Drafting the new AGENTS.md `cq-` rule for Realtime per-user filter (#3028).
- Extracting a shared `statusBadge` component. Two call sites is duplication, not DRY violation; rule-of-three not hit. Inline the 4-case mapping in the rail.

## Files to edit

- `apps/web-platform/hooks/use-conversations.ts` — add `limit?: number` to `UseConversationsOptions`; thread to `query.limit(opts?.limit ?? 50)`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — extend `handleSignOut` (line 186-189) to `await supabase.removeAllChannels()` BEFORE `auth.signOut()`. (Plan-time premise correction: `removeAllChannels()` is `Promise<('ok'|'timed out'|'error')[]>` — a single Promise of an array, NOT an array of Promises. `Promise.all(supabase.removeAllChannels())` is rejected by the supabase-js v2 type overload. Await the promise directly.) Add a one-line code comment per Kieran: "Sign-out tears down ALL channels by design — do not introduce long-lived channels that need to survive sign-out." Also widen the existing `Cmd/Ctrl+B` early-return at line 156 to skip `/dashboard/chat/*` so the rail's own `Cmd/Ctrl+B` handler owns toggle on chat pages.
- `knowledge-base/project/specs/feat-command-center-conversation-nav/spec.md` — TR8 path correction; TR1 `repo_url` scope note.

## Files to create

- `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` — server-component shell rendering `<ConversationsRail />` alongside `{children}`.
- `apps/web-platform/components/chat/conversations-rail.tsx` — client component (name chosen to avoid collision with `KbChatSidebar`, which is a different concept). Inlines the 4-case status-badge mapping.
- `apps/web-platform/test/conversations-rail.test.tsx` — unit tests (rail render shape, active-row, empty state, collapse, "View all" link).
- `apps/web-platform/test/use-conversations-limit.test.ts` — unit tests for `limit`.
- `apps/web-platform/e2e/conversations-rail.e2e.ts` — Playwright UI test (active-row, "View all" navigation, zero open WebSockets after sign-out).
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` — vitest integration test against Doppler `dev` Supabase for cross-tenant Realtime isolation.

## Open Code-Review Overlap

3 open scope-outs touch nearby files; all acknowledged, none folded in:

- **#2193** (banner refactor): plan's only `(dashboard)/layout.tsx` edit is `handleSignOut`, not the banner. Independent.
- **#2222** (gate auto-scroll), **#2223** (useMemo derivations): rail lives in a sibling segment-layout above `[conversationId]/page.tsx`. Adding a layout above does not regress the page's render perf.

## Functional Overlap Check

Skipped with rationale: internal Next.js App Router nested-layout navigation reusing existing hooks. No external library candidate; brainstorm CPO + CLO + CTO already covered functional scope.

## Implementation Phases

Each phase has a TDD gate per `cq-write-failing-tests-before`.

### Phase 0 — Setup (already complete)

- [x] Worktree, draft PR #3021, brainstorm, spec, issues #3024-#3028.

### Phase 1 — Hook contract widening + spec corrections

1. Failing test in `test/use-conversations-limit.test.ts`: `useConversations({ limit: 15 })` against a mock returning 30 rows → assert ≤15; default behavior unchanged when `limit` omitted; underlying `.limit(15)` reaches the Supabase query.
2. Implementation: extend `UseConversationsOptions`, thread `limit` to `.limit(opts?.limit ?? 50)`.
3. Spec edits: TR8 path → `docs/legal/privacy-policy.md`; add `repo_url` inheritance note to TR1.
4. `bun test` green; `bun typecheck` green.

### Phase 2 — Chat-segment layout shell

1. Failing unit test in `test/conversations-rail.test.tsx` (one suite covers both Phase 2 and Phase 3): assert `chat/layout.tsx` renders `<ConversationsRail />` plus `{children}` given a stubbed child. RTL cannot render the Next.js segment tree end-to-end — that assertion belongs in Phase 5 (Playwright). Per Kieran.
2. Implementation: create `app/(dashboard)/dashboard/chat/layout.tsx` as a server component. Two-column layout on desktop (rail left, content right); rail hidden via CSS `hidden md:block` on small viewports (drawer integration in Phase 4).
3. `bun test` green.

### Phase 3 — `ConversationsRail` client component

Each row links to `/dashboard/chat/[conversationId]` rendering: title (truncated server-side via existing `truncate`), inline 4-case status-badge mapping (`waiting_for_user → "Needs your decision"`, `active → "In progress"`, `completed → "Done"`, `failed → "Needs attention"`), relative-time, unread count.

1. Failing tests in `test/conversations-rail.test.tsx`:
   - Renders ≤15 rows; renders all when fewer.
   - Active-row indication via `useParams<{ conversationId: string }>()` — typed param, avoids string-parsing pathname (Kieran #4). Row with matching `conversationId` gets `aria-current="page"` and a distinct visual marker.
   - "View all in Command Center" footer link → `/dashboard`.
   - Empty state: "+ New conversation" CTA when hook returns 0 rows (covers disconnected-user case where `repo_url IS NULL`).
   - Collapse via `useSidebarCollapse("soleur:sidebar.chat-rail.collapsed")` + `Cmd/Ctrl+B`; state persists across reloads.
2. Implementation: client component using `useConversations({ limit: 15 })`, `useSidebarCollapse`, `useParams`, inline status-badge mapping. Existing `leader-colors.ts` for per-leader color coding.
3. `bun test` green.

### Phase 4 — Sign-out teardown + mobile drawer

1. Implementation only (per Code-Simplicity: don't unit-test ordering — Phase 5 e2e proves it via zero-open-WS assertion):
   ```ts
   async function handleSignOut() {
     const supabase = createClient();
     // Sign-out tears down ALL channels by design — do not introduce long-lived
     // channels that must survive sign-out. supabase-js v2 returns a SINGLE
     // Promise<('ok'|'timed out'|'error')[]> here (not an array of promises),
     // so await the promise directly. Promise.all(supabase.removeAllChannels())
     // is rejected by TS at compile time. Await before signOut() so phx_leave
     // sends while the JWT is still valid.
     await supabase.removeAllChannels();
     await supabase.auth.signOut();
     router.push("/login");
   }
   ```
2. Mobile: extend the existing dashboard drawer in `(dashboard)/layout.tsx` to include a "Recent conversations" section that renders the rail's row markup directly (no `variant` prop — handle via CSS responsive class composition per Code-Simplicity).
3. RTL test for drawer rendering on `<375px` viewport.
4. `bun test` green.

### Phase 5 — E2E + cross-tenant integration test (HARD MERGE GATE)

Two tests, separated by infrastructure constraint per Kieran #1:

**5a. `e2e/conversations-rail.e2e.ts` — Playwright against single-tenant mock:**

1. Mount `/dashboard/chat/<seeded-id>`. Assert rail renders with seeded titles, active-row indication on the seeded row, "View all" link routes to `/dashboard`.
2. Logout-teardown invariant — use this exact pattern (per deepen-plan research; raw `expect.poll` with `!ws.isClosed()`, NOT a synchronous post-redirect snapshot, because Playwright's CDP `close` event is not ordered against `waitForURL`):

   ```ts
   const realtimeSockets = new Set<WebSocket>();
   page.on('websocket', ws => {
     if (ws.url().includes('/realtime/v1/websocket')) realtimeSockets.add(ws);
   });
   await page.goto('/dashboard/chat/<seeded-id>');
   await expect.poll(() => realtimeSockets.size).toBeGreaterThan(0); // arm
   await page.getByRole('button', { name: /sign out/i }).click();
   await page.waitForURL('**/login');
   await expect.poll(
     () => [...realtimeSockets].filter(ws => !ws.isClosed()).length,
     { timeout: 5_000, message: 'open Realtime WS at /login' },
   ).toBe(0);
   ```

   `WebSocket` exposes only `isClosed()` — no `state` accessor. Track open sockets via `page.on('websocket')`, filter by URL prefix, and poll `!ws.isClosed()` against a 5-second budget. Asserting at `waitForURL` resolution synchronously would race the CDP-side close event and produce false failures masked by sleeps.

**5b. `test/conversations-rail-cross-tenant.integration.test.ts` — vitest against Doppler `dev` Supabase:**

1. Use the real Supabase JS client with two distinct user JWTs (seeded via Doppler `dev` anon key + service-role for fixture creation; tear down after).
2. Subscribe User A to the rail's exact channel + filter pattern. Insert/update conversations as User B. Assert NO payload arrives at A's subscription handler.
3. Skip with `it.skipIf(!process.env.SUPABASE_DEV_INTEGRATION)` so CI without the secret short-circuits cleanly. Document the env var in the Phase 5 acceptance criterion.
4. Document in `apps/web-platform/test/README.md` how to run: `SUPABASE_DEV_INTEGRATION=1 bun test:ci conversations-rail-cross-tenant`.

Both tests gate merge: 5a runs in CI; 5b runs locally pre-merge OR as a scheduled job on `dev`.

### Phase 6 — Privacy + review

1. Read `docs/legal/privacy-policy.md`. If existing language is surface-agnostic, no edit. If a clause scopes "conversation history display" to a specific surface, broaden to authenticated app generally.
2. `/soleur:plan-review` already ran inline (DHH + Kieran + Code-Simplicity); findings applied to this plan.
3. At PR time: `user-impact-reviewer` + `security-sentinel` with focus tags Realtime filter, cache scoping, logout teardown. Resolve P1/P2 findings inline per `rf-review-finding-default-fix-inline`.

## Acceptance Criteria

### Pre-merge (PR) — user-visible behavior

- [ ] Rail renders ≤15 rows with title + status badge + relative-time + unread count inside `/dashboard/chat/*`. Invisible on `/dashboard`, `/dashboard/kb`, `/dashboard/settings`.
- [ ] Active row indicated via `aria-current="page"` and a distinct visual marker.
- [ ] "View all in Command Center" footer routes to `/dashboard`.
- [ ] Disconnected users (`repo_url IS NULL`) see the empty-state CTA.
- [ ] Collapse via `Cmd/Ctrl+B`; state persists across reloads.
- [ ] Mobile drawer surfaces the same rail rows.
- [ ] After sign-out: zero open `/realtime/v1/websocket` connections at redirect time (Phase 5a Playwright assertion).
- [ ] Cross-tenant Realtime isolation: User A's subscription receives ZERO payloads triggered by User B's conversation INSERT/UPDATE (Phase 5b integration test).

### Pre-merge (PR) — workflow

- [ ] `bun test`, `bun test:ci`, `bun test:e2e`, `bun typecheck`, `bun lint` all pass.
- [ ] `user-impact-reviewer` + `security-sentinel` sign off on the diff.
- [ ] PR body includes `Closes #3024` and `Ref #3025 #3026 #3027 #3028 #2194`.

### Post-merge (operator)

- [ ] Verify `/dashboard/chat/<any-conv>` renders the rail in production.
- [ ] Confirm deferred issues #3025-#3028 remain open with re-evaluation criteria intact.
- [ ] Close #3024 once production smoke-test confirms rail render + active-row.

## Test Strategy

- **Unit (vitest):** hook (`use-conversations-limit.test.ts`), rail (`conversations-rail.test.tsx`), drawer integration via RTL.
- **E2E (Playwright):** UI behavior + zero-open-WS-after-signout assertion (`e2e/conversations-rail.e2e.ts`). Single-tenant mock-supabase is sufficient — cross-tenant Realtime isolation is NOT asserted here because the mock rejects `/realtime/*`.
- **Integration (vitest, real Supabase):** cross-tenant Realtime payload isolation (`test/conversations-rail-cross-tenant.integration.test.ts`). Requires `SUPABASE_DEV_INTEGRATION=1` + Doppler `dev` credentials; runs locally pre-merge.
- **Existing infra reused:** `@playwright/test ^1.58.2`, `e2e/global-setup.ts`, `e2e/mock-supabase.ts`. No new test framework. Mock-supabase fixture is NOT extended for multi-tenant — the integration test uses real Supabase instead.

## Risks (load-bearing only)

> **Corrected during deepen-plan research.** The brainstorm and earlier plan revision claimed "RLS does NOT enforce isolation on Realtime broadcast payloads — only the initial REST snapshot." Per official Supabase docs ([Postgres Changes — Scaling](https://supabase.com/docs/guides/realtime/postgres-changes#scaling), [postgres-changes.mdx source](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/realtime/postgres-changes.mdx)), this is **wrong**: *"every change event must be checked to see if the subscribed user has access."* RLS is applied per-event before broadcast. Per the same docs, `filter:` is enforced server-side on all tiers (no documented Free-tier carve-out). The existing hook's "Free tier ignores server-side filter" comment may be empirical evidence that contradicts the docs OR may be obsolete — verify in Phase 1.

1. **DELETE events bypass RLS.** Postgres cannot verify access to a deleted row, so `postgres_changes` DELETE events skip RLS. With `REPLICA IDENTITY FULL` (set in migration 015) the `old` record contains the full row including `user_id`, so a defensive client-side `user_id !== uid` drop check on DELETE payloads remains load-bearing. The existing hook ALREADY has this check at `use-conversations.ts:243-246` ("Free tier ignores server-side filter"); the comment justification is wrong but the check itself is correct for DELETE-event defense. Re-comment, do not remove. The cross-tenant integration test (Phase 5b) MUST exercise DELETE explicitly, not just INSERT/UPDATE.
2. **Tier-divergence between docs and observed behavior.** The hook comment "Free tier ignores server-side filter" was written by a teammate based on observed behavior. Supabase docs disagree. Two possibilities: (a) Free-tier server filter was buggy at write time and is now fixed; (b) docs lag reality. Phase 1 sub-task: read git blame on the comment, look up the PR that introduced it, and either delete the comment (if the bug is fixed in current Supabase) or keep it AND open a Supabase issue. Either way the integration test (Phase 5b) on the actual project tier is the source of truth, not docs OR memory.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / `TBD` / missing the threshold will fail `deepen-plan` Phase 4.6. (This plan has it filled — carry-forward from brainstorm.)
- `removeAllChannels()` is broad — sign-out tears down ALL channels by design. If a future component requires a long-lived channel that survives sign-out, it must be re-architected; do not work around the teardown. Code-comment in `handleSignOut` documents this contract.
- Order of `removeAllChannels()` vs. `auth.signOut()` matters: removal first, sign-out second. Reverse risks `phx_leave` sending on a torn-down auth context. `removeAllChannels()` returns a SINGLE `Promise<('ok'|'timed out'|'error')[]>` — a promise of an array, not an array of promises. Await the promise directly; `Promise.all(supabase.removeAllChannels())` is rejected by the TS overload (caught at typecheck during work Phase 4).
- Use `useParams<{ conversationId: string }>()` for active-row, not `usePathname` + string parsing.
- Inline the 4-case status-badge mapping in `ConversationsRail`. Do NOT extract a shared component for v1; rule-of-three not hit (`/dashboard` and rail = two call sites). If a third call site appears later, file an extraction issue then.
- The `(dashboard)/layout.tsx` edit is single-line scope: `handleSignOut`. Do not bundle other refactoring; #2194 stays untouched.
- The Phase 5b integration test requires `SUPABASE_DEV_INTEGRATION=1` + Doppler dev credentials. If absent, the test must `skipIf` (not fail) so local dev without secrets stays clean.
- **Do NOT introduce a dynamic segment AT or ABOVE `app/(dashboard)/dashboard/chat/layout.tsx` in future refactors.** Next.js issues [#49553](https://github.com/vercel/next.js/issues/49553), [#60395](https://github.com/vercel/next.js/issues/60395), [#44793](https://github.com/vercel/next.js/issues/44793): client components inside layouts whose route has a dynamic segment AT or ABOVE the layout will remount on intra-segment navigation. This feature's structure (`[conversationId]` BELOW `chat/layout.tsx`) avoids the bug. If a future refactor adds e.g. `app/[lang]/(dashboard)/dashboard/chat/layout.tsx`, the Realtime subscription will resubscribe on every conversation switch — silent perf regression that the no-remount premise of this plan depends on.
- DELETE events on `postgres_changes` bypass RLS by Postgres design — `replica identity full` (set in migration 015) is what allows the defensive client-side `user_id !== uid` drop check in `use-conversations.ts:243-246` to see `payload.old.user_id`. If migration 015 were ever rolled back, that defense collapses. Phase 5b's DELETE assertion is the regression gate.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carry-forward from brainstorm).

### Engineering (CTO) — reviewed (carry-forward)

Recommend chat-segment layout, not main sidebar. Single biggest risk: Realtime broadcasts ≠ RLS. Reuse `useConversations`. Ship in parallel with #2194.

### Legal (CLO) — reviewed (carry-forward)

No new privacy-policy disclosure expected (re-affirm Phase 6). RLS necessary but insufficient for snippets — defer (#3025). Required gates: `user-impact-reviewer` + `security-sentinel`.

### Product/UX Gate

**Tier:** blocking (mechanical: new `app/**/layout.tsx`)
**Decision:** reviewed (carry-forward + skip wireframes)
**Agents invoked:** spec-flow-analyzer (carry-forward), cpo (carry-forward)
**Skipped specialists:** ux-design-lead (rail reuses the existing `/dashboard` Command Center list pattern: same row contents minus snippet, same status badges. Visual reference is in production); copywriter (no new user-facing copy beyond founder-language status badges already decided)
**Pencil available:** N/A (skipped)

## Research Insights

- Realtime pattern (`use-conversations.ts:225-305`): per-user `filter:` + defensive client `user_id !== uid` + `repo_url` scoping + separate `users` UPDATE subscription on repo swap. Reuse, don't fork.
- Sign-out call site (`(dashboard)/layout.tsx:186-189`): single function `handleSignOut`. 1-line addition (plus comment).
- E2E infra: `@playwright/test ^1.58.2`. `e2e/global-setup.ts` writes a single `MOCK_SESSION` storage state. Mock rejects `/realtime/*` — confirms Phase 5 split is required.
- Privacy doc real path: `docs/legal/privacy-policy.md` (Eleventy).
- Existing chat sidebar `KbChatSidebar` is a KB-context drawer, NOT a switcher. Naming `ConversationsRail` chosen accordingly.
- Migration `015_conversations_replica_identity.sql` already sets `REPLICA IDENTITY FULL` on `conversations`. No new migration.

## Path / glob verification

```
$ ls apps/web-platform/app/\(dashboard\)/dashboard/chat/    # [conversationId]
$ ls apps/web-platform/hooks/use-conversations.ts            # exists
$ ls apps/web-platform/hooks/use-sidebar-collapse.ts         # exists
$ ls apps/web-platform/components/chat/kb-chat-sidebar.tsx   # exists (different concept)
$ ls apps/web-platform/playwright.config.ts                  # exists
$ ls apps/web-platform/e2e/global-setup.ts                   # exists
$ ls apps/web-platform/e2e/mock-supabase.ts                  # exists, single-tenant + rejects /realtime/*
$ ls docs/legal/privacy-policy.md                            # exists
$ ls apps/web-platform/supabase/migrations/015_conversations_replica_identity.sql  # exists
$ ls apps/web-platform/app/privacy/                          # DOES NOT EXIST — spec corrected in Phase 1
```

## CLI verification

No CLI invocations are embedded into user-facing docs by this plan. Skill-internal commands (`bun test`, `bun test:e2e`, `gh`, `git`) are present in `package.json` and standard tooling.

## Closes / Refs

Closes #3024
Ref #3025 #3026 #3027 #3028 #2194 #2222 #2223 #2193

## Plan Review Findings Applied (audit trail)

- DHH: dropped Phase 5 ordering unit test (kept implementation); cut 3 of 5 risks; rejected DHH's "collapse to 4 phases" — kept 6 to preserve TDD gates.
- Kieran: Phase 5 split into Playwright (mock) + integration (real Supabase) — load-bearing fix, mock cannot serve cross-tenant Realtime; `useParams` over `usePathname`; `await Promise.all(removeAllChannels())`; Phase 2 unit test reframed as layout-shape only; "removeAllChannels broad" demoted from Risks to Sharp Edges + code comment.
- Code-Simplicity: dropped shared `statusBadge.tsx` extraction; dropped `next/dynamic` (segment-based splitting handles isolation); dropped `variant="drawer"` prop (CSS responsive); consolidated 13 ACs to 8 user-visible + 3 workflow.
