# Tasks — perf: collapse per-request auth waterfall and unblock dashboard first paint

Plan: `knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md`
Closes: #5531, #5532, #5533, #5654

## Phase 0 — Baseline instrumentation

- [x] 0.1 Add per-stage `Server-Timing` emission on authenticated document responses in `apps/web-platform/middleware.ts` (`mw-auth`, `mw-revoke`, `mw-tc`, with `;desc=hit|miss|grace` where applicable).
- [x] 0.2 Capture the pre-change waterfall (Playwright trace or curl timing table) and record it in the PR body for before/after comparison.

## Phase 1 — Middleware auth chain

- [x] 1.1 Hoist the `getSession()` local read ahead of `getUser()`; kick off the revocation leg (JWT `iat` decode → `check_my_revocation` RPC, token-gated) as a promise and `Promise.all` it with `getUser()`. Preserve every existing redirect/cookie-clear/`reportEdgeSilentFallback` arm verbatim.
- [x] 1.2 Add the two positive-only `LRUCache` verdict caches (`MW_VERDICT_TTL_MS = 30_000`, reusing `lib/feature-flags/lru-cache.ts`): revocation keyed `"${user.id}:${iatSeconds}"` storing only `revoked === false`; T&C/billing keyed `user.id` storing only fully-passing rows, read-time version check against `TC_VERSION`.
- [x] 1.3 Immediately after `const requestHeaders = new Headers(request.headers)` (before the PUBLIC_PATHS early return), `delete` inbound `x-soleur-auth-user-id`; after `getUser()` resolves a user, `set` it on `requestHeaders`. Verify propagation through the `NextResponse.next({ request: { headers } })` response — re-issue `next()` after auth resolves if Next snapshots headers.
- [x] 1.4 Tests: extend `middleware.test.ts`/`middleware.fail-closed.test.ts`/`middleware.revocation-redirect.test.ts` with warm-cache, no-cache-on-error, no-cache-on-revoked, TC_VERSION-bump, and forged-header cases.

## Phase 2 — Handler-side verified identity

- [x] 2.1 Create `apps/web-platform/server/request-auth.ts` — `verifiedUserId(req)` reads the header, falls back to `createClient().auth.getUser()` when absent.
- [x] 2.2 `server/with-user-rate-limit.ts`: replace the `getUser()` call; narrow `Handler` to `(req, user: { id: string })`.
- [x] 2.3 Migrate `app/api/admin/check/route.ts`, `app/api/dashboard/today/route.ts`, `app/api/workspace/active-repo/route.ts` to `verifiedUserId()` (keep their own clients for data queries).
- [x] 2.4 Create `test/server/request-auth.test.ts` (header present / absent→fallback / forged-inbound) and update `with-user-rate-limit` tests.
- [x] 2.5 Matcher-coverage guard test: glob-walk `app/api/**/route.ts`, evaluate each path against `config.matcher`, assert all covered (Guard 1) + delete-before-any-return ordering assertion.

## Phase 3 — Root-layout identity dedupe

- [x] 3.1 `lib/supabase/server.ts`: wrap `createClient` in React `cache()`.
- [x] 3.2 `lib/feature-flags/identity.ts`: `Promise.all` the `users` + `workspace_members` selects; extend `Identity` with `email`, `subscriptionStatus`; update `ANON_IDENTITY` and fixtures.
- [x] 3.3 `app/layout.tsx`: add the documented-reason comment for `await headers()` (CSP nonce, #1213).
- [x] 3.4 Update `server.test.ts`/`identity.test.ts` fixtures for the widened `Identity`.

## Phase 4 — Dashboard first-paint ungate (#5654)

- [x] 4.1 `app/(dashboard)/dashboard/page.tsx`: remove the `kbLoading` whole-page early return; gate first-run on `foundationData !== undefined && !loading`; gate command-center-empty on `foundationData !== undefined`; render fixed-height foundation-section shimmer while `foundationData === undefined && conversations.length > 0`. Keep `isRedirecting401` and `provisioning` whole-page states.
- [x] 4.2 jsdom tests: foundation-pending renders inbox shell (no first-run/command-center); resolved empty state renders correct branch exactly once.

## Phase 5 — Conversation waterfall dedupe (#5533)

- [x] 5.1 `hooks/use-conversations.ts`: `useSWR(swrKeys.workspaceActiveRepo(), jsonFetcher)` replaces the internal `fetch('/api/workspace/active-repo')`; `auth.getSession()` replaces `auth.getUser()` for the id read.
- [x] 5.2 `hooks/use-onboarding.ts` + `components/dashboard/conversations-nav-badge.tsx`: `getUser` → `getSession`.
- [x] 5.3 Verify realtime `workspaceId` transition and `shouldDropForScope` unchanged.

## Phase 6 — Dashboard chrome server-render (#5532)

- [x] 6.1 `app/(dashboard)/layout.tsx` → async server component resolving `resolveIdentity` (deduped) and deriving `isAdmin`/`userEmail`/`subscriptionStatus` props.
- [x] 6.2 Create `app/(dashboard)/dashboard-shell.tsx` (`"use client"`) — move the existing component body verbatim; delete the `/api/admin/check` and `getSession`→`users` mount effects.
- [x] 6.3 Create `components/dashboard/payment-warning-banner.tsx`; update importing tests (`dashboard-layout-banner.test.tsx` et al.).
- [x] 6.4 jsdom/e2e check: `ADMIN_NAV_ITEMS` + banner state present in SSR HTML.

## Phase 7 — Docs & verification

- [x] 7.1 Author `knowledge-base/engineering/architecture/decisions/ADR-253-*.md` per plan §Architecture Decision.
- [x] 7.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + `node node_modules/vitest/vitest.mjs run` for touched suites.
- [x] 7.3 Post-merge: authenticated `Server-Timing` probe + Playwright waterfall ≲500 ms capture (plan §Acceptance Criteria → Post-merge).
- [x] 7.4 File the follow-up sweep issue for migrating the remaining ~70 `getUser()` route call sites to `verifiedUserId()`.
