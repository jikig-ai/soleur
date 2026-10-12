---
title: "feat: Chat UX redesign"
type: feat
date: 2026-03-29
issue: "#1289"
spec: knowledge-base/project/specs/feat-chat-ux-redesign/spec.md
wireframes: knowledge-base/product/design/command-center/chat-ux-redesign.pen
brainstorm: knowledge-base/project/brainstorms/2026-03-27-tag-and-route-brainstorm.md
---

# Chat UX Redesign

## Overview

Replace the Command Center's department grid (8 leader cards) with a chat-first interface. The user types immediately — no navigation required. @-mention autocomplete surfaces leaders as the discovery mechanism. Auto-routing is the default; @-mentions are the override.

Server-side routing already exists (`domain-router.ts` handles `parseAtMentions()` and `classifyMessage()`). This is primarily a client-side React/Tailwind implementation, with one small additive server change: an optional `source` field on `stream_start` messages to distinguish auto-routing from @-mention routing.

**Deferred:** Conversation sidebar deferred to #672 (conversation inbox). Sidebar requires multi-slot WebSocket connections — a significant server-side refactor that is not justified for the current user base (~5 users). Build the chat-first dashboard, validate it, and let real usage determine whether a sidebar is needed.

## Problem Statement

The current dashboard requires navigating through a department grid to reach the chat. This adds friction — extra clicks before the primary interaction. The @-mention system works server-side but has no client-side UX: no autocomplete, no visual hints. Users must know to type `@CMO` manually. Multi-leader response attribution exists but lacks routing badges and refined visual treatment.

## Proposed Solution

Three UI changes, primarily client-side:

1. **Chat-first dashboard** — Hero chat input replaces the department grid
2. **@-mention autocomplete** — Dropdown with leader metadata when user types `@`
3. **Multi-leader attribution** — Routing badge + color-coded message bubbles + mobile polish

Plus one small server-side addition:

1. **Routing source on `stream_start`** — Optional `source: "auto" | "mention"` field so the routing badge can distinguish auto-routing from @-mention routing

## Technical Approach

### Architecture

**Component hierarchy:**

- `dashboard/page.tsx` — Replaces grid with hero chat input, suggested prompts, leader strip (becomes `"use client"`)
- `dashboard/chat/[conversationId]/page.tsx` — Enhanced with `<RoutingBadge>`, extracted `<MessageBubble>`, `<ChatInput>` reused, mobile back arrow
- New: `ChatInput` and `AtMentionDropdown` as shared components (the only components genuinely used by multiple pages)

**Existing infrastructure (no changes needed):**

| Layer | File | Already supports |
|-------|------|-----------------|
| Router | `server/domain-router.ts` | `parseAtMentions()` + `classifyMessage()` auto-detection |
| Runner | `server/agent-runner.ts` | `dispatchToLeaders()` for parallel multi-leader sessions |
| WS types | `lib/types.ts` | `start_session(leaderId?)`, `stream_start/stream/stream_end` with `leaderId` |
| WS client | `lib/ws-client.ts` | Multi-stream multiplexing via `Map<DomainLeaderId, number>` |
| WS handler | `server/ws-handler.ts` | `start_session` without `leaderId` triggers auto-routing |

**One additive server-side change:**

| Layer | File | Change |
|-------|------|--------|
| WS types | `lib/types.ts` | Add optional `source?: "auto" \| "mention"` field to `stream_start` message |
| Agent runner | `server/agent-runner.ts` | Pass `routeResult.source` through to `stream_start` emission |
| WS client | `lib/ws-client.ts` | Store `source` from first `stream_start`; expose `activeLeaderIds: DomainLeaderId[]` (derived from `activeStreamsRef.current.keys()`) |

### Implementation Phases

#### Phase 1: Component Foundation + Server Addition

Extract the two shared chat components and make the one server-side change. The `@` button for mobile is included here since it's part of `ChatInput`.

**Files to create:**

- `apps/web-platform/components/chat/chat-input.tsx` — Enhanced `<textarea>` with @-mention trigger detection, send on Enter. Accepts `onSend(message: string)` and `onAtTrigger(query: string)` callbacks. Validates internally: rejects empty/whitespace-only messages. Supports multiple `@` mentions in one message — each `@` independently triggers the dropdown based on `selectionStart`. Includes `@` button visible only below `md:` breakpoint (`md:hidden`) for mobile users.
- `apps/web-platform/components/chat/at-mention-dropdown.tsx` — Dropdown list of leaders filtered by query. Each row: color avatar, abbreviation, full title, description. Keyboard navigation (arrow keys, Enter, Escape). Filters by `id`, `name`, and `title` (case-insensitive substring match). Reads from `DOMAIN_LEADERS` metadata.

**Files to modify:**

- `apps/web-platform/lib/types.ts` — Add optional `source?: "auto" | "mention"` to `stream_start` message type.
- `apps/web-platform/server/agent-runner.ts` — Pass `routeResult.source` into `stream_start` emission (between line 682 `routeMessage()` and the `dispatchToLeaders` call).
- `apps/web-platform/lib/ws-client.ts` — Read `source` from `stream_start`; expose `routeSource: "auto" | "mention" | null` and `activeLeaderIds: DomainLeaderId[]` in hook return value.

**Note:** `LEADER_COLORS` stays as a UI-side constant (not added to `domain-leaders.ts` server model). Extract the existing `LEADER_COLORS` map from the chat page into the `ChatInput` module or a shared `chat-colors.ts` constant file if needed by multiple components.

**Acceptance criteria:**

- [ ] `<ChatInput>` renders a textarea, detects `@` character, calls `onAtTrigger`, rejects empty messages
- [ ] `<AtMentionDropdown>` filters leaders by id/name/title substring match (case-insensitive)
- [ ] `@cm` in dropdown shows CMO only (1 match — "cmo" contains "cm")
- [ ] Keyboard navigation works: ↑/↓ to navigate, Enter to select, Escape to dismiss
- [ ] Multiple `@` mentions in one message each independently trigger dropdown
- [ ] Mobile `@` button visible below `md:`, hidden on desktop
- [ ] `stream_start` includes `source` field; `useWebSocket` exposes `routeSource` and `activeLeaderIds`

#### Phase 2: Chat-First Dashboard

Replace the department grid with the chat-first hero experience (wireframe 01). The dashboard page transitions from a server component to a client component (`"use client"`).

**Files to modify:**

- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — Full rewrite. Add `"use client"`. Remove the leader card grid. New layout:
  1. "COMMAND CENTER" label + "What are you building today?" headline
  2. Subtitle: "Ask anything. Your 8 department leaders will auto-route to the right experts."
  3. `<ChatInput>` centered with `<AtMentionDropdown>` wired up
  4. Hint text: "Type @ to mention a specific leader" + "Enter to send"
  5. Four suggested prompt cards inline (not a separate component — used only here). Each card: icon, title text, leader tags. Clicking a card fills the chat input (fill-only, no auto-submit — user presses Enter to confirm). Responsive: `grid-cols-2 md:grid-cols-4`.
  6. "YOUR ORGANIZATION" inline section — horizontal row of 8 leader abbreviations with accent colors. Clicking an abbreviation inserts `@{leaderId}` into the chat input and focuses it.

**Navigation flow:**

1. User submits message from dashboard input
2. Client navigates to `/dashboard/chat/new?msg=<encodeURIComponent(message)>` (with optional `&leader=X` if @-mentioned)
3. Chat page reads `msg` from `searchParams`, sends it after `session_started`

**Why URL param:** Simple, no storage API, no cleanup, no race conditions. Initial prompts from the hero input and suggested cards are short strings — URL length is not a concern.

**Acceptance criteria:**

- [ ] Dashboard renders the chat-first hero (matches wireframe 01)
- [ ] Typing `@` shows the autocomplete dropdown
- [ ] Clicking a suggested prompt card fills the input (does NOT auto-submit)
- [ ] Submitting a message navigates to the chat page and starts a session
- [ ] Deep link `/dashboard/chat/new?leader=cmo` still works (existing URL contract)
- [ ] "YOUR ORGANIZATION" strip shows all 8 leaders with correct colors
- [ ] Clicking a leader abbreviation inserts `@{id}` into input

#### Phase 3: Multi-Leader Attribution + Mobile Polish

Enhance the active conversation view with routing badges, refined message attribution, and mobile-specific elements (wireframes 03, 05).

**Files to modify:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`:
  - Replace inline `MessageBubble` with extracted version (inline in this file — same pattern as current codebase, just enhanced)
  - Replace hardcoded `LEADER_COLORS` with the shared constant
  - Add routing badge inline at top of conversation: reads `routeSource` from `useWebSocket` to show "Auto-routed to CMO, CRO" or "Directed to @CMO"
  - Add status line at bottom: "N leaders responding" using `activeLeaderIds.length`
  - During the 1-3s classification delay (before first `stream_start`), show a pulsing "Routing to the right experts..." indicator below the user's message
  - Read `msg` from search params, send as first message after `session_started`
  - Add back arrow in header for mobile (navigates to dashboard)
  - Add "CMO, CRO responding" status bar on mobile

**Message attribution behavior (from wireframe 03):**

- Leader name badge with colored background above each leader message
- Full title on first appearance per leader in thread, abbreviation only after
- User messages: right-aligned, dark card with lighter text
- Leader messages: left-aligned, slightly lighter card with colored left border

**Mobile additions (wireframe 05):**

- Back arrow in header (`md:hidden`) — navigates to `/dashboard`
- Status bar showing responding leader names
- Full-height message area, input pinned to bottom with `dvh` units

**Acceptance criteria:**

- [ ] Routing badge shows at top of conversation (matches wireframe 03)
- [ ] Badge distinguishes "Auto-routed to" vs "Directed to @" using `routeSource`
- [ ] Each leader message has colored name badge + left border
- [ ] Status shows "N leaders responding" during streaming
- [ ] Pulsing "Routing to the right experts..." shown during classification delay
- [ ] Multiple leaders' responses render as separate bubbles, not consolidated
- [ ] Initial message from `?msg=` param appears as first user bubble
- [ ] Mobile back arrow visible below `md:` (matches wireframe 05)
- [ ] Mobile status bar shows responding leader names

#### Phase 4: Tests

Tests written alongside components in prior phases where natural, but this phase covers comprehensive coverage and E2E.

**Files to create:**

- `apps/web-platform/test/chat-input.test.tsx` — Unit tests for @-trigger detection, keyboard navigation, send behavior, empty message rejection, multi-mention support, mobile `@` button
- `apps/web-platform/test/at-mention-dropdown.test.tsx` — Filtering by id/name/title, selection, keyboard nav, no-match state
- `apps/web-platform/e2e/chat-ux.spec.ts` — Playwright E2E: dashboard load → type message → navigate to chat → verify multi-leader response → routing badge

**Test runner:** `vitest` (project convention — `vitest.config.ts` exists, `vitest` in devDependencies).

**Acceptance criteria:**

- [ ] All component unit tests pass via `vitest`
- [ ] E2E test covers the full dashboard → chat → multi-leader flow
- [ ] No accessibility regressions (focus management, ARIA `role="listbox"` on dropdown)
- [ ] CSP nonce compatibility verified (no inline scripts or styles)
- [ ] Responsive verification at 375px, 768px, 1024px, 1440px

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| **Keep department grid as secondary nav below chat** | Adds visual clutter. The "YOUR ORGANIZATION" leader strip achieves discoverability without a full grid. Brainstorm decision #4 explicitly chose to transform the grid. |
| **Rich text / contentEditable for @-mentions** | Over-engineering. A plain textarea with cursor position detection for the `@` trigger is sufficient. Users type `@CMO`, not styled mention chips. Server-side `parseAtMentions` already handles the raw text. |
| **New `route_result` WS message type** | Over-engineering. Routing info is derivable from existing `stream_start` events. Adding an optional `source` field to `stream_start` is sufficient — one field addition, not a new message type. |
| **sessionStorage for message handoff** | Over-engineered for a short prompt string. URL search param (`?msg=`) is simpler — no storage API, no cleanup logic, no race conditions. Initial prompts are short. |
| **`scope` field on `DOMAIN_LEADERS`** | Duplicates `description`. The @-mention dropdown can display `description` directly. Adding a redundant field creates two places to update when a leader's responsibilities change. |
| **Separate `components/chat/` for single-use components** | Fights the codebase convention (all UI inline in page files). Only `ChatInput` and `AtMentionDropdown` are genuinely shared between pages. Single-use elements (suggested prompts, leader strip, routing badge, enhanced message bubble) stay inline in their page files. |
| **Auto-submit on suggested prompt click** | UX risk. Auto-submit means the user cannot preview or modify the prompt. For a product that routes to AI agents, fill-only is safer — user presses Enter to confirm. |
| **Conversation sidebar (Phase 4 in original plan)** | Deferred to #672. Requires multi-slot WebSocket connections (server-side `Map<userId, Map<slot, ws>>`) — significant refactor that cascaded into ~40% of plan complexity. For ~5 users, nobody has requested persistent chat on every page. Build chat-first dashboard, validate, let usage guide. |

## Acceptance Criteria

### Functional Requirements

- [ ] Dashboard shows chat-first hero (no department grid)
- [ ] Typing `@` triggers autocomplete dropdown with all 8 leaders
- [ ] Autocomplete filters by leader ID, name, and title (case-insensitive)
- [ ] Submitting a message auto-routes to relevant leaders
- [ ] Explicit `@CMO` in message overrides auto-routing
- [ ] Each leader's response renders in a separate bubble with colored border and name badge
- [ ] Routing badge shows "Auto-routed to X, Y" or "Directed to @X"
- [ ] Suggested prompt cards on empty state fill input (user confirms with Enter)
- [ ] "YOUR ORGANIZATION" strip shows all 8 leader abbreviations
- [ ] Mobile shows full-page chat with `@` button and back arrow
- [ ] Deep link `/dashboard/chat/new?leader=cmo` continues to work
- [ ] Status indicator shows "N leaders responding" during streaming

### Non-Functional Requirements

- [ ] No server-side routing logic changes; only additive `source` field on `stream_start`
- [ ] Preserves WebSocket close code routing (learning: ws-close-code-routing)
- [ ] Preserves abort-before-replace session pattern (learning: ws-session-race)
- [ ] CSP nonce compatible — no inline scripts/styles (learning: csp-nonce)
- [ ] Root layout forces dynamic rendering via `await headers()` (learning: csp-strict-dynamic)
- [ ] Grid divisibility rule holds at all breakpoints for suggested prompts (learning: grid-orphan-regression)

### Quality Gates

- [ ] Component unit tests for `ChatInput` and `AtMentionDropdown`
- [ ] E2E test covering dashboard → chat → multi-leader flow
- [ ] Accessibility: focus trap in dropdown, ARIA `role="listbox"` on autocomplete
- [ ] Responsive verification at 375px, 768px, 1024px, 1440px

## Test Scenarios

### Chat-First Dashboard

- Given the dashboard loads, when no conversation is active, then the chat-first hero is displayed with input, suggested prompts, and leader strip
- Given the user types a message and presses Enter, when the message is submitted, then the user navigates to `/dashboard/chat/new?msg=<message>` and a session starts with auto-routing
- Given the user clicks a suggested prompt card, when the card is clicked, then the prompt text fills the input (no auto-submit)

### @-Mention Autocomplete

- Given the user types `@` in the chat input, when the `@` character is detected, then the autocomplete dropdown appears showing all 8 leaders
- Given the dropdown is open and the user types `cm`, when filtering by id/name/title, then only CMO is shown (1 match — id "cmo" contains "cm")
- Given the dropdown is open, when the user presses ↓ and Enter, then the leader is selected and inserted into the input as `@{leaderId}`
- Given the dropdown is open, when the user presses Escape, then the dropdown closes without inserting anything
- Given the user types `@xyz` (no match), when filtering, then the dropdown shows "No matches"
- Given the user types `@CMO and @CRO`, when the autocomplete triggers on the second `@`, then it opens a fresh dropdown for the second mention

### Multi-Leader Response

- Given a message is sent without @-mentions, when the server auto-routes to CMO and CRO, then two separate message bubbles appear with CMO (pink border) and CRO (green border)
- Given a message contains `@CMO`, when the server routes via mention, then the routing badge shows "Directed to @CMO" (not "Auto-routed")
- Given multiple leaders are responding, when streams are active, then status shows "2 leaders responding"
- Given auto-routing classification takes 2 seconds, when the user is waiting, then a "Routing to the right experts..." indicator is visible below their message

### Message Handoff

- Given the user submits "help with pricing" from the dashboard, when the chat page loads, then the message from `?msg=` param appears as the user's first bubble and auto-routing begins
- Given the chat page receives `session_started`, when `msg` search param exists, then the message is sent immediately via `sendMessage()`

### Mobile Experience

- Given the user is on mobile (below `md:`), when they open a chat conversation, then the full-page chat view is shown with back arrow and `@` button
- Given the user taps the `@` button on mobile, when tapped, then `@` is inserted at cursor position and autocomplete dropdown opens
- Given leaders are responding on mobile, when streams are active, then the status bar shows "CMO, CRO responding"

### Error and Edge Cases

- Given the WebSocket drops mid-stream on mobile, when the connection is lost, then the status changes to "Reconnecting..." and partial content is preserved
- Given an empty message is submitted, when ChatInput validates, then the message is rejected (no navigation)

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Server-side multi-leader infrastructure is complete (#1059). Schema migration 010 made `domain_leader` nullable and added `leader_id` to messages. `dispatchToLeaders()` handles parallel multi-leader sessions. Only additive change needed: optional `source` field on `stream_start`.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Roadmap consistent (P1 item 1.11). Auto-detection accuracy is the key risk; @-mention override is the mitigation. Auto-detection accuracy will need real user testing during beta.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** HIGH concern. "Departments" metaphor is baked into all marketing content. "Choose a domain leader" copy describes the exact UX being deprecated. Opportunity: "One command center" is a stronger positioning upgrade. All public surfaces mentioning the old interaction model must be updated at ship time.

**Action required at ship time:** CMO content-opportunity gate must trigger. Marketing copy across the docs site and landing page needs alignment with the new "chat-first" interaction model.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** ux-design-lead (wireframes completed externally)
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

Wireframes approved (5 screens in `knowledge-base/product/design/command-center/`):

1. `01-dashboard-empty-state.png` — Chat-first landing with suggested prompts
2. `02-at-mention-autocomplete.png` — @-mention dropdown with filtered results
3. `03-active-conversation-multi-leader.png` — Multi-leader response thread
4. `04-conversation-sidebar.png` — Deferred to #672
5. `05-mobile-experience.png` — Full-page mobile chat

Copy in wireframes approved as part of the wireframe review.

## Dependencies and Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| @-mention cursor position for multi-mention | Medium | Use `selectionStart` to find the most recent `@` before cursor. Track active mention range. Each `@` independently triggers the dropdown. |
| Auto-routing classification delay (1-3s) | Medium | Show pulsing "Routing to the right experts..." indicator between message submission and first `stream_start`. |
| Mobile keyboard pushing content | Medium | Use `dvh` units and `position: sticky` for the input bar. Test on iOS Safari where keyboard behavior differs from Chrome. |
| Dashboard server→client component transition | Low | Current page uses `await createClient()` and `await supabase.auth.getUser()`. New client component must handle auth differently (client-side Supabase or pass data from a parent server component). |
| Autocomplete z-index conflicts with layout | Low | Use Tailwind `z-50` on dropdown in a positioned container that escapes overflow clipping. |
| CSP compatibility of new components | Low | No inline scripts or styles. All Tailwind classes. Root layout already forces dynamic rendering. |

**Dependencies:**

- Tag-and-route server-side implementation (#1059 brainstorm complete, migration 010 applied)
- Multi-turn conversation (#1044 merged per brainstorm)
- No external dependencies or new packages required

## Deferred Items

| Item | Issue | Why deferred | Re-evaluation criteria |
|------|-------|-------------|----------------------|
| Conversation sidebar | #672 | Requires multi-slot WebSocket connections — ~40% of original plan complexity for a feature nobody has requested | Revisit after 10+ active users report wanting contextual chat on non-dashboard pages |
| Multi-session inbox | #672 | Explicitly scoped out in spec (Non-Goals) | Phase 3 roadmap item |

## References

### Internal

- Spec: `knowledge-base/project/specs/feat-chat-ux-redesign/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-tag-and-route-brainstorm.md`
- Wireframes: `knowledge-base/product/design/command-center/chat-ux-redesign.pen`
- Dashboard page: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Layout: `apps/web-platform/app/(dashboard)/layout.tsx`
- Domain router: `apps/web-platform/server/domain-router.ts`
- Domain leaders: `apps/web-platform/server/domain-leaders.ts`
- WS client: `apps/web-platform/lib/ws-client.ts`
- WS handler: `apps/web-platform/server/ws-handler.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`
- Types: `apps/web-platform/lib/types.ts`

### Learnings Applied

- `2026-03-27-tag-and-route-multi-leader-architecture.md` — Multi-stream multiplexing via Map, per-leader stream lifecycle
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md` — Preserve close code routing in ws-client
- `2026-03-28-csp-connect-src-websocket-scheme-mismatch.md` — Keep explicit wss:// in connect-src
- `2026-03-27-ws-session-race-abort-before-replace.md` — Abort-before-replace pattern for session management
- `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` — Root layout must await headers()
- `2026-02-22-landing-page-grid-orphan-regression.md` — Grid divisibility rule at all breakpoints
- `2026-02-17-backdrop-filter-breaks-fixed-positioning.md` — No backdrop-filter without explicit height

### Related Issues

- #1289 — This feature (Chat UX redesign)
- #1059 — Tag-and-route brainstorm (closed)
- #672 — Conversation sidebar + multi-session inbox (deferred, Phase 3)
- #1044 — Multi-turn conversation (merged)
