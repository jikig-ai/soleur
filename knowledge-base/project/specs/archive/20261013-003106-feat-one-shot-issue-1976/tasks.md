# Tasks: Harden GDPR Storage Purge

**Plan:** `knowledge-base/project/plans/2026-04-12-fix-harden-gdpr-storage-purge-plan.md`
**Issue:** [#1976](https://github.com/jikig-ai/soleur/issues/1976)
**Branch:** `feat-one-shot-issue-1976`

## Phase 1: Test Setup (RED)

- [x] 1.1 Add Storage mock variables to `apps/web-platform/test/account-delete.test.ts`
  - Define `mockStorageList`, `mockStorageRemove`, `mockStorageFrom` before `vi.mock()`
  - Wire `storage: { from: mockStorageFrom }` into the `createServiceClient` mock factory
  - Default `mockStorageList` to return `{ data: [], error: null }` so existing tests are unaffected

- [x] 1.2 Extend `setupSupabaseMocks` helper with Storage defaults
  - Add `mockStorageList.mockResolvedValue({ data: [], error: null })` as default
  - Add `mockStorageRemove.mockResolvedValue({ data: [], error: null })` as default
  - This ensures existing tests are unaffected by Storage mock addition

- [x] 1.3 Write failing test: happy path blob purge
  - Use `mockStorageList.mockImplementation()` with argument-conditional returns
  - Mock `list("user-123")` to return 2 folder objects `[{ name: "conv-1" }, { name: "conv-2" }]`
  - Mock `list("user-123/conv-1")` to return `[{ name: "img1.png" }, { name: "doc1.pdf" }]`
  - Mock `list("user-123/conv-2")` to return `[{ name: "img2.jpg" }]`
  - Assert `remove()` called with `["user-123/conv-1/img1.png", "user-123/conv-1/doc1.pdf", "user-123/conv-2/img2.jpg"]`
  - Assert `mockStorageFrom` called with `"chat-attachments"`

- [x] 1.4 Write failing test: `list()` error is non-fatal
  - Mock `mockStorageList` to throw `new Error("Storage unavailable")`
  - Assert `deleteAccount()` returns `{ success: true }`
  - Assert `auth.admin.deleteUser` is still called

- [x] 1.5 Write failing test: `remove()` error is non-fatal
  - Mock `mockStorageList` to succeed with folder/file data
  - Mock `mockStorageRemove` to throw `new Error("Storage remove failed")`
  - Assert `deleteAccount()` returns `{ success: true }`
  - Assert `auth.admin.deleteUser` is still called

- [x] 1.6 Write failing test: cascade order includes Storage purge
  - Extend the existing "correct order" test to track `"storage-purge"` step
  - Add `mockStorageList.mockImplementation()` with folder/file data to the tracking setup
  - Expected order: `["abort", "workspace", "storage-purge", "auth"]`

- [x] 1.7 Write failing test: pagination across multiple pages
  - Mock `list("user-123")` first call to return exactly `PAGE_SIZE` (1,000) folder stubs, second call to return 5 more
  - Assert `list()` called with `offset: 0` then `offset: 1000` for the folder level
  - Assert all 1,005 folders are processed

- [x] 1.8 Write failing test: zero attachments
  - Use default mock (empty `{ data: [] }`)
  - Assert `remove()` is never called
  - Assert `deleteAccount()` returns `{ success: true }`

## Phase 2: Implementation (GREEN)

- [x] 2.1 Extract `listAllStorageObjects()` helper in `apps/web-platform/server/account-delete.ts`
  - Type parameter: `storage: SupabaseClient["storage"]` (import from `@supabase/supabase-js`)
  - Other parameters: `bucket: string`, `folder: string`
  - Returns: `Promise<string[]>` (object names)
  - Uses offset-based pagination loop with `PAGE_SIZE = 1_000`
  - Loop: fetch page with `{ limit: PAGE_SIZE, offset }`, collect names, break when `data.length < PAGE_SIZE` or `!data`

- [x] 2.2 Replace inline `list()` calls with `listAllStorageObjects()`
  - Folder level: `const folders = await listAllStorageObjects(service.storage, "chat-attachments", userId)`
  - File level: `const files = await listAllStorageObjects(service.storage, "chat-attachments", \`${userId}/${folderName}\`)`
  - Collect paths and call `remove()` as before

- [x] 2.3 Reset Storage mocks in `setupSupabaseMocks` helper
  - Add `mockStorageList.mockReset()` and `mockStorageRemove.mockReset()` to the existing helper
  - Set default Storage list to return `{ data: [], error: null }`

- [x] 2.4 Run `vitest run` -- all tests pass (existing + new)

## Phase 3: Refactor

- [x] 3.1 Review for simplification opportunities
  - Is the helper function warranted, or is the inline loop simple enough?
  - Are the mocks minimal and clear?

- [x] 3.2 Run `npx markdownlint-cli2 --fix` on any changed `.md` files

- [x] 3.3 Run full test suite: `cd apps/web-platform && npx vitest run`
