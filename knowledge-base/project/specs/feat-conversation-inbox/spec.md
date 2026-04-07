# Conversation Inbox (Command Center) Spec

**Issue:** #1690
**Brainstorm:** [2026-04-07-conversation-inbox-brainstorm.md](../../brainstorms/2026-04-07-conversation-inbox-brainstorm.md)
**Phase:** 3.3 (Make it Sticky)
**Status:** Draft — pending UX artifacts

## Problem Statement

Solo founders trigger AI agents, step away, and return later. There is no landing page that shows what happened and what needs attention. The current dashboard offers suggested prompts but no visibility into active, pending, or completed work. Founders must remember which conversations they started and manually check each one.

## Goals

- G1: Provide a single "return-to-app" view showing all conversation activity
- G2: Surface conversations requiring human decisions prominently
- G3: Enable filtering by status and domain to find specific conversations
- G4: Update conversation statuses in real-time without page refresh
- G5: Work on mobile viewports (phone and tablet)

## Non-Goals

- NG1: Archiving or bulk actions on conversations (defer to usage feedback)
- NG2: PWA badge counts or push notifications (covered by #1049)
- NG3: LLM-generated conversation summaries (overkill for MVP)
- NG4: Inline approve/reject actions from the list (click-through to conversation)
- NG5: Search across conversation content (defer to post-MVP)

## Functional Requirements

| ID | Requirement | Priority |
|----|------------|----------|
| FR1 | Replace `/dashboard` with conversation list as the app landing page | P0 |
| FR2 | Display status badges: "Needs your decision" (yellow), "In progress" (green), "Done" (gray), "Needs attention" (red) | P0 |
| FR3 | Show conversation title derived from first user message (truncated) | P0 |
| FR4 | Show last message snippet as preview (~100 chars) | P0 |
| FR5 | Show "last updated" relative timestamp per conversation | P0 |
| FR6 | Show domain leader attribution per conversation (colored badge) | P0 |
| FR7 | Filter by status via dropdown (All / Needs your decision / In progress / Done / Needs attention) | P0 |
| FR8 | Filter by domain via dropdown (All / CTO / CMO / CLO / etc.) | P0 |
| FR9 | Click conversation row to navigate to `/dashboard/chat/[id]` | P0 |
| FR10 | `+ New` button to start a new conversation (navigates to `/dashboard/chat/new`) | P0 |
| FR11 | Real-time status updates via Supabase Realtime (postgres_changes) | P1 |
| FR12 | Empty state: "No conversations yet" with `+ New` button | P0 |
| FR13 | Cursor-based pagination (load more on scroll or button) | P1 |
| FR14 | Mobile-responsive layout following existing chat page patterns | P0 |

## Technical Requirements

| ID | Requirement | Detail |
|----|------------|--------|
| TR1 | Supabase Realtime subscription | Subscribe to `postgres_changes` on `conversations` table filtered by `user_id`. Requires `REPLICA IDENTITY FULL` migration. |
| TR2 | CSP update | Add Supabase Realtime WebSocket endpoint to `lib/csp.ts` connect-src directive |
| TR3 | Conversation title query | Join to `messages` table for first user message. Use PostgREST embedded resources or lateral join to avoid N+1. |
| TR4 | Last message query | Join to `messages` table for most recent message. Same query optimization as TR3. |
| TR5 | Supabase error handling | Destructure `{ data, error }` on every query. Never assume success. (Learning: supabase-silent-error-return-values) |
| TR6 | Fire-and-forget safety | All async calls without await must have `.catch()`. Node 22 terminates on unhandled rejections. (Learning: fire-and-forget-promise-catch-handler) |
| TR7 | Responsive breakpoints | Test at desktop (>1024px), tablet (769-1024px), mobile (<=768px). No auto-fill grids with semantic grouping. (Learning: auto-fill-grid-loses-semantic-grouping) |
| TR8 | Touch targets | Minimum 44x44px tap targets for conversation rows and filter controls |

## Status State Machine

```text
                    ┌─────────────┐
         start ──>  │   active    │
                    │ In progress │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              v            v            v
    ┌─────────────┐  ┌──────────┐  ┌────────┐
    │waiting_for_  │  │completed │  │ failed │
    │    user      │  │   Done   │  │ Needs  │
    │Needs your    │  │          │  │  attn  │
    │  decision    │  └──────────┘  └────────┘
    └──────┬───────┘       ^            ^
           │               │            │
           └───────────────┘            │
           (user responds               │
            or 2hr timeout)             │
                                        │
           (server crash / abort) ──────┘
```

### Transitions (existing in agent-runner.ts)

- `active` -> `waiting_for_user`: Agent hits review gate
- `waiting_for_user` -> `active`: User responds to review gate
- `active` -> `completed`: Agent finishes or explicit close
- `waiting_for_user` -> `completed`: 2-hour inactivity timeout (hourly cleanup)
- `active` -> `failed`: Error, abort, or disconnect
- `active`/`waiting_for_user` -> `failed`: Server startup cleanup (>5 min stale)

## Affected Files

| File | Change |
|------|--------|
| `app/(dashboard)/dashboard/page.tsx` | Replace with Command Center (conversation list) |
| `app/(dashboard)/layout.tsx` | Update nav label from "Dashboard" to "Command Center" |
| `components/inbox/` (new) | ConversationList, ConversationRow, StatusBadge, FilterBar |
| `lib/csp.ts` | Add Supabase Realtime WSS to connect-src |
| `supabase/migrations/` (new) | `REPLICA IDENTITY FULL` on conversations table |
| `lib/types.ts` | Add UI status label type mapping |

## UX Gate

**Status: PENDING**

Per AGENTS.md: "For user-facing pages with a Product/UX Gate, specialists (ux-design-lead, copywriter) must produce artifacts before implementation."

Required before implementation:
- [ ] UX design artifact (.pen file) for Command Center layout, badge hierarchy, mobile layout
- [ ] Copywriter review of status badge labels against brand guide

## Test Scenarios

| # | Scenario | Expected |
|---|----------|----------|
| T1 | User with 0 conversations loads Command Center | Empty state with "No conversations yet" and `+ New` button |
| T2 | User with mixed-status conversations loads page | Conversations sorted by last_active desc, correct status badges |
| T3 | User filters by "Needs your decision" | Only `waiting_for_user` conversations shown |
| T4 | User filters by domain "CTO" | Only conversations with `domain_leader = 'cto'` shown |
| T5 | Conversation status changes while page is open | Badge updates in real-time via Supabase Realtime |
| T6 | User clicks a conversation row | Navigates to `/dashboard/chat/[id]` |
| T7 | User clicks `+ New` | Navigates to `/dashboard/chat/new` |
| T8 | Page renders on mobile viewport (375px) | Single-column layout, touch-friendly targets |
| T9 | Page renders on tablet viewport (768px) | Appropriate layout, no broken groupings |
| T10 | Supabase query fails | Error handled gracefully, not silently swallowed |
