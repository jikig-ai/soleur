# Tasks — feat-refactor-kb-routes

**Plan:** `knowledge-base/project/plans/2026-04-14-refactor-kb-routes-helpers-typed-errors-filenode-plan.md`
**Closes:** #2180, #2150, #2149
**Branch:** `feat-refactor-kb-routes`

## Phase 1 — Setup

- [ ] 1.1 Confirm worktree is clean (`git status`)
- [ ] 1.2 Baseline: run `node node_modules/vitest/vitest.mjs run` on KB suite (`test/github-api*`, `test/kb-*`, `test/file-tree-*`) — record current green baseline
- [ ] 1.3 Confirm `tsc --noEmit` is currently clean

## Phase 2 — #2149 Typed GitHubApiError (RED → GREEN → REFACTOR)

- [ ] 2.1 RED: create `apps/web-platform/test/github-api-error.test.ts` with failing assertions for the `GitHubApiError` class (instanceof, status, path, bodyText, message format, name)
- [ ] 2.2 RED: update `apps/web-platform/test/github-api.test.ts` to assert `handleErrorResponse` throws `GitHubApiError` with correct `.status` for 403/404/409/500
- [ ] 2.3 GREEN: implement `GitHubApiError` class in `apps/web-platform/server/github-api.ts`
- [ ] 2.4 GREEN: rewrite `handleErrorResponse` to throw `GitHubApiError` (preserving message format for backward compat)
- [ ] 2.5 REFACTOR: migrate 8 call sites to `instanceof GitHubApiError && err.status === N`
  - [ ] 2.5.1 `app/api/kb/file/[...path]/route.ts:126` (DELETE → GET 404)
  - [ ] 2.5.2 `app/api/kb/file/[...path]/route.ts:190` (DELETE → DELETE 409)
  - [ ] 2.5.3 `app/api/kb/file/[...path]/route.ts:204` (DELETE outer catch)
  - [ ] 2.5.4 `app/api/kb/file/[...path]/route.ts:383` (PATCH → GET 404)
  - [ ] 2.5.5 `app/api/kb/file/[...path]/route.ts:401` (PATCH → destination 404)
  - [ ] 2.5.6 `app/api/kb/file/[...path]/route.ts:514` (PATCH outer catch)
  - [ ] 2.5.7 `app/api/kb/upload/route.ts:169` (upload existence probe)
  - [ ] 2.5.8 `app/api/kb/upload/route.ts:272` (upload outer catch)
- [ ] 2.6 Run full KB test suite — confirm still green
- [ ] 2.7 Commit: `refactor(kb): introduce GitHubApiError with numeric status field`

## Phase 3 — #2180 Extract route helpers (RED → GREEN → REFACTOR)

- [ ] 3.1 RED: create `apps/web-platform/test/kb-route-helpers.test.ts` with failing tests for:
  - [ ] 3.1.1 `authenticateAndResolveKbPath` — all 10 validation branches
  - [ ] 3.1.2 `syncWorkspace` — happy path, failure path, cleanup guarantee
- [ ] 3.2 GREEN: create `apps/web-platform/server/kb-route-helpers.ts`
  - [ ] 3.2.1 Implement `authenticateAndResolveKbPath` with discriminated-union return
  - [ ] 3.2.2 Implement `syncWorkspace` with credential-helper scaffolding
  - [ ] 3.2.3 Export `KbRouteContext` type
- [ ] 3.3 REFACTOR DELETE handler to use both helpers — preserve response JSON shape byte-for-byte
- [ ] 3.4 REFACTOR PATCH handler to use both helpers — preserve response JSON shape byte-for-byte
- [ ] 3.5 Verify `kb-delete.test.ts` and `kb-rename.test.ts` still pass unchanged
- [ ] 3.6 Diff-check: compare response payloads (commitSha, oldPath, newPath, error codes) before/after
- [ ] 3.7 Commit: `refactor(kb): extract authenticateAndResolveKbPath + syncWorkspace helpers`

## Phase 4 — #2150 Extract FileNode component

- [ ] 4.1 Read current `apps/web-platform/components/kb/file-tree.tsx` in full
- [ ] 4.2 Identify file-only state (`deleteState`, `renameState`, rename refs) vs directory-only state (`uploadState`, file input ref)
- [ ] 4.3 Extract `FileNode` component (file rendering, rename input, delete confirmation, action buttons)
- [ ] 4.4 Slim `TreeItem` to directory-only; remove file-branch
- [ ] 4.5 Update child map in `TreeItem` to dispatch: `child.type === "directory" ? <TreeItem/> : <FileNode/>`
- [ ] 4.6 Keep icons (`FolderIcon`, `FileTypeIcon`, `UploadIcon`, `PencilIcon`, `TrashIcon`) and `formatRelativeTime` as module-scope helpers in the same file
- [ ] 4.7 Run `file-tree-delete.test.tsx`, `file-tree-rename.test.tsx`, `file-tree-upload.test.tsx` — expect all green unmodified
- [ ] 4.8 Manual smoke: load `/dashboard/kb/*` and verify upload / rename / delete / expand/collapse all work
- [ ] 4.9 Commit: `refactor(kb): split FileNode out of TreeItem`

## Phase 5 — Verification

- [ ] 5.1 Run `node node_modules/vitest/vitest.mjs run` on full KB + github-api suite — all green
- [ ] 5.2 Run `tsc --noEmit` — clean
- [ ] 5.3 Run `eslint` on changed files — clean
- [ ] 5.4 Diff against `main` — sanity-check scope:
  - [ ] 5.4.1 Only `server/github-api.ts`, `server/kb-route-helpers.ts`, `app/api/kb/file/[...path]/route.ts`, `app/api/kb/upload/route.ts`, `components/kb/file-tree.tsx` + corresponding tests changed
  - [ ] 5.4.2 No unrelated formatting drift
- [ ] 5.5 Re-read route files after refactor to confirm 100% byte-preserved response JSON
- [ ] 5.6 Run `skill: soleur:compound` per AGENTS.md before commit

## Phase 6 — Ship

- [ ] 6.1 `skill: soleur:ship` (runs review-gate, plan-review, semver label, PR open)
- [ ] 6.2 PR title: `refactor(kb): extract route helpers, typed GitHub errors, FileNode component split`
- [ ] 6.3 PR body includes `Closes #2180`, `Closes #2150`, `Closes #2149`
- [ ] 6.4 Semver label: `type/chore` (or `patch` — no user-visible change)
- [ ] 6.5 After CI green → `gh pr merge <N> --squash --auto`
- [ ] 6.6 Poll `gh pr view <N> --json state` until MERGED
- [ ] 6.7 `cleanup-merged` in worktree manager
- [ ] 6.8 Post-merge: verify `ship` Phase 7 release/deploy workflows pass
