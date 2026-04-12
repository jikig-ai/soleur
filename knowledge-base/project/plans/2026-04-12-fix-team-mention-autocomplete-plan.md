---
title: "fix: team mention autocomplete does not find custom-named leaders"
type: fix
date: 2026-04-12
---

# fix: team mention autocomplete does not find custom-named leaders

## Overview

When domain leaders have custom names configured in Settings > Team (e.g., CTO = "Oleg", CFO = "Patrick"), typing `@ole` in the conversation input shows "No matches" instead of suggesting the CTO. The `@mention` autocomplete dropdown does not search custom names.

## Problem Statement

The `AtMentionDropdown` component accepts a `customNames` prop and includes custom name matching in its filter logic. However, investigation reveals **two bugs** that together cause the reported behavior:

### Bug 1: Client-side -- `customNames` is not reaching the dropdown (primary report)

The data flow is:

1. `TeamNamesProvider` (in `app/(dashboard)/layout.tsx`) fetches from `GET /api/team-names`
2. `useTeamNames()` returns `{ names, ... }` with the fetched custom names map
3. `page.tsx` destructures `{ names: customNames }` and passes it to `<AtMentionDropdown customNames={customNames} />`

The filter logic in `at-mention-dropdown.tsx:26-37` is correct:

```typescript
const custom = customNames[leader.id]?.toLowerCase() ?? "";
return (
  leader.id.includes(q) ||
  leader.name.toLowerCase().includes(q) ||
  leader.title.toLowerCase().includes(q) ||
  custom.includes(q)
);
```

**Root cause candidates:**

- **Silent fetch failure:** If `GET /api/team-names` returns a non-200 (auth error, server error), the catch handler (`use-team-names.tsx:46-48`) logs to console but `names` stays as `{}`. The dropdown receives an empty `customNames` and cannot match custom names. No error indicator is shown to the user.
- **Loading race condition:** `loading` starts as `true` and no UI blocks the dropdown from rendering with empty names while the fetch is in-flight. If the user types `@` before the fetch resolves, `customNames` would be `{}`.
- **Provider context boundary:** Verify the `TeamNamesProvider` wraps the chat page correctly (it does -- confirmed in `layout.tsx:90`).

**Most likely cause:** Silent fetch failure. The provider's error handling swallows HTTP errors and falls back to empty names with no user feedback.

### Bug 2: Server-side -- `parseAtMentions` not receiving custom names

Even after fixing the client-side autocomplete (which inserts `@cto` -- the role ID), the server-side `parseAtMentions` has a parallel gap:

- `routeMessage()` in `domain-router.ts:91` calls `parseAtMentions(message)` **without** `customNames`
- `agent-runner.ts:1350` calls `routeMessage(content, apiKey, conversationContext)` **without** `customNames`

This means if a user manually types `@oleg` (instead of selecting from the autocomplete), the server won't resolve it to the CTO. The `parseAtMentions` function already supports `customNames` as an optional second parameter (with tests at `domain-router.test.ts:49-81`), but the callers don't provide it.

## Proposed Solution

### Part A: Fix the client-side autocomplete (primary fix)

1. **Add error resilience to `TeamNamesProvider` fetch:**
   - Add an `error` state to expose fetch failures
   - Add a retry mechanism (or at minimum expose the error so the chat page can show a subtle indicator)

2. **Add `loading` guard to `AtMentionDropdown`:**
   - Accept a `loading` prop (optional, defaults to `false`)
   - When `loading` is `true` and `query` is non-empty, show "Loading..." instead of "No matches"
   - The page already has access to `loading` from `useTeamNames()` -- pass it through

3. **Add test coverage for custom name filtering in `at-mention-dropdown.test.tsx`:**
   - Test: with `customNames={ cto: "Oleg" }`, query `"ole"` returns CTO
   - Test: with `customNames={ cfo: "Patrick" }`, query `"pat"` returns CFO
   - Test: custom name match is case-insensitive
   - Test: empty `customNames` falls back to default matching (regression guard)

### Part B: Fix the server-side routing

4. **Fetch custom names in `agent-runner.ts` and pass to `routeMessage`:**
   - Before calling `routeMessage`, fetch the user's custom names from the `team_names` table
   - Update `routeMessage` signature to accept `customNames`
   - Pass `customNames` through to `parseAtMentions`

5. **Add integration test for custom-name server routing**

### Part C: Improve observability

6. **Log when `customNames` is empty at dropdown render time** (dev-only) to make debugging easier

## Technical Considerations

- **Performance:** Fetching custom names in the agent-runner adds one Supabase query per message. The query is trivial (indexed by `user_id`) and can be cached per-session.
- **Security:** Custom names are user-owned data. No cross-user leakage risk since the fetch is scoped to the authenticated user.
- **Backward compatibility:** All changes are additive. The `customNames` parameter remains optional in `parseAtMentions`.

## Acceptance Criteria

- [ ] Typing `@ole` in the chat input when CTO is named "Oleg" shows the CTO in the autocomplete dropdown (`at-mention-dropdown.tsx`)
- [ ] Typing `@pat` when CFO is named "Patrick" shows the CFO in the autocomplete dropdown
- [ ] Custom name filtering is case-insensitive (e.g., `@OLE` matches "Oleg")
- [ ] When the team names API fetch fails, the dropdown still works with default names (no crash, graceful fallback)
- [ ] When the team names API fetch is still loading and user types `@ole`, the dropdown does not show "No matches" (shows a loading state or waits)
- [ ] Server-side `parseAtMentions` receives custom names when routing messages (agent-runner passes them through)
- [ ] Manually typed `@oleg` in a message resolves to the CTO on the server side
- [ ] All existing at-mention-dropdown tests continue to pass

## Test Scenarios

- Given CTO is named "Oleg" in Settings > Team, when typing "@ole" in the chat input, then the autocomplete dropdown shows CTO as a match
- Given CFO is named "Patrick" in Settings > Team, when typing "@PAT" in the chat input, then the autocomplete dropdown shows CFO as a match (case-insensitive)
- Given no custom names are configured, when typing "@cto" in the chat input, then the autocomplete shows CTO (default behavior preserved)
- Given the team names API returns 500, when typing "@ole" in the chat input, then the autocomplete shows "No matches" (not a crash) and default name matching still works
- Given the team names API is slow to respond, when typing "@" before it resolves, then the dropdown shows all 8 leaders with default names (or a loading indicator)
- Given CTO is named "Oleg" and the user manually types "@oleg" in a message, when the message is sent, then the server routes it to the CTO

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal bug fix for existing UI and server routing.

## MVP

### Part A: Client-side fix

#### `apps/web-platform/test/at-mention-dropdown.test.tsx` (new tests)

```typescript
it("filters by custom name -- @ole matches CTO named Oleg", () => {
  setup({ query: "ole", customNames: { cto: "Oleg" } });
  const options = screen.getAllByRole("option");
  expect(options).toHaveLength(1);
  expect(screen.getByText("1 match")).toBeInTheDocument();
});

it("custom name match is case-insensitive", () => {
  setup({ query: "OLE", customNames: { cto: "Oleg" } });
  const options = screen.getAllByRole("option");
  expect(options).toHaveLength(1);
});

it("shows loading state when names are loading and query targets custom name", () => {
  setup({ query: "ole", loading: true });
  // Should not show "No matches" -- should show loading or all leaders
});
```

#### `apps/web-platform/components/chat/at-mention-dropdown.tsx` (changes)

- Add optional `loading?: boolean` prop
- When `loading` is `true` and `filtered.length === 0` and `query` is non-empty, show "Loading team names..." instead of "No matches"

#### `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (changes)

- Pass `loading` from `useTeamNames()` to `AtMentionDropdown`:

```typescript
const { names: customNames, getDisplayName, loading: teamNamesLoading } = useTeamNames();
// ...
<AtMentionDropdown
  query={atQuery}
  visible={atVisible}
  customNames={customNames}
  loading={teamNamesLoading}
  onSelect={...}
  onDismiss={...}
/>
```

### Part B: Server-side fix

#### `apps/web-platform/server/domain-router.ts` (changes)

- Update `routeMessage` to accept optional `customNames` parameter
- Pass it through to `parseAtMentions`

#### `apps/web-platform/server/agent-runner.ts` (changes)

- Before calling `routeMessage`, query `team_names` table for the user
- Pass custom names to `routeMessage`

## References

- `apps/web-platform/components/chat/at-mention-dropdown.tsx` -- autocomplete dropdown component
- `apps/web-platform/hooks/use-team-names.tsx` -- TeamNamesProvider and useTeamNames hook
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- chat page integrating both
- `apps/web-platform/server/domain-router.ts` -- server-side mention parsing
- `apps/web-platform/server/agent-runner.ts` -- server-side message routing
- `apps/web-platform/app/api/team-names/route.ts` -- API route for team names CRUD
- `apps/web-platform/test/at-mention-dropdown.test.tsx` -- existing dropdown tests (no custom name coverage)
- `apps/web-platform/test/domain-router.test.ts` -- server-side parsing tests (custom name coverage exists)
