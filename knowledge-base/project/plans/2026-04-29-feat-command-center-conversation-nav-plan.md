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
- `apps/web-platform/app/(dashboard)/layout.tsx` — single edit: extend `handleSignOut` (line 186-189) to `await Promise.all(supabase.removeAllChannels())` BEFORE `auth.signOut()`. Add a one-line code comment per Kieran: "Sign-out tears down ALL channels by design — do not introduce long-lived channels that need to survive sign-out."
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
     // channels that must survive sign-out. removeAllChannels() returns
     // Promise<'ok'|'timed out'|'error'>[]; await before signOut() so phx_leave
     // sends while the JWT is still valid.
     await Promise.all(supabase.removeAllChannels());
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
2. After `handleSignOut`: register `page.on('websocket')` open/close events; assert zero open `/realtime/v1/websocket` connections at redirect time. Captures the load-bearing logout-teardown invariant the unit test would have given a false-positive on.

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

1. **Realtime broadcasts ≠ RLS.** RLS does not gate Realtime payloads, only the initial REST snapshot. A typo in the channel `filter:` would silently leak. Mitigation: reuse `useConversations` (existing pattern is correct) + Phase 5b cross-tenant integration test.
2. **Free-tier filter behavior.** The hook comment ("Free tier ignores server-side filter") suggests `filter:` may not be enforced on free-tier projects, leaving the defensive client-side `user_id !== uid` drop check as the gate. Verify prod plan tier; if free-tier, the defensive client check stays load-bearing; if paid-tier, the server filter is primary and the client check is belt-and-suspenders.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / `TBD` / missing the threshold will fail `deepen-plan` Phase 4.6. (This plan has it filled — carry-forward from brainstorm.)
- `removeAllChannels()` is broad — sign-out tears down ALL channels by design. If a future component requires a long-lived channel that survives sign-out, it must be re-architected; do not work around the teardown. Code-comment in `handleSignOut` documents this contract.
- Order of `removeAllChannels()` vs. `auth.signOut()` matters: removal first, sign-out second. Reverse risks `phx_leave` sending on a torn-down auth context. `removeAllChannels()` returns `Promise<'ok'|'timed out'|'error'>[]`; `await Promise.all(...)` is honest about the async fan-out.
- Use `useParams<{ conversationId: string }>()` for active-row, not `usePathname` + string parsing.
- Inline the 4-case status-badge mapping in `ConversationsRail`. Do NOT extract a shared component for v1; rule-of-three not hit (`/dashboard` and rail = two call sites). If a third call site appears later, file an extraction issue then.
- The `(dashboard)/layout.tsx` edit is single-line scope: `handleSignOut`. Do not bundle other refactoring; #2194 stays untouched.
- The Phase 5b integration test requires `SUPABASE_DEV_INTEGRATION=1` + Doppler dev credentials. If absent, the test must `skipIf` (not fail) so local dev without secrets stays clean.

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
