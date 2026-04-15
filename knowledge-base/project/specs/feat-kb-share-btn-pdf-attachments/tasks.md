# Tasks — fix KB share button on PDF attachments (#2232)

## Phase 1 — Setup & Failing Tests (TDD gate)

- [ ] 1.1 Delete `apps/web-platform/test/kb-share-md-only.test.ts` (behavior inverted).
- [ ] 1.2 Create `apps/web-platform/test/kb-share-allowed-paths.test.ts` with failing cases:
  - [ ] 1.2.1 allow `.md` path that exists → 200/201
  - [ ] 1.2.2 allow `.pdf` path that exists → 200/201
  - [ ] 1.2.3 allow `.png` path that exists → 200/201
  - [ ] 1.2.4 reject non-existent path → 404
  - [ ] 1.2.5 reject symlink → 400
  - [ ] 1.2.6 reject directory → 400
  - [ ] 1.2.7 reject path outside `kbRoot` → 400
- [ ] 1.3 Extend `apps/web-platform/test/kb-page-routing.test.tsx`:
  - [ ] 1.3.1 Assert `getByTestId("share")` present on `.pdf` branch.
  - [ ] 1.3.2 Assert `getByTestId("share")` present on `.png` branch.
  - [ ] 1.3.3 Assert `getByTestId("share")` still present on `.md` branch (regression).
- [ ] 1.4 Create `apps/web-platform/test/shared-page-binary.test.ts`:
  - [ ] 1.4.1 Fixture share record for `.pdf` → `/api/shared/[token]` returns `application/pdf`.
  - [ ] 1.4.2 Fixture share record for `.md` → `/api/shared/[token]` returns `application/json`.
  - [ ] 1.4.3 Revoked + 404 branches still work for non-markdown paths.
- [ ] 1.5 Create `apps/web-platform/test/shared-page-ui.test.tsx`:
  - [ ] 1.5.1 Mock `fetch` to return `application/pdf` → page renders `<PdfPreview>` stub.
  - [ ] 1.5.2 Mock `fetch` to return JSON → page renders `<MarkdownRenderer>` stub.
- [ ] 1.6 Review `apps/web-platform/test/share-links.test.ts` and update any `.md`-only assumptions.
- [ ] 1.7 Run test suite — confirm the new tests fail and all others pass.

## Phase 2 — Owner API

- [ ] 2.1 Edit `apps/web-platform/app/api/kb/share/route.ts`:
  - [ ] 2.1.1 Remove lines 32–37 (`.md` endsWith check).
  - [ ] 2.1.2 After `isPathInWorkspace` check, add `lstat` + `isFile()` + `isSymbolicLink()` validation.
  - [ ] 2.1.3 Add 50 MB file-size guard (same constant as `/api/kb/content`).
  - [ ] 2.1.4 Return 404 for non-existent, 400 for symlink/dir, 413 for oversize.
- [ ] 2.2 Run tests from 1.2 → green.

## Phase 3 — Shared Binary-Response Helper

- [ ] 3.1 Create `apps/web-platform/server/kb-binary-response.ts`:
  - [ ] 3.1.1 Export `MAX_BINARY_SIZE`, `CONTENT_TYPE_MAP`, `ATTACHMENT_EXTENSIONS`.
  - [ ] 3.1.2 Export `readBinaryFile(kbRoot, relativePath)` with lstat + symlink + size + readFile logic.
  - [ ] 3.1.3 Export `buildBinaryResponse({buffer, contentType, disposition, safeName})` with headers (Content-Type, Content-Disposition, Content-Length, X-Content-Type-Options, Cache-Control, CSP).
- [ ] 3.2 Refactor `apps/web-platform/app/api/kb/content/[...path]/route.ts` to call the helper; delete inlined duplicates.
- [ ] 3.3 Run existing kb-content tests → still green (no behavior change).

## Phase 4 — Public Viewer API

- [ ] 4.1 Edit `apps/web-platform/app/api/shared/[token]/route.ts`:
  - [ ] 4.1.1 Compute `ext = path.extname(shareLink.document_path).toLowerCase()`.
  - [ ] 4.1.2 Fork: `.md | ""` → existing `readContent` → JSON; else → `readBinaryFile` + `buildBinaryResponse`.
  - [ ] 4.1.3 Log `event: "shared_page_viewed"` in both branches.
  - [ ] 4.1.4 Keep 404 / 410 / 403 / 429 branches shared across both forks.
- [ ] 4.2 Run tests from 1.4 → green.

## Phase 5 — UI Wiring

- [ ] 5.1 Edit `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` non-markdown branch:
  - [ ] 5.1.1 Wrap the "Chat about this" link in a `<div className="flex items-center gap-2">`.
  - [ ] 5.1.2 Insert `<SharePopover documentPath={joinedPath} />` before the link.
- [ ] 5.2 Run tests from 1.3 → green.

## Phase 6 — Public Viewer Page

- [ ] 6.1 Edit `apps/web-platform/app/shared/[token]/page.tsx`:
  - [ ] 6.1.1 After `fetch(/api/shared/${token})`, check `res.headers.get("Content-Type")`.
  - [ ] 6.1.2 Branch: `application/json` → existing flow; `application/pdf` → `<PdfPreview src={...} filename={...} />`; `image/*` → `<img>`; else → download link.
  - [ ] 6.1.3 Derive filename from `Content-Disposition` header or token; pass to embed.
  - [ ] 6.1.4 Ensure `noindex` meta and CTA banner still render for all types.
- [ ] 6.2 Run tests from 1.5 → green.

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
