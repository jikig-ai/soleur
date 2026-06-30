# Brainstorm: Cache tab content for instant view switching

**Date:** 2026-06-22
**Branch:** feat-tab-content-cache
**PR:** #5639 (draft)
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

## What We're Building

A client-side caching layer for the web-platform dashboard so that switching
between the main views (Dashboard, Inbox, Knowledge Base, Routines) is **instant**
instead of triggering a full re-fetch every time. Adopt **SWR** (Vercel's
stale-while-revalidate library) and migrate the manual
`fetch` + `useEffect` + `useState` hooks to `useSWR`, in **one PR covering all
main views**.

### Behavior decided with operator
- **Freshness:** *instant, then refresh quietly* — show cached content on
  remount with no spinner, revalidate in the background, update in place if the
  data changed (classic stale-while-revalidate, SWR's default).
- **Persistence:** *session/in-memory only* — cache lives in memory while the app
  is open; a full browser reload starts fresh. **No content is written to disk**
  (no localStorage/sessionStorage of content).

## Why This Approach (SWR)

Root cause confirmed by repo research:
- The dashboard views are separate Next.js App Router routes, not in-place tabs.
- Every view fetches with plain `fetch()` in `useEffect` and holds the result in
  local `useState` (`hooks/use-conversations.ts:314`,
  `components/inbox/inbox-surface.tsx:61`, `hooks/use-kb-layout-state.tsx:113`,
  `app/(dashboard)/dashboard/page.tsx:143-284`).
- Switching away **unmounts** the view → local state is discarded → switching
  back **remounts** and re-fetches unconditionally.
- There is **no client-side cache layer** today (no React Query, SWR, Zustand,
  or in-memory store; `lib/safe-session.ts` is used only for sidebar/banner flags,
  not content).

SWR's defaults map 1:1 onto the chosen behavior: in-memory cache keyed by request,
instant return on remount, background revalidation, request dedup, session-only
(cleared on hard reload). It is the smallest, lowest-maintenance fix and can be
adopted hook-by-hook. TanStack Query (more powerful, heavier) and a hand-rolled
in-memory cache (no dep, but reinvents dedup/revalidation/eviction) were the
considered alternatives.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Library | SWR (`swr`) | Defaults == chosen UX; smallest footprint; Next.js-native |
| Freshness model | Stale-while-revalidate | Instant perceived load + quiet background refresh |
| Persistence | In-memory / session only | No content at rest → neutralizes PII-at-rest vector |
| Scope | All main views in one PR | Operator chose full coverage over incremental slice |
| Visual design | No new UI surface | Plumbing change; screens render identically (see Open Questions for optional refresh indicator) |

## Non-Goals

- Persisting content to localStorage/IndexedDB (explicitly excluded — in-memory only).
- Offline support / service-worker caching.
- Server-side HTTP cache headers / ETags (separate, server-router concern).
- Adopting TanStack Query or building a bespoke cache layer.
- Changing the visual design of any view.

## Open Questions

1. **Realtime merge for conversations.** `use-conversations.ts` subscribes to
   Supabase realtime (INSERT/UPDATE) and currently `setState`s. Under SWR these
   events must drive `mutate()` on the conversations cache key instead. Confirm
   the cache-key shape and the mutate strategy (optimistic vs. revalidate) at
   plan time.
2. **Background-refresh affordance.** Should there be a subtle, non-blocking
   "refreshing…" indicator while SWR revalidates, or is silent in-place update
   enough? (Only possible new visible element; otherwise no UI change.)
3. **Cache-key strategy for filtered/paginated views.** Inbox (`?status=archived`),
   conversation filters, KB tree — keys must encode the active filter/param so
   different filter states don't collide or thrash.
4. **`revalidateOnFocus` default.** SWR also revalidates on window focus by
   default; decide whether to keep (fresher) or tune (fewer calls) per view.
5. **Auth/workspace switch invalidation.** On workspace switch or sign-out the
   in-memory cache must be cleared so one user never sees another's cached
   content (single-user-incident threshold). Confirm the clear hook at plan time.

## User-Brand Impact

- **Artifact:** the web-platform dashboard client-side data cache (SWR layer over
  Dashboard / Inbox / KB / Routines fetch hooks).
- **Vector:** a cache that is not scoped/cleared correctly on workspace switch or
  sign-out could surface one user's content to another, or show stale
  security-relevant state — a single-user trust breach.
- **Threshold:** single-user incident.

The in-memory-only decision removes the data-at-rest exposure vector entirely; the
residual risk is cache **scoping/invalidation** (Open Question 5), which the plan
must address as a first-class requirement.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Tagged user-brand-critical (auto, per #5175); triad framing applied. The
substantive cross-cutting assessment for this scope is engineering + product +
legal-of-data-handling, synthesized below from the architecture research rather
than a full leader fan-out (well-understood frontend caching change, no external
vendor/ToS/credential surface).

### Engineering (CTO)

**Summary:** Net simplification — SWR replaces hand-rolled fetch/effect/state
plumbing with a single proven primitive and removes the unconditional-refetch-on-
mount anti-pattern. Main engineering risk is wiring Supabase realtime into SWR's
`mutate()` and getting per-filter cache keys right; both are well-trodden.

### Product (CPO)

**Summary:** Directly improves perceived performance on the most-used navigation
path with no visual change to learn. Scope is all-views-at-once per operator;
incremental rollout was offered and declined.

### Legal / Data-handling (CLO)

**Summary:** In-memory/session-only caching keeps no user content at rest, so no
new retention/DSAR surface is created. The only data-handling requirement is
correct cache invalidation on workspace switch / sign-out (Open Question 5) to
preserve single-user isolation.
