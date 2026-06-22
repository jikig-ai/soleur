---
feature: tab-content-cache
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-22-tab-content-cache-brainstorm.md
pr: 5639
---

# Feature: Cache tab content for instant view switching

## Problem Statement

Switching between the web-platform dashboard views (Dashboard, Inbox, Knowledge
Base, Routines) re-fetches all content from scratch every time, showing a loading
delay on every switch. Each view fetches with plain `fetch()` in `useEffect` and
stores results in local React state; navigating away unmounts the view and
discards its state, so returning forces a full re-fetch. There is no client-side
cache layer today.

## Goals

- Switching back to a previously visited view shows its content **instantly**
  (no spinner) from an in-memory cache.
- Cached content is **revalidated quietly in the background** on remount and
  updated in place if it changed (stale-while-revalidate).
- Cover all main dashboard views (Dashboard, Inbox, Knowledge Base, Routines) in
  one PR.
- The cache is correctly scoped and cleared on workspace switch / sign-out so one
  user never sees another user's cached content.

## Non-Goals

- Persisting content to localStorage / sessionStorage / IndexedDB (in-memory only).
- Offline support or service-worker caching.
- Server-side HTTP cache headers / ETags.
- Adopting TanStack Query or building a bespoke cache layer.
- Any change to the visual design of existing views.

## Functional Requirements

### FR1: Instant cached render on view switch
Returning to a previously loaded view renders its last-known content immediately,
without a loading spinner.

### FR2: Quiet background revalidation
On remount, the view revalidates its data in the background and updates in place
only if the data changed. No blocking spinner during revalidation.

### FR3: All main views covered
Dashboard, Inbox, Knowledge Base, and Routines fetch hooks all use the shared
caching layer.

### FR4: Cache isolation and invalidation
The in-memory cache is cleared (or scoped) on workspace switch and on sign-out so
cached content cannot leak across users or workspaces.

### FR5: Filter/param-aware caching
Views with filters or query params (e.g. Inbox `?status=archived`, conversation
filters, KB tree) cache per distinct filter state without collisions.

## Technical Requirements

### TR1: Adopt SWR
Add the `swr` dependency to `apps/web-platform`. Use SWR's in-memory cache and
default stale-while-revalidate behavior.

### TR2: Migrate fetch hooks to `useSWR`
Replace the `fetch` + `useEffect` + `useState` pattern in the affected hooks
(`hooks/use-conversations.ts`, `components/inbox/inbox-surface.tsx`,
`hooks/use-kb-layout-state.tsx`, `app/(dashboard)/dashboard/page.tsx`,
`components/routines/routines-surface.tsx`) with `useSWR(key, fetcher)`.

### TR3: Realtime integration for conversations
Wire the existing Supabase realtime INSERT/UPDATE subscription in
`use-conversations.ts` into SWR's `mutate()` for the conversations cache key
instead of `setState`.

### TR4: Cache-key convention
Define a consistent cache-key convention that encodes the endpoint plus active
filters/params (FR5), and a documented strategy for clearing keys on workspace
switch / sign-out (FR4).

### TR5: No content persisted to disk
Use SWR's default in-memory provider only; do not configure any localStorage/
sessionStorage cache provider.

## Open Questions (carry-forward to plan)

1. SWR `mutate()` strategy for realtime conversation events (optimistic vs revalidate).
2. Whether to show a subtle non-blocking "refreshing" indicator during revalidation.
3. `revalidateOnFocus` tuning per view.
4. Exact cache-clear hook on workspace switch / sign-out.

## User-Brand Impact

- **Artifact:** the web-platform dashboard client-side SWR cache over the
  Dashboard / Inbox / KB / Routines fetch hooks.
- **Vector:** incorrect cache scoping/invalidation could surface one user's
  content to another or show stale security-relevant state — a single-user trust
  breach.
- **Threshold:** single-user incident.

In-memory-only caching removes the data-at-rest vector; FR4/TR4 (scoping +
invalidation) are the load-bearing safeguards and must be verified before ship.
