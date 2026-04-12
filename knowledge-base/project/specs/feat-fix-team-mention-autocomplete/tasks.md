# Tasks: fix team mention autocomplete

## Phase 1: Setup and failing tests (RED)

- [ ] 1.1 Add custom name filter tests to `at-mention-dropdown.test.tsx`
  - [ ] 1.1.1 Test: query "ole" with `customNames: { cto: "Oleg" }` returns CTO
  - [ ] 1.1.2 Test: query "pat" with `customNames: { cfo: "Patrick" }` returns CFO
  - [ ] 1.1.3 Test: custom name match is case-insensitive ("OLE" matches "Oleg")
  - [ ] 1.1.4 Test: empty customNames still matches by leader.id, leader.name, leader.title
  - [ ] 1.1.5 Test: loading state shows "Loading team names..." instead of "No matches"
- [ ] 1.2 Add server-side routing test to `domain-router.test.ts`
  - [ ] 1.2.1 Test: `routeMessage` resolves `@oleg` to CTO when customNames is provided

## Phase 2: Core implementation (GREEN)

- [ ] 2.1 Add `loading` prop to `AtMentionDropdown` component
  - [ ] 2.1.1 Add optional `loading?: boolean` to `AtMentionDropdownProps` interface
  - [ ] 2.1.2 Show "Loading team names..." when `loading && filtered.length === 0 && query`
- [ ] 2.2 Pass `loading` from `useTeamNames()` to `AtMentionDropdown` in `page.tsx`
  - [ ] 2.2.1 Destructure `loading: teamNamesLoading` from `useTeamNames()`
  - [ ] 2.2.2 Pass `loading={teamNamesLoading}` to `AtMentionDropdown`
- [ ] 2.3 Fix server-side routing to pass custom names
  - [ ] 2.3.1 Update `routeMessage` signature to accept optional `customNames`
  - [ ] 2.3.2 Pass `customNames` from `routeMessage` to `parseAtMentions`
  - [ ] 2.3.3 In `agent-runner.ts`, fetch user's custom names before calling `routeMessage`

## Phase 3: Verification

- [ ] 3.1 Run all at-mention-dropdown tests: `npx vitest run test/at-mention-dropdown.test.tsx`
- [ ] 3.2 Run domain-router tests: `npx vitest run test/domain-router.test.ts`
- [ ] 3.3 Run full test suite for web-platform: `npx vitest run`
- [ ] 3.4 Verify no TypeScript errors: `npx tsc --noEmit`
