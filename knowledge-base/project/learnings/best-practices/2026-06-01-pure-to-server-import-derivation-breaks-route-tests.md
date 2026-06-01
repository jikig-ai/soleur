---
module: web-platform/kb
date: 2026-06-01
problem_type: test_failure
component: nextjs_route
symptoms:
  - "Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL in a route-handler test"
  - "touched-file test run green but full-suite exit gate red"
  - "route test reaches a real Supabase client after a derivation change"
root_cause: unmocked_dynamic_import
severity: medium
tags: [vitest, vi-mock, dynamic-import, full-suite-exit-gate, mock-sweep, test-blast-radius]
synced_to: [work]
---

# Learning: switching a route's derivation from pure → server-importing breaks every route test that exercised the old pure path

## Problem

PR #4737 changed the KB reconnect-banner signal. The `/api/kb/tree` route and the
settings page previously derived `needsReconnect` from the **pure** synchronous
helper `repoNeedsReconnect(repo_status, github_installation_id)`. The fix replaced
that with a new **async** `resolveNeedsReconnect(repoStatus, userInstallationId, userId)`
that, for the `ready + NULL user-install` cohort, lazy-imports a server-only module:

```ts
const { resolveInstallationId } = await import("@/server/resolve-installation-id");
const wsInstall = await resolveInstallationId(userId); // pulls the Supabase tenant client
```

The touched-file test run was **green** — the pure `test/lib/repo-status.test.ts`
and the new `test/lib/resolve-needs-reconnect.test.ts` (which mocks the module)
both passed. But `test/api/kb-tree.test.ts` — an *orphan* relative to the touched
file set — failed:

```
Error: Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL
 ❯ resolveInstallationId server/resolve-installation-id.ts:35:26
 ❯ resolveNeedsReconnect lib/repo-status.ts:57:27
```

Its `ready + null-install` case used to exercise a synchronous pure boolean; after
the change it reached the dynamic import and tried to instantiate a real Supabase
client. The break only surfaced when the work-phase **full-suite exit gate** ran
every consumer of the signal (`grep -rln "needsReconnect" test/`), not the
touched-file inner loop.

## Solution

Add the module mock to the orphan route test in the same change:

```ts
const { mockResolveInstallationId } = vi.hoisted(() => ({ mockResolveInstallationId: vi.fn() }));
vi.mock("@/server/resolve-installation-id", () => ({ resolveInstallationId: mockResolveInstallationId }));
// ...
beforeEach(() => {
  vi.clearAllMocks();
  mockResolveInstallationId.mockResolvedValue(null); // default = safe "freeze/alarm" shape
});
```

`vi.mock` intercepts both static AND dynamic `import()` of the specifier, so the
route's `await import("@/server/resolve-installation-id")` resolves to the mock.
Default the mock to the conservative shape in `beforeEach` so a test that forgets
to set it fails toward the alarm, never toward a real client call.

## Key Insight

When a derivation a route/page depends on switches from a **pure** helper to one
that imports a **server-only** module (static OR dynamic import), the change's
blast radius is not the files you edited — it is **every route-handler/page test
that exercised the old pure path**. Those tests never needed the server-module
mock before, so they are orphans relative to the touched-file set and pass the
inner loop. Sweep them with `grep -rln "<signal-or-helper>" test/` and add the
new module mock in the same edit cycle; rely on the **full-suite exit gate** (not
the touched-file run) to catch the orphan. Same family as
[[2026-04-27-wrapper-extension-test-mock-chain-sweep]] (mock-chain sweep on
wrapper extension) and [[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]]
(grep-enumerated work-lists).

Secondary: a dynamic `import()` inside a `lib/` module bypasses `tsc`'s static
path check, but that tradeoff is acceptable when a test mocks the same specifier —
a path typo then fails the test rather than shipping silently.

## Session Errors

1. **Orphan route test broke after the pure→async derivation swap** — `test/api/kb-tree.test.ts` hit a real Supabase client (`Missing SUPABASE_URL`) because it didn't mock the newly-lazy-imported `@/server/resolve-installation-id`. **Recovery:** added `vi.mock` + `vi.hoisted` for the module, defaulted to `mockResolvedValue(null)` in `beforeEach`. **Prevention:** when a route's derivation switches from a pure helper to one importing a server-only module, `grep -rln "<signal>" test/` and add the module mock to every covering test in the same change; trust the full-suite exit gate over the touched-file run.

2. **JSDoc overclaimed the error contract** — the `resolveNeedsReconnect` comment said "null/error RPC result keeps needsReconnect=true," but the impl has no try/catch, so an unexpected (non-`RuntimeAuthError`) throw *propagates* rather than returning true. Surfaced by test-design review. **Recovery:** tightened the comment to distinguish handled failures (→null→banner stays) from an unexpected throw (→propagates, fail-loud, matching the `kb/sync` precedent), and added a rejection-propagation test. **Prevention:** when a JSDoc asserts a "fail toward X" contract, back it with a test that exercises the failure mode, or word it to match what the code actually does.

## Tags
category: best-practices
module: web-platform/kb
