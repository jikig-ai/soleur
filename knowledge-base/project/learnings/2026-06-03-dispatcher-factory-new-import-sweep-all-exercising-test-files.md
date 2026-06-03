---
title: "Adding a cold-start dep import to a dispatcher factory breaks EVERY test that exercises it — sweep all"
date: 2026-06-03
category: test-failures
module: apps/web-platform/server/cc-dispatcher
tags: [vitest, mocking, dispatcher, cc-soleur-go, test-mock-sweep, full-suite-gate]
---

# Learning: sweep every factory-exercising test when adding a cold-start dependency import

## Problem

PR #4868 (Concierge gh-auth + bash permissions) added three new imports to
`realSdkQueryFactory` in `cc-dispatcher.ts`, all resolved in the cold-start
`Promise.all`: `resolveInstallationId`, `generateInstallationToken` (Issue A
GH_TOKEN mint), and `resolveBashAutonomous` (Issue B part 2 toggle read).

Each of these calls `getFreshTenantClient(...).rpc(...)`. Test files that
exercise the factory mock the tenant client as `{ from: mockSupabaseFrom }`
(no `.rpc`), so the unmocked new deps threw `TypeError` → the factory rejected →
the test broke.

`cc-dispatcher-real-factory.test.ts` broke immediately (caught in Phase 1, fixed
by adding the mocks). But `cc-dispatcher-prefill-guard.test.ts` — a SEPARATE
file that also imports `realSdkQueryFactory` — was NOT updated and only surfaced
when the **work-phase full-suite exit gate** ran (`vitest run` over all 725
files): 10 prefill-guard tests failed identically. A targeted-file test run
would have shipped it green.

## Solution

When adding a new dependency import that a dispatcher/factory resolves in its
cold-start path, enumerate EVERY test file that exercises that factory before
declaring the work done:

```bash
grep -rln "realSdkQueryFactory" test/   # the authoritative work-list
```

Add the new mock (defaulted to the no-op / no-connected-repo / off value) to
each file that constructs the factory — not just the obvious one. Mocks that
default to the inert value keep the unrelated assertions (prefill-guard,
context-reset, factory-shape) unaffected.

## Key Insight

`tsc` is silent on a missing `vi.mock` (the import resolves at type level); only
the runtime suite catches the unmocked-dep throw. And a per-file or
touched-file-only test run is blind to sibling files that import the same
factory. This is the exact failure class the **work Phase 2 full-suite exit
gate** (`scripts/test-all.sh` / `vitest run`) exists to catch — it earned its
keep here: the second broken file had no other signal. Same family as the
existing `cq`/best-practices "wrapper-extension test-mock-chain sweep" rule, but
for a factory's cold-start `Promise.all` rather than a fluent wrapper chain.

## Session Errors

1. **CWD drift across Bash calls** — `./node_modules/.bin/vitest` failed with
   "No such file or directory" because a prior `cd apps/web-platform` did not
   persist as expected. Recovery: prefix every command with an absolute
   `cd <worktree>/apps/web-platform && …`. **Prevention:** already covered by
   the work-skill CWD-drift rule; reinforced — never rely on persisted CWD in a
   worktree pipeline.
2. **Unmocked-import regression in two dispatcher test files** — see Problem.
   Recovery: added the three mocks to both `cc-dispatcher-real-factory.test.ts`
   and `cc-dispatcher-prefill-guard.test.ts`. **Prevention:** the
   `grep -rln "<factory>" test/` sweep above, run at the time the import is added.
3. **Pencil `open_document` blocked on an untracked `.pen`** (the #4855 wipe
   guard). Recovery: `printf '{}' > <file>.pen && git add && git commit` a
   placeholder first, then `open_document`. **Prevention:** when creating a NEW
   `.pen` via Pencil MCP, commit an empty placeholder before opening.
4. **Pencil `$--` design tokens rendered black-on-black** in a fresh tokenless
   `.pen`. Recovery: used explicit hex (`#0B0B0C`, `#F4F1EA`, `#C2410C`).
   **Prevention:** a fresh `.pen` with no brand token set has no `$--*`
   definitions — use explicit hex (or seed a token set) for wireframes.
5. **nav-states structural gate cold-start flake** — first run failed
   `page.goto /dashboard` at the 30s timeout (Next.js dev-server first-route
   compile); warm re-run passed 5/5. **Prevention:** treat a `page.goto` cold
   timeout on the FIRST route as environmental; re-run warm before treating it
   as a regression (the diff did not touch `/dashboard` or the shell).
