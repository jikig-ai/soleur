---
title: "Migrating a shared route helper's data source must sweep the route-level test mocks, not just the helper's own test"
date: 2026-06-05
category: best-practices
tags: [testing, vitest, mocks, adr-044, refactor, resolver-migration]
issue: 4956
pr: 4969
related:
  - knowledge-base/project/learnings/best-practices/2026-04-27-wrapper-extension-test-mock-chain-sweep.md
  - knowledge-base/project/learnings/best-practices/2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes.md
---

# Helper data-source migration must sweep the route-level test mocks

## Problem

#4956 migrated `authenticateAndResolveKbPath` (`apps/web-platform/server/kb-route-helpers.ts`)
off a tenant `users` read onto the ADR-044 service-role resolvers
(`resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta`). The plan's
`## Files to Edit` listed the helper's OWN test (`test/kb-route-helpers.test.ts`)
and updated it correctly — RED→GREEN passed, touched-file suite green, tsc clean.

But the **route handlers** that call the helper (`kb/file` PATCH/DELETE, exercised
by `test/kb-rename.test.ts` + `test/kb-delete.test.ts`) have their OWN test files
that mock the helper's transitive dependencies — they mocked
`getFreshTenantClient` + drove a tenant `users` row via `mockFrom`. After the
migration the helper no longer imports `getFreshTenantClient`; it calls the
(un-mocked-in-those-files) resolvers, which then ran against an incomplete mock
and threw. **33 tests in 2 files failed** — caught only by the Phase 2 exit
full-suite gate (`./node_modules/.bin/vitest run`), NOT by the touched-file
inner loop.

## Solution

When migrating a shared route helper's data-source/credential layer, enumerate
EVERY test that exercises the helper — directly AND through its routes — before
declaring the test edits done:

```bash
git grep -l "<helperName>" -- 'test/**'                 # direct + route-level callers
git grep -l "<oldDependencyImport>" -- 'test/**'        # files mocking the old data source
```

Each route-level test gets the same mock migration as the helper's own test:
replace the old-dependency `vi.mock(...)` with the new one, and translate any
fixture-builder (`setupUserData({overrides})`) so existing call sites keep
working against the new contract. Status-shape changes propagate: the kb/file
"no repository connected" case moved 400→404 (the resolver's status), with the
message preserved — so the assertion flips to the new code while the message
match stays (clients render `body.error`, not the numeric code).

Also sweep stale **citations**: an opt-in integration test
(`test/server/kb-route-helpers.tenant-isolation.test.ts`) documented the
helper's old `users`-read shape in its header/test names. The RLS assertions
stayed valid, but the labels now misled — reframed as a standalone `users`-table
RLS regression guard.

## Key Insight

`## Files to Edit` enumerating "the test for the file I changed" is necessary
but not sufficient. A helper's behavior contract is also asserted by its
**consumers'** tests, which mock the helper's transitive deps. The
cheapest detection is `git grep -l "<helper>" test/` at plan time (add the
route-level test files to Files-to-Edit) — otherwise the full-suite exit gate
catches it after the fact. This is the test-side analogue of
[[2026-04-27-wrapper-extension-test-mock-chain-sweep]] (sweep all supabase mock
chains when extending a wrapper) and the route-side
[[2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes]]
(sweep all write-route consumers when migrating a resolver).

## Session Errors

1. **Route-level test mocks not swept with the helper migration** — Recovery:
   migrated `kb-rename.test.ts` + `kb-delete.test.ts` mocks to the resolvers via
   a `setupUserData` translation shim; flipped the 400→404 assertion.
   Prevention: at plan time, `git grep -l "<helper>" test/` and add every
   route-level test to `## Files to Edit`; the Phase 2 full-suite exit gate is
   the backstop, not the first line of defense.
2. **Plan subagent's initial plan-file Write hit the bare-repo root** (forwarded
   from session-state.md) — Recovery: re-issued with the explicit worktree path.
   Prevention: already enforced by the worktree-write guard (one-off).
3. **`git grep "pat" .`** treated `.` as a revision ("unable to resolve
   revision") — Recovery: dropped the `.` (pathspecs only). Prevention: one-off.
4. **Review agents returned `529 Overloaded`** (6 attempts across 2 batches)
   before 2 succeeded on retry — Recovery: per the review skill's Rate-Limit
   Fallback gate, performed an inline review across the dimensions the
   overloaded agents would have covered, then retried the 2 highest-value lenses
   (security-sentinel + user-impact-reviewer), which both succeeded and returned
   CONCUR / no-real-findings. Prevention: one-off (transient API); the fallback
   gate is the existing mitigation.
