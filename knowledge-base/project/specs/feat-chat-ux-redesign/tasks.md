# Tasks: Chat UX Redesign

## Phase 1: Component Foundation + Server Addition

- [x]1.1 Add optional `source?: "auto" | "mention"` field to `stream_start` in `lib/types.ts`
- [x]1.2 Pass `routeResult.source` into `stream_start` emission in `server/agent-runner.ts`
- [x]1.3 Update `useWebSocket` in `lib/ws-client.ts` to expose `routeSource` and `activeLeaderIds`
- [x]1.4 Create `components/chat/chat-input.tsx` — textarea with @-trigger detection, Enter to send, empty validation, mobile `@` button (`md:hidden`)
- [x]1.5 Create `components/chat/at-mention-dropdown.tsx` — leader list filtered by id/name/title, keyboard nav (↑/↓/Enter/Escape), ARIA `role="listbox"`
- [x]1.6 Extract `LEADER_COLORS` from chat page into shared UI constant

## Phase 2: Chat-First Dashboard

- [x]2.1 Rewrite `dashboard/page.tsx` — add `"use client"`, remove department grid
- [x]2.2 Add hero layout: "COMMAND CENTER" label, headline, subtitle, `<ChatInput>` + `<AtMentionDropdown>`
- [x]2.3 Add 4 suggested prompt cards inline (fill-only, no auto-submit, `grid-cols-2 md:grid-cols-4`)
- [x]2.4 Add "YOUR ORGANIZATION" leader strip inline (8 abbreviations, click inserts `@{id}`)
- [x]2.5 Wire navigation: submit → `/dashboard/chat/new?msg=<encoded>` (+ `&leader=X` if @-mentioned)
- [x]2.6 Verify deep link `/dashboard/chat/new?leader=cmo` still works

## Phase 3: Multi-Leader Attribution + Mobile Polish

- [x]3.1 Read `msg` from search params in chat page, send after `session_started`
- [x]3.2 Add routing badge inline — reads `routeSource` for "Auto-routed to" vs "Directed to @"
- [x]3.3 Add "Routing to the right experts..." pulsing indicator during classification delay
- [x]3.4 Enhance message bubbles — colored left border, name badge, full title on first appearance
- [x]3.5 Add "N leaders responding" status line using `activeLeaderIds.length`
- [x]3.6 Add mobile back arrow (`md:hidden`) navigating to `/dashboard`
- [x]3.7 Add mobile status bar showing responding leader names

## Phase 4: Tests

- [x]4.1 Create `test/chat-input.test.tsx` — @-trigger, keyboard nav, empty rejection, multi-mention, mobile `@` button
- [x]4.2 Create `test/at-mention-dropdown.test.tsx` — filter by id/name/title, selection, no-match state
- [x]4.3 Create `e2e/chat-ux.spec.ts` — Playwright E2E: dashboard → chat → multi-leader response → routing badge
- [x]4.4 Responsive verification at 375px, 768px, 1024px, 1440px
- [x]4.5 Verify CSP nonce compatibility (no inline scripts/styles)
