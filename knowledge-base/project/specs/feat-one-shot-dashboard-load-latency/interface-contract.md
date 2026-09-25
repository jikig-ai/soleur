# Interface Contract — perf-dashboard-section-load-latency

Plan: `knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md` (read it fully — ACs, Guard Contract, Sharp Edges are binding).

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `apps/web-platform/middleware.ts`; `apps/web-platform/server/request-auth.ts` (new); `apps/web-platform/server/with-user-rate-limit.ts`; `apps/web-platform/lib/supabase/server.ts`; `apps/web-platform/lib/feature-flags/identity.ts`; `apps/web-platform/app/layout.tsx` (comment only); `apps/web-platform/app/api/admin/check/route.ts`; `apps/web-platform/app/api/dashboard/today/route.ts`; `apps/web-platform/app/api/workspace/active-repo/route.ts`; `apps/web-platform/app/(dashboard)/layout.tsx`; `apps/web-platform/app/(dashboard)/dashboard-shell.tsx` (new); `apps/web-platform/app/(dashboard)/dashboard/page.tsx`; `apps/web-platform/hooks/use-conversations.ts`; `apps/web-platform/hooks/use-onboarding.ts`; `apps/web-platform/components/dashboard/conversations-nav-badge.tsx`; `apps/web-platform/components/dashboard/payment-warning-banner.tsx` (new) |
| Agent 2 (Tests) | `apps/web-platform/test/middleware.test.ts`; `apps/web-platform/test/middleware.fail-closed.test.ts`; `apps/web-platform/test/middleware.revocation-redirect.test.ts`; `apps/web-platform/test/middleware.no-store.test.ts`; `apps/web-platform/test/with-user-rate-limit.test.ts`; `apps/web-platform/test/server/request-auth.test.ts` (new); `apps/web-platform/test/server/middleware-matcher-coverage.test.ts` (new — Guard 1); `apps/web-platform/test/host-identity.test.ts` (+ any identity fixture files); `apps/web-platform/test/dashboard-layout-*.test.tsx`; `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`; `apps/web-platform/test/conversations-nav-badge.test.tsx`; `apps/web-platform/test/conversations-active-repo-scope.test.tsx`; `apps/web-platform/test/use-conversations-*.test.tsx`; `apps/web-platform/test/command-center*.test.tsx`; `apps/web-platform/test/foundation-*.test.tsx`; `apps/web-platform/test/start-fresh-onboarding.test.tsx`; `apps/web-platform/test/onboarding-*.test.tsx`; `apps/web-platform/test/disconnect-hides-conversations.test.ts` |

Neither agent touches: version triad files, ADR files, plan/spec docs (lead owns).

## Public Interfaces

### `apps/web-platform/server/request-auth.ts` (new)

```ts
export async function verifiedUserId(req: Request): Promise<string | null>;
// Reads req.headers.get("x-soleur-auth-user-id"); returns it when non-empty.
// When absent/empty: falls back to (await createClient()).auth.getUser() and returns user?.id ?? null.
// Absent header NEVER trusts anything — fallback is the fail-closed direction.
```

### `apps/web-platform/server/with-user-rate-limit.ts`

```ts
type Handler = (req: Request, user: { id: string }) => Promise<Response>;
// narrowed from (req, user: User). verifiedUserId(req) replaces createClient()+auth.getUser().
// Behavior unchanged: 401 when null, 429 over budget, Sentry isolation scope + setUser unchanged.
```

### `apps/web-platform/middleware.ts` (behavior contract)

- `const MW_VERDICT_TTL_MS = 30_000` (module scope). Two `LRUCache` instances reusing `apps/web-platform/lib/feature-flags/lru-cache.ts`:
  - `revocationOkCache: LRUCache<string, true>` — key `"${jwtSub}:${iatSeconds}"` (both from the LOCAL JWT decode of the access token). Only `revoked === false` is stored — never `true`, never errors, never decode failures.
  - `tcRowCache: LRUCache<string, { tc_accepted_version: string | null; subscription_status: string | null }>` — key `user.id`. Stores only rows where `tc_accepted_version === TC_VERSION && subscription_status !== "unpaid"`. A cache read is honored only if `entry.tc_accepted_version === TC_VERSION` (version bump self-invalidates).
- `requestHeaders.delete("x-soleur-auth-user-id")` runs immediately after `const requestHeaders = new Headers(request.headers)` — BEFORE the PUBLIC_PATHS early return and before any `NextResponse.next({ request: { headers: requestHeaders } })` construction. After `getUser()` resolves a user, `requestHeaders.set("x-soleur-auth-user-id", user.id)` runs before the `NextResponse.next(...)` that carries the request forward is (re-)constructed (Next 16 snapshots `init.request.headers` into `x-middleware-request-*` at `next()` construction).
- Parallelism: the revocation leg (local `iat`/`sub` decode → cache check → `check_my_revocation` RPC on miss) starts concurrently with `getUser()` once token bytes exist (hoist `getSession()` before `getUser()`); join via `Promise.allSettled`/armed `.catch` so a redirecting path never leaves an unhandled rejection. The T&C `users` select still requires a verified `user` but may overlap the revocation leg's tail.
- All existing semantics preserved verbatim: `revoked === true` → clearSessionAndRedirect; RPC error / decode hiccup → grace + `reportEdgeSilentFallback` (op slugs unchanged); `tcError` → `/accept-terms` redirect; `tc_accepted_version !== TC_VERSION` → redirect; `unpaid` non-GET → 403 JSON; `!user` → `/login` redirect; PUBLIC_PATHS early return; bfcache `no-store` logic; CSP on every response.
- `Server-Timing` on authenticated document responses (success path only): `mw-auth;dur=<ms>`, `mw-revoke;dur=<ms>;desc=<hit|miss|grace>`, `mw-tc;dur=<ms>;desc=<hit|miss|grace|exempt>`.

### `apps/web-platform/lib/supabase/server.ts`

`createClient` exported wrapped in React `cache()` — same signature `( ) => Promise<SupabaseClient>`; per-request memoization only.

### `apps/web-platform/lib/feature-flags/identity.ts`

```ts
export interface Identity {
  userId: string | null;
  role: string | null;
  orgId: string | null;
  email: string | null;            // NEW — from userData.user.email
  subscriptionStatus: string | null; // NEW — from the users select (extended to role, subscription_status)
}
// ANON_IDENTITY keeps literal null for the new fields.
// resolveIdentity: after getUser(), the users select and workspace_members select run in Promise.all.
```

### `apps/web-platform/app/(dashboard)/` split

- `layout.tsx` → `export default async function DashboardLayout({ children })` server component: resolves identity via `resolveIdentity(await createClient())`; derives `isAdmin` via `process.env.ADMIN_USER_IDS?.split(",").includes(identity.userId)`; renders `<DashboardShell isAdmin userEmail subscriptionStatus>{children}</DashboardShell>`.
- `dashboard-shell.tsx` (new, `"use client"`): today's `DashboardLayout` component body verbatim with props `{ isAdmin: boolean; userEmail: string | null; subscriptionStatus: string | null; children: React.ReactNode }`. The `/api/admin/check` mount effect and the `getSession()`→`users` select effect are DELETED (props replace them).
- `components/dashboard/payment-warning-banner.tsx` (new): `PaymentWarningBanner` moved verbatim out of layout.tsx.

### `apps/web-platform/app/(dashboard)/dashboard/page.tsx` gating

- `isRedirecting401` and `provisioning` keep whole-page states. No `kbLoading` whole-page early return.
- First-run branch renders only when `foundationData !== undefined && !loading` (conversations resolved) AND the existing first-run predicates.
- Command-center-empty branch requires `foundationData !== undefined`.
- Foundation section: `FoundationSection` only when `visionExists && !allTasksComplete`; render a fixed-height shimmer while `foundationData === undefined && conversations.length > 0`.

### `apps/web-platform/hooks/use-conversations.ts`

- Active-repo leg: `useSWR(swrKeys.workspaceActiveRepo(), jsonFetcher)` replaces the internal `fetch("/api/workspace/active-repo")`; the `Failed to resolve the active repository` error path preserved.
- The `supabase.auth.getUser()` id read → `supabase.auth.getSession()` (`session?.user?.id`). Same for `hooks/use-onboarding.ts` and `components/dashboard/conversations-nav-badge.tsx` id-only reads.
- Realtime `workspaceId` null→id transition and `shouldDropForScope` unchanged.

## Test-writing notes for Agent 2

- Suites mock `@/lib/supabase/server` or `@supabase/ssr` — preserve the existing mock chain shapes (`createServerClient` mock with `auth.getUser`/`auth.getSession`/`rpc`/`from` spies; see current `middleware.test.ts`).
- Route-level tests that invoke handlers without middleware rely on `verifiedUserId()`'s absent-header `getUser()` fallback — keep that path exercised.
- New cases (per plan §Test Scenarios + §Guard Contract): warm revocation cache → zero RPC; revoked=true never cached; RPC error graces + never cached; T&C warm hit skips select; TC_VERSION bump ignores cached row; unpaid/tcError never cached; forged inbound `x-soleur-auth-user-id` stripped incl. on PUBLIC_PATHS; `withUserRateLimit` uses header when present (no getUser call) and falls back + 401 when absent; matcher-coverage walk over `app/api/**/route.ts` against `config.matcher`; `Promise.all` identity selects (assert getUser called once across layout chain); foundation-pending page renders inbox shell (no first-run/command-center); admin SSR HTML contains ADMIN_NAV_ITEMS.
