---
title: "perf: collapse per-request auth waterfall and unblock dashboard first paint"
date: 2026-09-25
type: perf
slug: perf-dashboard-section-load-latency
branch: feat-one-shot-dashboard-load-latency
issue: 5654
closes: [5531, 5532, 5533, 5654]
lane: cross-domain
priority: high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-25
**Sections enhanced:** Proposed Solution (Phases 1, 4), Risks, ACs, Architecture Decision, Files to Edit/Create, Observability
**Research agents used:** sequential-fallback — no Task fan-out in this runtime; deepen-plan halt gates, sharp-edges catalogue, precedent-diff, and test-compatibility audit applied inline

### Key Improvements

1. `NextResponse.next` header-snapshot ordering proved against installed `next@16.3.6` (`handleMiddlewareField` copies `init.request.headers` at construction) — the identity-header `.set` must precede (re-)construction, hedged wording removed.
2. Revocation verdict cache key changed to `(jwt sub, iat)` — both derivable from the local JWT decode, so the cache check preempts the RPC *before* `getUser()` resolves instead of serializing behind it.
3. Parallel revocation leg specified as settle-handled (`Promise.allSettled`/`catch`-armed) — an un-awaited rejection on a redirecting path would be an unhandled rejection.
4. ADR-253 ordinal verified free across **all** `origin/*` refs (max ADR-252), not just `origin/main`.
5. Two Guard Contract entries added (matcher-coverage walk; positive-only verdict store) — `scripts/lint-guard-contract.py` green.

### New Considerations Discovered

- `PaymentWarningBanner` is imported by `use-sidebar-collapse.ts` only as a comment reference; moving it is still correct but the move is to `components/dashboard/payment-warning-banner.tsx` with test-path updates.
- Route-level unit tests invoking handlers without middleware keep working because `verifiedUserId()`'s absent-header path falls back to `getUser()` — the fallback is what preserves the existing ~40 `getUser`-mocking test files' semantics.
- The 2026-04-10 CI-mock-hang learning interacts with re-adding `!loading` to the first-run gate — documented as a work-phase verification against `start-fresh-onboarding.test.tsx`.

## Overview

The production dashboard (app.soleur.ai) takes seconds to render each section because every request pays a serial multi-round-trip Supabase auth/gate chain in `middleware.ts`, pays it again inside API route wrappers, and then the client shell issues ~10 mount-time fetches — including a whole-page skeleton gated on a foundation-status fetch — before any meaningful content paints. This plan collapses the per-request tax (parallelization + positive-only short-TTL verdict caching + middleware-verified identity forwarding), removes the duplicated handler-side auth call, un-gates the dashboard's first paint from the foundation-status fetch, and server-renders the dashboard chrome's identity data so nav/banner state is present in the initial HTML instead of cascading in post-hydration.

Spec lacks valid lane: — no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement

Every authenticated request to the web platform — the HTML document *and* every `/api/*` call — runs the same serial chain in `apps/web-platform/middleware.ts`:

1. `supabase.auth.getUser()` — remote round-trip to the Supabase auth server.
2. `supabase.auth.getSession()` — local cookie read (kept only to read the raw access-token bytes for the `iat` decode).
3. `rpc("check_my_revocation")` — remote Postgres round-trip (the #4307 membership-revocation gate).
4. `users` table select (`tc_accepted_version, subscription_status`) — remote Postgres round-trip, on every path not in `TC_EXEMPT_PATHS` (which is only `/accept-terms`, `/api/accept-terms`, `/api/auth/github-resolve/callback`).

That is ~3 serial remote round-trips of fixed tax. The matcher (`middleware.ts` `config.matcher`) excludes only static assets, so **every** dashboard API call pays it — and then pays `auth.getUser()` a *second* time inside the route handler (`server/with-user-rate-limit.ts` for the 12 wrapped routes; a direct `createClient()` + `getUser()` in ~77 route files). A `/dashboard` document load followed by ~10 mount-time fetches therefore spends the overwhelming majority of its wall-clock on HTTP RTTs to Supabase rather than on rendering or data — the exact cost class #3931 already documented ("single-row RPC latency is dominated by HTTP RTT to Supabase, not query time").

Layered on top:

- **Root layout** (`app/layout.tsx`) — `await headers()` (forces dynamic rendering, required for the CSP nonce) then serially awaits `resolveIdentity()` (itself a serial `getUser` → `users.role` → `workspace_members` chain) then `getFeatureFlags()`. Two compounding facts: `resolveIdentity` is `cache()`-memoized but keyed on the `supabase` client argument, and `lib/supabase/server.ts` `createClient()` is **not** `cache()`d — so each layout/page in one render pass constructs a fresh client and the memoization never dedupes.
- **Dashboard chrome** (`app/(dashboard)/layout.tsx`) — a single `"use client"` component that fetches `/api/admin/check` and runs `getSession()` → `users` select in mount effects; nav items and the payment banner pop in post-hydration (#5532).
- **Dashboard home** (`app/(dashboard)/dashboard/page.tsx`) — the whole page early-returns a full-screen skeleton while `/api/dashboard/foundation-status` is in flight (`kbLoading`), even though that data only drives foundation-card checkmarks (#5654; the endpoint itself was the earlier partial mitigation). `useConversations` then runs its own serial waterfall: client `getUser()` → `fetch("/api/workspace/active-repo")` → `list_conversations_enriched` RPC — duplicating the page's own SWR fetch of the same `active-repo` endpoint.

Measured probe (unauthenticated, 2026-09-25): `curl https://app.soleur.ai/dashboard` → 302→`/login` TTFB ~230–260 ms across 3 samples, `/health` ~410 ms — this is the transport+server floor *before* any of the serial auth chain is visible. The authenticated path adds the serial RTTs above on every leg; per-request tax on the order of several hundred ms per request, multiplied across ~11 requests per dashboard mount, is consistent with the reported multi-second render.

## Research Insights

**Premise validation (Phase 0.6).** All five cited issues verified OPEN via `gh issue view`: #5531, #5532, #5533, #5654, #3931. PR #5537 verified MERGED (2026-06-18, quick-wins bundle, no closing-issue references — consistent with "different scope"). All four cited files exist and were read line-for-line; the diagnosis holds: `middleware.ts` serial chain confirmed (getUser→getSession→revocation RPC→users select), `withUserRateLimit` re-calls `getUser()` (12 route consumers, all of which read only `user.id`), `(dashboard)/layout.tsx` is fully `"use client"` with two mount-time data waterfalls, `dashboard/page.tsx` whole-page-skeletons on `foundationData === undefined`. Prior plan `2026-07-07-perf-dashboard-load-and-conversation-list-plan.md` already shipped the `list_conversations_enriched` RPC + `/api/dashboard/foundation-status` endpoint and **deferred** its Phase 3 (middleware parallelization — "security-gated") and Phase 4 (bundle split) plus the active-repo double-fetch dedupe; the consolidated follow-up tracker it prescribes was never located via issue search — this plan is effectively that follow-up, superseding the need for the tracker.

**Property List (Phase 0.6b).** The ask restated as observable properties: (P1) first meaningful dashboard content paints in ≲500 ms; (P2) the revocation gate keeps its semantics — a genuinely revoked member still bounces to `/login`, transient RPC/decode failures still grace-through; (P3) the T&C/billing gate keeps its fail-closed posture — unaccepted users still bounce to `/accept-terms`, `unpaid` stays GET-only; (P4) no new spoofable identity path; (P5) duplicated per-request work is removed rather than re-ordered only.

**Cut List (Phase 0.6b).** Candidate mechanisms evaluated against existing machinery: (a) *per-request memoization across middleware and route handlers* — cut, structurally impossible: middleware runs in the edge-runtime isolate, handlers in the Node runtime; no shared memo exists. The achievable equivalent is the identity-forwarding header (Phase 2), which is what the design adopts. (b) *Whole-`/api/*` matcher exclusion* — cut: removes the revocation/T&C/billing enforcement surface from API routes wholesale; violates P3. (c) *SWR / HTTP caching for the gates* — cut: client-side caches cannot help server middleware. (d) *Local JWT claim verification (`auth.getClaims()`)* — cut for this PR: it only avoids the auth-server RTT when the project uses **asymmetric** JWT signing keys; no evidence in repo that the Supabase project migrated off HS256 (ADR-033 evaluated asymmetric keys for the *runtime-JWT* substrate only). Recorded as a follow-up (Deferred). (e) *Redis/shared store for verdict caching* — cut: single-node Hetzner deployment (one middleware isolate); an in-process `Map` is sufficient — revisit at multi-replica.

**Value measurement (Phase 0.6c).** The saving claim is per-request RTT elimination. Static measurement at plan time: middleware runs 3 serial remote ops (down to ~1 after caching / ~2 after parallelization alone); root layout runs getUser + 2 serial selects (down to getUser + 1 parallel pair); each `/api/*` handler re-runs getUser (removed for the wrapped/hot routes via the identity header). Wall-clock baseline of the unauthenticated floor measured above (~250 ms); the per-request auth-tax hypothesis (~200–500 ms, prior plan's H3) is confirmed post-deploy via the Phase-0 `Server-Timing` instrumentation — no authenticated probe exists without credentials, which is exactly why the instrumentation is a deliverable rather than an assumption.

**Institutional learnings applied.** `2026-03-20-middleware-error-handling-fail-open-vs-closed` (explicit error handling; note the current T&C gate *deliberately* diverges to fail-closed per the in-file Art. 7(1) comment — this plan preserves that), `2026-05-29-middleware-tc-gate-does-not-fire-for-public-paths` (PUBLIC_PATHS early-return precedes T&C — the identity-header strip is placed *before* that early return), `2026-04-10-dashboard-onboarding-state-independent-of-conversation-loading` (first-run/command-center gating must not re-couple to a hangable conversation fetch — handled via the `foundationData !== undefined` + resolved-conversations guard), `2026-03-20-middleware-prefix-matching-bypass` (exact-or-slash matching precedent), #7418/ADR-176 (mechanism minimality), #5536 (precedent that auth-adjacent TTL caches carry a security-review burden).

**Reusable machinery found (not reinvented).** `lib/feature-flags/lru-cache.ts` — a 36-line pure-TS `LRUCache<K,V>` with TTL + size cap, edge-safe (no node imports); reused for both verdict caches. React `cache()` — already wraps `resolveIdentity`; extended to `createClient()` so the memoization actually dedupes across the layout chain. `lib/observability-edge.ts` `reportEdgeSilentFallback` — the existing edge-safe Sentry mirror; all existing call sites preserved unchanged.

**External verification.** Next.js request-header forwarding to route handlers (`NextResponse.next({ request: { headers } })`, set/delete on a cloned `Headers`) is the documented, supported pattern (Next.js middleware docs, stable since v13). `supabase.auth.getClaims()` exists for local JWT verification but only avoids the auth-server RTT under asymmetric signing keys — not this project's current substrate.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Verified reality | Plan response |
|---|---|---|
| Middleware runs ~3 serial remote round-trips per request incl. `/api/*` | Confirmed — `getUser` → `getSession` (local) → `check_my_revocation` RPC → `users` select; matcher covers all non-static paths; `TC_EXEMPT_PATHS` exempts only 3 paths | Phase 1 parallelizes + adds positive-only TTL verdict caches |
| `withUserRateLimit` calls `getUser()` again per API call | Confirmed — plus ~70 more route files doing the same | Phase 2 forwards a middleware-verified `x-soleur-auth-user-id` header (inbound stripped), consumed by a shared `verifiedUserId()` helper with a `getUser()` fallback; only the 12-route wrapper + the 3 dashboard-hot routes migrate in this PR |
| `useConversations` waterfall: getUser → active-repo → RPC | Confirmed at `hooks/use-conversations.ts` `fetchConversations` | Phase 5 — hook consumes the shared SWR `workspaceActiveRepo` entry; client `getUser` → `getSession` for id-only reads |
| #5654 "partially mitigated" by foundation-status | Confirmed — endpoint exists and the page still whole-page-skeletons on it | Phase 4 un-gates the shell; foundation section gets its own skeleton |
| "Whole-page skeleton" wording | Accurate but imprecise — `kbLoading` gates on foundation-status (not `/api/kb/tree` anymore; #5654's title is stale) | ACs written against foundation-status, the real gate |

## Proposed Solution

Five phases, ordered cheapest-and-highest-leverage first. Phases 1–2 are the dominant lever (every request); Phase 4 is the perceived-perf lever (first paint); Phases 3 and 6 remove the remaining serial/duplicate work.

### Phase 1 — Middleware: parallelize independent legs + positive-only verdict cache

`apps/web-platform/middleware.ts`:

1. **Reorder for parallelism, semantics-identical.** `getSession()` is a local cookie read — hoist it before `getUser()`. When an access token exists, locally decode the JWT `sub` + `iat` (the `iat` decode already exists for the revocation leg) and check the revocation-verdict cache *before* launching any RPC; on miss, kick off `check_my_revocation` as an un-awaited promise and `Promise.allSettled`-style join it with `getUser()` (the parallel leg must be settle-handled so a revoked/error result on an already-redirecting path can't surface as an unhandled rejection). The T&C/billing `users` select still runs only after a verified `user` exists (unchanged dependency) but now overlaps the revocation RPC's tail when present. Serial RTTs: 3 → at most 2 (one of which is the auth check itself).
2. **Positive-only TTL verdict caches** using the existing `LRUCache` primitive (module-scope `const`, e.g. `new LRUCache<string, true>(2000, MW_VERDICT_TTL_MS)` with `MW_VERDICT_TTL_MS = 30_000`):
   - *Revocation:* key `"${jwtSub}:${iatSeconds}"` where `jwtSub` is the `sub` claim from the same local JWT decode that already yields `iat` — computable before `getUser()` resolves, so the cache check can preempt the RPC entirely on a hit (keying on `user.id` would serialize the lookup behind the auth RTT and defeat the parallelism). Cache **only** `revoked === false` verdicts. `revoked === true`, RPC errors, and decode hiccups are never cached — every fail-closed/branch and every `reportEdgeSilentFallback` call site is preserved verbatim. Effect: a member removed mid-session keeps passing the middleware bounce for ≤ TTL; the load-bearing data boundary (RLS `is_workspace_member`) still denies them immediately — this bounded-staleness trade-off is the ADR's subject.
   - *T&C/billing:* key `user.id` → `{ tc_accepted_version, subscription_status }`. Store **only fully-passing rows** (`tc_accepted_version === TC_VERSION` *and* `subscription_status !== "unpaid"`). On read, a hit is honored only while `row.tc_accepted_version === TC_VERSION` — a `TC_VERSION` bump self-invalidates every entry without a write path. A user who newly accepts T&C was never cached (their prior row failed the store predicate), so the accept→dashboard path cannot stale-bounce. A `paid → unpaid` transition can serve ≤ TTL of stale write access (accepted residual; Stripe webhook propagation is already asynchronous); `unpaid → paid` is instantly correct because unpaid rows are never cached.
   - Isolate coherence: single-process Hetzner deployment means one middleware isolate; the cache is coherent. At multi-replica scale the worst case is the same ≤ TTL bound per isolate — documented in the ADR.
3. **Verified-identity header.** Immediately after `const requestHeaders = new Headers(request.headers)` — *before* the PUBLIC_PATHS early return — `requestHeaders.delete("x-soleur-auth-user-id")` strips any client-supplied spoof. After `getUser()` resolves a user, `requestHeaders.set("x-soleur-auth-user-id", user.id)`. The header only reaches a handler when middleware `next()`s the request, i.e., only after auth + revocation grace + T&C/billing all pass. **Ordering is load-bearing and verified against installed `next@16.3.6`** (`node_modules/next/dist/server/web/spec-extension/response.js`, `handleMiddlewareField`): `NextResponse.next({ request: { headers } })` iterates and *snapshots* the headers into `x-middleware-request-*` at construction time — a `requestHeaders.set` made after the response object exists does NOT propagate. Therefore the `next()` response consumed by the handler must be constructed (or re-issued, as `setAll` already does on cookie writes) **after** the `set` — the minimal change is to defer/re-issue the `NextResponse.next` call once auth resolves. A vitest asserting a wrapped handler observes the header is the proof.
4. **Per-stage `Server-Timing` header** on document responses (`mw-auth;dur=`, `mw-revoke;dur=`, `mw-tc;dur=`, each with `;desc=hit|miss|grace` where applicable) — the no-SSH instrument that lets post-deploy measurement confirm the tax collapse. Added on the success path only; redirect paths unchanged.

### Phase 2 — Handler-side: consume the verified identity

- New `apps/web-platform/server/request-auth.ts`: `verifiedUserId(req: Request): Promise<string | null>` — reads `x-soleur-auth-user-id`; when absent (direct unit-test invocation, dev paths, any future matcher gap) falls back to `(await createClient()).auth.getUser()` returning `user?.id ?? null`. The fallback keeps every existing caller correct and is the fail-closed direction (absent header ⇒ re-verify, never trust).
- `server/with-user-rate-limit.ts`: replace the `createClient()` + `getUser()` pair with `verifiedUserId(req)`; narrow the handler contract `type Handler = (req: Request, user: User)` → `(req: Request, user: { id: string })`. Verified: all 12 consumers read only `user.id` (greped 2026-09-25) — the narrowing is compile-safe; `tsc --noEmit` is the gate.
- Migrate the dashboard mount path's raw-`getUser` routes to the same helper: `app/api/admin/check/route.ts`, `app/api/dashboard/today/route.ts`, `app/api/workspace/active-repo/route.ts` (each keeps its own Supabase client for data queries; only the auth-verification RTT is removed). The remaining ~70 route files keep `getUser()` — a follow-up sweep, not this PR (Deferred).

### Phase 3 — Root-layout identity resolution dedupe + parallelize

`apps/web-platform/`:

- `lib/supabase/server.ts`: wrap `createClient` in React `cache()` so one server render pass shares one client — this is what makes `resolveIdentity`'s existing `cache()` actually dedupe across the root layout → child layout chain (today each site builds a new client object and the memo key never matches). Per-request memoization of a cookie-reading factory is safe; `cookies()` is already request-scoped.
- `lib/feature-flags/identity.ts`: after `getUser()`, run the `users` select and the `workspace_members` select in `Promise.all` (they are independent). Extend the select to `role, subscription_status` and extend `Identity` with additive fields `email: string | null` (from `userData.user.email`, zero extra cost) and `subscriptionStatus: string | null` — consumed by Phase 6; existing consumers (`app/layout.tsx`, `chat/layout.tsx`, `dashboard/settings/**`, `api/repo/install/route.ts`) read only `userId/role/orgId` and are unaffected.
- `app/layout.tsx`: **no code change required.** `await headers()` must stay — it is how the CSP nonce (`x-nonce`, set in middleware) reaches `NoFoucScript`; removing it re-breaks 'strict-dynamic' nonce injection (#1213). This is the "documented reason" arm of #5531's AC; the plan adds a comment pointer to this section.

### Phase 4 — Ungate dashboard first paint (#5654)

`apps/web-platform/app/(dashboard)/dashboard/page.tsx` — remove the `kbLoading` whole-page early return; make the three render branches foundation-aware instead of foundation-*gated*:

- `isRedirecting401` (foundation fetch bounced to login) keeps the whole-page skeleton — it exists to hold paint during navigation.
- `provisioning` (503) stays a whole-page state — it genuinely is one.
- **First-run branch** gains two guards: `foundationData !== undefined` (vision existence is *confirmed*, not defaulted-false while pending) AND `!loading` (conversations resolved, so a user *with* conversations can never see the first-run form while the list is in flight). The `!loading` re-add is deliberate and narrow: the 2026-04-10 learning removed it because mocked CI hangs made a *Command-Center* assertion unreachable — this change applies it only to the first-run branch, and a hung conversation fetch yields a section skeleton rather than the wrong screen.
- **Command-center-empty branch** gains `foundationData !== undefined` — while the foundation fetch is pending, render neither first-run nor command-center; fall through to the inbox structure (below) whose conversation region shows the existing row skeletons. When it resolves, the correct branch takes over — no first-run flash either direction.
- **Inbox branch** (rendered whenever the above don't fire): Today section, filter bar, and the existing loading-row skeletons / error card / rows render immediately. `FoundationSection` mounts only when `visionExists && !allTasksComplete` as today; to prevent the "no layout shift" AC from failing when it pops in on a cold load, render a fixed-height section shimmer while `foundationData === undefined && conversations.length > 0` only.
- Net effect: the shell, Today region, filter bar, and conversation skeletons paint at TTFB+hydration; conversation rows land after their (now shorter, Phase 5) chain — the foundation stat no longer gates any of it.

### Phase 5 — Conversation waterfall + client auth dedupe (#5533)

- `hooks/use-conversations.ts`: replace the internal `fetch("/api/workspace/active-repo")` with a `useSWR(swrKeys.workspaceActiveRepo(), jsonFetcher)` read — SWR dedupes concurrent same-key fetches, so page + nav badge + hook share one request. The hook's fetch path proceeds when the SWR value resolves (or when SWR itself resolves an error → existing `Failed to resolve the active repository` path). Preserves the `workspaceId` null→id transition the realtime channel keys on; the `shouldDropForScope` filter and scope-resolve backfill are untouched. This removes one serial leg AND one duplicate request from the waterfall (getUser → active-repo → RPC becomes getSession-local → shared-SWR → RPC).
- Client-side `auth.getUser()` → `auth.getSession()` where only `user.id` is needed (each is a browser→Supabase RTT today): `hooks/use-conversations.ts` (`fetchConversations`), `components/dashboard/conversations-nav-badge.tsx`, `hooks/use-onboarding.ts`. Rationale: these are UI-scoping reads of the client's own identity — authorization is enforced by middleware + RLS server-side; `getSession()` is the documented local-read for this.
- `dashboard/page.tsx`'s three data reads (foundation-status, today, active-repo) already fire in parallel via SWR — no batching needed; #5533's "no sequential client waterfall" AC is satisfied by the hook fix above.

### Phase 6 — Dashboard chrome server-render (#5532)

- `app/(dashboard)/layout.tsx` becomes an async **server component**: `const supabase = await createClient(); const identity = await resolveIdentity(supabase);` (cache-deduped against the root layout's call from Phase 3 — zero added RTT) → derive `isAdmin` (`process.env.ADMIN_USER_IDS?.split(",").includes(identity.userId) ?? false`, identical logic to `/api/admin/check`), `userEmail` (`identity.email`), `subscriptionStatus` (`identity.subscriptionStatus`); render `<DashboardShell …>{children}</DashboardShell>`.
- New `app/(dashboard)/dashboard-shell.tsx` (`"use client"`): the entire existing component body moves here verbatim, receiving `isAdmin`/`userEmail`/`subscriptionStatus` as props; delete the `/api/admin/check` mount effect and the `getSession`→`users` select effect. `PaymentWarningBanner` moves to its own `components/dashboard/payment-warning-banner.tsx` (it is exported from `layout.tsx` today — update the test import path). All keyboard/drawer/media-query/realtime effects stay client-side unchanged.
- `/api/admin/check` route stays (e2e tests `nav-states-shell.e2e.ts` / `start-fresh-conversations-rail.e2e.ts` still exercise it); it additionally migrates to `verifiedUserId()` in Phase 2.

## Architecture Decision (ADR/C4)

This change touches two architecture-level concerns and earns a new ADR (provisional **ADR-253**, verified free on 2026-09-25 by enumerating `knowledge-base/engineering/architecture/decisions` across every `origin/*` ref — max observed is ADR-252, so no pushed branch claims it either; still provisional until `soleur:ship`'s collision gate re-verifies):

- `### ADR` — **"Bounded-freshness positive-verdict caching + middleware-verified identity header for per-request auth cost."** Decisions to record: (a) the revocation/T&C gates move from per-request freshness to ≤`MW_VERDICT_TTL_MS` freshness *on the allow direction only* (fail/redirect verdicts are never cached); the data-layer boundary (RLS `is_workspace_member`, membership-keyed policies) is unaffected and remains the load-bearing enforcement; the middleware bounce is a UX-level defense-in-depth that already tolerates ~1 h of JWT-validity as its design envelope — 30 s is a narrowing of that envelope, not a new class. (b) `x-soleur-auth-user-id` is a middleware-minted, inbound-stripped internal trust signal; consumers must fall back to `getUser()` when it is absent, so the header is an optimization, never the sole authz path; the matcher-coverage invariant (every dynamic route traverses middleware) is pinned by a regression test. Alternatives to record as rejected: matcher exclusion of `/api/*` (drops T&C/billing/revocation enforcement on API routes); `getClaims()` local JWT verification (project is on HS256 — no JWKS to verify against; revisit if the project adopts asymmetric signing keys, cf. ADR-033); shared/external verdict store (single-process deployment); per-request memoization across runtimes (impossible edge↔Node).
- `### C4 views` — **No C4 impact**, verified against all three model files on a fresh read (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none new (dashboard user is the existing `founder` actor); (b) external systems/vendors — none new (Supabase Auth/Postgres, Flagsmith already modeled; request *volume* to Supabase decreases); (c) containers/data stores — `platform.webapp.auth`, `platform.webapp.dashboard`, `platform.webapp.api`, `platform.infra.supabase` all already exist; the verdict cache is in-process ephemeral state, not a modeled store; (d) actor↔surface relationships — unchanged set of edges, only their frequency changes. The one new trust signal (`x-soleur-auth-user-id`) is an intra-`webapp` edge — below the component granularity the model tracks.
- `### Sequencing` — the ADR is authored in this PR describing the as-shipped state; no later slice required.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Exclude `/api/*` from the middleware matcher | Removes revocation + T&C + billing enforcement from every API route — converts a latency problem into a compliance/security regression. Rejected. |
| `auth.getClaims()` local JWT verification everywhere | Only faster under asymmetric signing keys; the project runs HS256 today (ADR-033 scoped asymmetric keys to runtime JWTs). Deferred as a substrate follow-up. |
| Shared/external verdict store (Redis) | Single-process deployment — an in-process `LRUCache` is sufficient and dependency-free; revisit at multi-replica. |
| Cache negative verdicts too | A stale `unpaid`/unaccepted cache entry would wrongly block paying/accepting users for the TTL window. Positive-only caching keeps every fail-closed direction exact. |
| Convert whole dashboard home to server components / SSR data | Larger refactor across provider tree (SWRConfig, TourProvider, realtime wiring); the mount-fan-out reduction from Phases 4–6 captures the same first-paint win without re-architecting the route. Revisit if the post-deploy `Server-Timing` + waterfall still misses target. |
| Full migration of all ~77 `getUser` route call sites to `verifiedUserId` | Mechanical but wide blast radius; this PR migrates the wrapper + the dashboard-hot three and files the sweep as a follow-up. |
| Drop `await headers()` from root layout (make segments static again) | Contradicts the CSP nonce requirement — 'strict-dynamic' gets no nonce under static rendering and every script is blocked (#1213). The issue's own AC accepts a documented reason; documented. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a mis-scoped verdict cache or a spoofable/fragile identity header that either bounces healthy users (false `/login` or `/accept-terms` redirect loops) or — worst case — serves another user's scoped data if the inbound-header strip is bypassed by a future matcher change; on the render side, an existing user flashing the first-run "Tell your organization what you're building" screen reads as account/data loss.
- **If this leaks, the user's data is exposed via:** a request carrying a client-forged `x-soleur-auth-user-id` reaching a handler that skips `getUser()` (only possible if a route becomes reachable without middleware — the strip + the matcher-coverage guard exist exactly to keep that unreachable).
- **Brand-survival threshold:** `single-user incident` — auth/tenant-identity path; a single cross-user data read is a breach.

## Observability

```yaml
liveness_signal:
  what: "Existing /health endpoint (supabase:connected pair) + new Server-Timing stage durations (mw-auth / mw-revoke / mw-tc) emitted on authenticated document responses"
  cadence: "per-request (Server-Timing); Better Stack keyword monitor on /health unchanged"
  alert_target: "Better Stack monitor app_health (existing); Sentry for mirrored gate errors"
  configured_in: "apps/web-platform/middleware.ts (timing emission); apps/web-platform/infra/uptime-alerts.tf (existing monitor)"
error_reporting:
  destination: "Sentry web-platform via reportEdgeSilentFallback (edge-safe variant already imported by middleware.ts)"
  fail_loud: "existing op slugs preserved verbatim — revocation_gate.malformed_jwt / .no_iat / .transient_grace, tc_query_failed; new op slug middleware.auth_header.absent breadcrumb when a migrated handler sees no verified header (diagnoses matcher/header-propagation regressions without SSH)"
failure_modes:
  - mode: "verdict-cache bug causes wrong allow/deny"
    detection: "revocation/T&C redirect behavior covered by middleware.*.test.ts cache cases; Sentry transient_grace / tc_query_failed rate unchanged (a cache that suppresses real DB errors would collapse the op-slug rate to zero — visible on the Sentry breadcrumb dashboard)"
    alert_route: "Sentry issue + breadcrumb dashboards"
  - mode: "identity header missing/mis-propagated (matcher gap or Next header snapshotting)"
    detection: "vitest: wrapped handler observes header on a middleware-traversed request; absent header falls back to getUser (safe direction); Server-Timing mw-auth dur jumps back to full-RTT band post-deploy"
    alert_route: "Sentry breadcrumb middleware.auth_header.absent"
  - mode: "first-run flash regression"
    detection: "vitest/jsdom: foundation-pending + conversations-pending renders neither first-run nor command-center; existing e2e suite re-run"
    alert_route: "CI (e2e)"
logs:
  where: "web host pino stdout → Vector → Better Stack source 2457081 (soleur-inngest-vector-prd); edge-side events via Sentry"
  retention: "Better Stack Logs retention (90d table)"
discoverability_test:
  command: "grep -o 'x-soleur-auth-user-id' apps/web-platform/server/request-auth.ts"
  expected_output: "x-soleur-auth-user-id"
```

## Encryption Posture

```yaml
at_rest:
  - store: "middleware in-process verdict caches (LRUCache Maps: revocation-ok per (user.id,iat), T&C/billing row per user.id)"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/middleware.ts (module-scope LRUCache; process memory only, no disk/serialization path — asserted by the no-persistence comment at the declaration site)"
    defends_against: "nothing at rest by design — entries live ≤30s in process RAM and are gone on restart; the store exists to shed read load, not to hold data"
    does_not_defend: "a process-memory disclosure of the running isolate (attacker already inside the runtime sees live cookies anyway — strictly weaker data than the request stream the process handles)"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: ephemeral in-process state has no externally-checkable artifact"
in_transit:
  - connection: "middleware (edge isolate) -> route handler / RSC render (Node runtime), same process"
    enforced_at: "apps/web-platform/middleware.ts (requestHeaders.delete then .set of x-soleur-auth-user-id)"
    tls: "none — intra-process header propagation; the inbound client->edge leg is already TLS via Cloudflare"
    cert_verification: "off"
    does_not_defend: "a client-forged inbound header — mitigated not by TLS but by the unconditional delete-before-set at header construction plus the matcher-coverage guard test"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "the 'cache' is TTL-bounded volatile process memory holding a boolean and two enum strings keyed by already-pseudonymous user.id — there is no persistence substrate to encrypt, and the header never leaves the process"
  tracking_issue: "#5536 (the standing auth-cache-TTL review issue this feature is a sibling of)"
  reevaluate_when: "the web platform scales beyond one process/replica, or the cache stores anything beyond allow-verdicts"
  expires_on: "2026-12-24"
```

## Guard Contract

### Guard 1 — middleware matcher coverage of authenticated surfaces

**Property.** Every non-static route a request can reach — including every `/api/*` route handler that may consume `x-soleur-auth-user-id` — traverses `middleware.ts`, so the inbound-strip + verified-set sequence can never be bypassed.

**Assembly.** `export const config.matcher` in `apps/web-platform/middleware.ts` is the single chokepoint every request flows through; the guard's assembly is that config value evaluated against the set of route-handler paths produced by walking `apps/web-platform/app/api/**/route.ts` (the structure — glob-walk the directory and evaluate each discovered path against the matcher regex — not today's file list, which drifts with every new route).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Narrow the matcher to exclude `/api/dashboard` (e.g. add it to the negative lookahead) — a route that consumes the header no longer traverses the strip | RED |
| 2 | Delete the matcher-export test itself (guard's own dispatch — a suite that never evaluates the matcher cannot prove coverage) | RED (suite must fail on missing coverage assertion, not pass vacuously) |
| 3 | Add a second API route `app/api/zzz-probe/route.ts` outside the matcher after a compliant first one exists — the walk must evaluate every member, not stop at one | RED |
| 4 | Corrupt the test's matcher-evaluation so it asserts `true` unconditionally — must-PASS input (`/api/accept-terms` under the shipped matcher) still passes but the negation rows above reveal a harness that can never fail | RED on rows 1–3, PASS on the true input |
| 5 | Reorder `requestHeaders.delete("x-soleur-auth-user-id")` to *after* the PUBLIC_PATHS early return — a client-forged header on a public path forwards downstream | RED (a second test pins delete-before-any-return) |

### Guard 2 — positive-only verdict caching invariant

**Property.** The verdict caches store only allow-direction results (`revoked === false`; `tc_accepted_version === TC_VERSION && subscription_status !== "unpaid"`), so every deny/redirect decision is re-computed per request and fail-closed freshness is preserved.

**Assembly.** Every `cache.set(`/`revocationOk.set(`/`tcRowCache.set(` call site in `middleware.ts` (the chokepoint the stored verdicts flow through) — the guard greps the file and requires each `set` to be dominated by the passing-predicate condition; a `set` in an error or revoked branch is the defect class.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Cache `revoked === true` (add a set in the revoked branch) | RED — the bounce must re-check each request |
| 2 | Cache a row where `tc_accepted_version !== TC_VERSION` | RED — a just-accepted user stale-bounces for the TTL |
| 3 | Cache an `unpaid` row | RED — a paid user stays write-blocked for the TTL after checkout |
| 4 | Test file that never calls the cache predicate (reports "0 asserted") | RED — anti-vacuity row: the suite must show a nonzero assertion count on store-predicate coverage |
| 5 | Bump `TC_VERSION` and re-request with a warm cache — the cached row must be ignored, not trusted | RED if honored (must-PASS direction: a *matching* version row is served from cache) |

## Files to Edit

- `apps/web-platform/middleware.ts` — parallelized auth legs, positive-only verdict caches, `x-soleur-auth-user-id` strip/set, `Server-Timing` emission
- `apps/web-platform/server/with-user-rate-limit.ts` — `verifiedUserId()` replaces `getUser()`; `Handler` type narrows to `{ id: string }`
- `apps/web-platform/lib/supabase/server.ts` — `createClient` wrapped in React `cache()`
- `apps/web-platform/lib/feature-flags/identity.ts` — `Promise.all` on the two selects; `Identity` gains `email`, `subscriptionStatus`
- `apps/web-platform/app/layout.tsx` — comment only (documented reason `headers()` stays, per #5531 AC)
- `apps/web-platform/app/api/admin/check/route.ts`, `apps/web-platform/app/api/dashboard/today/route.ts`, `apps/web-platform/app/api/workspace/active-repo/route.ts` — `verifiedUserId()` migration
- `apps/web-platform/app/(dashboard)/layout.tsx` — becomes async server component (identity props)
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — un-gated render branches per Phase 4
- `apps/web-platform/hooks/use-conversations.ts` — SWR `workspaceActiveRepo` read + `getSession` for the id leg
- `apps/web-platform/hooks/use-onboarding.ts`, `apps/web-platform/components/dashboard/conversations-nav-badge.tsx` — `getUser` → `getSession` (id-only reads)
- `apps/web-platform/test/` — extend `middleware.*`, `with-user-rate-limit`, `identity`, `dashboard-layout-*` suites; update `server.test.ts`/`identity.test.ts` fixtures for the widened `Identity`

## Files to Create

- `apps/web-platform/server/request-auth.ts` — `verifiedUserId()` helper (header read + `getUser()` fallback)
- `apps/web-platform/app/(dashboard)/dashboard-shell.tsx` — `"use client"` island holding today's layout body verbatim
- `apps/web-platform/components/dashboard/payment-warning-banner.tsx` — moved verbatim out of `layout.tsx` (test import paths updated)
- `apps/web-platform/test/server/request-auth.test.ts` — header-present/header-absent/spoofed-header cases (satisfies `test/**/*.test.ts` vitest glob)
- `knowledge-base/engineering/architecture/decisions/ADR-253-*.md` — the verdict-caching + identity-header ADR
- `knowledge-base/product/design/dashboard/dashboard-load-states.pen` — committed this session

## Implementation Phases

Phase numbering follows Proposed Solution: **Phase 0** = baseline `Server-Timing` instrumentation + a captured pre-change waterfall (Playwright or curl timing table recorded into the PR body). **Phases 1–6** as above; each lands as its own commit so the PR stays bisectable and the middleware phase (the riskiest) is independently revertable. If review pressure splits the PR, Phase 1+2 ship together first and 4–6 follow — the issues map accordingly (closes list below assumes the full PR).

## Non-Goals / Deferred

- **#3931** (`is_jti_denied` deny-RPC caching in `lib/supabase/tenant.ts`) — different call site (agent-runtime tenant clients, not session middleware). The positive-verdict caching design here is a sibling precedent; the issue stays open.
- **~70 remaining `getUser()` route call sites** — follow-up sweep issue at ship time: migrate to `verifiedUserId()` (what/why/re-eval: safe after the header + helper prove out in prod; milestone Post-MVP/Later).
- **Asymmetric JWT signing-key adoption / `getClaims()`** — substrate change owned with ADR-033's lineage; re-evaluate when Supabase's HS256 deprecation date firms up.
- **#5644** (conversations rail + Routines SWR migration) — partially overlapped: this plan puts one SWR read inside `use-conversations` (active-repo leg) but does not convert the hook to SWR wholesale; that issue stays open.
- **Bundle code-splitting** (prior plan's Phase 4: `pdfjs-dist`, `@likec4/*`, `@codemirror/*` off the critical path) — still deferred; orthogonal lever if the post-deploy waterfall misses target.
- **#5535** (client-fetch retry/backoff) — adjacent reliability concern, not latency.
- **Removing `/api/admin/check`** — kept; still exercised by e2e and useful as a public surface.

## Open Code-Review Overlap

Open `code-review` issues touching planned files (queried 2026-09-25, 84 open issues scanned):

- **#2591** (`docs(security): document CSP middleware + route intersection`) — touches `middleware.ts`. **Acknowledge:** docs-only; orthogonal to the auth-chain reorder. Remains open.
- **#2193** (`refactor(billing): unify past_due and unpaid banners`) — touches `(dashboard)/layout.tsx`. **Acknowledge:** different concern (banner component consolidation). Phase 6 moves `PaymentWarningBanner` verbatim into the shell/own file without restructuring its internals; the scope-out stays open for its own cycle.
- **#2590** (`refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer`) — touches `dashboard/page.tsx`. **Acknowledge:** this plan's page edits are confined to the render-gate conditions and the `activeRepo` prop wiring — no first-run-composer restructuring.
- **#3564** (Core Web Vitals infra) — references `app/layout.tsx`. **No planned edit** to that file beyond a comment pointer; the `Server-Timing` header gives it partial instrumentation anyway. Remains open.

## Domain Review

**Domains relevant:** Engineering, Product (forced by the mechanical UI-surface override — `app/(dashboard)/layout.tsx` and `app/(dashboard)/dashboard/page.tsx` match `app/**/{page,layout}.tsx`).

### Engineering

**Status:** reviewed (sequential-fallback — this planning run executes inline, no Task fan-out available)
**Assessment:** The load-bearing risks are (a) revocation/T&C semantics preservation under bounded-freshness caching — mitigated by positive-only stores + the Guard Contract; (b) the `x-soleur-auth-user-id` trust boundary — mitigated by delete-before-set ordering, the matcher-coverage guard, and the `getUser()` fallback in `verifiedUserId()`; (c) the `(dashboard)/layout.tsx` server/client split touching the provider tree — mitigated by a verbatim move (props in, same JSX) and the existing `dashboard-layout-*.test.tsx` suite. Auth-gate reordering + header forwarding is a CTO/architecture-class concern — the ADR deliverable covers it; security review is required at PR time (security-sentinel + user-impact-reviewer per the brand-survival threshold).

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `app/**/page.tsx` + `app/**/layout.tsx` in Files to Edit/Create)
**Decision:** auto-accepted (pipeline) — headless run; no per-phase approval gate
**Agents invoked:** none — Task fan-out unavailable in this runtime; spec-flow and CPO lenses applied inline: the only user-facing delta is *which loading surface* appears during fetches (whole-page → section-level) plus admin-nav/payment-banner presence at first paint; the states, copy, and components are unchanged. Flow check: no dead ends introduced — every existing state (first-run, command-center, inbox, provisioning, redirect-hold, error) is preserved with tightened gating.
**Skipped specialists:** none (inline equivalent applied; see note)
**Pencil available:** yes (`PENCIL_CLI_KEY` present in Doppler `soleur/dev`); the vendored `@pencil.dev/cli` install path is deprecated/fails on a `sharp` native build in this environment, so the wireframe was authored directly as `.pen` JSON following the `swr-loading-states.pen` precedent — committed at `knowledge-base/product/design/dashboard/dashboard-load-states.pen`.

#### Findings

- The `.pen` encodes the three render states (before: whole-page skeleton; after: chrome + section skeletons; resolved: unchanged) and the three invariants (no first-run flash; provisioning/redirect states unchanged; admin-nav/banner in initial HTML).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `middleware.ts` runs `getUser()` concurrently with the revocation leg and emits `Server-Timing` stage durations (`mw-auth`, `mw-revoke`, `mw-tc`) on authenticated document responses.
- [ ] A second authenticated request for the same `(jwt sub, iat)` within `MW_VERDICT_TTL_MS` performs **zero** `check_my_revocation` RPC calls; a `revoked=true` verdict is never served from cache.
- [ ] A `users`-row fetch is skipped for a warm `(user.id, tc_accepted_version === TC_VERSION, non-unpaid)` entry; a `TC_VERSION` bump, an `unpaid` row, and a `tcError` are never cached — every deny path re-queries.
- [ ] `x-soleur-auth-user-id` is deleted from inbound headers before any early return and set after `getUser()`; a vitest proves a `withUserRateLimit` handler observes it on a middleware-traversed request, and that a client-supplied value is stripped.
- [ ] `withUserRateLimit` performs no `getUser()` when the header is present and still 401s unauthenticated callers via the `getUser()` fallback when it is absent.
- [ ] `resolveIdentity`'s `users` and `workspace_members` selects run in parallel; `createClient()` is `cache()`-wrapped so the identity resolution dedupes across the layout chain in one render pass (assert via a single `getUser` invocation in the render test).
- [ ] `/dashboard` renders the shell + Today region + filter bar + conversation skeletons without waiting for `/api/dashboard/foundation-status` (jsdom: the page body is present while the foundation fetch is pending).
- [ ] Neither the first-run state nor the command-center empty state renders while `foundationData === undefined` or while the first conversation fetch is in flight — no first-run flash for existing users (Guards + jsdom tests).
- [ ] Dashboard chrome renders `isAdmin` nav items, user email, and the payment-banner state from the initial server render — `/api/admin/check` and the `getSession`→`users` mount effects are deleted from the shell.
- [ ] `useConversations` issues no duplicate `/api/workspace/active-repo` request (shared SWR key) and no `auth.getUser()` browser RTT (`getSession` for the id read); the realtime `workspaceId` transition and `shouldDropForScope` are unchanged.
- [ ] ADR-253 authored and committed in this PR; C4 files verified no-change with the enumeration recorded.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; `node node_modules/vitest/vitest.mjs run` green for touched suites (middleware.*, with-user-rate-limit, identity, request-auth, dashboard-layout-*, dashboard page).

### Post-merge (verification — automatable; bake into `soleur:ship` post-merge checks, no operator step)

- [ ] `curl -s -o /dev/null -D - https://app.soleur.ai/dashboard` on an authenticated session shows `Server-Timing` headers carrying `mw-auth`, `mw-revoke`, `mw-tc` durations; repeat request shows `hit` descriptors on the cached stages. Requires an authenticated browser session/cookie — if none is available at ship time this degrades to a documented Playwright-authenticated check, not an operator step.
- [ ] Playwright waterfall capture (authenticated) shows first meaningful content ≲500 ms on a cold `/dashboard` load; capture attached to the PR body or the closing comment on #5654.

## Test Scenarios

- Given an authenticated warm-cache request, when middleware runs, then exactly one Supabase round-trip occurs (`getUser`) and revocation + T&C verdicts come from cache — asserted by mock call counts in `middleware.test.ts`.
- Given `check_my_revocation` returns `revoked=true`, when the request runs, then the user is redirected to `/login` with cleared `sb-*` cookies — identical to today (`middleware.revocation-redirect.test.ts` extended with a warm-cache variant).
- Given the revocation RPC errors, when the request runs, then it graces through AND nothing is written to the verdict cache (next request re-queries) — `middleware.fail-closed.test.ts` + new no-cache-on-error case.
- Given a cached T&C row and a bumped `TC_VERSION`, when the next request runs, then the user is redirected to `/accept-terms` (version compare at read time, not at store time).
- Given a user who just POSTed `/api/accept-terms`, when they land on `/dashboard`, then no stale bounce occurs — because the pre-acceptance row was never cacheable (store predicate required `tc_accepted_version === TC_VERSION`).
- Given a request carrying a forged `x-soleur-auth-user-id`, when middleware runs, then the inbound value is deleted before any path can forward it — including on PUBLIC_PATHS (Guard 1 row 5).
- Given a matcher diff that excludes an `/api` route, when the coverage test runs, then it fails (Guard 1).
- Given `foundationData === undefined` and conversations still loading, when `/dashboard` renders, then neither first-run nor command-center mounts — the inbox shell + skeletons render instead.
- Given `visionExists === false`, zero conversations, and both fetches resolved, when `/dashboard` renders, then the first-run state appears exactly once (no intermediate wrong state).
- Given an admin user, when the dashboard layout server-renders, then `ADMIN_NAV_ITEMS` markup is present in the SSR HTML before hydration.

## Downtime & Cutover

No offline-inducing operation: no infra change, no migration, no router/tunnel change. Deployment rides the standard `web-platform-release.yml` path (merge → image build → container swap), identical in risk profile to every routine `apps/web-platform/**` merge — no drain design is introduced by this diff. Rollback is a plain `git revert` (in-process caches carry no state to drain). The only behavioral window is the container restart itself, already governed by the existing release pipeline.

## Dependencies & Risks

- **Bounded-staleness security trade-off** (primary risk): a removed/role-changed member can ride a cached `revoked=false` for ≤30 s; RLS (`is_workspace_member`, `messages_workspace_member_select`) remains the authoritative data boundary and denies them regardless — but the UX-level bounce delays by ≤ TTL. Mitigations: TTL kept at 30 s (not the ~1 h JWT validity the gate was designed against), positive-only caching, ADR-253 records the acceptance, security-sentinel review at PR time is mandatory.
- **Header trust boundary**: a future matcher narrowing or an early-return path that leaks an unstripped header would make `x-soleur-auth-user-id` client-forgeable to migrated handlers. Mitigations: Guard 1 (matcher coverage) + Guard 1 row 5 (delete-before-any-return) + the `getUser()` fallback keeps the header advisory, never sole-authoritative.
- **`NextResponse.next` header-snapshot ordering** — confirmed at `next@16.3.6` (`handleMiddlewareField` copies `init.request.headers` into `x-middleware-request-*` at construction): the `next()` response must be (re-)constructed after `x-soleur-auth-user-id` is set, and the propagation vitest is the load-bearing proof. Also: the parallel revocation leg must be `Promise.allSettled`/`catch`-armed — an un-awaited rejected promise on a redirecting path is an unhandled rejection.
- **`resolveIdentity` callers see a wider `Identity`** (additive `email`/`subscriptionStatus`) — consumer grep done at plan time; `tsc` is the gate.
- **CI-mock hang interplay** (the 2026-04-10 learning): re-adding `!loading` to the first-run branch could strand first-run behind a hung conversations fetch in mocked e2e — mitigated because command-center assertions are unaffected and the first-run tests resolve their conversation mocks; flagged for the work phase to verify `start-fresh-onboarding.test.tsx` still passes.
- **Rollback**: single `git revert` of the PR — the caches are in-process (nothing to drain, no schema, no migration); the header is additive with a fallback, so a partial revert of Phase 2 alone also works.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled (threshold = `single-user incident`, `requires_cpo_signoff: true` set).
- Do NOT weaken the fail-closed arms while reordering: `revoked === true` bounce, `tcError` → `/accept-terms` redirect, `tc_accepted_version !== TC_VERSION` redirect, and `unpaid` 403 all keep per-request freshness — only *passing* verdicts are cached.
- The `requestHeaders.delete("x-soleur-auth-user-id")` must precede the PUBLIC_PATHS early return and every `NextResponse.next({ request: { headers: requestHeaders } })` construction — delete-once-at-construction is the only ordering that covers all exits.
- `getSession()` is local in this client (cookie read) — do not "fix" it into `getUser()` for the revocation leg; the `iat` decode needs token bytes, not another auth RTT (the existing comment at the call site documents this).
- Do not widen `Identity` non-additively — `ANON_IDENTITY` must keep literal `null` for the new fields, and `server.test.ts`/`identity.test.ts` fixtures need the fields added (they `toEqual`-compare).
- The `use-conversations` hook's realtime subscription keys on the `workspaceId` null→id transition — the SWR-sourced `active-repo` value must still drive that transition in the same order; do not parallel-mount the realtime effect ahead of repo resolution.
- `cq-silent-fallback-must-mirror-to-sentry`: all existing `reportEdgeSilentFallback` call sites stay; the cache is not a silent fallback (it is the designed path), but a *suppressible* error (e.g. swallowing `revokeError` behind a stale hit) would be — the positive-only design structurally prevents it.
- Preserve the file's leading no-op comment block (the live-verify gate exercise marker, PR #5488) verbatim when editing `middleware.ts`.

## References

- Issues: #5531, #5532, #5533, #5654 (closed by this plan); #3931, #5644, #5535, #5536, #2590, #2591, #2193, #3564 (related/left open)
- Prior plan: `knowledge-base/project/plans/2026-07-07-perf-dashboard-load-and-conversation-list-plan.md` (shipped `list_conversations_enriched` + `foundation-status`; deferred its Phase 3 middleware work — this plan is that follow-up)
- ADRs: ADR-067 (SWR cache), ADR-044 (workspace/active-repo ownership), ADR-033 (JWT substrate), ADR-047 (layout collapse authority), ADR-029 (rename-at-boundary)
- Learnings: `2026-03-20-middleware-error-handling-fail-open-vs-closed.md`, `2026-05-29-middleware-tc-gate-does-not-fire-for-public-paths.md`, `2026-04-10-dashboard-onboarding-state-independent-of-conversation-loading.md`, `2026-03-20-middleware-prefix-matching-bypass.md`
- Wireframe: `knowledge-base/product/design/dashboard/dashboard-load-states.pen`
- External: Next.js middleware request-header forwarding (`NextResponse.next({ request: { headers } })`, stable since v13); Supabase `getClaims()`/JWKS docs (asymmetric-keys-only local verification)
