---
title: "fix: extract shared KB constants and Supabase mock helper"
type: fix
date: 2026-04-12
deepened: 2026-04-12
---

# Extract shared KB constants and Supabase mock helper

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 3 (Proposed Solution Part 2, Test Scenarios, new Sharp Edges)
**Research sources:** 4 institutional learnings, codebase analysis of 17 test files

### Key Improvements

1. Mock helper must implement `.then()` for PromiseLike compatibility (Supabase v2 query
   builder is thenable -- documented in project learning `supabase-query-builder-mock-thenable-20260407`)
2. All mock functions shared with `vi.mock()` factories must use `vi.hoisted()` -- the helper
   must be designed to work with hoisted references, not export pre-built mocks
3. Added concrete `mockQueryChain` implementation with variable-depth chaining and `.single()`
   terminal support
4. Added sharp edges section documenting three pitfalls from institutional learnings

## Overview

Two small refactors from PR #2002 code review findings:

1. **#2014 -- KB constants drift:** `MAX_FILE_SIZE` (1MB) is defined independently in
   `server/kb-reader.ts` and `server/context-validation.ts` (as `MAX_CONTEXT_CONTENT_LENGTH`
   with a comment "matches kb-reader MAX_FILE_SIZE"). A separate pair of duplicated attachment
   constants (`MAX_FILE_SIZE` = 20MB, `ALLOWED_CONTENT_TYPES`/`ALLOWED_TYPES`) exists in
   `app/api/attachments/presign/route.ts` and `components/chat/chat-input.tsx`.

2. **#2016 -- Supabase mock repetition:** 17 test files independently reconstruct Supabase's
   fluent query API (`from().select().eq().single()`) with nested `vi.fn().mockReturnValue`
   chains. A Supabase SDK upgrade or query refactor cascades across all test files.

**Note:** The original issue #2014 references `ALLOWED_EXTENSIONS` in `file-tree.tsx` --
that code no longer exists. The codebase has evolved since the issue was filed. The current
duplication is between the file pairs listed above.

## Problem Statement

### KB Constants (#2014)

Four files define overlapping size/type constants:

| Constant | Value | File | Domain |
|----------|-------|------|--------|
| `MAX_FILE_SIZE` | 1MB | `server/kb-reader.ts:6` | KB reading |
| `MAX_CONTEXT_CONTENT_LENGTH` | 1MB | `server/context-validation.ts:8` | Context validation |
| `MAX_FILE_SIZE` | 20MB | `app/api/attachments/presign/route.ts:15` | Attachment upload |
| `MAX_FILE_SIZE` | 20MB | `components/chat/chat-input.tsx:14` | Client attachment validation |
| `ALLOWED_CONTENT_TYPES` | 5 MIME types | `app/api/attachments/presign/route.ts:7` | Attachment upload |
| `ALLOWED_TYPES` | 5 MIME types | `components/chat/chat-input.tsx:6` | Client attachment validation |
| `MAX_FILES_PER_MESSAGE` | 5 | `app/api/attachments/presign/route.ts:16` | Attachment upload |
| `MAX_FILES` | 5 | `components/chat/chat-input.tsx:15` | Client attachment validation |

If someone changes the KB file size limit in `kb-reader.ts`, they must remember to update
`context-validation.ts`. If someone changes the attachment MIME types in the presign route,
they must remember to update `chat-input.tsx`.

### Supabase Mock Helper (#2016)

17 test files mock `@/lib/supabase/server`, `@/lib/supabase/service`, or `@supabase/supabase-js`
with bespoke `vi.fn()` chains. Common patterns that are repeated:

- `createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } }))`
- `createServiceClient: vi.fn(() => ({ from: mockFrom }))`
- `mockFrom.mockImplementation((table) => ({ select: ..., eq: ..., single: ... }))`
- Chain builders like `mockQueryBuilder(data)` (defined inline in `vision-route.test.ts:61-70`)

The original issue referenced `kb-upload.test.ts`, `kb-share-md-only.test.ts`, and
`kb-content-binary.test.ts` -- those files no longer exist. The problem is now broader:
17 files, not 3.

## Proposed Solution

### Part 1: KB Constants (`lib/kb-constants.ts`)

Create `apps/web-platform/lib/kb-constants.ts` exporting two constant groups:

```ts
// KB reading constants
export const KB_MAX_FILE_SIZE = 1024 * 1024; // 1MB

// Attachment constants (shared between server presign route and client validation)
export const ATTACHMENT_ALLOWED_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "application/pdf",
]);
export const ATTACHMENT_MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB
export const ATTACHMENT_MAX_FILES = 5;
```

Then update the four consumer files to import from `@/lib/kb-constants`.

**Scope decision:** The `getExtension()` map in `presign/route.ts` is not duplicated
elsewhere, so it stays in the route file.

### Part 2: Supabase Mock Helper (`test/helpers/mock-supabase.ts`)

Create `apps/web-platform/test/helpers/mock-supabase.ts` exporting reusable helpers for the
two most common patterns:

1. **`mockQueryChain(data, error?)`** -- returns a fluent chain mock that is **thenable**
   (implements `.then()`) so `await chain.select().eq()` works. All chaining methods return
   `this`; `.single()` returns a thenable resolving to `{ data, error }`.

2. **`createMockSupabaseClient(overrides?)`** -- not a pre-built mock. Instead, a factory
   that returns `{ mockGetUser, mockFrom }` vi.fn instances that test files wire into their
   own `vi.hoisted()` + `vi.mock()` blocks. The helper cannot export a ready-made `vi.mock()`
   factory because `vi.mock()` must be called at the top level of each test file.

#### Research Insights: mockQueryChain Implementation

The Supabase JS v2 query builder is a `PromiseLike` -- it implements `.then()` so queries
can be `await`ed directly. Mocks that only make terminal methods (`.single()`, `.limit()`)
return Promises break when queries are `await`ed without a terminal.

**Concrete implementation pattern (from institutional learning):**

```ts
import { vi } from "vitest";

/**
 * Create a thenable query chain mock that supports variable-depth chaining.
 * All chaining methods (.select, .eq, .in, .is, .order, .limit) return `this`.
 * The chain is PromiseLike: `await chain.select().eq()` resolves to { data, error }.
 * `.single()` returns a separate thenable resolving to { data, error }.
 */
export function mockQueryChain<T>(data: T, error: { message: string } | null = null) {
  const result = { data, error };
  const chain: Record<string, unknown> = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    neq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    is: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    range: vi.fn().mockReturnThis(),
    insert: vi.fn().mockReturnThis(),
    update: vi.fn().mockReturnThis(),
    upsert: vi.fn().mockReturnThis(),
    delete: vi.fn().mockReturnThis(),
    // PromiseLike: allows `await chain.select().eq()`
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
    // Terminal: `.single()` returns a separate thenable
    single: vi.fn(() => ({
      then: (onfulfilled?: (v: unknown) => unknown) =>
        Promise.resolve(result).then(onfulfilled),
    })),
  };
  // Make all chaining methods return `chain` (mockReturnThis needs the reference)
  for (const key of ["select", "eq", "neq", "in", "is", "order", "limit", "range",
                      "insert", "update", "upsert", "delete"]) {
    (chain[key] as ReturnType<typeof vi.fn>).mockReturnValue(chain);
  }
  return chain;
}
```

#### Design Constraint: vi.hoisted() Compatibility

The helper CANNOT export a `vi.mock()` factory because vitest hoists `vi.mock()` calls to
the file top. Test files must still declare their own `vi.hoisted()` block and `vi.mock()`
call. The helper provides building blocks, not a complete mock setup.

**Usage pattern in test files:**

```ts
import { mockQueryChain } from "./helpers/mock-supabase";

const { mockGetUser, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

// In tests:
mockFrom.mockReturnValue(mockQueryChain({ id: "123", name: "test" }));
```

**Scope decision -- incremental migration:** Do NOT rewrite all 17 test files in this PR.
Instead:

- Create the helper with `mockQueryChain` (primary value -- eliminates the chain boilerplate)
- Migrate 3-4 representative test files to prove the helper works
- Leave remaining files for incremental adoption (each future PR that touches a test file
  can migrate it)

The 3-4 files to migrate are:

- `test/presign-route.test.ts` -- has `setupConversationOwnership` with explicit chain (lines 77-91)
- `test/vision-route.test.ts` -- has inline `mockQueryBuilder` (lines 61-70)
- `test/disconnect-route.test.ts` -- duplicates the `createClient`/`createServiceClient` pattern
- `test/account-delete.test.ts` -- has `setupSupabaseMocks` helper with chain

## Acceptance Criteria

- [ ] `lib/kb-constants.ts` exists with `KB_MAX_FILE_SIZE`, `ATTACHMENT_ALLOWED_TYPES`,
      `ATTACHMENT_MAX_FILE_SIZE`, and `ATTACHMENT_MAX_FILES` exports
- [ ] `server/kb-reader.ts` imports `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`
- [ ] `server/context-validation.ts` imports `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`
- [ ] `app/api/attachments/presign/route.ts` imports attachment constants from `@/lib/kb-constants`
- [ ] `components/chat/chat-input.tsx` imports attachment constants from `@/lib/kb-constants`
- [ ] No duplicate constant definitions remain in any of the four consumer files
- [ ] `test/helpers/mock-supabase.ts` exists with `mockQueryChain` helper
- [ ] `mockQueryChain` implements `.then()` for PromiseLike compatibility (thenable)
- [ ] `mockQueryChain` supports `.single()` as a terminal that returns a separate thenable
- [ ] 3-4 test files migrated to use the shared helper
- [ ] All existing tests pass without changes to assertions
- [ ] `lib/kb-constants.ts` does NOT include `"use client"` directive
- [ ] `getExtension()` map stays in `presign/route.ts` (not extracted -- no duplication)

## Test Scenarios

### KB Constants (existing tests should continue passing)

- Given kb-reader uses `KB_MAX_FILE_SIZE` from the shared module, when a file exceeds 1MB,
  then `readContent` throws `KbValidationError`
- Given context-validation uses `KB_MAX_FILE_SIZE` from the shared module, when content
  exceeds 1MB, then `validateConversationContext` throws
- Given presign route uses `ATTACHMENT_MAX_FILE_SIZE` from shared module, when file exceeds
  20MB, then route returns 400 `file_too_large`
- Given chat-input uses `ATTACHMENT_ALLOWED_TYPES` from shared module, when user attaches
  an unsupported type, then error is shown

### Mock Helper (new unit tests in `test/helpers/mock-supabase.test.ts`)

- Given `mockQueryChain({ id: "123" })`, when `await chain.select("*").eq("id", "123")`,
  then resolves to `{ data: { id: "123" }, error: null }` (thenable without terminal)
- Given `mockQueryChain({ id: "123" })`, when `await chain.select().eq().single()`,
  then resolves to `{ data: { id: "123" }, error: null }` (with `.single()` terminal)
- Given `mockQueryChain(null, { message: "not found" })`, when `await chain.select().eq()`,
  then resolves to `{ data: null, error: { message: "not found" } }` (error case)
- Given a migrated test file uses `mockQueryChain`, when `vi.clearAllMocks()` runs in
  `beforeEach`, then the chain's `vi.fn()` call counts are reset correctly
- Given `mockQueryChain`, when used inside a `vi.mock()` factory via `vi.hoisted()`,
  then the import resolves correctly (not blocked by hoisting)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Related Issues and PRs

- Issue #2014: extract shared KB constants to prevent drift
- Issue #2016: extract shared Supabase mock helper for tests
- PR #2002: source code review that identified both issues

### Learning Reference

- `knowledge-base/project/learnings/2026-03-18-shared-test-helpers-extraction.md` -- same
  pattern for bash test helpers. Key insight: "When two test files duplicate helper functions,
  implementation drift is inevitable. Extract shared helpers early."

### Files to Modify

**New files:**

- `apps/web-platform/lib/kb-constants.ts`
- `apps/web-platform/test/helpers/mock-supabase.ts`

**Modified files (constants):**

- `apps/web-platform/server/kb-reader.ts` -- replace local `MAX_FILE_SIZE` with import
- `apps/web-platform/server/context-validation.ts` -- replace local `MAX_CONTEXT_CONTENT_LENGTH`
  with import
- `apps/web-platform/app/api/attachments/presign/route.ts` -- replace local constants with imports
- `apps/web-platform/components/chat/chat-input.tsx` -- replace local constants with imports

**Modified files (mock helper migration):**

- `apps/web-platform/test/presign-route.test.ts`
- `apps/web-platform/test/vision-route.test.ts`
- `apps/web-platform/test/disconnect-route.test.ts`
- `apps/web-platform/test/account-delete.test.ts`

## Sharp Edges

These pitfalls are documented in institutional learnings and directly apply to this work:

1. **Thenable mock is mandatory.** Supabase JS v2 query builder implements `PromiseLike`.
   A mock that only makes `.single()` or `.limit()` return Promises will silently resolve
   to `undefined` when the query is `await`ed without a terminal method. The `mockQueryChain`
   helper MUST implement `.then()` on the chain object itself.
   (Source: `learnings/test-failures/supabase-query-builder-mock-thenable-20260407.md`)

2. **`vi.hoisted()` is required for shared mock references.** Any `vi.fn()` referenced inside
   a `vi.mock()` factory must be declared via `vi.hoisted()`. The helper file can export
   utility functions (like `mockQueryChain`) but NOT pre-declared `vi.fn()` instances that
   test files pass into `vi.mock()` -- those must be hoisted per-file.
   (Source: `learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`)

3. **Module-level Supabase client timing.** Some modules call `createClient()` at module
   scope (e.g., `agent-runner.ts`). For those, `mockFrom` must be wired inside the `vi.mock()`
   factory, not in a `beforeEach`. This PR's migration candidates (`presign-route`,
   `vision-route`, `disconnect-route`, `account-delete`) all use route handlers that call
   `createClient()`/`createServiceClient()` per-request, so this is not a blocker -- but the
   helper's documentation should note this constraint for future adopters.
   (Source: `learnings/2026-04-06-vitest-module-level-supabase-mock-timing.md`)

4. **`"use client"` directive in shared constants.** `chat-input.tsx` is a client component.
   The shared `lib/kb-constants.ts` must NOT include `"use client"` -- it exports plain
   constants that are tree-shakeable. Next.js correctly handles importing a server-compatible
   module from a client component as long as the module only exports serializable values.

5. **Test runner: use `npx vitest`, not `bunx vitest`.** The project uses vitest via npm.
   `bunx vitest` fetches the latest version which may have incompatible native bindings.
   (Source: `learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`)

## References

- #2014 -- extract shared KB constants to prevent drift
- #2016 -- extract shared Supabase mock helper for tests
- `knowledge-base/project/learnings/2026-03-18-shared-test-helpers-extraction.md`
- `knowledge-base/project/learnings/test-failures/supabase-query-builder-mock-thenable-20260407.md`
- `knowledge-base/project/learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`
- `knowledge-base/project/learnings/2026-04-06-vitest-module-level-supabase-mock-timing.md`
