---
title: "fix: Agent team icon not showing in command center or conversations"
type: fix
date: 2026-04-14
deepened: 2026-04-14
---

# fix: Agent Team Icon Not Showing in Command Center or Conversations

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 5
**Research sources:** Codebase analysis, existing test patterns, related learnings

### Key Improvements

1. Added concrete code snippets for each file modification with exact line references
2. Added required test mock pattern for `conversation-row.test.tsx` (without mock, tests crash with "useTeamNames must be used within TeamNamesProvider")
3. Added `DomainLeaderId` type guard for `conversation.domain_leader` to prevent runtime type errors
4. Identified potential `getIconPath` call on `null` domain_leader that would throw without a guard

### New Considerations Discovered

- `ConversationRow` conditionally renders `LeaderAvatar` only when `conversation.domain_leader` is truthy, so the `getIconPath` call is already guarded by the same conditional -- no additional null check needed
- The `LeaderStrip` component is a private function in `page.tsx`, not exported -- it needs `getIconPath` passed as a prop since it cannot call `useTeamNames()` without changing its signature (it is not a hook-using component currently, but as a function component it CAN use hooks)
- All existing `conversation-row.test.tsx` tests will fail without adding a `vi.mock("@/hooks/use-team-names")` -- the component currently does not import or use the hook

## Overview

After PR #2130 added the `LeaderAvatar` component with `customIconPath` prop support, custom icons uploaded via team settings only display on the team settings page and within chat conversation messages. The Command Center dashboard (conversation list, foundation cards, leader strip) always shows default domain icons because `customIconPath` is never passed to `LeaderAvatar` on those surfaces.

## Problem Statement

The `LeaderAvatar` component accepts an optional `customIconPath` prop. When provided, it renders the user's uploaded icon image instead of the default lucide-react domain icon. However, three surfaces use `LeaderAvatar` without wiring up `customIconPath`:

1. **`ConversationRow`** (`components/inbox/conversation-row.tsx` lines 191, 223) -- shows default icon in both mobile and desktop conversation list rows
2. **Foundation cards** (`app/(dashboard)/dashboard/page.tsx` lines 501, 615) -- shows default icon on incomplete foundation cards
3. **`LeaderStrip`** (`app/(dashboard)/dashboard/page.tsx` line 777) -- shows default icons in the "YOUR ORGANIZATION" leader strip

The `TeamNamesProvider` already wraps the entire `(dashboard)` layout, so `useTeamNames()` and its `getIconPath` method are accessible from all dashboard components. The fix is to wire `getIconPath` into the three affected surfaces.

### Research Insights

**Relevant learning (2026-04-12):** Silent RLS failures in `team_names` table return empty `{}` instead of errors. The `useTeamNames` hook already handles this gracefully -- `getIconPath` returns `null` when no icon path exists, and `LeaderAvatar` renders the default lucide icon when `customIconPath` is `null`. No additional error handling needed in the fix.

**React Context performance:** Calling `useTeamNames()` in additional child components within the same `TeamNamesProvider` scope adds zero network overhead. The provider fetches once on mount and distributes data via context. Additional consumers only re-render when the context value changes (names/icons updated). The `getIconPath` callback is memoized via `useCallback` with `[iconPaths]` dependency.

## Root Cause

PR #2130 implemented `LeaderAvatar` with `customIconPath` and wired it on the two surfaces where it was being actively developed (team settings and chat messages), but missed the three other `LeaderAvatar` call sites that existed prior to the PR.

## Proposed Solution

Wire `customIconPath` from `useTeamNames().getIconPath()` to every `LeaderAvatar` instance across the dashboard.

### Files to Modify

1. **`components/inbox/conversation-row.tsx`**
   - Import `useTeamNames` from `@/hooks/use-team-names`
   - Call `useTeamNames()` to get `getIconPath` inside `ConversationRow`
   - Pass `customIconPath={getIconPath(conversation.domain_leader)}` to both `LeaderAvatar` instances (mobile and desktop)

2. **`app/(dashboard)/dashboard/page.tsx`**
   - Import `useTeamNames` from `@/hooks/use-team-names`
   - Call `useTeamNames()` to get `getIconPath` inside `DashboardPage`
   - Pass `customIconPath={getIconPath(card.leaderId)}` to foundation card `LeaderAvatar` instances
   - Pass `getIconPath` to `LeaderStrip` component as a prop
   - In `LeaderStrip`, accept `getIconPath` prop and pass `customIconPath={getIconPath(leader.id as DomainLeaderId)}` to `LeaderAvatar`

### Design Decision: Prop Drilling vs. Direct Hook Usage

Two approaches:

- **A: `ConversationRow` accepts `getIconPath` as a prop** -- keeps the component pure/testable, parent controls data flow
- **B: `ConversationRow` calls `useTeamNames()` directly** -- simpler, no prop changes needed, but adds a context dependency to a component that currently has none

**Recommended: Approach B** -- `ConversationRow` is already a client component within the `TeamNamesProvider` scope. Adding `useTeamNames()` directly is simpler, avoids prop drilling through the parent, and matches the pattern used in `chat/[conversationId]/page.tsx`. The `DashboardPage` can also call `useTeamNames()` directly for the foundation cards and leader strip.

**Exception: `LeaderStrip`** is a private function component inside `page.tsx`. It can either: (a) call `useTeamNames()` directly (it is a valid React function component), or (b) receive `getIconPath` as a prop from `DashboardPage`. Since `DashboardPage` already calls `useTeamNames()` for foundation cards, passing it as a prop avoids a second hook call and is simpler. Recommended: prop from parent.

### Concrete Implementation Details

#### 1. `components/inbox/conversation-row.tsx`

```tsx
// Add import at top
import { useTeamNames } from "@/hooks/use-team-names";
import type { DomainLeaderId } from "@/server/domain-leaders";

// Inside ConversationRow function body, before return:
const { getIconPath } = useTeamNames();

// Mobile LeaderAvatar (line ~191) -- already inside domain_leader truthiness check:
<LeaderAvatar
  leaderId={conversation.domain_leader}
  size="md"
  customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)}
/>

// Desktop LeaderAvatar (line ~223) -- same pattern:
<LeaderAvatar
  leaderId={conversation.domain_leader}
  size="md"
  customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)}
/>
```

#### 2. `app/(dashboard)/dashboard/page.tsx`

```tsx
// Add import at top
import { useTeamNames } from "@/hooks/use-team-names";

// Inside DashboardPage function body, after other hooks:
const { getIconPath } = useTeamNames();

// Foundation cards (both empty-state and inbox-state instances):
<LeaderAvatar
  leaderId={card.leaderId}
  size="sm"
  customIconPath={getIconPath(card.leaderId)}
/>

// Pass to LeaderStrip:
<LeaderStrip onLeaderClick={handleLeaderClick} getIconPath={getIconPath} />
```

#### 3. `LeaderStrip` component (same file)

```tsx
// Update props type
function LeaderStrip({
  onLeaderClick,
  getIconPath,
}: {
  onLeaderClick: (leaderId: string) => void;
  getIconPath: (leaderId: DomainLeaderId) => string | null;
}) {
  // Inside the map:
  <LeaderAvatar
    leaderId={leader.id}
    size="sm"
    customIconPath={getIconPath(leader.id as DomainLeaderId)}
  />
}
```

### Test Mock Requirements

The `conversation-row.test.tsx` file does NOT currently mock `useTeamNames`. Once `ConversationRow` imports and calls `useTeamNames()`, all existing tests will fail with:

> Error: useTeamNames must be used within a TeamNamesProvider

**Required mock (add to `test/components/conversation-row.test.tsx`):**

```tsx
// Add after existing vi.mock("next/navigation")
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({
    names: {},
    iconPaths: {},
    nudgesDismissed: [],
    namingPromptedAt: null,
    loading: false,
    error: null,
    updateName: vi.fn(),
    updateIcon: vi.fn(),
    dismissNudge: vi.fn(),
    refetch: vi.fn(),
    getDisplayName: (id: string) => id.toUpperCase(),
    getBadgeLabel: (id: string) => id.toUpperCase().slice(0, 3),
    getIconPath: () => null,
  }),
}));
```

This matches the pattern used in `test/chat-page.test.tsx` (lines 44-50). Default `getIconPath: () => null` ensures existing tests behave as before (no custom icons = default lucide icons).

**Optional: add a test for custom icon rendering:**

```tsx
it("renders custom icon when getIconPath returns a path", () => {
  const useTeamNamesMock = await import("@/hooks/use-team-names");
  vi.mocked(useTeamNamesMock.useTeamNames).mockReturnValue({
    ...vi.mocked(useTeamNamesMock.useTeamNames)(),
    getIconPath: (id: string) => id === "cto" ? "settings/team-icons/cto.png" : null,
  });

  render(
    <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
  );

  const imgs = screen.getAllByAltText("CTO custom icon");
  expect(imgs.length).toBeGreaterThanOrEqual(1);
  expect(imgs[0].getAttribute("src")).toBe("/api/kb/content/settings/team-icons/cto.png");
});
```

## Acceptance Criteria

- [ ] Custom icons uploaded via team settings display on conversation list rows (both mobile and desktop layouts)
- [ ] Custom icons display on incomplete foundation cards in the Command Center
- [ ] Custom icons display in the "YOUR ORGANIZATION" leader strip
- [ ] Default domain icons still display when no custom icon is set
- [ ] Existing tests continue to pass (mock `useTeamNames` in `conversation-row.test.tsx`)
- [ ] No new network requests introduced (icon paths come from the existing `TeamNamesProvider` context, which is already fetched once on mount)

## Test Scenarios

- Given a user has uploaded a custom icon for CTO, when they view the conversation list, then the CTO conversation rows show the custom icon instead of the default Cog icon
- Given a user has uploaded a custom icon for CLO, when they view incomplete foundation cards, then the Legal Foundations card shows the custom icon
- Given a user has uploaded custom icons for multiple leaders, when they view the leader strip, then each leader with a custom icon shows the uploaded image
- Given a user has NOT uploaded any custom icons, when they view any surface, then all leaders show their default lucide-react domain icons (no regression)
- Given a custom icon fails to load (404, network error), when displayed on any surface, then the component falls back to the default lucide-react icon (existing `onError` handler in `LeaderAvatar`)

### Edge Cases

- **`domain_leader` is null:** `ConversationRow` already guards `LeaderAvatar` rendering with `{conversation.domain_leader && ...}`, so `getIconPath` is never called with a null value
- **`getIconPath` returns null:** `LeaderAvatar` handles `customIconPath={null}` correctly -- renders the default lucide icon (tested in `leader-avatar.test.tsx` line 80)
- **Image load failure:** `LeaderAvatar` has `onError={() => setImgError(true)}` which triggers fallback to the default icon (tested in `leader-avatar.test.tsx` line 70)
- **Loading race:** `useTeamNames` returns `loading: true` initially. During loading, `getIconPath` returns `null` (the `iconPaths` state is `{}`), so default icons show until data loads. Once loaded, a re-render triggers and custom icons appear. This is acceptable behavior -- brief flash of default icons on page load.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** This is a straightforward prop-wiring bug fix with no architectural implications. The data layer (`TeamNamesProvider`) and presentation layer (`LeaderAvatar`) are already correctly implemented -- only the connection between them is missing on three surfaces. No new API calls, no schema changes, no performance concerns. The `useTeamNames()` hook is already loaded in the dashboard layout context; consuming it in additional child components adds zero overhead.

### Product/UX Gate

**Tier:** NONE
**Decision:** No user-facing impact beyond fixing the already-designed feature to work as intended. The icons, upload flow, and rendering behavior are already implemented and reviewed in PR #2130.

## References

- Related issue: #2161
- Implementation PR: #2130 (feat(dashboard): agent identity badges and team icon customization)
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-13-dashboard-agent-identity-brainstorm.md`
- Learning: `knowledge-base/project/learnings/2026-04-12-silent-rls-failures-in-team-names.md`
- Learning: `knowledge-base/project/learnings/2026-04-13-vitest-mock-sharing-and-issue-batching.md` (mock pattern reference)

## Key Files

- `apps/web-platform/components/leader-avatar.tsx` -- the component (no changes needed)
- `apps/web-platform/hooks/use-team-names.tsx` -- the hook providing `getIconPath` (no changes needed)
- `apps/web-platform/components/inbox/conversation-row.tsx` -- needs `useTeamNames` + `customIconPath` wiring
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- needs `useTeamNames` + `customIconPath` wiring on foundation cards and `LeaderStrip`
- `apps/web-platform/test/components/conversation-row.test.tsx` -- needs `vi.mock("@/hooks/use-team-names")` added
- `apps/web-platform/components/settings/team-settings.tsx` -- reference for correct wiring pattern
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- reference for correct wiring pattern
- `apps/web-platform/test/chat-page.test.tsx` -- reference for `useTeamNames` mock pattern
