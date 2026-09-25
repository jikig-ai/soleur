---
title: "ADR-253: Bounded-freshness positive-verdict caching + middleware-verified identity header for per-request auth cost"
status: Accepted
date: 2026-09-25
supersedes: []
amends: []
tags: [performance, middleware, auth, supabase, caching]
---

# ADR-253: Bounded-freshness positive-verdict caching + middleware-verified identity header for per-request auth cost

## Status

Accepted — 2026-09-25. Delivers the plan
`knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md`;
closes #5531, #5532, #5533, #5654.

## Context

Every authenticated request to `app.soleur.ai` — the HTML document *and* every
`/api/*` call — ran the same serial chain in `apps/web-platform/middleware.ts`:
`supabase.auth.getUser()` (remote auth-server round-trip), `getSession()`
(local cookie read), `rpc("check_my_revocation")` (Postgres round-trip, the
#4307 membership-revocation gate), and a `users` table select for the
T&C/billing gate. ~3 serial remote round-trips of fixed tax per request — and
each route handler then paid `auth.getUser()` a second time inside
`server/with-user-rate-limit.ts` (12 wrapped routes) or inline in the route
(~77 sites). A dashboard mount issues ~10–11 client fetches, each paying ~4
Supabase RTTs; #3931 had already documented that this cost class is dominated
by HTTP RTT, not query time. The result: every dashboard section rendered in
seconds.

## Decision

1. **Parallelize the independent middleware legs.** `getSession()` (a local
   cookie read that yields the raw access token) is hoisted ahead of
   `getUser()`; the revocation leg (local `sub`+`iat` decode → verdict-cache
   check → `check_my_revocation` RPC on miss) runs concurrently with
   `getUser()`, joined with `Promise.allSettled`/armed `.catch` so a redirecting
   path never leaves an unhandled rejection. The T&C/billing `users` select
   still requires a verified `user` but overlaps the revocation leg's tail.

2. **Positive-only TTL verdict caches.** Two in-process `LRUCache`s
   (`MW_VERDICT_TTL_MS = 30_000`, reusing
   `apps/web-platform/lib/feature-flags/lru-cache.ts`):
   - Revocation: key `"${jwtSub}:${iatSeconds}"` (both derivable from the local
     JWT decode, so the cache check preempts the RPC before `getUser()`
     resolves). Only `revoked === false` is stored — never `true`, never RPC
     errors, never decode hiccups.
   - T&C/billing: key `user.id`; stores only rows where
     `tc_accepted_version === TC_VERSION && subscription_status !== "unpaid"`,
     and a read is honored only while `entry.tc_accepted_version === TC_VERSION`
     (a `TC_VERSION` bump self-invalidates every entry with no write path).

   Both caches are **allow-direction only**: every deny/redirect verdict is
   re-computed per request, so fail-closed freshness is preserved exactly.

3. **Middleware-verified identity header.** Middleware deletes inbound
   `x-soleur-auth-user-id` immediately after cloning the request headers —
   before the `PUBLIC_PATHS` early return and before any `NextResponse.next`
   construction — then sets it to `user.id` after `getUser()` resolves. Route
   handlers consume it via `server/request-auth.ts › verifiedUserId()`, which
   falls back to `createClient().auth.getUser()` when the header is absent
   (direct unit-test invocation, dev paths, any future matcher gap). The header
   is an optimization, never the sole authz path — absent ⇒ re-verify, never
   trust.

4. **Per-stage `Server-Timing` emission** (`mw-auth` / `mw-revoke` / `mw-tc`
   with `hit|miss|grace|exempt` descriptors) on authenticated document
   responses — the no-SSH instrument that verifies the tax collapse post-deploy
   (`hr-no-dashboard-eyeball-pull-data-yourself`).

5. **Supporting de-serialization.** `createClient()` in
   `lib/supabase/server.ts` is wrapped in React `cache()` so
   `resolveIdentity`'s existing `cache()` actually dedupes across the layout
   chain in one render pass; `resolveIdentity` runs its `users` +
   `workspace_members` selects in `Promise.all` and widens `Identity` with
   additive `email`/`subscriptionStatus`; the dashboard chrome becomes a server
   component feeding identity props to a verbatim client shell; the dashboard
   page drops the whole-page `kbLoading` skeleton in favor of
   foundation-aware branches; `useConversations` reads the shared SWR
   `workspaceActiveRepo` key instead of re-fetching, and id-only client reads
   move from `auth.getUser()` (remote) to `auth.getSession()` (local).

## Bounded-staleness trade-off (the decision under scrutiny)

The revocation and T&C gates move from per-request freshness to ≤30 s freshness
*on the allow direction only*. A member removed mid-session can pass the
middleware bounce for up to 30 s; the data-layer boundary (RLS
`is_workspace_member`, membership-keyed policies) still denies them
immediately — the middleware bounce is UX-level defense-in-depth that already
tolerated ~1 h of JWT validity as its design envelope, so 30 s is a narrowing
of that envelope, not a new class. Likewise a `paid → unpaid` transition can
serve ≤30 s of stale write access; Stripe webhook propagation was already
asynchronous, and `unpaid → paid` is instantly correct because `unpaid` rows
are never cached. A user who newly accepts the T&C was never cached (their
prior row failed the store predicate), so the accept→dashboard path cannot
stale-bounce.

The `x-soleur-auth-user-id` trust boundary is defended by: (a) unconditional
delete-before-any-return ordering; (b) a matcher-coverage guard test that walks
`app/api/**/route.ts` and asserts every handler path traverses middleware;
(c) the `getUser()` fallback keeping the header advisory.

Isolate coherence: the deployment is a single Node process (Hetzner); the
in-process caches are coherent. At multi-replica scale the worst case is the
same ≤30 s bound per isolate — re-evaluate then.

## Alternatives considered

- **Exclude `/api/*` from the middleware matcher** — removes revocation + T&C +
  billing enforcement from every API route; converts a latency problem into a
  compliance/security regression. Rejected.
- **`auth.getClaims()` local JWT verification** — only avoids the auth-server
  RTT under asymmetric signing keys; the Supabase project runs HS256 (ADR-033
  scoped asymmetric keys to the runtime-JWT substrate). Deferred; re-evaluate
  if the project adopts asymmetric keys.
- **Shared/external verdict store (Redis)** — single-process deployment makes
  an in-process `LRUCache` sufficient and dependency-free; revisit at
  multi-replica.
- **Caching negative verdicts too** — a stale `unpaid`/unaccepted entry would
  wrongly block paying/accepting users for the TTL window; positive-only
  caching keeps every fail-closed direction exact.
- **Whole-page SSR conversion of the dashboard home** — larger refactor across
  the provider tree; the mount-fan-out reduction captures the same first-paint
  win without re-architecting the route.
- **Migrating all ~77 `getUser()` route sites to `verifiedUserId()`** — wide
  mechanical blast radius; this change migrates the wrapper + the
  dashboard-hot three, and the remaining sweep is a filed follow-up.

## Consequences

- Per-request remote round-trips in middleware drop from ~3 serial to ~1
  (the `getUser()` auth check; the gated legs hit cache in the common case),
  and wrapped/hot API handlers drop their second `getUser()` entirely.
- `Server-Timing` makes the per-stage cost externally observable post-deploy.
- Two regression guards (`middleware-matcher-coverage`, positive-only verdict
  store) pin the new trust boundaries in CI.
- Follow-up issued at ship: migrate remaining `getUser()` route call sites.
