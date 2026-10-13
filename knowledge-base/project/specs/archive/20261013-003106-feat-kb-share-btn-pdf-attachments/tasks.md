# Tasks — fix KB share button on PDF attachments (#2232)

## Phase 1 — Setup & Failing Tests (TDD gate)

- [x] 1.1 Delete `apps/web-platform/test/kb-share-md-only.test.ts` (behavior inverted).
- [x] 1.2 Create `apps/web-platform/test/kb-share-allowed-paths.test.ts` with failing cases:
  - [x] 1.2.1 allow `.md` path that exists → 200/201
  - [x] 1.2.2 allow `.pdf` path that exists → 200/201
  - [x] 1.2.3 allow `.png` path that exists → 200/201
  - [x] 1.2.4 reject non-existent path → 404
  - [x] 1.2.5 reject symlink → 400
  - [x] 1.2.6 reject directory → 400
  - [x] 1.2.7 reject path outside `kbRoot` → 400
- [x] 1.3 Extend `apps/web-platform/test/kb-page-routing.test.tsx`:
  - [x] 1.3.1 Assert `getByTestId("share")` present on `.pdf` branch.
  - [x] 1.3.2 Assert `getByTestId("share")` present on `.png` branch.
  - [x] 1.3.3 Assert `getByTestId("share")` still present on `.md` branch (regression).
- [x] 1.4 Create `apps/web-platform/test/shared-page-binary.test.ts`:
  - [x] 1.4.1 Fixture share record for `.pdf` → `/api/shared/[token]` returns `application/pdf`.
  - [x] 1.4.2 Fixture share record for `.md` → `/api/shared/[token]` returns `application/json`.
  - [x] 1.4.3 Revoked + 404 branches still work for non-markdown paths.
- [x] 1.5 Create `apps/web-platform/test/shared-page-ui.test.tsx`:
  - [x] 1.5.1 Mock `fetch` to return `application/pdf` → page renders `<PdfPreview>` stub.
  - [x] 1.5.2 Mock `fetch` to return JSON → page renders `<MarkdownRenderer>` stub.
- [x] 1.6 Review `apps/web-platform/test/share-links.test.ts` and update any `.md`-only assumptions.
- [x] 1.7 Run test suite — confirm the new tests fail and all others pass.

## Phase 2 — Owner API

- [x] 2.1 Edit `apps/web-platform/app/api/kb/share/route.ts`:
  - [x] 2.1.1 Remove lines 32–37 (`.md` endsWith check).
  - [x] 2.1.2 After `isPathInWorkspace` check, add `lstat` + `isFile()` + `isSymbolicLink()` validation.
  - [x] 2.1.3 Add 50 MB file-size guard (same constant as `/api/kb/content`).
  - [x] 2.1.4 Return 404 for non-existent, 400 for symlink/dir, 413 for oversize.
- [x] 2.2 Run tests from 1.2 → green.

## Phase 3 — Shared Binary-Response Helper

- [x] 3.1 Create `apps/web-platform/server/kb-binary-response.ts`:
  - [x] 3.1.1 Export `MAX_BINARY_SIZE`, `CONTENT_TYPE_MAP`, `ATTACHMENT_EXTENSIONS`.
  - [x] 3.1.2 Export `readBinaryFile(kbRoot, relativePath)` with lstat + symlink + size + readFile logic.
  - [x] 3.1.3 Export `buildBinaryResponse({buffer, contentType, disposition, safeName})` with headers (Content-Type, Content-Disposition, Content-Length, X-Content-Type-Options, Cache-Control, CSP).
- [x] 3.2 Refactor `apps/web-platform/app/api/kb/content/[...path]/route.ts` to call the helper; delete inlined duplicates.
- [x] 3.3 Run existing kb-content tests → still green (no behavior change).

## Phase 4 — Public Viewer API

- [x] 4.1 Edit `apps/web-platform/app/api/shared/[token]/route.ts`:
  - [x] 4.1.1 Compute `ext = path.extname(shareLink.document_path).toLowerCase()`.
  - [x] 4.1.2 Fork: `.md | ""` → existing `readContent` → JSON; else → `readBinaryFile` + `buildBinaryResponse`.
  - [x] 4.1.3 Log `event: "shared_page_viewed"` in both branches.
  - [x] 4.1.4 Keep 404 / 410 / 403 / 429 branches shared across both forks.
- [x] 4.2 Run tests from 1.4 → green.

## Phase 5 — UI Wiring

- [x] 5.1 Edit `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` non-markdown branch:
  - [x] 5.1.1 Wrap the "Chat about this" link in a `<div className="flex items-center gap-2">`.
  - [x] 5.1.2 Insert `<SharePopover documentPath={joinedPath} />` before the link.
- [x] 5.2 Run tests from 1.3 → green.

## Phase 6 — Public Viewer Page

- [x] 6.1 Edit `apps/web-platform/app/shared/[token]/page.tsx`:
  - [x] 6.1.1 After `fetch(/api/shared/${token})`, check `res.headers.get("Content-Type")`.
  - [x] 6.1.2 Branch: `application/json` → existing flow; `application/pdf` → `<PdfPreview src={...} filename={...} />`; `image/*` → `<img>`; else → download link.
  - [x] 6.1.3 Derive filename from `Content-Disposition` header or token; pass to embed.
  - [x] 6.1.4 Ensure `noindex` meta and CTA banner still render for all types.
- [x] 6.2 Run tests from 1.5 → green.

## Phase 7 — Manual QA

- [ ] 7.1 Log in, upload a PDF to KB via existing upload UI.
- [ ] 7.2 Verify "Share" button appears on the PDF page.
- [ ] 7.3 Click Share → Generate link → copy.
- [ ] 7.4 Open the link in a private window → verify PDF renders inline with Soleur header + CTA banner.
- [ ] 7.5 Revoke the link → re-open → verify "revoked" error UI.
- [ ] 7.6 Upload a PNG, repeat 7.2–7.5 with inline image render.
- [ ] 7.7 Share an existing `.md` file → verify markdown flow unchanged (regression).
- [ ] 7.8 Capture before/after screenshots for PR.

## Phase 8 — Review, Ship, Postmerge

- [ ] 8.1 Push branch, spawn `plan-review` for this plan (if deepen-plan not already ran it).
- [ ] 8.2 Run `skill: soleur:compound` before commit.
- [ ] 8.3 Run `skill: soleur:ship` — include `Closes #2232` in PR body.
- [ ] 8.4 Queue auto-merge, poll until MERGED.
- [ ] 8.5 Run `skill: soleur:postmerge` — verify release/deploy workflows succeed, confirm production serves shared PDF endpoint.
