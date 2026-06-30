---
date: 2026-06-23
tags: [swr, testing, web-platform, caching, vitest]
category: best-practices
pr: 5639
adr: ADR-067
---

# Adopting SWR in web-platform: test-isolation + shared-key discipline

Lessons from migrating the dashboard data layer (Inbox / KB / Dashboard /
Routines) from `fetch`+`useEffect`+`useState` to `useSWR` (ADR-067, PR #5639).

## SWR's default cache is a module singleton — isolate it in tests

SWR's default cache (no `provider`) is a process-global `Map`. In the shared
happy-dom vitest worker, cached entries leak **across test cases and across
files**, producing order-dependent flakes: a test that primes `kbTree()` with a
non-empty tree makes a later "empty tree" test see stale data; a "shows loading
skeleton" test sees cached data and never shows the skeleton.

Fix: wrap every render of a migrated component/hook in a **fresh per-render
cache**:

```tsx
<SWRConfig value={{ provider: () => new Map(), dedupingInterval: 0, shouldRetryOnError: false }}>
```

`test/helpers/swr-wrapper.tsx` (`SwrTestProvider`) packages this. `rerender`
preserves the same provider instance (so within-test cache continuity holds);
each fresh `render` gets a clean Map. `dedupingInterval: 0` + `shouldRetryOnError:
false` keep fetch-count and explicit-Retry assertions deterministic (SWR's
built-in error backoff would otherwise re-fire the test-controlled fetcher on
its own schedule). For shared test harnesses that already wrap many renders
(e.g. `RailSlotHarness`), add the `SWRConfig` there once — it fixes every
consumer centrally.

## The blast radius of a migration is "every test that renders the real thing"

Two sweep classes bit during this migration:

1. **New hook call inside a shared component → sibling mocks need the method.**
   Adding `supabase.auth.onAuthStateChange(...)` inside `useSignOut` (mounted in
   the dashboard layout) broke **every** test that renders the real
   `DashboardLayout` with a supabase mock lacking `onAuthStateChange`
   (`is not a function`). Grep `git grep -l '(dashboard)/layout\|useSignOut' test/`
   and add the stub to each in the same commit.
2. **Migrated component rendered without a provider → cache leak.** Grep for
   every `render(<MigratedThing` and wrap it. Topical name-filtering misses
   page-level renderers (e.g. `command-center.test.tsx` renders `DashboardPage`).

## Shared cache keys must have ONE value shape

`swrKeys.inboxEmails("active")` is shared by Inbox + Dashboard with the SAME
fetcher (`fetchInboxItems`) → free dedup, correct. But the dashboard reads the
KB tree as `{tree}` while the KB tab reads `{tree,lastSync,needsReconnect}` —
sharing `swrKeys.kbTree()` would cross-contaminate the cache (whichever fetcher
ran last wins). Give the tree-only consumer a **distinct key**
(`["/api/kb/tree","dashboard"]`). Rule: same key ⇒ same value shape + same
error-mapping, or use a disambiguated key.

## Gotchas

- **SWR v2 passes an array key to the fetcher as a SINGLE argument** — destructure
  `async ([, status]) => ...`, not `(prefix, status)`.
- **`clearSwrCache` clears `.data`, not key strings.** `mutate(() => true,
  undefined, { revalidate: false })` nulls every entry's data but the serialized
  key string lingers in the Map — assert leak-absence on cached **data**, never
  on `cache.keys()`.
- **GAP F:** the first-load skeleton must gate on `data === undefined` (+ no
  error), NEVER `isValidating` — else a background revalidation of a warm cache
  re-shows the skeleton. A 401-redirect path should hold `loading` true (a typed
  error kind) so it doesn't flash the empty/error state on the way to `/login`.
- **Cache-clear ordering is the load-bearing safety property** (multi-tenant):
  `await clearSwrCache(mutate)` BEFORE `router.push` on sign-out, and at the
  workspace-switch RPC-commit boundary, with `revalidateOnReconnect: false` for
  content keys. See [[ADR-067]].

## Sequencing high-isolation surfaces

The conversations rail (`use-conversations.ts`) was deferred to a follow-up
(#5644) by CTO ruling: FR4 cache-clear already covers it globally (the clear
evicts the whole cache regardless of which surfaces are on SWR), so a
realtime→`mutate()` rewrite on the most tenant-isolation-sensitive surface is a
performance refactor, not a safety fix — sequence it into its own PR to bound
regression risk.
