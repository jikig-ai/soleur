# Tasks — feat-kb-chat-sidebar

Issue: #2345 · PR: #2347 · Branch: `kb-chat-sidebar`
Plan: `knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md`

## Phase 0 — Gate

- [x] 0.1 Milestone resolved — #2345 promoted to Phase 3 P3 (roadmap row 3.23), commit `4561b1f4`, 2026-04-15.
- [ ] 0.2 Confirm Doppler `dev` config has `NEXT_PUBLIC_KB_CHAT_SIDEBAR=1` available for local QA.

## Phase 1 — Primitives (zero user-visible change)

- [ ] 1.1 Create `apps/web-platform/hooks/use-media-query.ts` (SSR-safe hook). Test: `test/use-media-query.test.ts`.
- [ ] 1.2 Create `apps/web-platform/components/ui/sheet.tsx` with right-side / bottom snap points; drag < 10vh = close. Test: `test/sheet.test.tsx`.
- [ ] 1.3 Extract `<ChatSurface variant>` from `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`.
  - [ ] 1.3.1 Create `components/chat/chat-surface.tsx` with full/sidebar variant branches.
  - [ ] 1.3.2 Create `components/chat/message-bubble.tsx` (lifted + enable markdown on user bubbles so blockquotes render).
  - [ ] 1.3.3 Create `components/chat/review-gate-card.tsx` (lifted).
  - [ ] 1.3.4 Create `components/chat/status-indicator.tsx` (lifted).
  - [ ] 1.3.5 Reduce `chat/[conversationId]/page.tsx` to thin shell around `<ChatSurface variant="full">`.
  - [ ] 1.3.6 Apply `min-w-0` + `[overflow-wrap:anywhere]` throughout sidebar variant; code blocks wrap (not scroll).
- [ ] 1.4 Tests: update `test/chat-page.test.tsx`; add `test/chat-surface-sidebar.test.tsx`.
- [ ] 1.5 Regression: `/dashboard/chat/<id>` visually identical to main (screenshot-diff or manual).

## Phase 2 — KB sidebar shell + flag + first analytics emit

- [ ] 2.1 Schema migration `supabase/migrations/20260415a_add_context_path_to_conversations.sql`:
  - [ ] 2.1.1 `ALTER TABLE conversations ADD COLUMN context_path TEXT`.
  - [ ] 2.1.2 `CREATE UNIQUE INDEX ... ON (user_id, context_path) WHERE context_path IS NOT NULL`.
  - [ ] 2.1.3 Update `Conversation` interface in `lib/types.ts`.
- [ ] 2.1b Backfill migration `supabase/migrations/20260415b_backfill_context_path.sql` (conditional — apply only if staging shows legacy shape matches; skip otherwise).
- [ ] 2.2 Extend `lib/types.ts`: `start_session` WSMessage gains optional `resumeByContextPath`; `Conversation` gains `context_path`. (No `add_context` variant in v1 — deferred.)
- [ ] 2.3 `server/context-validation.ts` — no v1 change (selections travel as blockquote text in user message, not as a separate field).
- [ ] 2.4 Extend `server/ws-handler.ts` `case "start_session":` at L284 to handle `resumeByContextPath`:
  - [ ] 2.4.1 If present + no explicit conversationId: query `conversations WHERE user_id=? AND context_path=? LIMIT 1`.
  - [ ] 2.4.2 If found: emit `session_resumed { conversationId, resumedFromTimestamp, messageCount }`.
  - [ ] 2.4.3 If miss: fall through to pending-creation with `contextPath` on pending record; first message write uses `ON CONFLICT DO NOTHING` against UNIQUE index.
- [ ] 2.5 `server/agent-runner.ts` — no v1 change (selections arrive inline in user message text).
- [ ] 2.6 Mount sidebar in `app/(dashboard)/dashboard/kb/layout.tsx`:
  - [ ] 2.6.1 Add `KbChatContext` provider.
  - [ ] 2.6.2 Lazy-load `KbChatSidebar` via `next/dynamic({ ssr: false })`.
  - [ ] 2.6.3 Gate mount on `NEXT_PUBLIC_KB_CHAT_SIDEBAR === "1"`.
- [ ] 2.7 Create `components/chat/kb-chat-sidebar.tsx`:
  - [ ] 2.7.1 Resolving state (skeleton + 10s timeout + retry).
  - [ ] 2.7.2 Header: filename in `JetBrains Mono`, close `aria-label="Close panel"`, `↗ Open full` when `messageCount ≥ 10`.
  - [ ] 2.7.3 Resumed-thread banner ("Continuing from [date]") that auto-dismisses on first new user message.
  - [ ] 2.7.4 Empty state: heading + subtext (per copywriter).
  - [ ] 2.7.5 Close-mid-stream abort via `user_closed`.
  - [ ] 2.7.6 Doc-switch preserves Doc A's draft in `sessionStorage.drafts[contextPath]`.
  - [ ] 2.7.7 Emit `kb.chat.opened` + `kb.chat.thread_resumed` on resolve.
  - [ ] 2.7.8 Expose `submitQuote(text)` on `KbChatContext` that calls `openSidebar()` + forwards to chat-input ref. Keeps `ChatInput` free of KB-domain knowledge.
- [ ] 2.8 Update `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
  - [ ] 2.8.1 Stateful trigger label ("Ask about this document" / "Continue thread") in BOTH markdown and non-markdown branches.
  - [ ] 2.8.2 Flag off-path: legacy `/dashboard/chat/new?msg=...&context=...` link preserved.
- [ ] 2.9 Update `components/inbox/conversation-row.tsx` to render "KB" badge when `context_path IS NOT NULL`.
- [ ] 2.10 `sessionStorage` persistence: `sidebarOpen`, `drafts[contextPath]`.
- [ ] 2.11 Tests: `test/kb-chat-sidebar.test.tsx`, WS-handler tests for both new cases, `test/context-validation.test.ts`.

## Phase 3 — Narrow-column hardening + QA

- [ ] 3.1 Audit `min-w-0` coverage at every flex level inside sidebar.
- [ ] 3.2 Verify `next/dynamic` bundle-split (ChatSurface not in synchronous layout bundle).
- [ ] 3.3 Verify attach flow usable at 380px; file a follow-up if not.
- [ ] 3.4 Playwright screenshot pass at 1440 / 1024 / 768 / 375.

## Phase 4 — Selection → quoted context

- [ ] 4.1 Create `components/kb/selection-toolbar.tsx`:
  - [ ] 4.1.1 Scope to `articleRef`; ignore selections outside.
  - [ ] 4.1.2 Client-side size preflight (disabled state when >8KB).
  - [ ] 4.1.3 Portal-render anchored at `range.getBoundingClientRect()`.
  - [ ] 4.1.4 Dismiss on collapse / click-outside / Escape (`stopPropagation` on Escape).
  - [ ] 4.1.5 iOS Safari: `user-select: text` + suppress `contextmenu` when pill visible.
  - [ ] 4.1.6 Does not interfere with link clicks or text copy.
- [ ] 4.2 Mount `<SelectionToolbar>` in markdown branch of `kb/[...path]/page.tsx`.
- [ ] 4.3 Extend `components/chat/chat-input.tsx`:
  - [ ] 4.3.1 `forwardRef` + `useImperativeHandle` exposing `insertQuote(text)`.
  - [ ] 4.3.2 Prepend `> <text>\n\n` (append to draft when streaming).
  - [ ] 4.3.3 Scroll textarea into view + 400ms flash on inserted blockquote.
  - [ ] 4.3.4 `ChatInput` does NOT read `KbChatContext` — stays domain-free.
- [ ] 4.3b Mobile "Referenced passage" chip rendered by `KbChatSidebar` (not `ChatInput`); dismisses on scroll or first new message.
- [ ] 4.3c `KbChatSidebar` emits `kb.chat.selection_sent` on message-send when draft starts with a blockquote (not emitted by ChatInput).
- [ ] 4.4 Keyboard shortcut `Cmd/Ctrl+Shift+L` in markdown article.
- [ ] 4.5 Chat input placeholder with shortcut hint (sidebar variant).
- [ ] 4.6 Tests: `test/selection-toolbar.test.tsx`, augmented `chat-input.test.tsx`.

## Phase 5 — Analytics hardening

- [ ] 5.1 Create `lib/analytics-client.ts` (fail-soft `track()`).
- [ ] 5.2 Create `app/api/analytics/track/route.ts` (forwards to Plausible; 402 → 204 graceful skip; validate response shape).
- [ ] 5.3 Provision three Plausible goals via API (`kb.chat.opened`, `kb.chat.selection_sent`, `kb.chat.thread_resumed`).
- [ ] 5.4 Document ops step in `knowledge-base/marketing/analytics/plausible-goals.md`.
- [ ] 5.5 End-to-end test: all three emits reach Plausible dashboard in staging.
- [ ] 5.6 Tests: `test/api/analytics-track.test.ts`.

## Phase 6 — Accessibility + flag rollout prep

- [ ] 6.1 `<aside aria-label>`, Escape close, focus move on open, focus return on close.
- [ ] 6.2 Mobile drag-handle `aria-label="Resize panel"` + tooltip.
- [ ] 6.3 Doppler `dev` flag = 1, `prd` flag = 0 at merge.
- [ ] 6.4 File follow-up issues from Deferrals table in plan (7 issues).

## Phase 7 — Tests + QA

- [ ] 7.1 Full vitest run: `cd apps/web-platform && node node_modules/vitest/vitest.mjs run`.
- [ ] 7.2 Playwright QA both flag states (on / off).
- [ ] 7.3 Cross-browser manual QA (Chrome, Safari, iOS Safari).
- [ ] 7.4 Full-chat-route regression: `/dashboard/chat/<id>` identical to main.
- [ ] 7.5 Two-tab concurrent scenario validation.

## Phase 8 — Ship

- [ ] 8.1 `skill: soleur:ship` with appropriate semver label.
- [ ] 8.2 Apply migration in prod; verify via REST API.
- [ ] 8.3 Flip prd flag to 1 after founder sign-off.
- [ ] 8.4 One-week soak; monitor Plausible goals.
- [ ] 8.5 Follow-up PR to remove flag + legacy fallback.
