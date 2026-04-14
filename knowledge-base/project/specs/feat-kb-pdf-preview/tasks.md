# Tasks: Fix KB PDF Preview

Plan: `knowledge-base/project/plans/2026-04-14-fix-kb-pdf-preview-plan.md`
Issue: #2153

## Phase 1: Setup

- [ ] 1.1 Install `react-pdf` in `apps/web-platform/package.json`
  - Run `npm install react-pdf@10` from `apps/web-platform/` (pin major to avoid cross-major drift)
  - Verify `pdfjs-dist` is pulled as transitive dependency
  - Verify no React 19 peer dependency conflicts (already verified: `^19.0.0` in peer deps)
- [ ] 1.2 Regenerate lockfiles
  - Run `bun install` from repo root to update `bun.lock`
  - Run `npm install` from `apps/web-platform/` to update `package-lock.json`
  - Verify both lockfiles reflect the new dependency

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/components/kb/pdf-preview.tsx`
  - Configure pdf.js worker via `import.meta.url` pattern (in same module)
  - Implement `PdfPreview` component with `Document` + `Page` from react-pdf
  - Page-by-page rendering with `useState` for `pageNumber` and `numPages`
  - Prev/Next navigation buttons with disabled states at boundaries
  - Page indicator: "Page X of Y"
  - Loading spinner state while PDF loads
  - Error state with download fallback
  - Download button in header bar
  - Match existing dark theme styling (neutral-800 borders, neutral-300 text, amber accents)
- [ ] 2.2 Update `apps/web-platform/components/kb/file-preview.tsx`
  - Replace inline `PdfPreview` function with `dynamic()` import from `./pdf-preview`
  - Use `ssr: false` option on the dynamic import
  - Add loading skeleton component for the dynamic import fallback
- [ ] 2.3 Update `apps/web-platform/lib/csp.ts`
  - Change `worker-src 'self'` to `worker-src 'self' blob:` (line 59)
  - No other CSP changes -- `object-src 'none'` and `frame-src 'none'` stay

## Phase 3: Testing

- [ ] 3.1 Update `apps/web-platform/test/file-preview.test.tsx`
  - Mock `react-pdf` at module level (Document, Page, pdfjs) -- happy-dom lacks canvas
  - Mock `next/dynamic` to render the PDF component synchronously in tests
  - Update "renders embed for .pdf files" test -- no longer checks for `<embed>`
  - Add test: PDF component receives correct `src` and `filename` props
  - Add test: download button rendered for PDF files
  - Add test: page navigation buttons appear for multi-page PDFs
  - Add test: error state shows download fallback
  - Keep all non-PDF tests unchanged (image, text, docx, csv, lightbox)
  - Use `.Provider` pattern not React 19 `<Context value>` shorthand (esbuild limitation)
- [ ] 3.2 Run test suite
  - Run `node node_modules/vitest/vitest.mjs run` from `apps/web-platform/`
  - Verify all tests pass (both `unit` and `component` projects)

## Phase 4: Verification

- [ ] 4.1 Verify build succeeds
  - Run `npm run build` from `apps/web-platform/` (catches TypeScript errors)
- [ ] 4.2 Verify lockfile consistency
  - Confirm `bun.lock` at repo root is updated
  - Confirm `package-lock.json` in `apps/web-platform/` is updated
  - Both must reflect `react-pdf` and `pdfjs-dist`
