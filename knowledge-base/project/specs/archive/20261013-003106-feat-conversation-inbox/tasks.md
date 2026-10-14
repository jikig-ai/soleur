# Tasks: Command Center (Conversation Inbox)

**Plan:** [2026-04-07-feat-command-center-conversation-inbox-plan.md](../../plans/2026-04-07-feat-command-center-conversation-inbox-plan.md)
**Issue:** #1690

## Implementation (single phase)

- [x] 1. Create migration `REPLICA IDENTITY FULL` on conversations table
  - File: `apps/web-platform/supabase/migrations/0XX_conversations_replica_identity.sql`
- [x] 2. Update types in `lib/types.ts`
  - Add `created_at: string` to `Conversation` interface
  - Add `STATUS_LABELS` record (founder-language labels)
- [x] 3. Create `useConversations` hook (data + realtime in one hook)
  - File: `apps/web-platform/hooks/use-conversations.ts`
  - Two simple queries: conversations + messages (no PostgREST embedded resources)
  - Status and domain filter params
  - Fetch all (limit 50, no pagination for beta)
  - Supabase Realtime subscription for UPDATE events
  - **CRITICAL:** Explicit `filter: user_id=eq.${userId}` on Realtime subscription
  - Destructure `{ data, error }` — never assume success
- [x] 4. Replace dashboard page with Command Center
  - File: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - Conversation rows: status badge, title, snippet, 3-letter leader badge (CTO/CMO), timestamp
  - Amber bg tint on `waiting_for_user` rows, muted text on `completed` rows
  - Filter bar: status dropdown + domain dropdown + "New conversation" button (inline in page)
  - Empty state (0 conversations): suggested prompt cards + leader strip + CTA
  - Filtered empty: "No conversations match your filters" + "Clear filters"
  - Loading: inline skeleton rows with `animate-pulse`
  - Error: reuse `ErrorCard` with retry
  - Extract `ConversationRow` to `components/inbox/conversation-row.tsx` (will exceed 80 lines)
  - Status badge colors inline in component JSX (not a lookup table)
- [x] 5. Update sidebar nav in `app/(dashboard)/layout.tsx`
  - Label: "Dashboard" → "Command Center"
  - Active state: include `/dashboard/chat/*`
- [x] 6. Write tests in `test/command-center.test.tsx`
  - T1: Empty state renders suggested prompts and CTA
  - T2: Populated state renders conversations sorted by `last_active` desc
  - T3: Status filter shows only matching conversations
  - T4: Click row navigates to `/dashboard/chat/[id]`
  - T5: "New conversation" button navigates to `/dashboard/chat/new`
- [x] 7. Mobile responsiveness verification
  - Test at 375px, 768px, 1024px+
  - Verify touch targets ≥ 44px
  - Verify no layout breakage at tablet breakpoint
