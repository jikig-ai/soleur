---
category: ui-bugs
module: web-platform/dashboard
tags: [supabase, e2e, loading-state, onboarding]
severity: medium
---

# Learning: Dashboard onboarding state should not depend on conversation loading

## Problem

Three E2E tests for the command center state consistently failed in CI:

- `shows Command Center when all 4 foundation files exist`
- `suggested prompts render in command center`
- `suggested prompt click navigates to chat`

All failed at `expect(page.getByText("Your organization is ready.")).toBeVisible({ timeout: 15_000 })`.
The page showed the inbox loading skeleton instead of the command center empty state.

The root cause was that the dashboard page's rendering logic coupled the onboarding
state (first-run / foundations / command center) to the `loading` flag from
`useConversations`. The `useConversations` hook's `loading` state depends on
Supabase client initialisation completing (navigator locks, session recovery,
`auth.getUser()` API call). In CI's mock environment, this initialisation could
hang indefinitely because the Supabase browser client's internal lock acquisition
and session recovery interact poorly with mock HTTP servers that return 200 instead
of 101 for WebSocket upgrade requests.

## Solution

Removed the `!loading` dependency from the dashboard page's onboarding state
conditions. The onboarding state (first-run, foundations, command center) is
determined by the KB tree, not by conversation loading. Specifically:

1. **First-run state**: Changed from `!kbError && !visionExists && !loading && conversations.length === 0`
   to `!kbError && !visionExists && conversations.length === 0`

2. **Command center empty state**: Changed from `!loading && !error && conversations.length === 0`
   to `conversations.length === 0 && !hasActiveFilter && !error`

When conversations eventually load and are non-empty, React re-renders and the
page transitions to the inbox view. This is correct behavior -- users should see
meaningful content immediately rather than a loading skeleton.

## Key Insight

Page rendering state machines should separate "what state am I in" from "is data
still loading". The onboarding state (determined by KB tree presence) and the
conversation loading state are independent concerns. Coupling them creates fragile
conditions where external service initialisation (Supabase client locks, WebSocket
connections) can block the entire page from rendering meaningful content.

In E2E tests, mock servers that return HTTP 200 for WebSocket upgrade requests
(instead of 101 Switching Protocols) can cause Supabase Realtime clients to
behave unpredictably, but the real fix is ensuring page rendering does not depend
on these connections completing.

## Tags

category: ui-bugs
module: web-platform/dashboard
