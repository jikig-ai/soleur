# Tasks: KB REST API

**Issue:** #1688
**Plan:** `knowledge-base/project/plans/2026-04-07-feat-kb-rest-api-plan.md`
**Branch:** feat-kb-rest-api

## Phase 1: Core Implementation

- [x] 1.1 Add `gray-matter` (>= 4.0.3) to `apps/web-platform/package.json` dependencies
- [x] 1.2 Run `bun install` then `npm install` in `apps/web-platform/` to regenerate both lockfiles
- [x] 1.3 Create `apps/web-platform/server/kb-reader.ts` with types (`TreeNode`, `ContentResult`, `SearchResult`, `SearchMatch`)
- [x] 1.4 Implement `buildTree(kbRoot)` — recursive .md scan, empty dir exclusion, dirs-first sorting, relative paths only
- [x] 1.5 Implement `readContent(kbRoot, relativePath)` — null byte rejection, `isPathInWorkspace(filePath, kbRoot)`, .md check, stat size guard (>1MB reject), gray-matter with `{ engines: {} }`, YAML parse errors return `frontmatter: {}`
- [x] 1.6 Implement `searchKb(kbRoot, query)` — recursive .md find, escape regex chars, case-insensitive match, highlight offsets (char indices), frontmatter per match, sort by match count, cap at 100
- [x] 1.7 Create `apps/web-platform/app/api/kb/tree/route.ts` — auth + workspace lookup + logger.error on failure + buildTree
- [x] 1.8 Create `apps/web-platform/app/api/kb/content/[...path]/route.ts` — auth + workspace lookup + path join + logger.error + readContent
- [x] 1.9 Create `apps/web-platform/app/api/kb/search/route.ts` — auth + workspace lookup + validate q (required, max 200 chars) + logger.error + searchKb
- [x] 1.10 Create `apps/web-platform/test/kb-reader.test.ts` — unit tests for all functions:
  - [x] 1.10.1 buildTree: empty dir, nested, mixed types, sorting, missing KB dir
  - [x] 1.10.2 readContent: valid file, missing (404), non-.md (404), traversal (403), null bytes (403), frontmatter, no frontmatter, malformed YAML, dir path, file >1MB
  - [x] 1.10.3 searchKb: basic match, case insensitive, highlight offsets, max 100 cap, regex chars escaped, no matches, query too long

## Phase 2: Security Tests + Verification

- [x] 2.1 Create `apps/web-platform/test/kb-security.test.ts` — negative-space security tests (path validation coverage, no absolute paths in responses, route imports check)
- [x] 2.2 Run full test suite: `bun test` in `apps/web-platform/`
- [x] 2.3 Verify TypeScript compiles: `npx tsc --noEmit`
- [x] 2.4 Verify CSRF coverage test still passes (GET routes exempt)
- [x] 2.5 Verify both lockfiles are in sync
