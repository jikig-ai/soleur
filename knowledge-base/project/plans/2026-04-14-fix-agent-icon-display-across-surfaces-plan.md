---
title: "fix: Agent team icon not showing in command center or conversations"
type: fix
date: 2026-04-14
---

# fix: Agent Team Icon Not Showing in Command Center or Conversations

## Overview

After PR #2130 added the `LeaderAvatar` component with `customIconPath` prop support, custom icons uploaded via team settings only display on the team settings page and within chat conversation messages. The Command Center dashboard (conversation list, foundation cards, leader strip) always shows default domain icons because `customIconPath` is never passed to `LeaderAvatar` on those surfaces.

## Problem Statement

The `LeaderAvatar` component accepts an optional `customIconPath` prop. When provided, it renders the user's uploaded icon image instead of the default lucide-react domain icon. However, three surfaces use `LeaderAvatar` without wiring up `customIconPath`:

1. **`ConversationRow`** (`components/inbox/conversation-row.tsx` lines 191, 223) -- shows default icon in both mobile and desktop conversation list rows
2. **Foundation cards** (`app/(dashboard)/dashboard/page.tsx` lines 501, 615) -- shows default icon on incomplete foundation cards
3. **`LeaderStrip`** (`app/(dashboard)/dashboard/page.tsx` line 777) -- shows default icons in the "YOUR ORGANIZATION" leader strip

The `TeamNamesProvider` already wraps the entire `(dashboard)` layout, so `useTeamNames()` and its `getIconPath` method are accessible from all dashboard components. The fix is to wire `getIconPath` into the three affected surfaces.

## Root Cause

PR #2130 implemented `LeaderAvatar` with `customIconPath` and wired it on the two surfaces where it was being actively developed (team settings and chat messages), but missed the three other `LeaderAvatar` call sites that existed prior to the PR.

## Proposed Solution

Wire `customIconPath` from `useTeamNames().getIconPath()` to every `LeaderAvatar` instance across the dashboard.

### Files to Modify

1. **`components/inbox/conversation-row.tsx`**
   - Accept a `getIconPath` prop (function) from the parent
   - Pass `customIconPath={getIconPath(conversation.domain_leader)}` to both `LeaderAvatar` instances (mobile line 191, desktop line 223)

2. **`app/(dashboard)/dashboard/page.tsx`**
   - Import and call `useTeamNames()` to get `getIconPath`
   - Pass `customIconPath={getIconPath(card.leaderId)}` to foundation card `LeaderAvatar` instances (lines 501, 615)
   - Pass `getIconPath` to `LeaderStrip` component
   - In `LeaderStrip`, accept `getIconPath` prop and pass `customIconPath={getIconPath(leader.id)}` to `LeaderAvatar` (line 777)
   - Pass `getIconPath` to `ConversationRow` via prop

### Design Decision: Prop Drilling vs. Direct Hook Usage

Two approaches:

- **A: `ConversationRow` accepts `getIconPath` as a prop** -- keeps the component pure/testable, parent controls data flow
- **B: `ConversationRow` calls `useTeamNames()` directly** -- simpler, no prop changes needed, but adds a context dependency to a component that currently has none

**Recommended: Approach B** -- `ConversationRow` is already a client component within the `TeamNamesProvider` scope. Adding `useTeamNames()` directly is simpler, avoids prop drilling through the parent, and matches the pattern used in `chat/[conversationId]/page.tsx`. The `DashboardPage` can also call `useTeamNames()` directly for the foundation cards and leader strip.

## Acceptance Criteria

- [ ] Custom icons uploaded via team settings display on conversation list rows (both mobile and desktop layouts)
- [ ] Custom icons display on incomplete foundation cards in the Command Center
- [ ] Custom icons display in the "YOUR ORGANIZATION" leader strip
- [ ] Default domain icons still display when no custom icon is set
- [ ] Existing tests continue to pass (mock `useTeamNames` in `conversation-row.test.tsx` if needed)
- [ ] No new network requests introduced (icon paths come from the existing `TeamNamesProvider` context, which is already fetched once on mount)

## Test Scenarios

- Given a user has uploaded a custom icon for CTO, when they view the conversation list, then the CTO conversation rows show the custom icon instead of the default Cog icon
- Given a user has uploaded a custom icon for CLO, when they view incomplete foundation cards, then the Legal Foundations card shows the custom icon
- Given a user has uploaded custom icons for multiple leaders, when they view the leader strip, then each leader with a custom icon shows the uploaded image
- Given a user has NOT uploaded any custom icons, when they view any surface, then all leaders show their default lucide-react domain icons (no regression)
- Given a custom icon fails to load (404, network error), when displayed on any surface, then the component falls back to the default lucide-react icon (existing `onError` handler in `LeaderAvatar`)

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

## Key Files

- `apps/web-platform/components/leader-avatar.tsx` -- the component (no changes needed)
- `apps/web-platform/hooks/use-team-names.tsx` -- the hook providing `getIconPath` (no changes needed)
- `apps/web-platform/components/inbox/conversation-row.tsx` -- needs `useTeamNames` + `customIconPath` wiring
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- needs `useTeamNames` + `customIconPath` wiring on foundation cards and `LeaderStrip`
- `apps/web-platform/components/settings/team-settings.tsx` -- reference for correct wiring pattern
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- reference for correct wiring pattern
