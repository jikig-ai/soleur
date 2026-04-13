# Tasks: fix Vision completion check

## Phase 1: Server — Add size to KB tree

- [x] 1.1 Add `size?: number` to `TreeNode` interface in `apps/web-platform/server/kb-reader.ts` (after line 17)
- [x] 1.2 Refactor stat call in `buildTree`'s `mapWithConcurrency` callback (lines 183-186): change `.then(stat => stat.mtime.toISOString()).catch(() => undefined)` to `.catch(() => null)`, then extract `stat?.mtime.toISOString()` and `stat?.size`
- [x] 1.3 Add `size` field to returned `TreeNode` object (line 187-193)

## Phase 2: Shared constant

- [x] 2.1 Add `FOUNDATION_MIN_CONTENT_BYTES = 500` to `apps/web-platform/lib/kb-constants.ts`
- [x] 2.2 Update `apps/web-platform/server/vision-helpers.ts` line 67 to use `FOUNDATION_MIN_CONTENT_BYTES` instead of hardcoded `500`

## Phase 3: Client — Size-aware completion check

- [x] 3.1 Add `size?: number` to client-side `TreeNode` interface in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (line 39-44)
- [x] 3.2 Add `FileInfo` interface and update `flattenTree` to return `Map<string, FileInfo>` instead of `Set<string>` (lines 46-50)
- [x] 3.3 Rename `kbPaths`/`setKbPaths` state to `kbFiles`/`setKbFiles` (lines 111, 137)
- [x] 3.4 Update `useState` type from `Set<string>` to `Map<string, FileInfo>` with `new Map()` default
- [x] 3.5 Import `FOUNDATION_MIN_CONTENT_BYTES` and update `done` derivation (lines 154-157): check both existence AND `size >= FOUNDATION_MIN_CONTENT_BYTES`
- [x] 3.6 Keep `visionExists` as `kbFiles.has("overview/vision.md")` (file-existence-only, first-run gate unchanged)

## Phase 4: Tests

- [x] 4.1 Update `apps/web-platform/test/command-center.test.tsx` inline KB tree mock (lines 139-155): add `size: 1000` to each file node
- [x] 4.2 Add test in `command-center.test.tsx`: stub vision.md (size 200) does NOT show green checkmark
- [x] 4.3 Update `buildMockTree` helper in `apps/web-platform/test/start-fresh-onboarding.test.tsx` (lines 58-96): add optional `sizes` parameter, default file size to 1000
- [x] 4.4 Add test in `start-fresh-onboarding.test.tsx`: stub vision.md with size 200 does not count as complete
- [x] 4.5 Add test: all four foundation files at >= 500 bytes shows "Your organization is ready", but with one at 300 bytes shows foundations section
- [x] 4.6 Verify all existing tests pass with updated mocks
- [x] 4.7 Run full test suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`
