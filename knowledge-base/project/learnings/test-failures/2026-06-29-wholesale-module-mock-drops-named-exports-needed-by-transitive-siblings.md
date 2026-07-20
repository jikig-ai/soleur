# Learning: A wholesale `vi.mock("<module>", () => ({...}))` drops named exports that transitive sibling modules need

## Problem

Implementing #5689 item 2, I added a stub for the pino module logger to
`cron-workspace-sync-health.test.ts`:

```ts
vi.mock("@/server/logger", () => ({ default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));
```

The RED run failed **10 pre-existing, unrelated** arm-2 ("stale-sync-failed")
tests with:

```
[vitest] No "createChildLogger" export is defined on the "@/server/logger" mock.
  ❯ server/github/probe-octokit.ts:30:13
  ❯ server/inngest/functions/_cron-shared.ts:3:1
```

Root cause: a **wholesale factory mock replaces the ENTIRE module**, so every
export the factory does not list disappears. `@/server/logger` exports both a
`default` (the pino instance) AND named exports like `createChildLogger`, and a
real sibling module in the SUT's import graph (`probe-octokit.ts`, reached
transitively via `_cron-shared.ts` → the cron handler) imports `createChildLogger`.
My factory listed only `default`, so that real consumer broke at module-init.

## Solution

The thing under test (`syncWorkspace`) was itself mocked, so the module logger
arg the cron passes to it is **never exercised** in tests. The fix was to **not
mock the logger at all** — let the real module load (it already loads in the real
graph). For the two other new module mocks I converted them to preserve all other
exports:

```ts
vi.mock("@/server/workspace-sync", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/workspace-sync")>();
  return { ...actual, syncWorkspace: (...a) => syncWorkspaceSpy(...a) };
});
```

## Key Insight

Before adding a wholesale `vi.mock("<module>", () => ({...}))` for any module
with **multiple named exports** (logger, observability, db-helper, supabase
wrappers), check whether real sibling modules in the SUT's import graph consume
OTHER exports of it. Default to `vi.mock(spec, async (importOriginal) => ({
...await importOriginal(), <override> }))`; reserve a wholesale factory for
modules you fully own/replace. If the thing under test already mocks the
*consumer* of the export, you may not need to mock the module at all.

Detection is free: **run the FULL test file**, not just `-t "<new test>"`. The
RED run surfaced the 10 sibling failures immediately, each naming the missing
export — a `-t` filter would have hidden them until the full-suite exit gate.

### Sharp sub-case: `importOriginal`+spread does NOT restore `@sentry/nextjs` getter re-exports

The "default to `importOriginal`+spread" fix above has an exception for modules
that expose named exports via **getters / `export *` re-exports** rather than
own-enumerable properties — `@sentry/nextjs` is the canonical one.
`{ ...(await importOriginal()) }` copies only own-enumerable keys, so
getter-based re-exports (`addBreadcrumb`, most of the SDK surface) silently drop
and a transitive sibling (here the rate-limiter's `Sentry.addBreadcrumb` at
`server/rate-limiter.ts`) still fails with `No "addBreadcrumb" export is defined
on the "@sentry/nextjs" mock`. Fix: **enumerate the specific methods the file's
code paths reach explicitly**, no spread:

```ts
vi.mock("@sentry/nextjs", () => ({
  captureException: (...a: unknown[]) => captureException(...a),
  addBreadcrumb: vi.fn(), // transitive: rate-limiter rejection log
}));
```

Detection is the same free move — run the FULL test file; the transitive-sibling
test names the missing method. (Encountered wiring a `captureException` spy for a
workstream route degrade test, PR for the workstream degraded-read fix.)

## Session Errors

1. **Wholesale `@/server/logger` mock dropped `createChildLogger`** — broke 10
   transitive-sibling tests. **Recovery:** removed the logger mock (consumer
   already mocked) + `importOriginal`+spread on the other two new module mocks.
   **Prevention:** the Key Insight above, routed to work SKILL.md's vi.mock
   Sharp Edges.

## Tags
category: test-failures
module: vitest, cron-workspace-sync-health
related: 2026-06-29-brainstorm-soak-gated-tracker-item-and-grep-helper-sig-before-accepting-obstacle.md
issue: 5689
