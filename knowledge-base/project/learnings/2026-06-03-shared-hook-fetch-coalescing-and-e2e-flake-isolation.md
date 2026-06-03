# Learning: shared-hook fetch fan-out, coalescing test-races, and isolating e2e infra flakes from real regressions

## Problem

Folding the dashboard "Working on: {repo}" row into the workspace pill required a
shared `useActiveRepo()` hook consumed by BOTH `OrgSwitcherContainer` and
`LiveRepoBadge`. The dashboard band mounts TWICE (CSS-exclusive mobile + rail),
so two consumers × two bands = **4 uncoordinated pollers** of
`/api/workspace/active-repo` — a 2–4 round-trip endpoint that issues a corrective
RPC *write* on the J5 (access-revocation) path. Four agents independently flagged
this as a 2× regression with 4 racing corrective writes.

Two downstream snags surfaced while fixing it:
1. The new J5 re-arm regression test raced the fetch-coalescing latch.
2. The blocking structural-UI e2e gate (`nav-states-shell.e2e.ts`) "failed" 7/16
   then 2/9 — a *different* failing set each run.

## Solution

**Fetch fan-out → module-level in-flight coalescing.** When a `useState`+`useEffect`
fetch hook is consumed by N always-mounted components, a naive per-instance fetch
multiplies requests (and any side-effecting writes the endpoint performs). Coalesce
concurrent callers behind a module-level `inFlight` promise that self-clears in
`finally`; every caller awaits the same request and sets its own state from the
result. This keeps the hook outside the `nav-single-mount.test.ts` component-import
guard (a hook is not a component) while restoring a single fetch/write per
mount/focus. Export a `__resetActiveRepoCoalesceForTests()` so a deliberately
never-resolving fetch stub in one test cannot poison the latch for the next.

**Coalescing test-race.** A `vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(N))`
passes the instant `fetch` is *called* — synchronously, before the body settles —
so firing the next event immediately coalesces it into the still-in-flight request
and the intended next response is never consumed. Gate the next event on a
*body-settle* signal: attach `.finally(() => { committed = true })` to the relevant
mock's `json()` promise and `waitFor` on `committed`, not on call-count. Reset the
coalescing latch between simulated focus events (in prod they're seconds apart, so
the latch is always clear).

**Isolating an e2e infra flake from a real regression.** The structural-UI gate's
failures were all `Target page/browser has been closed` / `goto Timeout` cascades,
and the **failing set was non-deterministic across reruns** (tests that failed run 1
passed run 2). That signature ⇒ infrastructure, not a diff regression. Root cause:
`e2e/mock-supabase.ts` sets `MOCK_USER.id = "test-user-id"` (not a UUID); a dashboard
websocket connect calls `ws-handler.ts tenantFor("test-user-id")` →
`getFreshTenantClient` → `getUserById` → `@supabase/auth-js: Expected parameter to be
UUID`. That error is NOT a `RuntimeAuthError`, so `tenantFor` re-throws it (line 152),
and in the WS path it becomes a process-killing `unhandledRejection`. To clear a
genuine regression vs flake: re-run, and if the failing set changes AND the errors are
`browser closed`/`goto timeout` (not assertion mismatches), it's infra — then confirm
the in-scope assertions (the ones your diff affects) pass deterministically across runs.

## Key Insight

- A hook shared by multiple always-mounted components multiplies every request the
  endpoint serves — and every *write* it performs. Coalesce at the hook's module
  scope; don't rely on a component-import single-mount guard to catch hook-level fan-out.
- `waitFor(callCount)` is a *call* signal, not a *settle* signal. For
  fetch-coalesced hooks, wait on a body-settle flag before firing the next event.
- A non-deterministic failing set + `browser closed`/`goto timeout` errors = e2e
  infra flake, not a diff regression. Verify by checking that the assertions your
  diff actually touches pass across reruns.

## Session Errors

1. **e2e structural-UI gate flaked (`unhandledRejection: Expected parameter to be
   UUID` in `ws-handler.ts tenantFor`).** Recovery: re-ran the gate, observed a
   non-deterministic failing set with `browser closed`/`goto timeout` cascades,
   isolated the in-scope identity-band assertions which passed in both runs.
   **Prevention:** follow-up PR makes `tenantFor` fail-open to `null` on a
   malformed-UUID `userId` (a non-UUID can never resolve a tenant) so it can never
   become an uncaught `unhandledRejection`; complementary fixture fix makes
   `MOCK_USER.id` a real UUID. This is a different subsystem from the sidebar
   feature, so it ships as its own PR (scope discipline).

2. **New J5 re-arm test raced the coalescing latch (failed twice).** Recovery:
   gated the second focus event on a `.finally()` body-settle flag and reset the
   latch between events. **Prevention:** captured inline as a test comment + the
   "wait on settle, not call-count" insight above; route a one-line bullet to the
   `work` skill's vitest sharp-edges.

## Tags
category: integration-issues
module: web-platform/dashboard-nav
