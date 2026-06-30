# ADR-067: Adopt SWR for client-side data caching (stale-while-revalidate)

- **Status:** Accepted
- **Date:** 2026-06-23
- **Issue:** #5640 / PR #5639 (feat-tab-content-cache)
- **Lineage:** ADR-044 (workspace ownership / active-repo resolution), ADR-047 (single nav rail / per-drill portal), #5632 (provider-tree stability), migrations 075 (conversations RLS) / 059 (conversations.workspace_id).

## Context

Switching between the web-platform dashboard views (Dashboard, Inbox, Knowledge
Base, Routines) re-fetched all content from scratch on every switch, showing a
loading delay each time. Each view fetched via plain `fetch()` (or a Supabase
client query) inside `useEffect` and stored results in local React state;
navigating away unmounted the view and discarded its state, so returning forced
a full re-fetch. There was no client-side cache layer.

The single load-bearing risk in adding any client cache is **scope/invalidation**:
the dashboard is multi-tenant (per-user and per-workspace), so a cache that
survived a sign-out or a workspace switch could surface one principal's content
(inbox subjects, conversation titles, KB contents) to the next — a single-user
trust breach (`brand_survival_threshold = single-user incident`).

Alternatives considered: **TanStack Query** (heavier; more than this needs),
a **bespoke in-memory cache** (re-implements SWR's revalidation/dedup/focus
semantics), and **HTTP cache headers / ETags** (server round-trip on every
switch — does not give instant render). All rejected in the brainstorm.

## Decision

Client data fetching in the dashboard standardizes on **SWR** (Vercel's
stale-while-revalidate library) with an **in-memory, session-only** cache:

1. **In-memory only (CPO condition C1).** SWR's default `Map` cache provider —
   NO localStorage/sessionStorage/persistent provider. No user content is
   persisted at rest, so the cache adds no retention/DSAR surface.
2. **Cleared on sign-out and workspace switch (FR4 — the load-bearing
   safeguard).** `clearSwrCache(mutate)` (`lib/swr-config.ts`) matches every key
   and evicts without revalidating. It is awaited **before** navigation in
   `use-sign-out.ts` (and mirrored on `onAuthStateChange("SIGNED_OUT")`), and
   called at the `set_current_workspace_id` RPC-commit boundary in
   `org-switcher-container.tsx`. `revalidateOnReconnect` is **OFF** for content
   keys so the workspace-switch offline-park window cannot write stale
   workspace-A keys back.
3. **Stale-while-revalidate UX.** A returning view renders cached content
   instantly (FR1) and revalidates quietly in the background (FR2); the
   first-load skeleton gates on `data === undefined` (never `isValidating`) so
   background revalidation never re-shows it. An ambient gold top shimmer
   (operator-approved Option A) appears only while `isValidating && data`; there
   is **no "from cache" status indicator**.
4. **Realtime-backed surfaces drive the cache via `mutate()`** (not
   stale-then-revalidate) so live agent/conversation status is never served
   stale.

`<SWRConfig>` is mounted at a structurally stable position in
`(dashboard)/layout.tsx` (provider-tree stability, cf. #5632).

## Rollout sequencing

This ADR's decision is delivered across surfaces. PR #5639 migrates **Inbox,
Knowledge Base (tree + thread-info), Dashboard (KB tree, today, email-triage,
active-repo + orphan nudge), and the Routines list** to `useSWR`, plus the
safety foundation (provider + clear-on-sign-out/switch).

Two surfaces are **deliberately sequenced into a follow-up** to bound regression
risk — this is a refinement of the rollout, not a gap in the decision:

- **Conversations rail (`use-conversations.ts`, plan TR3).** Deferred to a
  dedicated follow-up PR (CTO ruling, 2026-06-23). The conversations rail is the
  most tenant-isolation-sensitive surface (own + workspace-shared realtime
  channels, `shouldDropForScope` equivalence to the fetch query, RLS mig 075,
  null→id scope-resolve backfill, bounded conversation-created retry). FR4's
  cache-clear safety already covers it **globally** (the clear evicts the whole
  cache regardless of which surfaces are on SWR), and TR3 is a
  performance/consistency refactor (realtime→`mutate()`), not a safety
  requirement — so deferral carries no isolation regression. The realtime→mutate
  conversion must preserve `shouldDropForScope` equivalence, the scope-resolve
  backfill, and the id-keyed create retry; the follow-up inherits the
  `user-impact-reviewer` gate (`brand_survival_threshold = single-user incident`).
- **Routines → Recent Runs pagination.** Keeps its cursor-keyset pagination
  rather than migrating to `useSWRInfinite` (secondary sub-tab; disproportionate
  for the cache benefit). Tracked alongside the TR3 follow-up.

## C4 impact

**None.** Verified against `model.c4`, `views.c4`, `spec.c4`: SWR is an
in-process npm library, not a networked third party — it adds no external actor,
no vendor edge, and no data-store. The `dashboard` (React) container is a model
leaf; an in-memory client cache is internal to it. Caching changes fetch
*timing*, not the `founder → dashboard → api → supabase` access topology.

## Consequences

- **Positive:** instant view-switching (no spinner on return); less hand-rolled
  fetch/effect/state plumbing; consistent cache-key convention
  (`swrKeys.*`) with free dedup where surfaces share an endpoint (Dashboard ↔
  Inbox both key `/api/inbox/emails`).
- **Negative / watch:** cache scope correctness is now a standing invariant —
  any new dashboard `useSWR` consumer inherits the clear-on-sign-out/switch
  guarantee only because the cache is global; a future per-subtree `<SWRConfig>`
  with its own provider would need its own clear wiring. The conversations rail
  remains on its bespoke realtime path until the TR3 follow-up.
