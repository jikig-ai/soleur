# Tasks: fix-agent-icon-display

## Phase 1: Setup

- [x] 1.1 Read `LeaderAvatar` component interface (`components/leader-avatar.tsx`) -- confirm `customIconPath` prop type
- [x] 1.2 Read `useTeamNames` hook (`hooks/use-team-names.tsx`) -- confirm `getIconPath` returns `string | null`
- [x] 1.3 Review working implementation in `chat/[conversationId]/page.tsx` lines 48, 360, 480-519 as reference pattern

## Phase 2: Core Implementation

- [x] 2.1 Wire `customIconPath` in `ConversationRow` (`components/inbox/conversation-row.tsx`)
  - [x] 2.1.1 Import `useTeamNames` from `@/hooks/use-team-names` and `DomainLeaderId` type from `@/server/domain-leaders`
  - [x] 2.1.2 Call `const { getIconPath } = useTeamNames();` inside `ConversationRow` function body
  - [x] 2.1.3 Add `customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)}` to mobile `LeaderAvatar` (line ~191)
  - [x] 2.1.4 Add `customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)}` to desktop `LeaderAvatar` (line ~223)

- [x] 2.2 Wire `customIconPath` in `DashboardPage` (`app/(dashboard)/dashboard/page.tsx`)
  - [x] 2.2.1 Import `useTeamNames` from `@/hooks/use-team-names`
  - [x] 2.2.2 Call `const { getIconPath } = useTeamNames();` inside `DashboardPage` function body
  - [x] 2.2.3 Add `customIconPath={getIconPath(card.leaderId)}` to empty-state foundation card `LeaderAvatar` (line ~501)
  - [x] 2.2.4 Add `customIconPath={getIconPath(card.leaderId)}` to inbox-state foundation card `LeaderAvatar` (line ~615)
  - [x] 2.2.5 Pass `getIconPath={getIconPath}` to `LeaderStrip` component (line ~561)

- [x] 2.3 Wire `customIconPath` in `LeaderStrip` (same file, line ~763)
  - [x] 2.3.1 Add `getIconPath` to `LeaderStrip` props: `{ onLeaderClick: ...; getIconPath: (id: DomainLeaderId) => string | null }`
  - [x] 2.3.2 Add `customIconPath={getIconPath(leader.id as DomainLeaderId)}` to `LeaderAvatar` (line ~777)

## Phase 3: Testing

- [x] 3.1 Add `vi.mock("@/hooks/use-team-names")` to `test/components/conversation-row.test.tsx` (match pattern from `test/chat-page.test.tsx` lines 44-50)
- [x] 3.2 Run test suite: `node node_modules/vitest/vitest.mjs run` (worktree-safe)
- [x] 3.3 Verify all existing tests pass with the mock in place
- [x] 3.4 (Optional) Add test case for custom icon rendering in `conversation-row.test.tsx`
