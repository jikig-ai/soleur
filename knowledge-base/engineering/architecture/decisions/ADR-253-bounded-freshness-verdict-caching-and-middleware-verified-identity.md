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
   Expiry is **absolute** (write-anchored): `LRUCache.get()` does not refresh
   `at` on read, so a continuously-hit verdict still dies at write+TTL — a
   sliding window would void the ≤30 s bound precisely under traffic (the
   review panel's convergent P1; a hit-path re-`set` is likewise gated out).

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
delete-before-ANY-return ordering — the strip runs above even the `/health`
early return; (b) a matcher-coverage guard test that walks `app/**/route.ts`
(stripping `(group)` segments) and asserts every handler path traverses
middleware — including attacker-controlled `.png`-suffixed request-pathname
probes on dynamic-terminal routes, because the matcher's extension exclusion
is scoped to single-segment filenames + `/icons/` so nested paths like
`/api/kb/file/x.png` still traverse the gate; (c) the `getUser()` fallback
keeping the header advisory.

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

## Amendment — 2026-09-26 (#8978)

Three scoped extensions of Decision items 3–4, plus one measured rejection:

- **Render-path header consumption.** `resolveIdentity` (the layout/render
  chain's identity resolver) now consumes `x-soleur-auth-user-id` the same way
  route handlers do: when the minted header is present, the caller id is
  accepted only if the *local* session JWT's own `sub` claim agrees AND the
  token carries the `email` claim `Identity` requires; every gap (absent
  header, mismatched `sub`, missing claim, malformed token, no session)
  falls back to remote `getUser()`. The header remains advisory — the JWT
  cross-check means a divergent minted value self-invalidates.
- **`Server-Timing` surface widened.** Emission of `mw-auth` / `mw-revoke` /
  `mw-tc` is no longer document-only: authenticated `/api/*` responses carry
  it too, and document classification now keys on fetch mode
  (`sec-fetch-mode: navigate` or `request.mode === "navigate"`), which closes
  the service-worker-proxied-navigation blind spot (#8969). `Cache-Control:
  no-store` remains document-only.
- **Auth-verdict cache: REJECTED by measurement.** A per-request
  `getUser()`-verdict cache keyed by access-token hash was conditional on
  `mw-auth` dominating the cold `/api/*` tax. The committed perf probe
  (`scripts/live-verify/perf-probe.ts`, 5 cold + 1 warm samples, 2026-09-26)
  measured `mw-auth` at 0.13–4.38 s against document TTFB of 0.77–13.73 s —
  the residual post-middleware tier (document render + upstream warmth)
  dominates, so an auth-verdict cache would have bought a bounded-staleness
  liability for a minority tier. Not adopted; the rejection is recorded so a
  future revisit re-runs the probe first.

Review-round extensions on the same amendment (PR #8984 panel):

- **Refreshed session cookies now propagate downstream.** `setAll` syncs the
  rotated cookie into the forwarded `requestHeaders` snapshot — previously
  the clone predated auth resolution, so render-path `getSession()` saw the
  pre-refresh token and paid a second remote refresh on exactly the
  expired-token cold-session population the fast path targets.
- **Bounded email-claim staleness.** `pending-invites` and `resolveIdentity`
  accept the session JWT's `email` claim, which reflects token-mint time —
  after an email change the claim is stale for ≤ the access-token TTL (~1h),
  self-healing on refresh. The remote `getUser()` arm stays auth-server-fresh
  (absent claim / mismatched `sub` / malformed token).
- **Rejection reasoning, sharpened.** Beyond mw-auth's minority TTFB share,
  a per-request verdict cache could never accelerate the first cold request
  (the population this issue is about), and mount-fan-out misses would not
  coalesce without in-flight dedup — the measured win would have been warm
  tail-only. The render-path residual (doc TTFB minus `mw-*` legs, up to
  ~12.7 s) is where the remaining cold time lives; note the attribution rests
  on document-level arithmetic since the probe's per-request waterfall
  misread Playwright's `timing()` unit convention at first measurement
  (fixed in the same PR).

## Amendment — 2026-09-27 (#8978 residual cold tiers)

Post-merge probes of the first amendment (#8984) showed the ≤500 ms FCP
criterion still unmet: cold document TTFB 2.5–43.4 s, driven by unbounded
remote Supabase legs stalling 20–38 s per call on a cold upstream (Sentry
span evidence: `check_my_revocation` 26.4–28.5 s; `resolveIdentity`'s
`users`/`workspace_members` pair 20.7–37.5 s; `auth/v1/user` 3–6 s; no
queueing gap anywhere — every tier is remote-call latency). This amendment
extends the decision with three mechanisms.

- **Bounded wait on every Supabase-facing leg.** `check_my_revocation` RPC,
  the T&C `users` select, and both `resolveIdentity` selects carry
  `AbortSignal.timeout` bounds (8 s — above the largest observed legitimate
  cold miss at 6.9 s, below the 20–38 s stall class). postgrest-js settles
  an abort as an error OBJECT (`{hint: "Request was aborted (timeout or
  manual cancellation)"}`, never a rejection), so each timeout lands on the
  leg's PRE-EXISTING arm: revocation grace (positive-only verdict cache
  untouched), T&C `tcError` fail-closed redirect, identity degrade
  (role "prd", orgId/subscriptionStatus null). No new verdict semantics were
  introduced; the timeout is distinguished in telemetry via an
  abort-shaped-error check (`revocation_gate.rpc_timeout`,
  `mw_auth.timeout` ops).
- **`getUser()` bounded — gated arm fired.** The prior amendment deferred an
  mw-auth bound pending evidence of recurring stalls; the 2026-09-27 probe
  measured 2.6–4.9 s `mw-auth` on 4 of 6 samples, so the arm fired. gotrue's
  `getUser()` exposes no `abortSignal` — the bound is a `Promise.race` vs a
  10 s `setTimeout`. A timeout reclassifies onto the EXISTING `!user` →
  `/login` redirect arm (verified-identity semantics unchanged); a genuine
  throw still propagates to 500 as before. The raced loser settles in the
  background — its `setAll` cookie writes mutate closure state, never an
  already-returned redirect.
- **In-flight dedup for revocation misses.** Concurrent cold misses on the
  same `${jwtSub}:${iat}` cache key shared one RPC each before; a
  `Map<key, Promise<RevocationOutcome>>` now coalesces them — joiners share
  the work but apply the positive-only store/arm rules independently, and
  the entry is deleted on settle so a later cold request re-queries.
- **Periodic upstream warm-up.** `server/supabase-edge-warmer.ts` issues a
  bounded `GET <supabase>/rest/v1/` with the anon key every ~18 s from the
  Node render/server dispatcher — the span data named cold PostgREST
  compute/transport as the dominant tier, and this is the cheap amortizer.
  Failure-tolerant by contract (a throwing tick resolves to a warn, never a
  rejection), `unref`'d, heartbeat-logged every ~6 min. One recorded caveat:
  middleware's Next-managed fetch dispatcher MAY hold a separate undici pool
  — the warmer provably covers the render/API path; the per-leg bounds cap
  the middleware cold remainder either way.

Consequences: the residual 20–38 s document/middleware stalls become bounded
≤ ~8–10 s degrade-path outcomes; the mount fan-out's N-fold cold-miss
amplification collapses to one RPC per key; and the warm-up removes the cold
class itself between requests. The ≤500 ms AC remains a Phase-2 measurement
target, not a claim this amendment satisfies by construction.
