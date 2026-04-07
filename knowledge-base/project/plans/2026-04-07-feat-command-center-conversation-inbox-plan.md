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
- **Query strategy:** Two simple queries (PostgREST embedded resources cannot express per-resource ordering/filtering — confirmed by plan review):

```typescript
// Query 1: Fetch conversations
const { data: conversations, error } = await supabase
  .from("conversations")
  .select("*")
  .order("last_active", { ascending: false })
  .order("created_at", { ascending: false }) // tiebreaker
  .limit(50);

// Query 2: Fetch first + last messages for displayed conversations
const conversationIds = conversations.map(c => c.id);
const { data: messages, error: msgError } = await supabase
  .from("messages")
  .select("conversation_id, role, content, leader_id, created_at")
  .in("conversation_id", conversationIds)
  .order("created_at", { ascending: true });

// Client-side: derive title (first user message) and preview (last message) per conversation
```

### Domain Leader Badges

- **3-letter abbreviation** using the uppercase leader ID: `CTO`, `CMO`, `CLO`, `CPO`, `CRO`, `COO`, `CFO`, `CCO`
- No separate name label needed — the badge IS the identifier
- Uses existing `LEADER_BG_COLORS` for per-leader color coding

### Navigation Changes

| Current | New |
|---|---|
| `/dashboard` → prompt composer | `/dashboard` → Command Center (conversation list) |
| No back-to-list from chat | Chat page back arrow links to `/dashboard` (already does) |
| Sidebar "Dashboard" active only on exact `/dashboard` | Sidebar "Dashboard" active on `/dashboard` AND `/dashboard/chat/*` |
| Suggested prompts on dashboard | Shown in empty state (0 conversations); hidden when conversations exist |

### Existing Assets to Reuse

| Asset | Location | Usage |
|---|---|---|
| `Conversation` type | `lib/types.ts:80-87` | Add `created_at: string` (missing from interface but exists in DB) |
| `relativeTime()` | `lib/relative-time.ts` | Timestamp display |
| `LEADER_BG_COLORS` | `components/chat/leader-colors.ts` | Domain leader badge colors |
| `DOMAIN_LEADERS` | `server/domain-leaders.ts` | Domain filter dropdown values |
| `ErrorCard` | `components/ui/error-card.tsx` | Error state |
| `createClient()` | `lib/supabase/client.ts` | Browser Supabase client (includes Realtime) |
| Mobile patterns | Chat page | `100dvh`, `md:` breakpoints, `safe-bottom`, 44px touch targets |

### Implementation (single phase — 2-3 days)

**1. Migration: REPLICA IDENTITY FULL**
Create `supabase/migrations/0XX_conversations_replica_identity.sql`:

```sql
ALTER TABLE public.conversations REPLICA IDENTITY FULL;
```

**2. Type updates**
In `lib/types.ts`:
- Add `created_at: string` to `Conversation` interface
- Add `STATUS_LABELS` record mapping DB values to founder-language labels

```typescript
export type ConversationStatus = Conversation["status"];

export const STATUS_LABELS: Record<ConversationStatus, string> = {
  waiting_for_user: "Needs your decision",
  active: "Executing",
  completed: "Completed",
  failed: "Needs attention",
} as const;
```

Status badge colors live inline in the component JSX, not in a lookup table.

**3. `useConversations` hook (single hook — data + realtime)**
Create `hooks/use-conversations.ts`:
- Fetch conversations + messages via two simple queries (see Query Strategy above)
- Accept `statusFilter` and `domainFilter` params
- Fetch all (limit 50) — no pagination for beta
- **Supabase Realtime subscription in the same hook:**
  - Subscribe to `postgres_changes` on `conversations` table
  - **CRITICAL: Must specify `filter: user_id=eq.${userId}`** — Realtime does NOT respect RLS by default. Without this filter, all users receive all conversation changes (data leak).
  - Handle `UPDATE` events only — update badge in place without reordering the list
  - Cleanup subscription on unmount
- Return `{ conversations, loading, error, refetch }`
- Destructure `{ data, error }` on every query — never assume success

```typescript
const channel = supabase
  .channel('command-center')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'conversations',
    filter: `user_id=eq.${userId}` // CRITICAL: prevents data leak
  }, (payload) => {
    updateConversationStatus(payload.new);
  })
  .subscribe();
```

**4. Replace dashboard page**
Rewrite `app/(dashboard)/dashboard/page.tsx`:
- Remove: hero, chat input, at-mention handling
- Add: filter bar, conversation rows, empty/filtered/loading/error states
- **Empty state (0 conversations):** Reuse current dashboard's suggested prompt cards and leader strip. Heading: "Your organization is ready." Subline: "Start a conversation to put your agents to work." Preserves onboarding/discovery flow for new users.
- **Filtered empty state:** "No conversations match your filters." Button: "Clear filters"
- **Loading state:** 3-4 inline skeleton rows with `animate-pulse`
- **Error state:** Reuse `ErrorCard` with retry
- **Filter bar:** Status dropdown + Domain dropdown + "New conversation" button. Inline in page component — extract to own file only if it exceeds ~80 lines.
- **Conversation rows:** Each row shows status badge (pill with colored dot), title, snippet, 3-letter domain leader badge (e.g., `CTO`), relative timestamp. `waiting_for_user` rows get amber bg tint. `completed` rows get muted text. Entire row clickable → `/dashboard/chat/[id]`. Extract `ConversationRow` to own file (will exceed 80 lines with desktop/mobile variants).
- **Status badge:** Inline in ConversationRow or extract if reused. Pill shape, colored dot + text, colors per status: amber (decision), blue (executing), green (completed), red (attention).

**5. Update sidebar nav**
In `app/(dashboard)/layout.tsx`:
- Change nav label from "Dashboard" to "Command Center"
- Change active logic: `pathname === "/dashboard" || pathname.startsWith("/dashboard/chat")`

**6. Tests**
Create `test/command-center.test.tsx`:
- T1: Empty state renders suggested prompts and "New conversation" CTA
- T2: Populated state renders conversations sorted by `last_active` desc
- T3: Status filter shows only matching conversations
- T4: Click row navigates to `/dashboard/chat/[id]`
- T5: "New conversation" button navigates to `/dashboard/chat/new`

**7. Mobile responsiveness verification**
- Test at 375px (mobile), 768px (tablet), 1024px+ (desktop)
- Verify touch targets ≥ 44px
- Verify no layout breakage at tablet breakpoint

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
- [ ] Click row navigates to `/dashboard/chat/[id]`
- [ ] "New conversation" button navigates to `/dashboard/chat/new`
- [ ] Empty state: suggested prompt cards + leader strip + "Your organization is ready" CTA
- [ ] Filtered empty state: "No conversations match your filters" with clear button
- [ ] Real-time status badge updates via Supabase Realtime (UPDATE events, user_id filtered)
- [ ] Loading skeleton during initial data fetch
- [ ] Error state with retry (reusing ErrorCard)
- [ ] Mobile-responsive (375px, 768px, 1024px+)
- [ ] Domain leader badges use 3-letter abbreviation (CTO, CMO, etc.) — no separate name label
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
- WelcomeCard/suggested prompts/leader strip preserved in empty state for 0-conversation users
- 0-message conversations show "Untitled conversation" fallback
- Loading skeleton specified
- Filtered vs zero-conversations empty states differentiated
- Realtime subscribes to UPDATE only with explicit `user_id` filter (security-critical)
- List reorders only on page load/filter change, not on realtime UPDATE (badge updates in place)
- Domain leader badges use 3-letter abbreviation (CTO, CMO) — no name label duplication
- Sidebar active state expanded to include `/dashboard/chat/*`
- Domain filter includes "General" for NULL `domain_leader`

**ux-design-lead:** Wireframes created in `knowledge-base/product/design/inbox/command-center.pen`. Four screens: desktop populated, mobile populated, empty state, filtered state. Key design decisions: amber background tint on "Needs your decision" rows, pill-shaped badges with colored dots, muted text for completed rows, vertical card stacking on mobile.

**copywriter:** Badge labels reviewed against brand guide. Accepted: "Executing" (not "In progress"), "Completed" (not "Done"), "New conversation" (not "+ New"), richer empty state copy. Kept "Needs attention" over "Failed" per brainstorm founder-language decision. Added tooltip recommendation for decision-required badge.

## Test Scenarios

### Acceptance Tests

- Given a user with 0 conversations, when they load `/dashboard`, then they see suggested prompt cards, leader strip, and "Your organization is ready" with a "New conversation" button
- Given a user with mixed-status conversations, when they load `/dashboard`, then conversations are sorted by `last_active` descending with correct status badges
- Given a user viewing the list, when they select "Needs your decision" from the status filter, then only `waiting_for_user` conversations are shown with a "2 results" count
- Given a user viewing the list, when they select "CTO" from the domain filter, then only conversations with `domain_leader = 'cto'` are shown
- Given a user viewing the list, when a conversation status changes server-side, then the badge updates in real-time without page refresh
- Given a user viewing the list, when they click a conversation row, then they navigate to `/dashboard/chat/[id]`
- Given a user on mobile (375px), when they view the Command Center, then conversation rows are vertically stacked cards with ≥44px touch targets

### Edge Cases

- Given a conversation with 0 messages, when displayed in the list, then title shows "Untitled conversation" with no snippet
- Given active filters that match 0 conversations, when displayed, then show "No conversations match your filters" with a "Clear filters" button (not the zero-conversations empty state)
- Given a user with 60+ conversations, when they load the page, then only the 50 most recent are shown
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

| Risk | Mitigation |
|---|---|
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
