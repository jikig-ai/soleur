---
name: duplicate-component-mount-across-layouts
description: When a Next.js App Router nested layout adds a stateful component that the parent layout (e.g., a mobile drawer) also intends to surface, both mount it unconditionally — opening duplicate Realtime subscriptions, doubling work, and causing fan-out across every dashboard route, not just the segment the component belongs to. Caught only by multi-agent review; unit tests pass because each render site is correct in isolation.
type: best-practice
tags: [nextjs, app-router, realtime, supabase, multi-agent-review, performance, layouts]
category: best-practices
module: apps/web-platform
---

# Duplicate Component Mount Across Nested Layouts

## Problem

Plan `2026-04-29-feat-command-center-conversation-nav-plan.md` mounted
a chat-segment `ConversationsRail` from
`app/(dashboard)/dashboard/chat/layout.tsx` (the desktop sidebar).
Phase 4 separately surfaced the same rail inside the parent dashboard
mobile drawer in `app/(dashboard)/layout.tsx`, so users on mobile can
switch threads without leaving the drawer.

Both layouts mounted the rail unconditionally:

```tsx
// (dashboard)/layout.tsx (parent)
<div data-testid="conversations-rail-drawer">
  <ConversationsRail />
</div>

// (dashboard)/dashboard/chat/layout.tsx (child)
<aside data-testid="conversations-rail">
  <ConversationsRail />
</aside>
```

Each mount opens a `command-center` Realtime channel via
`useConversations`. On a `/dashboard/chat/<id>` page at the md+
breakpoint:

1. The chat-layout rail mounts → channel A.
2. The parent drawer rail mounts (because the layout is on every
   dashboard route) → channel B.
3. `useConversations` on each rail fires its own initial fetch.

Two channels per chat page is wasted server load and a doubled
WebSocket fan-out. Worse: the drawer rail mounts on `/dashboard`,
`/dashboard/kb`, `/dashboard/settings` — every dashboard route, not
just chat — even though the drawer rail is only meaningful inside the
chat segment.

Three review agents flagged this independently (perf P1,
architecture-strategist, code-quality-analyst). Unit tests passed:
each layout's render shape is correct in isolation. The duplication is
visible only when both render trees are composed.

## Why Mechanical Checks Missed It

- Component-level unit tests render one layout at a time. Each is
  correct in isolation.
- TypeScript and lint have no concept of "two render sites compose
  into one tree at runtime."
- The Realtime channel name is hard-coded inside `useConversations`,
  so a test that asserts "channel.subscribe called once" only sees one
  call per render site.
- The drawer rail is gated by `drawerOpen` from the user's
  perspective (button click), but `drawerOpen=false` does not prevent
  the JSX from being evaluated — only the visual presentation.

## Solution

Gate the parent-layout (drawer) mount on **both** `drawerOpen` AND the
segment that owns the component:

```tsx
{drawerOpen && pathname.startsWith("/dashboard/chat") && (
  <div data-testid="conversations-rail-drawer" className="md:hidden">
    <ConversationsRail />
  </div>
)}
```

Two conditions, both required:

1. `drawerOpen` — drawer is open. Otherwise the JSX is not in the
   tree → no mount → no channel.
2. `pathname.startsWith("/dashboard/chat")` — the rail is only
   meaningful in the chat segment. Mounting it on `/dashboard/kb` is
   work without payoff.

The chat-segment rail keeps `hidden md:block` so the desktop and
drawer mounts are mutually exclusive at the breakpoint level. At any
viewport, on any route, the rail mounts at most once.

## Prevention

When a plan adds a stateful component (Realtime subscription, polling
hook, expensive memo) to **both** a parent layout and a child layout
in Next.js App Router:

- Identify every render site at plan time. The plan's "Non-Goals"
  section should explicitly state "single mount" if that is the
  intent.
- Gate the parent-layout mount on both UI state (open/closed) AND
  segment ownership (`pathname.startsWith(...)`). The segment check is
  the load-bearing one — without it, the component mounts on every
  sibling route.
- Add a regression test that asserts the parent layout does NOT
  mount the component when the gating UI state is false. The test
  failure mode is "this exists but should not" — `queryByTestId(...)
  → null` is the assertion.

The general pattern: **two mount sites, one of them gated by
composition condition**. If a plan wants a component visible in two
layouts, exactly one of those layouts is the "owner" and the other
must condition its mount on UI state plus segment.

## Session Errors

(Same 10-item inventory as
`2026-04-29-supabase-removeallchannels-api-shape.md` — the
session-error inventory is shared across both learnings produced by
this run; see that file for the full list with prevention notes.)
