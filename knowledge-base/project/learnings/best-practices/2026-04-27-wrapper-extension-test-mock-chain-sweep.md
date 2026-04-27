# Test mock chain sweep when extending Supabase wrappers

**Date:** 2026-04-27
**PR:** #2959
**Issue:** #2956
**Category:** best-practices

## Problem

PR #2959 introduced `updateConversationFor` — a typed wrapper around
`.from("conversations").update(...).eq("id", ...).eq("user_id", ...)` —
to enforce the R8 composite-key invariant in one place. Two separate
extensions to the wrapper each silently broke the same set of tests:

1. **First migration** (single `.eq` → composite `.eq.eq`) broke 18 tests
   across 6 files. Shared mock helper `test/helpers/agent-runner-mocks.ts`
   modeled `.update().eq() → { error: null }` (a one-shot, not chainable).
   The wrapper's second `.eq("user_id", ...)` call hit `undefined.eq` and
   threw.

2. **Review-driven addition of `expectMatch?: boolean`** added a `.select("id")`
   tail to the chain — broke another 5 tests. Same root cause: shared mock
   modeled `.eq()` as terminal, not as a doorway to `.select(...)`.

Both extensions caught only when the full vitest suite ran. `tsc --noEmit`
was silent because the mock factory returns `{ from: vi.fn() }` typed as
`any` at the supabase mock boundary.

## Root Cause

Test mocks for fluent APIs (Supabase, Drizzle, Knex) tend to be authored
**for the exact chain shape needed at the time of writing**, not as
recursive chains that survive wrapper extensions. Every time the wrapper
gains a new chained method, every mock that intercepts the chain needs
to be updated in the same commit — or the suite breaks at runtime.

This pattern is identical to the React `cq-raf-batching-sweep-test-helpers`
class (introducing `requestAnimationFrame` requires sweeping
`vi.useFakeTimers` setups) and `cq-preflight-fetch-sweep-test-mocks`
(adding a HEAD pre-flight requires sweeping `global.fetch` mocks). It is
the network/DB cousin of the same problem.

## Solution

When extending a Supabase wrapper that's used by hot-path code:

1. **Grep before edit.** Run `rg "vi.mock\\(.*supabase|mockSupabaseFrom|createSupabaseMockImpl" apps/web-platform/test/`
   to find every mock surface that intercepts the chain.

2. **Sweep mocks in the same commit.** For each mock surface, ensure the
   chain is **recursive** by default — each chained call returns the same
   chain object so future extensions resolve transparently:

   ```ts
   const conversationsUpdateChain: Record<string, unknown> = {
     error: null,
     eq: vi.fn(),
     select: vi.fn(() =>
       Promise.resolve({ data: [{ id: "mock" }], error: null }),
     ),
   };
   (conversationsUpdateChain.eq as ReturnType<typeof vi.fn>)
     .mockReturnValue(conversationsUpdateChain);
   ```

3. **Run targeted tests immediately after the mock edit.** `tsc` won't
   catch chain-shape drift; only the full suite does. Skip the temptation
   to defer until "the implementation is done."

4. **Bake the recursive shape into the helper.** Migrate inline copies of
   the mock chain (e.g., the inline copy in `canusertool-tiered-gating.test.ts`)
   to import from `test/helpers/agent-runner-mocks.ts` so future
   extensions only edit one file. Pre-existing duplication on this PR
   was a third (deferred) tax that a single helper would have neutralized.

## Prevention

- **When editing a wrapper module** in `apps/web-platform/server/*-writer.ts`
  (or any future shared-wrapper convention) that calls a fluent API,
  treat the mock chain in `test/helpers/*-mocks.ts` as a tightly-coupled
  artifact. Edit them together.

- **When adding a new chained method to the wrapper** (`.select`, `.in`,
  `.range`, `.maybeSingle`), grep the test directory in the same edit
  cycle. Don't wait for the suite to fail.

- **Recursive-by-default mock chains** are cheap to write and survive
  wrapper extensions. Prefer them over hand-shaped per-method mocks.

## Session Errors

This session encountered the chain-extension drift TWICE in the same PR
(once for the initial composite-key migration, once for the review-driven
`expectMatch` addition). Capturing this rule means the next wrapper
extension shouldn't repeat the cycle.

**Prevention proposal:** Add a Sharp Edges entry to the work skill
referencing this learning when the work involves extending a `*-writer.ts`
or similar wrapper module under `apps/web-platform/server/`.

## Related

- `cq-raf-batching-sweep-test-helpers` (rAF + fake timers)
- `cq-preflight-fetch-sweep-test-mocks` (HEAD pre-flight + fetch mocks)
- `cq-vitest-setup-file-hook-scope` (per-test vs per-file hook scope)
- PR #2954 (introduced the R8 pattern at one site)
- PR #2959 (generalized the R8 pattern via wrapper)

## Tags

category: best-practices
module: apps/web-platform/server
