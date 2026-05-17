---
name: postgrest-builder-thenable-not-promise-catch-absent
description: Supabase PostgrestBuilder is a thenable that awaits cleanly but does not implement `.catch()` — TS2551 errors at edit time and silent runtime breakage if the type check is bypassed. Use `try`/`catch` around `await` instead.
date: 2026-05-16
category: build-errors
tags: [supabase, postgrest, typescript, thenable, vitest, tests]
related_prs: ["#3883"]
related_learnings:
  - knowledge-base/project/learnings/test-failures/2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md
---

# Learning: PostgrestBuilder is a thenable, not a Promise — no `.catch()` available

## Problem

In a Vitest integration test (`apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts`), a cleanup line used the familiar Promise `.catch()` shorthand to swallow best-effort delete errors:

```typescript
await service
  .from("message_attachments")
  .delete()
  .eq("id", insertId)
  .catch(() => {});
```

`tsc --noEmit` rejected this with:

```
test/server/attachment-pipeline.tenant-isolation.test.ts(266,10): error TS2551:
  Property 'catch' does not exist on type
  'PostgrestFilterBuilder<any, any, any, null, "message_attachments", unknown, "DELETE">'.
  Did you mean 'match'?
```

The TS2551 "Did you mean 'match'?" hint is misleading — the user wanted Promise-`.catch`, not Supabase-`.match`.

## Root cause

`@supabase/postgrest-js` returns chained builder objects (`PostgrestQueryBuilder`, `PostgrestFilterBuilder`, etc.) that implement **only `.then()`** to participate in the `await` protocol. They are thenables (per the ECMAScript thenable interface) but NOT full Promise instances — `.catch()` and `.finally()` are absent from the builder's type definitions and runtime methods.

`await pg.from("x").select()` works because `await` only needs a `.then()` method. `await pg.from("x").select().catch(...)` fails at the type-check boundary because the builder lacks the method.

Adjacent thenable APIs in the codebase have the same shape (e.g., Supabase Storage `bucket.upload()` returns a similar builder), so the trap repeats whenever a contributor reaches for the Promise convenience methods on a Supabase return.

## Solution

Wrap the `await` in `try`/`catch`:

```typescript
try {
  await service
    .from("message_attachments")
    .delete()
    .eq("id", insertId);
} catch {
  // best-effort cleanup
}
```

This compiles cleanly and behaves identically for the cleanup-on-error case. Equivalent options:

- Cast through `Promise.resolve(builder)` to lift it into a real Promise — works but adds noise and a microtask, and obscures intent in test code.
- Assign the awaited result to a variable that ignores errors (`const { error } = await builder; void error;`) — explicit but verbose.

The `try`/`catch` form is the idiomatic Supabase pattern; the existing test suites (`apps/web-platform/test/server/*.tenant-isolation.test.ts`) use it for `service.auth.admin.deleteUser(...)` cleanup.

## Prevention

- When using a Supabase builder result in tests, default to `try { await … } catch {}` rather than `.catch(() => {})`. The Promise-shorthand habit is unsafe on builders.
- When a builder cleanup line is added in a code review, suggest the `try/catch` shape rather than `.catch()` — same byte cost, no TS2551 risk.
- Consider a Sharp-Edges note in any future `data-layer-tests` skill or vitest reference that explicitly says "PostgrestBuilder thenable ≠ Promise; no .catch/.finally."

## Session Errors

- **TS2551 on `.catch()`** — Recovery: replaced `.catch(() => {})` with `try { await … } catch {}`. Prevention: documented in this learning + Sharp Edges note in test scaffolding skills.
- **Probe RPC test referenced non-existent `__pg_policy_shape_probe`** — Recovery: deleted the soft-skipping test block before commit; AC25(a) covers the no-WITH-CHECK shape via operator post-merge `pg_policy` query instead. Prevention: don't write tests against infrastructure not shipping in the same PR; tests must either fire green-or-red against what the PR ships, not gate on optional hypothetical infra.
