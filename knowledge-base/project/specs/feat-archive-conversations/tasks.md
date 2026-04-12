# Tasks: Archive Conversations

## Phase 1: Database Migration

- [x] 1.1 Create `apps/web-platform/supabase/migrations/019_add_archived_at.sql`
  - [x] 1.1.1 Add `archived_at timestamptz DEFAULT NULL` column to `conversations`
  - [x] 1.1.2 Add index `idx_conversations_user_archived` on `(user_id, archived_at)`
- [ ] 1.2 Verify migration applies locally via `supabase db reset`

## Phase 2: Types and Hook

- [x] 2.1 Add `archived_at: string | null` to `Conversation` interface in `apps/web-platform/lib/types.ts`
- [x] 2.2 Update `useConversations` hook in `apps/web-platform/hooks/use-conversations.ts`
  - [x] 2.2.1 Add `archiveFilter` parameter to hook options
  - [x] 2.2.2 Default query excludes archived (`.is("archived_at", null)`)
  - [x] 2.2.3 Archived query (`.not("archived_at", "is", null)`)
  - [x] 2.2.4 Add `archiveConversation(id)` function
  - [x] 2.2.5 Add `unarchiveConversation(id)` function
  - [x] 2.2.6 Update Realtime handler to patch `archived_at` and splice/remove from local state based on `archiveFilter`

## Phase 3: UI — Archive Actions and Filter Tab

- [x] 3.1 Add archive/unarchive button to `apps/web-platform/components/inbox/conversation-row.tsx`
  - [x] 3.1.1 Archive icon button with `e.stopPropagation()`
  - [x] 3.1.2 Conditional render: "Archive" vs "Unarchive" based on `archived_at`
  - [x] 3.1.3 Archived visual indicator (muted opacity or badge)
- [x] 3.2 Add archive toggle to `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - [x] 3.2.1 "Active" / "Archived" tab control (separate from status filter)

## Phase 4: Tests

- [x] 4.0 Update stale mock data in `apps/web-platform/test/command-center.test.tsx` (add cost fields from migration 017)
- [x] 4.1 Extend `apps/web-platform/test/command-center.test.tsx`
  - [x] 4.1.1 Archived conversations hidden from default view
  - [x] 4.1.2 Archived tab shows archived conversations
  - [x] 4.1.3 Archive button moves conversation to archived
  - [x] 4.1.4 Unarchive restores to active list
- [x] 4.2 Extend `apps/web-platform/test/components/conversation-row.test.tsx`
  - [x] 4.2.1 Archive button renders correctly
  - [x] 4.2.2 Archive click does not trigger row navigation
  - [x] 4.2.3 Archived visual indicator when `archived_at` is set
- [ ] 4.3 Verify migration applies to production after merge
