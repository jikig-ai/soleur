---
title: "Tasks: refactor(kb) shared-page dedupe"
branch: feat-kb-shared-page-dedupe
plan: ../../plans/2026-04-17-refactor-kb-shared-page-dedupe-plan.md
date: 2026-04-17
---

# Tasks: refactor(kb) shared-page dedupe

Derived from `knowledge-base/project/plans/2026-04-17-refactor-kb-shared-page-dedupe-plan.md`.

## 1. Setup / context

- [x] 1.1 Confirm working directory is the `feat-kb-shared-page-dedupe` worktree
- [x] 1.2 Confirm `apps/web-platform/node_modules/` is populated (run `npm install` in `apps/web-platform/` if stale)

## 2. RED — failing tests (no implementation code yet)

- [x] 2.1 Create `apps/web-platform/test/classify-response.test.ts` with cases for 404, 410 revoked, 410 content-changed, 410 legacy-null-hash, !ok, markdown, pdf, image (including no-`Content-Disposition` → no `"file"` fallback), download, and fetch-throw
- [x] 2.2 Create `apps/web-platform/test/kb-content-header.test.tsx` covering with-download and without-download variants
- [x] 2.3 Create `apps/web-platform/test/kb-content-skeleton.test.tsx` covering default and custom-widths variants
- [x] 2.4 Create `apps/web-platform/test/shared-image-a11y.test.tsx` asserting `alt="Shared image"` + `title=<filename>`
- [x] 2.5 Update `apps/web-platform/test/shared-page-binary.test.ts` to assert `"Document no longer available"` on 404
- [x] 2.6 Update `apps/web-platform/test/kb-share.test.ts` (and `kb-share-allowed-paths.test.ts` if applicable) — symlink-rejected → `status: 403, error: "Access denied"`
- [x] 2.7 Run `./node_modules/.bin/vitest run` from `apps/web-platform/` and confirm RED state on 2.1–2.6

## 3. GREEN — implementation

- [x] 3.1 Create `apps/web-platform/components/kb/kb-content-skeleton.tsx` with `widths?` prop
- [x] 3.2 Add `KbContentSkeleton` to `apps/web-platform/components/kb/index.ts`
- [x] 3.3 Create `apps/web-platform/components/kb/kb-content-header.tsx` with paired `downloadHref` / `downloadFilename` props
- [x] 3.4 Add `KbContentHeader` to `apps/web-platform/components/kb/index.ts`
- [x] 3.5 Create `apps/web-platform/app/shared/[token]/classify-response.ts` with `SharedData`, `PageError`, `classifyResponse`, private `extractFilename` with filename-basename fallback
- [x] 3.6 Edit `apps/web-platform/app/shared/[token]/page.tsx` — replace `useEffect` body, import new helpers, swap inline skeleton for `<KbContentSkeleton />`, change image `alt="Shared image"` + `title={filename}`, delete inline `LoadingSkeleton` and `extractFilename`
- [x] 3.7 Edit `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — replace both `<header>` blocks with `<KbContentHeader …/>`, replace `<ContentSkeleton />` with `<KbContentSkeleton widths={["85%","70%","90%","65%","80%","75%"]} />`, delete `CONTENT_SKELETON_WIDTHS` + `ContentSkeleton`
- [x] 3.8 Edit `apps/web-platform/server/kb-share.ts` — flip `symlink-rejected` branch to `status: 403, error: "Access denied"`; widen `CreateShareResult` status union to include `403`
- [x] 3.9 Edit `apps/web-platform/app/api/shared/[token]/route.ts` — re-map binary branch 404 message to `"Document no longer available"`
- [x] 3.10 Run `./node_modules/.bin/vitest run` and confirm all previously-RED tests now GREEN
- [x] 3.11 Run `./node_modules/.bin/tsc --noEmit` and confirm zero type errors

## 4. REFACTOR + polish

- [x] 4.1 Run full vitest suite; investigate any pre-existing test that now fails (update the test's assertion cleanly; do not weaken it)
- [x] 4.2 Grep the web-platform for stale tokens: `extractFilename`, `LoadingSkeleton` (inside `shared/[token]`), `CONTENT_SKELETON_WIDTHS`, `ContentSkeleton`. Confirm only new-component references remain
- [x] 4.3 Grep for `"Invalid document path"` — verify the string is still present on null-byte / workspace-escape / not-a-file branches but GONE from the symlink-rejected branch
- [x] 4.4 Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-17-refactor-kb-shared-page-dedupe-plan.md knowledge-base/project/specs/feat-kb-shared-page-dedupe/tasks.md`
- [x] 4.5 Verify no `package.json` changes (no new deps)

## 5. Ship

- [ ] 5.1 Run `skill: soleur:compound` to capture learnings
- [ ] 5.2 Commit, push, open PR via `skill: soleur:ship`
- [ ] 5.3 PR body includes all five `Closes #…` lines (#2321, #2318, #2312, #2306, #2301), references #2486 as the pattern, includes a net-impact table, and notes the telemetry-grep migration (`code` tag vs. `error` string)
- [ ] 5.4 PR labels: `type/chore`, `domain/engineering`, `code-review`, `priority/p2-medium`, `semver:patch`
- [ ] 5.5 Milestone: `Phase 3: Make it Sticky`

## 6. Post-merge verification

- [ ] 6.1 Verify `/api/kb/share` POST against a symlink returns 403 (Playwright MCP or curl with Doppler-sourced CSRF token)
- [ ] 6.2 Verify `/api/shared/<expired-token>` binary path returns `"Document no longer available"`
- [ ] 6.3 Confirm all five issues auto-closed on merge; milestone counters updated
