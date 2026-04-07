---
module: web-platform
date: 2026-04-07
problem_type: test_failure
component: testing_framework
symptoms:
  - "TypeError: query.eq is not a function"
  - "Supabase query builder mock breaks when chaining after .limit()"
  - "await query.order(...) resolves to undefined instead of query result"
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [supabase, vitest, mock, thenable, query-builder]
synced_to: []
---

# Learning: Supabase JS query builder mocks must be thenable

## Problem

When mocking `@supabase/supabase-js` for component tests, the Supabase JS v2 query builder is a `PromiseLike` — it implements `.then()` so queries can be `await`ed directly without a terminal method. If the mock only makes `.limit()` a terminal (returning a Promise), any query that chains `.eq()` after `.limit()` gets "not a function" errors, and any query `await`ed without `.limit()` silently resolves to `undefined`.

```typescript
// BROKEN: .limit() returns a Promise, breaking further chaining
const builder = {
  select: vi.fn().mockReturnThis(),
  order: vi.fn().mockReturnThis(),
  limit: vi.fn().mockImplementation(() =>
    Promise.resolve({ data, error: null }),
  ),
};
// await builder.select("*").order(...) → undefined (no .then())
// builder.select("*").limit(50).eq("status", "active") → TypeError
```

## Solution

Add a `.then()` method to the mock builder so it behaves like the real Supabase client. All chaining methods (`.select`, `.eq`, `.order`, `.limit`, `.in`, `.is`) return `this`, and `.then()` resolves to the mock data.

```typescript
function createQueryBuilder(data: unknown[]) {
  const result = { data, error: null };
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    is: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  };
  return builder;
}
```

This allows `await query.order(...)`, `await query.limit(50)`, and `query.limit(50).eq(...)` to all work correctly.

## Key Insight

The Supabase JS v2 client's query builder implements `PromiseLike` — calling `await builder` triggers `.then()` regardless of which chaining method was called last. Test mocks that only support specific terminal methods (`.limit()`, `.single()`) break when queries are structured differently. Always make the mock builder itself thenable.

## Session Errors

**Worktree disappeared between creation and use** — First `conversation-inbox` worktree was lost, requiring recreation. Recovery: recreated with `worktree-manager.sh --yes create`. Prevention: verify worktree exists with `ls` before switching to it.

**CPO assessment used stale issue data** — Reported tag-and-route (#1059) as "not started" when it was shipped 10 days prior. Recovery: user corrected, verified with `gh issue view`. Prevention: domain assessment agents should verify issue status with `gh issue view --json state` before asserting status.

**PostgREST embedded resource syntax prescribed incorrectly in plan** — Plan included `.limit(1).order().eq()` inside `select()` which PostgREST doesn't support. Recovery: caught by Kieran reviewer, replaced with two simple queries. Prevention: plans prescribing Supabase/PostgREST query syntax should include a verification note: "Confirm syntax against Supabase JS client docs before implementing."

**ConversationRow renders both mobile/desktop layouts in DOM** — Components using `md:hidden` / `hidden md:flex` CSS produce duplicate text in happy-dom test environment where media queries don't apply. Recovery: used `getAllByText` instead of `getByText`. Prevention: when testing responsive components with CSS-hidden variants, always use `getAllByText` / `queryAllByText`.

**`git add` from bare repo root** — Running `git add` from the bare repo root fails because bare repos have no working tree. Recovery: ran from worktree directory. Prevention: always `cd` to worktree before git operations.

## Related

- [vitest-module-level-supabase-mock-timing](../2026-04-06-vitest-module-level-supabase-mock-timing.md) — related Supabase mock timing issue
- [supabase-silent-error-return-values](../2026-03-20-supabase-silent-error-return-values.md) — Supabase error handling pattern

## Tags

category: test-failures
module: web-platform
