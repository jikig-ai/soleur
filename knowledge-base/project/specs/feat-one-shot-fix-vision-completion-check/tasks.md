# Tasks: fix Vision completion check

## Phase 1: Server — Add size to KB tree

- [ ] 1.1 Add `size?: number` to `TreeNode` interface in `apps/web-platform/server/kb-reader.ts`
- [ ] 1.2 Populate `size` from the existing `stat()` call in `buildTree`'s `mapWithConcurrency` callback
- [ ] 1.3 Verify `/api/kb/tree` response includes `size` for file nodes

## Phase 2: Client — Size-aware completion check

- [ ] 2.1 Update `flattenTree` in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` to return `Map<string, FileInfo>` instead of `Set<string>`
- [ ] 2.2 Rename `kbPaths`/`setKbPaths` state to `kbFiles`/`setKbFiles`
- [ ] 2.3 Add `FOUNDATION_MIN_CONTENT_BYTES = 500` constant
- [ ] 2.4 Update `done` derivation to check both existence and size >= threshold
- [ ] 2.5 Keep `visionExists` as file-existence-only (first-run detection unchanged)

## Phase 3: Tests

- [ ] 3.1 Update `apps/web-platform/test/command-center.test.tsx` mock KB tree to include `size` fields
- [ ] 3.2 Add test: stub vision.md (size 200) does NOT show green checkmark
- [ ] 3.3 Add test: substantial vision.md (size 800) shows green checkmark
- [ ] 3.4 Update `apps/web-platform/test/start-fresh-onboarding.test.tsx` mock tree builders to include `size` fields
- [ ] 3.5 Verify existing tests pass with updated mocks
- [ ] 3.6 Run full test suite: `cd apps/web-platform && npx vitest run`
