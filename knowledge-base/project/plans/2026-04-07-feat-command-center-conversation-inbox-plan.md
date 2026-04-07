---
title: "feat: Command Center (Conversation Inbox)"
type: feat
date: 2026-04-07
---

# feat: Command Center (Conversation Inbox)

## Overview

Replace the current `/dashboard` page with a **Command Center** — a conversation list that shows what happened and what needs attention. This is the "return-to-app" landing page for solo founders who trigger agents, step away, and return later.

**Issue:** #1690 | **Phase:** 3.3 (Make it Sticky) | **Branch:** `conversation-inbox` | **PR:** #1759

## Problem Statement

Solo founders trigger AI agents and return later. There is no landing page showing conversation activity. The current dashboard offers suggested prompts but no visibility into active, pending, or completed work. Founders must manually navigate to each conversation to check status.

## Proposed Solution

Replace `/dashboard` with a conversation list sorted by `last_active`, showing status badges, domain leader attribution, message previews, and real-time updates via Supabase Realtime. A "+ New conversation" button preserves the ability to start fresh conversations.

### Key Design Artifacts

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-conversation-inbox-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-conversation-inbox/spec.md`
- **Wireframes:** `knowledge-base/product/design/inbox/command-center.pen`
- **Screenshots:** `knowledge-base/product/design/inbox/screenshots/`

## Technical Approach

### Architecture

**Data flow:** Supabase browser client → RLS-filtered query → React state → UI. No custom API endpoint needed — RLS on `conversations` enforces `user_id = auth.uid()`.

**Real-time:** Supabase Realtime (`postgres_changes`) on the `conversations` table. This is the first Supabase Realtime usage in the codebase. It establishes a pattern for read-only real-time data flows, separate from the bidirectional WebSocket used for chat.

**No migration needed for the core feature.** The `conversations` table already has the correct schema: `status` check constraint (`active`, `waiting_for_user`, `completed`, `failed`), `last_active`, `domain_leader` (nullable), plus indexes on `user_id` and `status`. One small migration is needed: `REPLICA IDENTITY FULL` on the conversations table for Supabase Realtime to include all column values in change payloads.

**CSP:** Already permits `wss://${supabaseHost}` in connect-src (`lib/csp.ts:56`). No CSP change needed.

### Status Badge Mapping

| Database Value | UI Label | Color | Visual Weight |
|---|---|---|---|
| `waiting_for_user` | Needs your decision | Amber (yellow) | **Loudest** — amber bg tint on row |
| `active` | Executing | Blue | Medium |
| `completed` | Completed | Green | Muted text |
| `failed` | Needs attention | Red | Medium-low (de-emphasized) |

**Copywriter note:** Labels reviewed against brand guide. "Executing" (not "In progress") implies agents doing work. "Completed" (not "Done") has more weight. "Needs attention" kept over "Failed" — brainstorm decided founder language, though brand guide says errors should be honest. Revisit if user testing shows confusion.

### Conversation Title & Preview Strategy

- **Title:** Derived from first user message, truncated at ~60 chars with ellipsis. Fallback: "Untitled conversation" for 0-message records.
- **Preview:** Last message snippet (either role), ~100 chars, stripped of markdown formatting.
- **Query:** Single Supabase query with PostgREST embedded resources to avoid N+1:

```typescript
const { data, error } = await supabase
  .from("conversations")
  .select(`
    *,
    first_message:messages!inner(content).limit(1).order(created_at.asc).eq(role,user),
    last_message:messages(content, role, leader_id).limit(1).order(created_at.desc)
  `)
  .eq("status", statusFilter) // if filter active
  .order("last_active", { ascending: false })
  .range(0, 19); // cursor-based pagination
```

**Note:** PostgREST embedded resource syntax may need adjustment — verify against Supabase docs. If embedded resources can't express the lateral join, fall back to a database view or two sequential queries.

### Navigation Changes

| Current | New |
|---|---|
| `/dashboard` → prompt composer | `/dashboard` → Command Center (conversation list) |
| No back-to-list from chat | Chat page back arrow links to `/dashboard` (already does) |
| Sidebar "Dashboard" active only on exact `/dashboard` | Sidebar "Dashboard" active on `/dashboard` AND `/dashboard/chat/*` |
| Suggested prompts on dashboard | Moved to empty state + `/dashboard/chat/new` |

### Existing Assets to Reuse

| Asset | Location | Usage |
|---|---|---|
| `Conversation` type | `lib/types.ts:80-87` | Already has correct shape |
| `relativeTime()` | `lib/relative-time.ts` | Timestamp display |
| `LEADER_BG_COLORS` | `components/chat/leader-colors.ts` | Domain leader badge colors |
| `DOMAIN_LEADERS` | `server/domain-leaders.ts` | Domain filter dropdown values |
| `ErrorCard` | `components/ui/error-card.tsx` | Error state |
| `createClient()` | `lib/supabase/client.ts` | Browser Supabase client (includes Realtime) |
| Mobile patterns | Chat page | `100dvh`, `md:` breakpoints, `safe-bottom`, 44px touch targets |

### Implementation Phases

#### Phase 1: Foundation (migration + types + query hook)

**Tasks:**

1.1. **Migration: REPLICA IDENTITY FULL**
Create `supabase/migrations/0XX_conversations_replica_identity.sql`:

```sql
ALTER TABLE public.conversations REPLICA IDENTITY FULL;
```

This enables Supabase Realtime to include all column values in change payloads (not just primary key).

1.2. **Status label types**
Add to `lib/types.ts`:

```typescript
export type ConversationStatus = Conversation["status"];

export const STATUS_LABELS: Record<ConversationStatus, string> = {
  waiting_for_user: "Needs your decision",
  active: "Executing",
  completed: "Completed",
  failed: "Needs attention",
} as const;

export const STATUS_COLORS: Record<ConversationStatus, {
  dot: string;
  text: string;
  bg: string;
  border: string;
}> = {
  waiting_for_user: {
    dot: "bg-amber-500",
    text: "text-amber-500",
    bg: "bg-amber-500/10",
    border: "border-amber-500/30",
  },
  active: {
    dot: "bg-blue-500",
    text: "text-blue-500",
    bg: "bg-blue-500/10",
    border: "border-blue-500/30",
  },
  completed: {
    dot: "bg-green-500",
    text: "text-green-500",
    bg: "bg-green-500/10",
    border: "border-green-500/30",
  },
  failed: {
    dot: "bg-red-500",
    text: "text-red-500",
    bg: "bg-red-500/10",
    border: "border-red-500/30",
  },
};
```

1.3. **Data fetching hook: `useConversations`**
Create `hooks/use-conversations.ts`:
- Fetch conversations with embedded first/last message via Supabase client
- Accept `statusFilter` and `domainFilter` params
- Cursor-based pagination (load 20, "Load more" button)
- Return `{ conversations, loading, error, loadMore, hasMore }`
- Destructure `{ data, error }` on every query — never assume success (learning: supabase-silent-error-return-values)

1.4. **Supabase Realtime hook: `useConversationRealtime`**
Create `hooks/use-conversation-realtime.ts`:
- Subscribe to `postgres_changes` on `conversations` table filtered by `user_id`
- Handle `INSERT` (new from other tabs), `UPDATE` (status changes), `DELETE`
- On UPDATE: update badge in place without reordering the list (defer full reorder to avoid jarring shifts per spec-flow-analyzer recommendation)
- On INSERT: prepend to list
- Cleanup subscription on unmount
- No reconnection logic needed — Supabase client handles it internally

#### Phase 2: Core UI (page + components)

**Tasks:**

2.1. **StatusBadge component**
Create `components/inbox/status-badge.tsx`:
- Pill shape with colored dot + text
- Uses `STATUS_LABELS` and `STATUS_COLORS` from types
- Variants per status (amber/blue/green/red)

2.2. **ConversationRow component**
Create `components/inbox/conversation-row.tsx`:
- Desktop: horizontal row with status badge, title, snippet, domain leader badge, timestamp
- Mobile: vertical card stacking (status + timestamp on first line, title/snippet middle, leader bottom)
- `waiting_for_user` rows get subtle amber background tint (`bg-amber-500/[0.06]`)
- `completed` rows get muted text (`text-neutral-400` for title, `text-neutral-600` for snippet)
- Entire row is clickable → navigates to `/dashboard/chat/[id]`
- Touch target: min-h-[44px] on mobile

2.3. **FilterBar component**
Create `components/inbox/filter-bar.tsx`:
- Status dropdown: All / Needs your decision / Executing / Completed / Needs attention
- Domain dropdown: All / General / CTO / CMO / CLO / CPO / CRO / COO / CFO / CCO
- "General" maps to `domain_leader IS NULL`
- Active filter gets amber border + amber text
- Result count badge when filter active ("2 results")
- "+ New conversation" button (amber/gold, navigates to `/dashboard/chat/new`)
- Mobile: dropdowns side-by-side, button full-width below

2.4. **Replace dashboard page**
Rewrite `app/(dashboard)/dashboard/page.tsx`:
- Remove: hero, chat input, suggested prompts, leader strip, at-mention handling
- Add: FilterBar, ConversationRow list, empty state, loading skeleton, error state
- **Empty state (0 conversations):** "Your organization is ready." subline: "Start a conversation to put your agents to work." Button: "New conversation" (copywriter-approved copy)
- **Filtered empty state:** "No conversations match your filters." Button: "Clear filters"
- **Loading state:** 3-4 skeleton rows matching conversation row height
- **Error state:** Reuse `ErrorCard` with retry

2.5. **Update sidebar nav label**
In `app/(dashboard)/layout.tsx`:
- Change nav label from "Dashboard" to "Command Center"
- Change active logic from `pathname === "/dashboard"` to `pathname === "/dashboard" || pathname.startsWith("/dashboard/chat")`

#### Phase 3: Polish + Tests

**Tasks:**

3.1. **Loading skeleton component**
Create `components/inbox/conversation-skeleton.tsx`:
- 3-4 animated placeholder rows with pulse animation
- Match ConversationRow dimensions

3.2. **Keyboard accessibility**
- Conversation rows are focusable via tab
- Enter/Space opens conversation
- Arrow keys navigate between rows (optional, nice-to-have)

3.3. **Tests**
Create `test/command-center.test.tsx`:
- T1: Empty state renders "Your organization is ready" with CTA
- T2: Populated state renders conversations sorted by last_active
- T3: Status badges show correct founder-language labels
- T4: Status filter shows only matching conversations
- T5: Domain filter shows only matching conversations
- T6: Click row navigates to `/dashboard/chat/[id]`
- T7: "New conversation" button navigates to `/dashboard/chat/new`
- T8: Error state renders ErrorCard with retry
- T9: Filtered empty state differs from zero-conversations state
- T10: Supabase error is handled (destructured, displayed)

3.4. **Mobile responsiveness verification**
- Test at 375px (mobile), 768px (tablet), 1024px+ (desktop)
- Verify touch targets ≥ 44px
- Verify no auto-fill grid issues (use explicit breakpoints)

## Alternative Approaches Considered

| Approach | Why Not |
|---|---|
| Extend existing WebSocket for real-time | WS is conversation-scoped and bidirectional. Inbox needs user-scoped read-only. Would add complexity to already-dense 300+ line ws-handler. |
| Custom API endpoint for conversation list | RLS already enforces user isolation. Browser client query is sufficient. No server code needed. |
| Add `title` column to conversations table | Adds migration for a read-only feature. Derive from first message is zero-migration and join is cheap with existing index. |
| Polling instead of Supabase Realtime | Stale (5-30s latency), unnecessary load. Supabase Realtime is ~10 lines of client code. |
| Side panel for conversation detail | More complex to build. Full page navigation matches existing chat route and is mobile-friendly. |
| Tab-based status groups | Takes more horizontal space. Dropdown is simpler and scales to more filter options. |

## Acceptance Criteria

### Functional Requirements

- [ ] Command Center replaces `/dashboard` as the app landing page
- [ ] Conversations listed with correct status badges (founder language)
- [ ] Status badges: "Needs your decision" (amber), "Executing" (blue), "Completed" (green), "Needs attention" (red)
- [ ] "Needs your decision" rows visually loudest (amber background tint)
- [ ] Conversation title derived from first user message, truncated with ellipsis
- [ ] Last message snippet shown as preview (~100 chars)
- [ ] Domain leader badge with color coding per leader
- [ ] "Last updated" relative timestamp (reusing `relativeTime()`)
- [ ] Filter by status via dropdown
- [ ] Filter by domain via dropdown (including "General" for null)
- [ ] Result count shown when filter active
- [ ] Click row navigates to `/dashboard/chat/[id]`
- [ ] "New conversation" button navigates to `/dashboard/chat/new`
- [ ] Empty state: "Your organization is ready" with CTA
- [ ] Filtered empty state: "No conversations match your filters" with clear button
- [ ] Real-time status badge updates via Supabase Realtime
- [ ] New conversations from other tabs appear via Realtime INSERT
- [ ] Loading skeleton during initial data fetch
- [ ] Error state with retry (reusing ErrorCard)
- [ ] Cursor-based pagination (load 20, "Load more")
- [ ] Mobile-responsive (375px, 768px, 1024px+)
- [ ] Touch targets ≥ 44px
- [ ] Sidebar nav label updated to "Command Center"
- [ ] Sidebar nav active state includes `/dashboard/chat/*`

### Non-Functional Requirements

- [ ] Supabase queries destructure `{ data, error }` — never assume success
- [ ] Fire-and-forget async calls have `.catch()` handlers
- [ ] No auto-fill grids with semantic grouping
- [ ] REPLICA IDENTITY FULL migration applied

## Domain Review

**Domains relevant:** Marketing, Engineering, Product

### Marketing (CMO) — carried from brainstorm

**Status:** reviewed
**Assessment:** "Command Center" naming approved. Status badges must use founder language. Empty state is critical conversion surface — accepted "Your organization is ready" copy. Return-visit hook ("Needs your decision") is strongest re-engagement mechanic. Delegate layout to ux-design-lead (done).

### Engineering (CTO) — carried from brainstorm

**Status:** reviewed
**Assessment:** No core migration needed. Supabase Realtime recommended over extending WS. CSP already permits Realtime WSS. Cursor-based pagination from day one. 2-3 day estimate. REPLICA IDENTITY FULL migration required.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo (brainstorm carry-forward), ux-design-lead, copywriter
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

**spec-flow-analyzer:** Identified 15 gaps. Critical ones resolved in this plan:
- Status mapping defined explicitly (see Status Badge Mapping table)
- First-message composition moves to `/dashboard/chat/new` (existing chat input sufficient)
- WelcomeCard/suggested prompts removed from dashboard; empty state has brand-compliant CTA
- 0-message conversations show "Untitled conversation" fallback
- Loading skeleton specified
- Filtered vs zero-conversations empty states differentiated
- Realtime subscribes to INSERT/UPDATE/DELETE (not just UPDATE)
- List reorders only on page load/filter change, not on realtime UPDATE (badge updates in place)
- Sidebar active state expanded to include `/dashboard/chat/*`
- Domain filter includes "General" for NULL `domain_leader`

**ux-design-lead:** Wireframes created in `knowledge-base/product/design/inbox/command-center.pen`. Four screens: desktop populated, mobile populated, empty state, filtered state. Key design decisions: amber background tint on "Needs your decision" rows, pill-shaped badges with colored dots, muted text for completed rows, vertical card stacking on mobile.

**copywriter:** Badge labels reviewed against brand guide. Accepted: "Executing" (not "In progress"), "Completed" (not "Done"), "New conversation" (not "+ New"), richer empty state copy. Kept "Needs attention" over "Failed" per brainstorm founder-language decision. Added tooltip recommendation for decision-required badge.

## Test Scenarios

### Acceptance Tests

- Given a user with 0 conversations, when they load `/dashboard`, then they see "Your organization is ready" with a "New conversation" button
- Given a user with mixed-status conversations, when they load `/dashboard`, then conversations are sorted by `last_active` descending with correct status badges
- Given a user viewing the list, when they select "Needs your decision" from the status filter, then only `waiting_for_user` conversations are shown with a "2 results" count
- Given a user viewing the list, when they select "CTO" from the domain filter, then only conversations with `domain_leader = 'cto'` are shown
- Given a user viewing the list, when a conversation status changes server-side, then the badge updates in real-time without page refresh
- Given a user viewing the list, when they click a conversation row, then they navigate to `/dashboard/chat/[id]`
- Given a user on mobile (375px), when they view the Command Center, then conversation rows are vertically stacked cards with ≥44px touch targets

### Edge Cases

- Given a conversation with 0 messages, when displayed in the list, then title shows "Untitled conversation" with no snippet
- Given active filters that match 0 conversations, when displayed, then show "No conversations match your filters" with a "Clear filters" button (not the zero-conversations empty state)
- Given a user with 25+ conversations, when they load the page, then only 20 are shown with a "Load more" button
- Given the Supabase query fails, when the page loads, then ErrorCard is shown with a retry button
- Given a conversation with `domain_leader = NULL`, when "General" domain filter is selected, then the conversation is shown

### Integration Verification

- **Browser:** Navigate to `/dashboard`, verify conversation list loads with correct badges and timestamps. Apply status filter, verify list updates. Click a row, verify navigation to chat page.

## Dependencies & Risks

| Dependency | Status | Risk |
|---|---|---|
| Multi-turn continuity (#1044) | CLOSED ✅ | None |
| Phase 2 security (#674) | CLOSED ✅ | None |
| Tag-and-route (#1059) | CLOSED ✅ | None |
| Supabase Realtime on project plan | Needs verification | Free tier: 200 concurrent connections. Acceptable for beta. |
| PostgREST embedded resource syntax | Needs verification | May need alternative query approach if syntax can't express lateral join. |

| Risk | Mitigation |
|---|---|
| PostgREST can't do the title/snippet join in one query | Fall back to two sequential queries or a database view |
| Supabase Realtime doesn't respect RLS for subscriptions | Verify during implementation. If not, use the existing WS for user-scoped filtering |
| REPLICA IDENTITY FULL impacts write performance | Negligible for beta user count. Monitor if conversation writes slow down |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-conversation-inbox-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-conversation-inbox/spec.md`
- Wireframes: `knowledge-base/product/design/inbox/command-center.pen`
- ADR-005 persistent sessions: `knowledge-base/engineering/architecture/decisions/ADR-005-persistent-session-architecture.md`
- Current dashboard: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- Layout/nav: `apps/web-platform/app/(dashboard)/layout.tsx`
- Types: `apps/web-platform/lib/types.ts:80-87`
- Leader colors: `apps/web-platform/components/chat/leader-colors.ts`
- Relative time: `apps/web-platform/lib/relative-time.ts`
- CSP: `apps/web-platform/lib/csp.ts:56`
- Supabase client: `apps/web-platform/lib/supabase/client.ts`

### Learnings Applied

- Supabase silent errors: destructure `{ error }` on every query (`2026-03-20-supabase-silent-error-return-values.md`)
- Fire-and-forget `.catch()`: required on Node 22 (`2026-03-20-fire-and-forget-promise-catch-handler.md`)
- Auto-fill grid grouping: use explicit breakpoints, not auto-fill (`ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md`)
- Three-breakpoint testing: always test desktop, tablet (769-1024px), mobile (`2026-02-22-landing-page-grid-orphan-regression.md`)
- Review gate stuck status: AbortSignal cancellation exists in agent-runner (`2026-03-20-review-gate-promise-leak-abort-timeout.md`)
