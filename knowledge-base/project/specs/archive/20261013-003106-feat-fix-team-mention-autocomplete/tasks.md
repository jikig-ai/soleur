# Tasks: fix team mention autocomplete

## Phase 1: Setup and failing tests (RED)

- [x] 1.1 Add custom name filter tests to `apps/web-platform/test/at-mention-dropdown.test.tsx`
  - [x] 1.1.1 Test: query "ole" with `customNames: { cto: "Oleg" }` returns CTO
  - [x] 1.1.2 Test: query "pat" with `customNames: { cfo: "Patrick" }` returns CFO
  - [x] 1.1.3 Test: custom name match is case-insensitive ("OLE" matches "Oleg")
  - [x] 1.1.4 Test: empty customNames still matches by leader.id, leader.name, leader.title
  - [x] 1.1.5 Test: loading=true with non-matching query shows "Loading team..." not "No matches"
  - [x] 1.1.6 Test: loading=true with matching default query still shows matches
  - [x] 1.1.7 Test: custom name shows in display format "Oleg (CTO)"
  - [x] 1.1.8 Test: multiple custom names matching same query shows all (e.g., "ole" -> Oleg + Olena)
- [x] 1.2 Add server-side routing test to `apps/web-platform/test/domain-router.test.ts`
  - [x] 1.2.1 Test: `routeMessage` resolves `@oleg` when customNames provided (mention mode, no API call)

## Phase 2: Core implementation (GREEN)

- [x] 2.1 Add `loading` prop to `AtMentionDropdown` component (`apps/web-platform/components/chat/at-mention-dropdown.tsx`)
  - [x] 2.1.1 Add optional `loading?: boolean` to `AtMentionDropdownProps` interface
  - [x] 2.1.2 Show "Loading team..." when `loading && filtered.length === 0 && query`
- [x] 2.2 Pass `loading` from `useTeamNames()` to `AtMentionDropdown` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - [x] 2.2.1 Destructure `loading: teamNamesLoading` from `useTeamNames()`
  - [x] 2.2.2 Pass `loading={teamNamesLoading}` to `AtMentionDropdown`
- [x] 2.3 Fix server-side routing to pass custom names
  - [x] 2.3.1 Update `routeMessage` in `apps/web-platform/server/domain-router.ts` to accept optional `customNames` parameter
  - [x] 2.3.2 Pass `customNames` from `routeMessage` to `parseAtMentions`
  - [x] 2.3.3 In `apps/web-platform/server/agent-runner.ts` (around line 1347), fetch user's custom names from `team_names` table using service client with explicit `user_id` filter
  - [x] 2.3.4 Pass fetched custom names to `routeMessage`

## Phase 3: Verification

- [x] 3.1 Run at-mention-dropdown tests: `npx vitest run test/at-mention-dropdown.test.tsx`
- [x] 3.2 Run domain-router tests: `npx vitest run test/domain-router.test.ts`
- [x] 3.3 Run team-names-hook tests: `npx vitest run test/team-names-hook.test.tsx`
- [x] 3.4 Run full test suite for web-platform: `npx vitest run`
- [x] 3.5 Verify no TypeScript errors: `npx tsc --noEmit`
