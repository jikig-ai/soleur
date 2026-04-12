---
title: "fix: harden GDPR Storage purge — add test coverage + pagination"
type: fix
date: 2026-04-12
deepened: 2026-04-12
---

# fix: Harden GDPR Storage Purge in account-delete.ts

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Test Scenarios, Acceptance Criteria)
**Research sources used:** Supabase JS Storage API docs (Context7), Vitest mock API docs (Context7), project learnings (4 applied)

### Key Improvements

1. Added argument-conditional mock pattern for `mockStorageList` (different returns based on folder path argument)
2. Added `remove()` failure test scenario (separate from `list()` failure -- both must be non-fatal)
3. Added boundary condition test for exactly PAGE_SIZE items (must trigger one more page fetch)
4. Clarified type import for `listAllStorageObjects` helper parameter

## Overview

Harden the Storage blob purge in `account-delete.ts` (step 3.5, lines 59-83) shipped with #1961. Two gaps exist: (1) no test coverage for the Storage mock in `account-delete.test.ts`, and (2) the `list()` calls use a fixed `{ limit: 1_000 }` without pagination, so users with >1,000 conversation folders or >1,000 files per folder will have orphaned blobs after account deletion -- a GDPR Article 17 violation.

**Issue:** [#1976](https://github.com/jikig-ai/soleur/issues/1976)
**Parent:** [#1961](https://github.com/jikig-ai/soleur/issues/1961) (chat attachments)

## Problem Statement

The blob purge code has two problems:

1. **No test coverage.** The existing test file (`account-delete.test.ts`) mocks `service.from()` for DB queries but does not mock `service.storage.from()`. The Storage purge path is completely untested -- both the happy path and the error path (Storage failure must be non-fatal per the existing try/catch design).

2. **Pagination gap.** Supabase Storage `list()` returns at most `limit` objects per call (default 100, current code uses 1,000). There are TWO pagination gaps:
   - **Folder level:** `list(userId, { limit: 1_000 })` at line 64 -- a user with >1,000 conversations misses folders beyond the first page.
   - **File level:** `list(\`${userId}/${folder.name}\`, { limit: 1_000 })` at line 72 -- a conversation with >1,000 attachments misses files beyond the first page.

   The Supabase Storage `list` API supports `offset`-based pagination (`{ limit, offset }`). The fix is a paginated loop that increments `offset` by `limit` until a page returns fewer items than `limit`.

## Proposed Solution

### Part 1: Add Storage mock to test file

Add a `mockStorage` object to the existing mock factory in `account-delete.test.ts`. The mock must be wired into the `createServiceClient` mock alongside the existing `mockFrom` and `mockAuth`.

**Storage mock structure:**

```typescript
// apps/web-platform/test/account-delete.test.ts
const mockStorageList = vi.fn();
const mockStorageRemove = vi.fn();
const mockStorageFrom = vi.fn().mockReturnValue({
  list: mockStorageList,
  remove: mockStorageRemove,
});

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    auth: mockAuth,
    storage: { from: mockStorageFrom },  // <-- NEW
  }),
}));
```

### Research Insights: Mock Setup

**Argument-conditional returns with `mockImplementation`:** The happy path test needs `mockStorageList` to return different data depending on the folder argument. Use `mockImplementation` with argument inspection rather than `mockReturnValue` (which returns the same value regardless of arguments):

```typescript
// Pattern: argument-conditional mock (from Vitest docs)
mockStorageList.mockImplementation((folder: string, _opts?: unknown) => {
  if (folder === "user-123") {
    // Top-level: return conversation folders
    return Promise.resolve({ data: [{ name: "conv-1" }, { name: "conv-2" }], error: null });
  }
  if (folder === "user-123/conv-1") {
    return Promise.resolve({ data: [{ name: "img1.png" }, { name: "doc1.pdf" }], error: null });
  }
  if (folder === "user-123/conv-2") {
    return Promise.resolve({ data: [{ name: "img2.jpg" }], error: null });
  }
  return Promise.resolve({ data: [], error: null });
});
```

**Default mock in `beforeEach`:** Reset `mockStorageList` and `mockStorageRemove` in the existing `beforeEach(() => vi.clearAllMocks())` block. Since `vi.clearAllMocks()` already resets all mocks, the Storage mocks need a default implementation set in `setupSupabaseMocks` to avoid `undefined` returns:

```typescript
// Inside setupSupabaseMocks (or called from it)
mockStorageList.mockResolvedValue({ data: [], error: null });
mockStorageRemove.mockResolvedValue({ data: [], error: null });
```

This ensures existing tests (which don't care about Storage) get empty results and don't break.

**New tests (5):**

1. **Happy path:** Mock `list()` with argument-conditional returns for folder and file levels. Assert that `remove()` is called with the correctly assembled paths in the format `userId/folderName/fileName`.

2. **`list()` error path (non-fatal):** Mock `mockStorageList` to throw an error. Assert that `deleteAccount()` still returns `{ success: true }` (Storage failure is non-fatal -- the existing try/catch wraps the entire block).

3. **`remove()` error path (non-fatal):** Mock `mockStorageList` to succeed but `mockStorageRemove` to throw. Assert that `deleteAccount()` still returns `{ success: true }`. This is a distinct failure mode from `list()` failure -- both must be non-fatal.

4. **Cascade order includes Storage before auth:** Extend the existing "correct order" test to verify Storage purge runs between workspace deletion and auth deletion. The expected order becomes: `["abort", "workspace", "storage-purge", "auth"]`.

5. **Zero attachments:** Mock `list()` to return empty `{ data: [] }`. Assert `remove()` is never called.

### Part 2: Fix pagination with offset loop

Extract a helper function `listAllStorageObjects` that paginates through all objects in a Storage folder:

```typescript
// apps/web-platform/server/account-delete.ts
import type { SupabaseClient } from "@supabase/supabase-js";

const PAGE_SIZE = 1_000;

async function listAllStorageObjects(
  storage: SupabaseClient["storage"],
  bucket: string,
  folder: string,
): Promise<string[]> {
  const names: string[] = [];
  let offset = 0;

  while (true) {
    const { data } = await storage
      .from(bucket)
      .list(folder, { limit: PAGE_SIZE, offset });

    if (!data || data.length === 0) break;

    names.push(...data.map((obj) => obj.name));

    if (data.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }

  return names;
}
```

### Research Insights: Type Safety

**Use `SupabaseClient["storage"]` not `ReturnType`:** Per the learning `supabase-returntype-resolves-to-never.md`, `ReturnType<typeof createServiceClient>` can resolve to `never` in certain TypeScript configurations. Import `SupabaseClient` from `@supabase/supabase-js` and use the indexed access type `SupabaseClient["storage"]` for the parameter type.

### Research Insights: Pagination

**Boundary condition -- exactly PAGE_SIZE items:** When `list()` returns exactly `PAGE_SIZE` items, the loop must fetch one more page to confirm there are no more. The `data.length < PAGE_SIZE` check handles this correctly -- if we get exactly 1,000 items, we fetch again. This is the standard offset-based pagination pattern confirmed by Supabase JS Storage docs (Context7). The worst case is one extra empty-page fetch when the total is an exact multiple of PAGE_SIZE.

**Offset vs cursor pagination:** Supabase Storage uses offset-based pagination (not cursor-based). This means if objects are deleted during pagination, items could be skipped or duplicated. For GDPR deletion this is acceptable -- we are collecting objects to delete, and any skipped objects represent a best-effort gap (same as the existing non-pagination code). Cursor-based pagination is not available for Storage `list()`.

Then replace the two fixed-limit `list()` calls with this helper:

```typescript
// Step 3.5 — paginated version
const folders = await listAllStorageObjects(service.storage, "chat-attachments", userId);
const allPaths: string[] = [];
for (const folderName of folders) {
  const files = await listAllStorageObjects(
    service.storage,
    "chat-attachments",
    `${userId}/${folderName}`,
  );
  allPaths.push(...files.map((f) => `${userId}/${folderName}/${f}`));
}
if (allPaths.length > 0) {
  await service.storage.from("chat-attachments").remove(allPaths);
}
```

### Part 3: Pagination test

Add a test that mocks `list()` to return exactly `PAGE_SIZE` items on the first call and fewer on the second call. Assert that `list()` is called twice with incrementing offsets, and that all paths from both pages are collected for removal.

## Technical Considerations

- **Mock timing:** Per the Vitest mock timing learning (`2026-04-06-vitest-module-level-supabase-mock-timing.md`), the `mockStorageFrom`/`mockStorageList`/`mockStorageRemove` variables must be defined before the `vi.mock()` call (which is hoisted). The existing test already follows this pattern with `mockFrom` and `mockAuth`.

- **Thenable not needed:** The Storage `list()` and `remove()` methods return normal Promises, not Supabase query builder chains. The thenable learning (`supabase-query-builder-mock-thenable-20260407.md`) applies only to PostgREST query builders, not Storage API calls.

- **`remove()` batch size:** The Supabase Storage `remove()` API does not document a maximum batch size for file paths (unlike the vector API which caps at 500). The current approach of collecting all paths and calling `remove()` once is acceptable. If future scale requires it, batching the `remove()` call into chunks of 1,000 is a straightforward follow-up. Note: the `remove()` API also returns `{ data, error }` -- per the Supabase silent errors learning, the error should be checked even though the entire block is try/catch'd (for logging specificity).

- **Non-fatal contract:** The entire Storage purge block is wrapped in `try/catch` (line 61-83). Both the existing code and the hardened version must preserve this: Storage failures log a warning but do not fail the account deletion. This is correct -- the auth record deletion (which triggers FK CASCADE for DB rows) is the critical path. Orphaned blobs are a data hygiene issue, not a data integrity issue.

- **Performance:** For a user with N conversation folders and M files per folder, the pagination loop makes `ceil(N/1000) + N * ceil(M/1000)` API calls plus one `remove()` call. At current scale (single-digit users, <100 conversations each) this is negligible. The `for...of` sequential loop for folders is intentional to avoid rate-limiting Supabase Storage.

## Acceptance Criteria

- [ ] `account-delete.test.ts` includes a `mockStorage` that mocks `service.storage.from("chat-attachments")` with `.list()` and `.remove()`
- [ ] Storage mock defaults to empty results in `setupSupabaseMocks` so existing tests are unaffected
- [ ] Happy path test: blob paths collected from nested folder/file listing and passed to `remove()` in correct format (`userId/folder/file`)
- [ ] `list()` error path test: Storage `list()` throws, `deleteAccount()` still returns `{ success: true }`
- [ ] `remove()` error path test: Storage `remove()` throws after successful `list()`, `deleteAccount()` still returns `{ success: true }`
- [ ] Zero attachments test: `list()` returns empty, `remove()` is never called
- [ ] Cascade order test updated to include Storage purge step between workspace and auth
- [ ] `list()` calls use offset-based pagination loop instead of fixed `{ limit: 1_000 }`
- [ ] Pagination test: when first page returns exactly `PAGE_SIZE` items, a second page is fetched with `offset: PAGE_SIZE`
- [ ] `listAllStorageObjects` helper uses `SupabaseClient["storage"]` type (not `ReturnType`)
- [ ] All existing tests in `account-delete.test.ts` continue to pass
- [ ] `cd apps/web-platform && npx vitest run` passes with zero failures

## Test Scenarios

### Acceptance Tests

- Given a user with 2 conversation folders each containing 3 files, when `deleteAccount` runs, then `storage.from("chat-attachments").remove()` is called with all 6 paths in the format `userId/conv1/file1`, `userId/conv1/file2`, etc.
- Given a Storage API that throws on `list()`, when `deleteAccount` runs, then the function returns `{ success: true }` and `auth.admin.deleteUser` is still called
- Given a user with 1,500 conversation folders (exceeding PAGE_SIZE of 1,000), when `deleteAccount` runs, then `list()` is called twice for the folder level (offset 0, then offset 1,000) and all 1,500 folders are processed
- Given a user with a conversation containing 2,500 files, when `deleteAccount` runs, then `list()` is called three times for that folder (offsets 0, 1,000, 2,000) and all 2,500 file paths are collected

### Edge Cases

- Given a user with zero attachments (no conversations or empty storage prefix), when `deleteAccount` runs, then `remove()` is never called and the function succeeds
- Given a Storage API where `list()` returns `{ data: null }`, when `deleteAccount` runs, then the pagination loop terminates gracefully without error
- Given a Storage API where `list()` succeeds but `remove()` throws, when `deleteAccount` runs, then the function still returns `{ success: true }` and `auth.admin.deleteUser` is still called
- Given a user with exactly PAGE_SIZE (1,000) conversation folders, when `deleteAccount` runs, then `list()` is called twice for the folder level (offsets 0 and 1,000) -- the second call returns empty, confirming no more folders

## Domain Review

**Domains relevant:** Legal

### Legal (CLO)

**Status:** reviewed (inline)
**Assessment:** This fix directly addresses a GDPR Article 17 (Right to Erasure) compliance gap. The current code silently fails to delete Storage blobs for users with >1,000 objects. While the risk is low at current scale (single-digit users), this must be fixed before Phase 4 beta recruitment when real user deletions become possible. The non-fatal error handling is correct -- best-effort blob cleanup with guaranteed auth record deletion is the right tradeoff. Orphaned blobs without user identity linkage (the DB rows including `message_attachments` are FK-cascaded) have minimal privacy risk, but full erasure is the compliance target.

## Institutional Learnings Applied

| Learning | File | Application |
|----------|------|-------------|
| Vitest mock timing | `2026-04-06-vitest-module-level-supabase-mock-timing.md` | Define mock variables before `vi.mock()` (hoisted) |
| Supabase thenable builders | `supabase-query-builder-mock-thenable-20260407.md` | Storage API returns Promises, not query builders -- thenable pattern not needed here |
| Supabase silent errors | `2026-03-20-supabase-silent-error-return-values.md` | Destructure `{ data, error }` on every `list()` call |
| Account deletion cascade order | `account-deletion-cascade-order-20260402.md` | Storage purge must run before auth deletion (non-fatal), auth deletion triggers FK CASCADE |

## References

### Internal References

- Implementation file: `apps/web-platform/server/account-delete.ts:59-83` (step 3.5)
- Test file: `apps/web-platform/test/account-delete.test.ts`
- Parent plan: `knowledge-base/project/plans/2026-04-11-feat-chat-attachments-plan.md`
- Storage bucket migration: `apps/web-platform/supabase/migrations/019_chat_attachments.sql`

### External References

- Supabase Storage `list()` API: supports `{ limit, offset, sortBy }` for offset-based pagination
- Supabase Storage `remove()` API: accepts array of file paths, no documented batch limit
- GDPR Article 17: Right to Erasure
