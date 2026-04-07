# Tasks: Command Center (Conversation Inbox)

**Plan:** [2026-04-07-feat-command-center-conversation-inbox-plan.md](../../plans/2026-04-07-feat-command-center-conversation-inbox-plan.md)
**Issue:** #1690

## Phase 1: Foundation

- [ ] 1.1 Create migration `REPLICA IDENTITY FULL` on conversations table
  - File: `apps/web-platform/supabase/migrations/0XX_conversations_replica_identity.sql`
- [ ] 1.2 Add status label types and color constants to `lib/types.ts`
  - `STATUS_LABELS` record mapping DB values to founder-language labels
  - `STATUS_COLORS` record with dot/text/bg/border Tailwind classes per status
- [ ] 1.3 Create `useConversations` hook
  - File: `apps/web-platform/hooks/use-conversations.ts`
  - Supabase query with embedded resources for title + last message
  - Status and domain filter params
  - Cursor-based pagination (load 20, hasMore, loadMore)
  - Destructure `{ data, error }` — never assume success
- [ ] 1.4 Create `useConversationRealtime` hook
  - File: `apps/web-platform/hooks/use-conversation-realtime.ts`
  - Subscribe to INSERT/UPDATE/DELETE on conversations table
  - On UPDATE: update badge in place (no list reorder)
  - On INSERT: prepend to list
  - Cleanup on unmount

## Phase 2: Core UI

- [ ] 2.1 Create `StatusBadge` component
  - File: `apps/web-platform/components/inbox/status-badge.tsx`
  - Pill shape with colored dot + text
  - Uses `STATUS_LABELS` and `STATUS_COLORS`
- [ ] 2.2 Create `ConversationRow` component
  - File: `apps/web-platform/components/inbox/conversation-row.tsx`
  - Desktop: horizontal row (badge, title, snippet, leader badge, timestamp)
  - Mobile: vertical card stacking
  - Amber bg tint for `waiting_for_user` rows
  - Muted text for `completed` rows
  - Clickable → `/dashboard/chat/[id]`
  - Min touch target 44px
- [ ] 2.3 Create `FilterBar` component
  - File: `apps/web-platform/components/inbox/filter-bar.tsx`
  - Status dropdown with founder-language labels
  - Domain dropdown (All / General / CTO / CMO / etc.)
  - Active filter amber border + result count badge
  - "New conversation" button (amber/gold)
  - Mobile: side-by-side dropdowns, full-width button
- [ ] 2.4 Create `ConversationSkeleton` loading component
  - File: `apps/web-platform/components/inbox/conversation-skeleton.tsx`
  - 3-4 animated placeholder rows with pulse animation
- [ ] 2.5 Replace dashboard page with Command Center
  - File: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - Remove: hero, chat input, suggested prompts, leader strip
  - Add: FilterBar, ConversationRow list, empty/filtered/loading/error states
  - Empty state: "Your organization is ready." + "New conversation" CTA
  - Filtered empty: "No conversations match your filters." + "Clear filters"
  - Loading: ConversationSkeleton
  - Error: ErrorCard with retry
- [ ] 2.6 Update sidebar nav
  - File: `apps/web-platform/app/(dashboard)/layout.tsx`
  - Change label: "Dashboard" → "Command Center"
  - Change active logic: include `/dashboard/chat/*`

## Phase 3: Polish + Tests

- [ ] 3.1 Keyboard accessibility
  - Tab-focusable conversation rows
  - Enter/Space to open conversation
- [ ] 3.2 Write tests
  - File: `apps/web-platform/test/command-center.test.tsx`
  - T1-T10 from spec test scenarios
  - Edge cases: 0-message conversations, filtered empty, pagination, error handling
- [ ] 3.3 Mobile responsiveness verification
  - Test at 375px, 768px, 1024px+
  - Verify touch targets ≥ 44px
  - Verify no layout breakage at tablet breakpoint
- [ ] 3.4 Verify Supabase Realtime
  - Confirm RLS filters subscriptions by user_id
  - Confirm REPLICA IDENTITY FULL delivers all column values
  - Test: change conversation status in another tab → badge updates
