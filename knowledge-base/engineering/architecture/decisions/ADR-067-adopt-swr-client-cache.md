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

## Amendment (2026-07-09): Router-Cache `staleTimes` (the RSC-shell half)

**Status:** Accepted. **Issue/PR:** feat-one-shot-router-cache-staletimes-tab-switch.
**Threshold:** `single-user incident` (inherited).

### Context

The SWR cache above made the dashboard tabs' *data* fetches instant, but users
still saw a `loading.tsx` skeleton flash on returning to a previously-visited
tab. The residual cause is a **second, independent client cache**: the Next.js
App Router **Router Cache**, which holds each route segment's server-rendered
**RSC shell**. Next.js 15 defaults `staleTimes.dynamic = 0` (it was `30` in
Next 14), so the Router Cache discards a dynamic route's RSC the instant you
navigate away — every return refetches the RSC from the server and re-triggers
the route-segment Suspense skeleton. SWR does not, and structurally cannot,
cover this (it caches `fetch` results, not the RSC shell).

### Decision

The tab-switch story now has **two cooperating client caches**:

| Layer | Mechanism | Wiped/cleared at a principal boundary by |
|---|---|---|
| **Data** | SWR in-memory cache | `clearSwrCache(mutate)` on sign-out + workspace-switch (FR4) |
| **RSC shell** | App Router Router Cache | **hard navigation** (`window.location.assign` / full document load) — the ONLY Router-Cache wipe |

Enable Router-Cache reuse with `experimental.staleTimes = { dynamic: 30 }` in
`apps/web-platform/next.config.ts` (`static` left at its Next 15 default 300 s —
irrelevant to the dynamic tab bug). `withSentryConfig` preserves the key
(Next 15.5.18).

### The load-bearing isolation invariant

A **Router-Cache hit serves an RSC payload from client memory with NO server
round-trip**, so `middleware.ts` — the auth gate, the #4307 revocation gate, the
T&C-consent gate, and billing — does **not** run for cached segments. A warm
cache therefore defers not just transition-time isolation but the **continuous,
per-request** authorization gates by up to `dynamic` seconds. There is no public
API to selectively evict the App Router Router Cache (`router.refresh()` busts
only the *current* route); a **hard navigation (full document load) is the only
full wipe**. The invariant is thus:

> The Router Cache is wiped by a hard navigation at **every** navigation that
> crosses an authenticated-principal boundary, in **any** tab.

The complete, enumerated boundary set (not "three transitions"):

- **Principal-ENTRY:** OTP sign-in success (`components/auth/login-form.tsx` —
  the *default* login UI verifies client-side, a **soft** nav, so this was a live
  cross-user vector), and the onboarding funnel's terminal hops into
  `/dashboard`/`/dashboard/kb` (`setup-key`, `connect-repo` ×5, `signup`,
  `accept-terms`). OAuth/magic-link (`(auth)/callback/route.ts`) and dev-signin
  already hard-load — no change.
- **Principal-LEAVING:** sign-out button + the sibling-tab `SIGNED_OUT` listener
  (`components/auth/use-sign-out.ts`, GAP C/D), account deletion
  (`components/settings/delete-account-dialog.tsx`, GAP F), and the in-session
  401/**302** session-revocation bounces (`dashboard/page.tsx`,
  `hooks/use-kb-layout-state.tsx`, `kb/[...path]/page.tsx`, GAP F).
- **Workspace switch:** `components/dashboard/org-switcher-container.tsx` (already
  hard-navs — the precedent) and **invite-accept** (`invite/[token]/invite-actions.tsx`
  `handleAccept` — `accept-invite` calls `set_current_workspace_id`, so it crosses
  a workspace boundary and was converted to a hard nav).

**Two revocation sub-cases (distinct backstops):**

- **jti session-revocation** (`revoked=true`): every mount-time SWR data fetch
  hits `/api/*` → middleware → the #4307 gate → `clearSessionAndRedirect`
  **302→/login**. Fast backstop, well inside 30 s — via **middleware, not RLS**.
  The 401 handlers (GAP F) must detect this **302** (`fetch` follows it to 200
  HTML, so a `status===401`-only guard silently never fires); they also key on
  `res.redirected && new URL(res.url).pathname === "/login"`.
- **workspace-membership removal** (session still valid): does **not** 401/302.

### The data backstop is `resolveActiveWorkspace()`, NOT RLS

For the cached tabs whose data routes use the RLS-**bypassing**
`createServiceClient()` (`/api/dashboard/foundation-status`, `/api/kb/tree`),
workspace scoping is enforced by **`resolveActiveWorkspace()`'s membership probe**
(`server/workspace-resolver.ts` — explicit `workspace_members` query + solo
shortcut), which returns own/empty scope after removal at **HTTP 200** (empty ≠
leak). RLS `is_workspace_member` (migrations 053/059/075) backstops only the
**session-client** routes; `kb_files`/`kb_chunks` are owner/shared-keyed.

**Backstop enumeration (verified 2026-07-09):** all 9 `force-dynamic` tabs
(inbox, routines, workstream, audit, audit/github, releases, settings/privacy,
settings/scope-grants, inbox/email) use the **cookie-scoped `createClient()`**
(RLS session client) with belt-and-suspenders `.eq(user_id/founder_id/workspace_id)`
filters — own/tenant-scoped, no cross-principal exposure. `/api/inbox/emails`
uses the session client ("NEVER `createServiceClient` here"). The two
service-client SWR routes route through the membership probe (above). The **one
exception with no probe/RLS backstop** is `admin/analytics/page.tsx`, which bakes
**all-tenant** data (every user's email + all conversations) into a cacheable RSC
via `createServiceClient()`, gated only by an `ADMIN_USER_IDS` **env** check —
**GAP H** (a mount-time `router.refresh()` that re-runs the server authz on warm
return) is its guard.

### Router Cache ≠ bfcache

A hard navigation wipes the in-memory Router Cache but **not** the browser's
back/forward cache (bfcache) — a whole-document snapshot that could restore a
rendered authenticated page after sign-out + Back. `force-dynamic` tabs already
emit `no-store`; **GAP G** sets `Cache-Control: no-store` on authenticated
(non-`PUBLIC_PATHS`) **document** responses in **`middleware.ts`** (route groups
are URL-stripped, so the global `security-headers.ts` `source:"/(.*)"` matcher
cannot select authenticated routes; middleware has the auth + per-path signal),
scoped to `Sec-Fetch-Dest: document` so API/RSC caching, the client Router Cache,
and public-page bfcache are untouched.

### Bounded, accepted residual

RSC-only `force-dynamic` tabs with no mount-time SWR fetch bake **own**
user-scoped rows, so a stale shell there is the user's own data (no
cross-principal exposure), bounded to ≤ `dynamic` (30) s. Session hijack is
unchanged (the JWT is already valid ~1 h). `dynamic: 30` is the deliberate
UX-vs-revocation-latency bound (the descope lever is a smaller `dynamic`).

### C4 impact

**None** — verified against `model.c4`, `views.c4`, `spec.c4` (same basis this
ADR recorded for SWR): `staleTimes` is an in-process Next.js flag, the Router
Cache is in-memory in the existing `dashboard` React container leaf, no external
actor / vendor / data-store / access-relationship changes. Caching changes fetch
*timing*; the boundary-wipe invariant keeps per-principal isolation identical. No
`.c4` edit.
