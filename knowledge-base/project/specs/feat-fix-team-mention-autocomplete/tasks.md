# Tasks: fix team mention autocomplete

## Phase 1: Setup and failing tests (RED)

- [ ] 1.1 Add custom name filter tests to `apps/web-platform/test/at-mention-dropdown.test.tsx`
  - [ ] 1.1.1 Test: query "ole" with `customNames: { cto: "Oleg" }` returns CTO
  - [ ] 1.1.2 Test: query "pat" with `customNames: { cfo: "Patrick" }` returns CFO
  - [ ] 1.1.3 Test: custom name match is case-insensitive ("OLE" matches "Oleg")
  - [ ] 1.1.4 Test: empty customNames still matches by leader.id, leader.name, leader.title
  - [ ] 1.1.5 Test: loading=true with non-matching query shows "Loading team..." not "No matches"
  - [ ] 1.1.6 Test: loading=true with matching default query still shows matches
  - [ ] 1.1.7 Test: custom name shows in display format "Oleg (CTO)"
  - [ ] 1.1.8 Test: multiple custom names matching same query shows all (e.g., "ole" -> Oleg + Olena)
- [ ] 1.2 Add server-side routing test to `apps/web-platform/test/domain-router.test.ts`
  - [ ] 1.2.1 Test: `routeMessage` resolves `@oleg` when customNames provided (mention mode, no API call)

## Phase 2: Core implementation (GREEN)

- [ ] 2.1 Add `loading` prop to `AtMentionDropdown` component (`apps/web-platform/components/chat/at-mention-dropdown.tsx`)
  - [ ] 2.1.1 Add optional `loading?: boolean` to `AtMentionDropdownProps` interface
  - [ ] 2.1.2 Show "Loading team..." when `loading && filtered.length === 0 && query`
- [ ] 2.2 Pass `loading` from `useTeamNames()` to `AtMentionDropdown` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - [ ] 2.2.1 Destructure `loading: teamNamesLoading` from `useTeamNames()`
  - [ ] 2.2.2 Pass `loading={teamNamesLoading}` to `AtMentionDropdown`
- [ ] 2.3 Fix server-side routing to pass custom names
  - [ ] 2.3.1 Update `routeMessage` in `apps/web-platform/server/domain-router.ts` to accept optional `customNames` parameter
  - [ ] 2.3.2 Pass `customNames` from `routeMessage` to `parseAtMentions`
  - [ ] 2.3.3 In `apps/web-platform/server/agent-runner.ts` (around line 1347), fetch user's custom names from `team_names` table using service client with explicit `user_id` filter
  - [ ] 2.3.4 Pass fetched custom names to `routeMessage`

## Phase 3: Verification

- [ ] 3.1 Run at-mention-dropdown tests: `npx vitest run test/at-mention-dropdown.test.tsx`
- [ ] 3.2 Run domain-router tests: `npx vitest run test/domain-router.test.ts`
- [ ] 3.3 Run team-names-hook tests: `npx vitest run test/team-names-hook.test.tsx`
- [ ] 3.4 Run full test suite for web-platform: `npx vitest run`
- [ ] 3.5 Verify no TypeScript errors: `npx tsc --noEmit`
