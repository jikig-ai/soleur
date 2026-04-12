# Tasks: Archive Conversations

## Phase 1: Database Migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/019_add_archived_at.sql`
  - [ ] 1.1.1 Add `archived_at timestamptz DEFAULT NULL` column to `conversations`
  - [ ] 1.1.2 Add index `idx_conversations_user_archived` on `(user_id, archived_at)`
- [ ] 1.2 Verify migration applies locally via `supabase db reset`

## Phase 2: Types and Hook

- [ ] 2.1 Add `archived_at: string | null` to `Conversation` interface in `apps/web-platform/lib/types.ts`
- [ ] 2.2 Update `useConversations` hook in `apps/web-platform/hooks/use-conversations.ts`
  - [ ] 2.2.1 Add `archiveFilter` parameter to hook options
  - [ ] 2.2.2 Default query excludes archived (`.is("archived_at", null)`)
  - [ ] 2.2.3 Archived query (`.not("archived_at", "is", null)`)
  - [ ] 2.2.4 Add `archiveConversation(id)` function
  - [ ] 2.2.5 Add `unarchiveConversation(id)` function
  - [ ] 2.2.6 Update Realtime handler to patch `archived_at` and splice/remove from local state based on `archiveFilter`

## Phase 3: UI — Archive Actions and Filter Tab

- [ ] 3.1 Add archive/unarchive button to `apps/web-platform/components/inbox/conversation-row.tsx`
  - [ ] 3.1.1 Archive icon button with `e.stopPropagation()`
  - [ ] 3.1.2 Conditional render: "Archive" vs "Unarchive" based on `archived_at`
  - [ ] 3.1.3 Archived visual indicator (muted opacity or badge)
- [ ] 3.2 Add archive toggle to `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - [ ] 3.2.1 "Active" / "Archived" tab control (separate from status filter)

## Phase 4: Tests

- [ ] 4.0 Update stale mock data in `apps/web-platform/test/command-center.test.tsx` (add cost fields from migration 017)
- [ ] 4.1 Extend `apps/web-platform/test/command-center.test.tsx`
  - [ ] 4.1.1 Archived conversations hidden from default view
  - [ ] 4.1.2 Archived tab shows archived conversations
  - [ ] 4.1.3 Archive button moves conversation to archived
  - [ ] 4.1.4 Unarchive restores to active list
- [ ] 4.2 Extend `apps/web-platform/test/components/conversation-row.test.tsx`
  - [ ] 4.2.1 Archive button renders correctly
  - [ ] 4.2.2 Archive click does not trigger row navigation
  - [ ] 4.2.3 Archived visual indicator when `archived_at` is set
- [ ] 4.3 Verify migration applies to production after merge
