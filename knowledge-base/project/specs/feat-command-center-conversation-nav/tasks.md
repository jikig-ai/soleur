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

- [ ] 4.1 Write failing RTL test for drawer rendering at `<375px` viewport
  - [ ] 4.1.1 Drawer open → "Recent conversations" section visible with the 15 rail rows + "View all" link
  - [ ] 4.1.2 Drawer closed → rail rows not in the DOM (hidden, not just visually)
- [ ] 4.2 Run vitest; confirm 4.1 fails (RED)
- [ ] 4.3 Implement drawer integration in `apps/web-platform/app/(dashboard)/layout.tsx`
  - [ ] 4.3.1 Add a "Recent conversations" section to the existing mobile drawer
  - [ ] 4.3.2 Render the rail's row markup directly (no `variant` prop)
  - [ ] 4.3.3 No other refactoring of `(dashboard)/layout.tsx` per Non-Goals
- [ ] 4.4 Run vitest; confirm 4.1 passes (GREEN)
- [ ] 4.5 Implement sign-out teardown in `handleSignOut` (line ~186 of `(dashboard)/layout.tsx`)
  - [ ] 4.5.1 `await Promise.all(supabase.removeAllChannels())` BEFORE `auth.signOut()`
  - [ ] 4.5.2 Add code comment: "Sign-out tears down ALL channels by design — do not introduce long-lived channels that must survive sign-out. removeAllChannels() returns Promise<'ok'|'timed out'|'error'>[]; await before signOut() so phx_leave sends while the JWT is still valid."
  - [ ] 4.5.3 No unit test for ordering — Phase 5a e2e zero-open-WS assertion covers the user-visible invariant
- [ ] 4.6 `bun typecheck` green; `bun lint` green
- [ ] 4.7 Commit: `git commit -m "feat(auth): tear down realtime channels before sign-out"`

## Phase 5: E2E + cross-tenant integration test (HARD MERGE GATE)

### 5a. Playwright UI test (against single-tenant mock)

- [ ] 5a.1 Write `apps/web-platform/e2e/conversations-rail.e2e.ts`
  - [ ] 5a.1.1 Navigate to `/dashboard/chat/<seeded-id>` (use existing `MOCK_SESSION` + seed conversations via mock fixture)
  - [ ] 5a.1.2 Assert rail is visible, contains seeded titles, active row has `aria-current="page"`
  - [ ] 5a.1.3 Click "View all in Command Center" → verify navigation to `/dashboard`
  - [ ] 5a.1.4 Logout-teardown invariant — use the exact pattern from the plan's Phase 5a (`page.on('websocket')` open-set, `expect.poll(() => [...openSet].filter(ws => !ws.isClosed()).length).toBe(0)` with 5s timeout). Do NOT assert synchronously after `waitForURL('/login')` — Playwright CDP `close` events are not ordered against navigation, and a synchronous snapshot will race the close.
- [ ] 5a.2 Run `bun test:e2e`; confirm 5a passes

### 5b. Cross-tenant Realtime integration test (against Doppler `dev` Supabase)

- [ ] 5b.1 Write `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
  - [ ] 5b.1.1 `it.skipIf(!process.env.SUPABASE_DEV_INTEGRATION)` so CI without the secret short-circuits cleanly
  - [ ] 5b.1.2 Use real Supabase JS client with two distinct user JWTs (seeded via Doppler `dev` anon key + service-role for fixture creation)
  - [ ] 5b.1.3 User A subscribes via the rail's exact channel + filter pattern (`channel("command-center")` + `postgres_changes` + `filter: user_id=eq.<A-uid>`)
  - [ ] 5b.1.4 As User B (separate client), INSERT a conversation row
  - [ ] 5b.1.5 Wait 2 seconds; assert User A's subscription handler received ZERO payloads referencing User B's row
  - [ ] 5b.1.6 As User B, UPDATE a conversation row; repeat the assertion
  - [ ] 5b.1.7 As User B, DELETE a conversation row; assert User A's handler received ZERO payloads. **DELETE is the load-bearing case** per Supabase docs: Postgres cannot verify access to a deleted row, so `postgres_changes` DELETE events bypass RLS. The defensive client-side `user_id !== uid` drop check at `use-conversations.ts:243-246` is what catches this; this test verifies it.
  - [ ] 5b.1.8 Tear down: delete seeded fixtures, close both clients
- [ ] 5b.2 Document run command in `apps/web-platform/test/README.md` (create if absent): `SUPABASE_DEV_INTEGRATION=1 bun test:ci conversations-rail-cross-tenant`
- [ ] 5b.3 Run locally pre-merge; confirm green. If you don't have `SUPABASE_DEV_INTEGRATION=1` available, the test must skip — but operator MUST run it before marking PR ready.

## Phase 6: Privacy + review gates

- [ ] 6.1 Read `docs/legal/privacy-policy.md` (and Eleventy mirror at `plugins/soleur/docs/pages/legal/privacy-policy.md`)
- [ ] 6.2 If existing language is surface-agnostic → no edit, document the no-op in PR description
- [ ] 6.3 If a clause scopes "conversation history display" to a specific surface → broaden to authenticated app generally; commit
- [ ] 6.4 Push branch; mark PR ready
- [ ] 6.5 At PR review time: `user-impact-reviewer` + `security-sentinel` invoked by review skill (focus tags: Realtime filter, cache scoping, logout teardown)
- [ ] 6.6 Resolve P1/P2 review findings inline per `rf-review-finding-default-fix-inline`
- [ ] 6.7 Final pre-merge gate: `bun test`, `bun test:ci`, `bun test:e2e`, `bun typecheck`, `bun lint` all green; both review agents signed off; PR body has `Closes #3024` + `Ref #3025 #3026 #3027 #3028 #2194`
- [ ] 6.8 `/soleur:ship`

## Phase 7: Post-merge verification (operator)

- [ ] 7.1 Verify `/dashboard/chat/<any-conv>` renders the rail in production
- [ ] 7.2 Smoke-test active-row + "View all" link + sign-out
- [ ] 7.3 Confirm deferred issues #3025-#3028 remain open
- [ ] 7.4 Close #3024 once 7.1-7.2 pass
