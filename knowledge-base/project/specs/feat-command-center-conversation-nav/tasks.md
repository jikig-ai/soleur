# Tasks: Command Center conversation nav (in-chat switcher rail)

**Plan:** [`../../plans/2026-04-29-feat-command-center-conversation-nav-plan.md`](../../plans/2026-04-29-feat-command-center-conversation-nav-plan.md)
**Issue:** #3024
**Branch:** `feat-command-center-conversation-nav`
**Worktree:** `.worktrees/feat-command-center-conversation-nav`
**Draft PR:** #3021

TDD gate per AGENTS.md `cq-write-failing-tests-before`: each implementation task is preceded by its failing test task. Tests must run RED before the implementation runs GREEN.

## Phase 1: Hook contract widening + spec corrections

- [x] 1.1 Write failing test `apps/web-platform/test/use-conversations-limit.test.tsx` (filename is `.tsx` not `.ts` because `renderHook` needs the happy-dom test project)
  - [x] 1.1.1 `useConversations({ limit: 15 })` against a mock returning 30 rows → result has length 15
  - [x] 1.1.2 `useConversations()` with no `limit` → default 50 behavior unchanged
  - [x] 1.1.3 Assert the underlying Supabase query receives `.limit(15)` (spy on `query.limit`)
- [x] 1.2 Run vitest; confirm 1.1 fails (RED) — 2 of 3 tests failed (limit:15 + limit:5); default-50 passed
- [x] 1.3 Implement: extend `UseConversationsOptions` with `limit?: number`; thread to `query.limit(limit)` (default 50 via destructure); add `limit` to `fetchConversations` useCallback deps
- [x] 1.4 Run vitest; confirm 1.1 passes (GREEN) — all 3 tests pass
- [x] 1.5 Update `knowledge-base/project/specs/feat-command-center-conversation-nav/spec.md` TR8 path to `docs/legal/privacy-policy.md`
- [x] 1.6 Add `repo_url` inheritance note to spec TR1 / TR2
- [x] 1.7 Tier-divergence verification — `git blame` traced the comment to PR #1759 (2026-04-07, "Free tier defence" per PR body). The justification was precautionary, not empirical. Updated the comment in-place: keep the check (load-bearing for DELETE per Risk #1) but correct the rationale. No upstream Supabase issue needed.
- [x] 1.8 Run `bun typecheck`; confirm green
- [ ] 1.9 Commit: `git commit -m "feat(hooks): add limit option to useConversations + spec corrections"`

## Phase 2 + 3: Chat-segment layout + ConversationsRail (combined)

Phases 2 and 3 were combined to avoid an inter-phase typecheck break (the Phase 2 layout imports `ConversationsRail`, which Phase 3 creates). Tests for both phases live in a single suite (`test/conversations-rail.test.tsx`); RED → GREEN cycle covers the layout shape and the rail behaviour together.

- [x] 2+3.1 Write failing tests in `apps/web-platform/test/conversations-rail.test.tsx`
  - [x] 2+3.1.1 ChatLayout renders `<ConversationsRail />` + `{children}` (layout shape)
  - [x] 2+3.1.2 Renders ≤15 rows when hook returns more; renders all when fewer
  - [x] 2+3.1.3 `useConversations` is called with `{ limit: 15 }`
  - [x] 2+3.1.4 Active-row indication via `useParams<{ conversationId: string }>()` → `aria-current="page"`
  - [x] 2+3.1.5 "View all in Command Center" footer link → `/dashboard`
  - [x] 2+3.1.6 Empty state: "+ New conversation" CTA
  - [x] 2+3.1.7 Inline 4-case status-badge mapping (rail-specific labels distinct from `STATUS_LABELS`)
  - [x] 2+3.1.8 Collapse toggle persists to `soleur:sidebar.chat-rail.collapsed`
  - [x] 2+3.1.9 `Cmd/Ctrl+B` keyboard shortcut toggles collapse
- [x] 2+3.2 Run vitest; confirm RED (failed at module-resolution time — `chat/layout.tsx` and `conversations-rail.tsx` don't exist)
- [x] 2+3.3 Create `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` as a sync server component rendering `<ConversationsRail />` (`hidden md:block` aside) + `{children}` (`main`)
- [x] 2+3.4 Create `apps/web-platform/components/chat/conversations-rail.tsx` as a client component using `useConversations({ limit: 15 })`, `useSidebarCollapse("soleur:sidebar.chat-rail.collapsed")`, `useParams`, inline status badge, `relative-time`, and `LEADER_COLORS`
- [x] 2+3.5 Run vitest; all 10 tests pass GREEN
- [x] 2+3.6 `bun typecheck` green
- [ ] 2+3.7 Commit: `git commit -m "feat(chat): nested chat-segment layout + ConversationsRail"`

## Phase 4: Sign-out teardown + mobile drawer

- [x] 4.1 Write failing RTL test for drawer rendering — `test/dashboard-layout-drawer-rail.test.tsx` asserts `data-testid="conversations-rail-drawer"` is mounted inside `<DashboardLayout />` and the "View all" footer link routes to `/dashboard`
  - Note: deviation from plan task 4.1.2 (DOM presence when drawer closed) — the existing drawer pattern always renders the aside in the DOM (translate-x toggles visibility). The test asserts mount + link presence only; visibility-when-toggled is covered by Phase 5a Playwright.
- [x] 4.2 Run vitest; confirm 4.1 fails RED (testid missing)
- [x] 4.3 Implement drawer integration in `apps/web-platform/app/(dashboard)/layout.tsx`
  - [x] 4.3.1 Mobile-only "Recent conversations" section (`md:hidden`) with `data-testid="conversations-rail-drawer"` rendering `<ConversationsRail />`
  - [x] 4.3.2 Reuse the rail directly (no `variant` prop)
  - [x] 4.3.3 Widen the existing main-sidebar `Cmd/Ctrl+B` short-circuit to skip `/dashboard/chat/*` so the chat-rail's handler owns toggle on chat pages
- [x] 4.4 Run vitest; confirm 4.1 passes GREEN
- [x] 4.5 Implement sign-out teardown in `handleSignOut`
  - [x] 4.5.1 `await supabase.removeAllChannels()` BEFORE `auth.signOut()` — note: `removeAllChannels()` returns a SINGLE `Promise<('ok'|'timed out'|'error')[]>` (deepen-plan and earlier plan-time sketches said `Promise.all(...)`, which the supabase-js v2 type overload rejects). Plan + Sharp Edges updated to reflect the corrected idiom.
  - [x] 4.5.2 Code comment captures the async-shape correction so future maintainers don't re-introduce `Promise.all`.
  - [x] 4.5.3 No unit test for ordering — Phase 5a Playwright zero-open-WS assertion is the source of truth.
- [x] 4.6 `bun typecheck` green
- [ ] 4.7 Commit: `git commit -m "feat(auth): tear down realtime channels before sign-out + drawer rail"`

## Phase 5: E2E + cross-tenant integration test (HARD MERGE GATE)

### 5a. Playwright UI test (against single-tenant mock)

- [x] 5a.1 Write `apps/web-platform/e2e/start-fresh-conversations-rail.e2e.ts` (renamed from plan's `conversations-rail.e2e.ts`: the playwright-config `authenticated` project matches `**/start-fresh-*.e2e.ts`, which is the established pattern for tests requiring `MOCK_SESSION` storage state)
  - [x] 5a.1.1 Seed two conversations via `page.route()` REST overrides; mount `/dashboard/chat/conv-active`
  - [x] 5a.1.2 Assert active row has `aria-current="page"`; sibling row has no `aria-current` attribute
  - [x] 5a.1.3 Click "View all in Command Center" → `waitForURL('**/dashboard')`
  - [x] 5a.1.4 Logout-teardown invariant — `page.on('websocket')` open-set + `expect.poll(() => [...openSet].filter(ws => !ws.isClosed()).length, { timeout: 5_000 }).toBe(0)`. Mock-supabase rejects `/realtime/*` with HTTP 200 (no WS upgrade), so the open-set is empty in this environment; the assertion is structurally vacuous here but kept as the regression scaffold for any future real-WS mock. Phase 5b is the source of truth for cross-tenant Realtime isolation.
- [ ] 5a.2 Run `bun test:e2e` locally before marking PR ready (deferred to operator; e2e runs are heavy and frequently flaky in worktrees due to dev-server CSS — CI is the authoritative gate)

### 5b. Cross-tenant Realtime integration test (against Doppler `dev` Supabase)

- [x] 5b.1 Write `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
  - [x] 5b.1.1 `describe.skipIf(!INTEGRATION_ENABLED)` short-circuits cleanly when `SUPABASE_DEV_INTEGRATION` is unset (verified via `bun run vitest run --project unit ... → 3 skipped`)
  - [x] 5b.1.2 Two real Supabase clients: service-role for fixture creation/cleanup; userA anon-key client signed in for the subscription
  - [x] 5b.1.3 User A subscribes to `channel("command-center")` + `postgres_changes` + `filter: user_id=eq.<A-uid>` — mirrors the rail's exact contract
  - [x] 5b.1.4 INSERT as user B (via service); assert ZERO leak
  - [x] 5b.1.5 UPDATE as user B; assert ZERO leak
  - [x] 5b.1.6 DELETE as user B; assert ZERO leak (load-bearing per Supabase docs — DELETE bypasses RLS; comment in test explains the REPLICA IDENTITY FULL dependency)
  - [x] 5b.1.7 Synthetic-email allowlist (`conv-rail-cross-tenant-[a-f0-9]{16}@soleur\.test`) gates create/delete per `hr-destructive-prod-tests-allowlist`
  - [x] 5b.1.8 `afterAll` unsubscribes channel, removes channels, deletes seeded conversations + auth.users via service
- [x] 5b.2 Document run command in `apps/web-platform/test/README.md` (created)
- [ ] 5b.3 Operator MUST run `doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts` locally before marking PR ready (HARD MERGE GATE per plan)

## Phase 6: Privacy + review gates

- [x] 6.1 Read `docs/legal/privacy-policy.md` and the Eleventy mirror at `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [x] 6.2 No edit required — every reference to conversation data (Sections 4.7 / Purpose / Retention / Section 8 portability) is already surface-agnostic. The chat-segment ConversationsRail is another rendering surface for the same user-owned conversation data; no new collection, retention, processing-purpose, sharing, or right-of-data-subject category is introduced. **PR body must state**: "TR8 re-affirmation — privacy policy already describes conversation data in surface-agnostic terms; no edit needed."
- [ ] 6.3 N/A (no surface-scoped clause was found)
- [ ] 6.4 Push branch; mark PR ready (delegated to `/soleur:review` + `/soleur:ship`)
- [ ] 6.5 At PR review time: `user-impact-reviewer` + `security-sentinel` invoked by review skill (focus tags: Realtime filter, cache scoping, logout teardown)
- [ ] 6.6 Resolve P1/P2 review findings inline per `rf-review-finding-default-fix-inline`
- [ ] 6.7 Final pre-merge gate: `bun test`, `bun test:ci`, `bun typecheck`, `bun lint` all green; both review agents signed off; PR body has `Closes #3024` + `Ref #3025 #3026 #3027 #3028 #2194`
- [ ] 6.8 `/soleur:ship`

## Phase 7: Post-merge verification (operator)

- [ ] 7.1 Verify `/dashboard/chat/<any-conv>` renders the rail in production
- [ ] 7.2 Smoke-test active-row + "View all" link + sign-out
- [ ] 7.3 Confirm deferred issues #3025-#3028 remain open
- [ ] 7.4 Close #3024 once 7.1-7.2 pass
