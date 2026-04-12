---
title: "fix: extract shared KB constants and Supabase mock helper"
type: fix
date: 2026-04-12
---

# Extract shared KB constants and Supabase mock helper

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

1. **`createMockSupabaseClient(overrides?)`** -- returns a mock client with `auth.getUser`
   and `from` pre-wired to `vi.fn()` instances. Returns the mock functions for per-test
   configuration.

2. **`mockQueryChain(data, error?)`** -- returns a fluent chain mock
   (`select().eq().eq().single()`) resolving to `{ data, error }`. Handles variable chain
   depth.

**Scope decision -- incremental migration:** Do NOT rewrite all 17 test files in this PR.
Instead:

- Create the helper with the two functions above
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
- [ ] `test/helpers/mock-supabase.ts` exists with `createMockSupabaseClient` and `mockQueryChain`
- [ ] 3-4 test files migrated to use the shared helper
- [ ] All existing tests pass without changes to assertions
- [ ] `getExtension()` map stays in `presign/route.ts` (not extracted -- no duplication)

## Test Scenarios

- Given kb-reader uses `KB_MAX_FILE_SIZE` from the shared module, when a file exceeds 1MB,
  then `readContent` throws `KbValidationError`
- Given context-validation uses `KB_MAX_FILE_SIZE` from the shared module, when content
  exceeds 1MB, then `validateConversationContext` throws
- Given presign route uses `ATTACHMENT_MAX_FILE_SIZE` from shared module, when file exceeds
  20MB, then route returns 400 `file_too_large`
- Given chat-input uses `ATTACHMENT_ALLOWED_TYPES` from shared module, when user attaches
  an unsupported type, then error is shown
- Given `mockQueryChain({ id: "123" })` returns a fluent chain, when test calls
  `.select().eq().single()`, then it resolves to `{ data: { id: "123" }, error: null }`
- Given a migrated test file uses `createMockSupabaseClient`, when `vi.clearAllMocks()` runs
  in `beforeEach`, then all mock functions are reset correctly

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

## References

- #2014 -- extract shared KB constants to prevent drift
- #2016 -- extract shared Supabase mock helper for tests
- `knowledge-base/project/learnings/2026-03-18-shared-test-helpers-extraction.md`
