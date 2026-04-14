# Tasks: fix-agent-icon-display

## Phase 1: Setup

- [ ] 1.1 Read and understand `LeaderAvatar` component interface (`components/leader-avatar.tsx`)
- [ ] 1.2 Read `useTeamNames` hook to understand `getIconPath` API (`hooks/use-team-names.tsx`)
- [ ] 1.3 Review working implementations in `team-settings.tsx` and `chat/[conversationId]/page.tsx` as reference patterns

## Phase 2: Core Implementation

- [ ] 2.1 Wire `customIconPath` in `ConversationRow` (`components/inbox/conversation-row.tsx`)
  - [ ] 2.1.1 Import `useTeamNames` from `@/hooks/use-team-names`
  - [ ] 2.1.2 Call `useTeamNames()` to get `getIconPath`
  - [ ] 2.1.3 Pass `customIconPath={getIconPath(conversation.domain_leader)}` to mobile `LeaderAvatar` (line ~191)
  - [ ] 2.1.4 Pass `customIconPath={getIconPath(conversation.domain_leader)}` to desktop `LeaderAvatar` (line ~223)

- [ ] 2.2 Wire `customIconPath` in `DashboardPage` foundation cards (`app/(dashboard)/dashboard/page.tsx`)
  - [ ] 2.2.1 Import `useTeamNames` from `@/hooks/use-team-names`
  - [ ] 2.2.2 Call `useTeamNames()` to get `getIconPath` in the `DashboardPage` component
  - [ ] 2.2.3 Pass `customIconPath={getIconPath(card.leaderId)}` to both foundation card `LeaderAvatar` instances (empty state and inbox state)

- [ ] 2.3 Wire `customIconPath` in `LeaderStrip` (`app/(dashboard)/dashboard/page.tsx`)
  - [ ] 2.3.1 Accept `getIconPath` prop in `LeaderStrip` component
  - [ ] 2.3.2 Pass `customIconPath={getIconPath(leader.id)}` to `LeaderAvatar` in the strip
  - [ ] 2.3.3 Pass `getIconPath` from `DashboardPage` to `LeaderStrip`

## Phase 3: Testing

- [ ] 3.1 Run existing test suite to verify no regressions
- [ ] 3.2 Update `conversation-row.test.tsx` to mock `useTeamNames` if tests fail due to missing context
- [ ] 3.3 Verify all 5 test scenarios from the plan pass
