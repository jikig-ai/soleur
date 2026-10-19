# Conversation Inbox (Command Center) Brainstorm

**Date:** 2026-04-07
**Issue:** #1690
**Branch:** conversation-inbox
**Participants:** Founder, CPO, CMO, CTO

## What We're Building

Replace the current `/dashboard` page with a **Command Center** — a conversation list that shows what happened and what needs attention. This is the action loop: "what needs my decision?"

The Command Center replaces the current dashboard's suggested-prompts layout with a conversation-centric landing page. A `+ New` button provides inline access to start new conversations, preserving the current dashboard's primary action.

### Core Components

- Conversation list sorted by `last_active` descending
- Status badges using founder-centric language
- Status and domain dropdown filters
- Last message snippet as preview content
- Conversation title derived from first user message
- Click-through navigation to `/dashboard/chat/[id]`
- Real-time status updates via Supabase Realtime
- "Last updated" relative timestamps (reuse `relative-time.ts`)
- Mobile-responsive (follow existing chat page patterns)

## Why This Approach

**Combined dashboard + inbox:** The founder returns to the app and immediately sees what needs attention. No extra navigation step. The `+ New` button preserves the ability to start fresh conversations. This is the strongest "return-to-app" experience for Phase 3's stickiness goal.

**Supabase Realtime over WebSocket:** The existing WebSocket is conversation-scoped and bidirectional (chat). The inbox needs user-scoped, read-only status updates. Supabase Realtime (postgres_changes) is ~10 lines of client code, needs no server changes, and avoids adding complexity to the already-dense 300+ line ws-handler. This is the first Supabase Realtime usage in the codebase — it establishes a pattern for read-only real-time data flows.

**Founder language over system language:** Status badges speak to what the founder should do, not what the system is doing. This aligns with the brand guide's voice principles.

**Derive title from first message:** Zero migration. The join to messages is cheap with the existing `idx_messages_conversation_created` index. Avoids adding a column for a read-only feature.

## Key Decisions

| # | Decision | Choice | Alternatives Considered |
|---|----------|--------|------------------------|
| 1 | Feature role | Combined: inbox IS dashboard with `+ New` chat access | Separate route; sibling view |
| 2 | Feature name | Command Center | Inbox; Activity; Dashboard |
| 3 | Badge vocabulary | Founder language: "Needs your decision" / "In progress" / "Done" / "Needs attention" | System language (waiting_for_user, active, etc.); Hybrid |
| 4 | Real-time mechanism | Supabase Realtime (postgres_changes on conversations) | Extend existing WebSocket; Polling on focus |
| 5 | Click-through | Navigate to `/dashboard/chat/[id]` (full page) | Side panel; In-place replacement |
| 6 | Conversation titles | Derive from first user message (truncated, join to messages) | Add title column; LLM-generated summary |
| 7 | Preview content | Last message snippet (~100 chars) | Status-specific prompt; Title only |
| 8 | Empty state | Minimal placeholder ("No conversations yet" + `+ New` button) | CTA-driven onboarding; Suggested prompts grid |
| 9 | Stale state handling | Show "last updated" timestamp; rely on existing agent-runner cleanup (5min startup, 2hr hourly) | Auto-detect + offer action; Defer to Phase 4 |
| 10 | Filter scope | Status dropdown + Domain dropdown, sort by last_active desc | Status only; Tab-based status groups |
| 11 | Implementation approach | Spec + UX artifacts first, then build | Direct implementation; Minimal + iterate |

### Status Badge Mapping

| Database Value | UI Label | Visual Treatment |
|---------------|----------|-----------------|
| `waiting_for_user` | Needs your decision | Yellow/amber — loudest, primary action |
| `active` | In progress | Green — work is happening |
| `completed` | Done | Muted/gray — low visual weight |
| `failed` | Needs attention | Red — error state, de-emphasized |

## Open Questions

1. **Should completed conversations auto-archive or persist?** A cluttered list kills the "what needs attention" signal, but removing completed work hides compounding value. Defer to UX design pass.
2. **PWA badge count on app icon?** Would strengthen return-visit hook but adds iOS/Android-specific complexity. Defer to review gate notifications (#1049).
3. **Conversation title length and truncation strategy?** Exact char limit TBD during UX design.
4. **Multi-leader conversations:** A single conversation can involve CTO, CLO, CMO. Which domain does the filter match? First leader? All? Defer to UX/spec.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** "Inbox" naming sets email-like expectations — "Command Center" is better. Status badges ARE brand copy and must use founder language, not system language. The empty state is the most important conversion surface for Phase 3 — even with a minimal placeholder, it must guide toward the first conversation. The return-visit hook ("Needs your decision") is the strongest re-engagement mechanic. Mobile-first inbox strengthens the delivery pivot narrative. Delegate layout review to conversion-optimizer and ux-design-lead.

### Engineering (CTO)

**Summary:** No migration needed for core feature — schema has correct status enum, indexes, and RLS. Recommends Supabase Realtime over extending WebSocket (10 lines client code vs. 300+ line ws-handler complexity). Needs REPLICA IDENTITY FULL migration and CSP update for Realtime. API can use Supabase browser client directly with RLS — no custom endpoint needed. Cursor-based pagination from day one. 2-3 day estimate.

### Product (CPO)

**Summary:** Dependencies cleared (#1044 closed, #674 closed). Schema and WebSocket infrastructure exist. Tag-and-route (#1059) is shipped, so domain filtering is viable. UX gate requires design artifacts before implementation for user-facing pages. Key product question: the "waiting-for-user" badge is the core value prop — the visual hierarchy must make it the loudest element. Recommends spec + UX first (Approach B).

## Infrastructure Notes

### Existing Assets (No Changes Needed)

- `conversations` table with `status` check constraint, `last_active`, `domain_leader`
- `messages` table with `leader_id`, indexed on `(conversation_id, created_at)`
- RLS policies enforcing `user_id = auth.uid()`
- TypeScript `Conversation` type in `lib/types.ts`
- `relative-time.ts` utility for timestamp formatting
- `leader-colors.ts` for per-leader color coding
- Mobile-responsive patterns in chat page (`100dvh`, `md:` breakpoints, `safe-bottom`)
- Orphaned conversation cleanup in agent-runner (5min startup, 2hr hourly)

### New Infrastructure Required

- Supabase Realtime: `REPLICA IDENTITY FULL` migration on conversations table
- CSP update in `lib/csp.ts` for Realtime WebSocket endpoint
- Status badge component (new, hand-rolled like existing components)
- Filter dropdown component (new)
- Conversation list API or direct Supabase client query with RLS

### Key Learnings to Apply

- Supabase client silently discards errors — destructure `{ error }` on every query
- WebSocket TOCTOU race on reconnection — if using WS, check readyState after await
- Fire-and-forget async calls need `.catch()` on Node 22
- `auto-fill` grids break semantic grouping on mobile — use explicit breakpoints
- Test all three breakpoints (desktop >1024, tablet 769-1024, mobile <=768)
