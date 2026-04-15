# Tasks: Consolidate KB Viewer Action Buttons

Plan: `knowledge-base/project/plans/2026-04-15-fix-kb-viewer-action-buttons-ux-plan.md`

## 1. Tests first (TDD)

- [ ] 1.1 Add failing test: `FilePreview` with `showDownload={false}` hides internal filename/Download row for `.pdf` (`apps/web-platform/test/file-preview.test.tsx`)
- [ ] 1.2 Add failing test: `FilePreview` with `showDownload={false}` hides internal filename/Download row for `.txt`
- [ ] 1.3 Add failing test: PDF error fallback still renders a download link even with `showDownload={false}`
- [ ] 1.4 Add failing test: dashboard KB page header renders Download/Share/Chat trio in that order (`apps/web-platform/test/kb-page-header.test.tsx` or new block in `kb-page-routing.test.tsx`)
- [ ] 1.5 Add failing test: `KbBreadcrumb` decodes URL-encoded segments; returns raw segment when decoding throws (`apps/web-platform/test/kb-breadcrumb.test.tsx`)

## 2. Core implementation

- [ ] 2.1 Add `showDownload?: boolean` prop (default `true`) to `PdfPreview` (`apps/web-platform/components/kb/pdf-preview.tsx`); gate the filename/Download row on it; keep the error branch unchanged
- [ ] 2.2 Add `showDownload?: boolean` prop (default `true`) to `TextPreview` in `file-preview.tsx`; gate the filename/Download row
- [ ] 2.3 Add `showDownload?: boolean` prop (default `true`) to `FilePreview`; pass through to `PdfPreview` and `TextPreview`
- [ ] 2.4 Update `kb-breadcrumb.tsx` to decode segments via a `safeDecode` helper with try/catch fallback
- [ ] 2.5 Update dashboard page `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
  - [ ] Derive `filename = pathSegments[pathSegments.length - 1] ?? joinedPath`
  - [ ] Add a `Download` anchor in the non-markdown header BEFORE `<SharePopover />` with neutral-border styling matching Share
  - [ ] Pass `showDownload={false}` to `<FilePreview />` in the non-markdown branch
  - [ ] Do NOT add Download to the markdown-branch header
- [ ] 2.6 Verify shared viewer `app/shared/[token]/page.tsx` remains unchanged (relies on default `showDownload={true}`)

## 3. Verify

- [ ] 3.1 Run existing `apps/web-platform/test/file-preview.test.tsx` -- all prior tests pass (default `showDownload={true}` preserves behavior)
- [ ] 3.2 Run new tests from section 1 -- all green
- [ ] 3.3 Run full `apps/web-platform/` test script (per `package.json scripts.test`) from a worktree using `node node_modules/vitest/vitest.mjs run` (AGENTS.md rule `cq-in-worktrees-run-vitest-via-node-node`)
- [ ] 3.4 QA in dev server: dashboard PDF, dashboard TXT, dashboard markdown, dashboard CSV (fallback), shared PDF -- capture screenshots
- [ ] 3.5 Run `npx markdownlint-cli2 --fix` on changed `.md` files

## 4. Ship

- [ ] 4.1 Run `skill: soleur:compound`
- [ ] 4.2 `/ship` with `patch` semver label, attach QA screenshots in PR body
