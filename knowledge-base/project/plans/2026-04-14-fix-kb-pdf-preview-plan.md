---
title: "fix: Replace dead embed-based PDF preview with react-pdf viewer"
type: fix
date: 2026-04-14
---

# fix: Replace dead embed-based PDF preview with react-pdf viewer

## Overview

The KB file viewer's PDF preview is dead code. `file-preview.tsx` renders an `<embed>` tag, but `csp.ts` sets `object-src 'none'` which silently blocks it. Tests pass because happy-dom does not enforce CSP. Users see a blank rectangle with no error message.

The backend at `/api/kb/content/[...path]` already serves PDFs correctly with proper MIME type, `nosniff`, and sanitized `Content-Disposition` headers (PR from 2026-04-12 security hardening). Only the frontend rendering is broken.

## Problem Statement / Motivation

PDF preview was shipped as part of the KB viewer feature (Phase 3: Make it Sticky). The CSP policy was written to be restrictive by design (`object-src 'none'`, `frame-src 'none'`) -- which is correct security practice. However, the `<embed>` tag requires `object-src` to allow the PDF source, which conflicts with the restrictive policy.

Relaxing `object-src` is the wrong fix. The `<embed>` approach also has other problems:

- No page navigation -- renders the browser's built-in PDF viewer (inconsistent across browsers)
- No mobile support -- most mobile browsers do not render `<embed>` PDFs at all
- No control over rendering -- cannot style, paginate, or add a loading state

This is a PWA-first product where mobile must work.

## Proposed Solution

Replace `<embed>` with `react-pdf` (a React wrapper around Mozilla's pdf.js):

1. **Add `react-pdf` as app-level dependency** in `apps/web-platform/package.json`
2. **Dynamic-import the PDF component** to avoid bundling pdf.js on non-PDF routes (~500KB)
3. **Configure pdf.js worker** using `import.meta.url` pattern (same-origin, no CDN dependency)
4. **Add `blob:` to `worker-src`** in `csp.ts` -- pdf.js may create blob URLs for its worker
5. **Page-by-page navigation** with prev/next buttons and page indicator
6. **Keep download fallback button** (already exists)
7. **Update existing tests** to match the new component structure
8. **Regenerate lockfiles** -- both `bun.lock` and `package-lock.json` (Dockerfile uses `npm ci`)

## Technical Considerations

### CSP Changes

Current CSP in `csp.ts` (line 59): `worker-src 'self'`

pdf.js creates a Web Worker for parsing. When using the `import.meta.url` pattern, the worker file is served from the same origin (covered by `'self'`). However, some bundler configurations cause pdf.js to create a blob URL for the worker, which requires `blob:` in `worker-src`.

**Proposed change:** `worker-src 'self' blob:` -- minimal CSP relaxation. `object-src 'none'` and `frame-src 'none'` remain untouched.

### Next.js App Router + Dynamic Import

react-pdf uses `import.meta.url` and canvas APIs that are not available during SSR. The docs state: "In Next.js, make sure to skip SSR when importing the module."

Use Next.js `dynamic()` with `ssr: false`:

```typescript
// apps/web-platform/components/kb/file-preview.tsx
import dynamic from "next/dynamic";

const PdfPreview = dynamic(
  () => import("./pdf-preview").then((mod) => mod.PdfPreview),
  { ssr: false, loading: () => <PdfPreviewSkeleton /> }
);
```

The actual `PdfPreview` component lives in a separate file (`pdf-preview.tsx`) that configures the worker and imports react-pdf. This ensures the worker configuration happens in the same module as the components (per react-pdf docs).

### React 19 Compatibility

react-pdf v10.x supports React 19. The project uses `react: ^19.1.0`. No `swcMinify: false` workaround needed for Next.js 15+ (that was for pre-v15 only).

### Worker File Strategy

The `import.meta.url` approach is recommended by react-pdf docs and works with Next.js's webpack bundler. The worker file from `pdfjs-dist/build/pdf.worker.min.mjs` is resolved at build time. No need to manually copy the worker to `public/` -- the bundler handles it.

If the bundler approach fails (e.g., in production build), fall back to copying the worker to `public/pdf.worker.min.mjs` via a `postinstall` script.

### Mobile Memory

Page-by-page rendering (one `<Page>` component at a time) prevents loading all pages into memory simultaneously. This is critical for mobile PWA users with limited RAM.

### Bundle Impact

pdf.js core is ~500KB gzipped. Dynamic import ensures this only loads when a user opens a PDF file. Non-PDF routes are unaffected.

## Acceptance Criteria

- [ ] PDF files render correctly in the KB viewer with visible page content
- [ ] Page navigation (prev/next) works, showing current page and total pages
- [ ] Download button remains functional
- [ ] Loading state shown while PDF loads
- [ ] Error state with download fallback shown when PDF fails to load
- [ ] CSP `worker-src` updated to allow pdf.js worker (no other CSP relaxation)
- [ ] `object-src 'none'` and `frame-src 'none'` remain unchanged
- [ ] Component is dynamically imported (no pdf.js in non-PDF route bundles)
- [ ] Both `bun.lock` and `package-lock.json` regenerated
- [ ] Existing tests updated to reflect new component structure
- [ ] Works on mobile viewport (PWA)

## Test Scenarios

- Given a PDF file in the KB, when the user opens it in the viewer, then the first page renders visibly
- Given a multi-page PDF, when the user clicks "Next", then the next page renders and the page indicator updates
- Given a multi-page PDF on page 1, when the user clicks "Previous", then the button is disabled
- Given a multi-page PDF on the last page, when the user clicks "Next", then the button is disabled
- Given a PDF file, when it fails to load, then an error message and download fallback are shown
- Given a PDF file, when it is loading, then a loading spinner is shown
- Given a PDF file, when the user clicks "Download", then the file downloads with correct filename
- Given a non-PDF file, when opened in the viewer, then the PDF component is NOT loaded (dynamic import)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

This modifies an existing (broken) UI component. The visual design is minimal -- prev/next buttons and a page counter in the same style as existing KB viewer components. No new pages or user flows are introduced.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| react-pdf v10 incompatible with React 19 | Verified via context7 docs: v10.x supports React 19 |
| pdf.js worker blocked by CSP | Add `blob:` to `worker-src`; verify in production |
| Large bundle size from pdf.js | Dynamic import isolates to PDF routes only |
| `import.meta.url` fails in production build | Fallback: copy worker to `public/` with postinstall script |
| pdfjs-dist peer dependency conflict | Check `npm view react-pdf peerDependencies` before install |

## Files to Modify

- `apps/web-platform/package.json` -- add `react-pdf` dependency
- `apps/web-platform/components/kb/file-preview.tsx` -- replace inline `PdfPreview` with dynamic import
- `apps/web-platform/components/kb/pdf-preview.tsx` -- **new file**: react-pdf based component
- `apps/web-platform/lib/csp.ts` -- add `blob:` to `worker-src`
- `apps/web-platform/test/file-preview.test.tsx` -- update tests for new component structure
- `bun.lock` -- regenerated
- `apps/web-platform/package-lock.json` -- regenerated (if exists; Dockerfile uses `npm ci`)

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Relax `object-src` to allow `<embed>` | Rejected | Weakens CSP, no mobile support, no pagination |
| Use `<iframe>` with `frame-src` relaxation | Rejected | Same CSP tradeoff, inconsistent rendering |
| pdf.js directly (without react-pdf wrapper) | Rejected | More boilerplate, react-pdf handles canvas lifecycle |
| Server-side PDF-to-image conversion | Rejected | Over-engineered for this use case, adds server load |

## References

- Issue: [#2153](https://github.com/jikig-ai/soleur/issues/2153)
- [react-pdf docs](https://github.com/wojtekmaj/react-pdf)
- [pdf.js worker CSP requirements](https://github.com/nicolo-ribaudo/pdfjs-dist)
- Learning: `knowledge-base/project/learnings/security-issues/2026-04-12-binary-content-serving-security-headers.md`
- Learning: `knowledge-base/project/learnings/2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`
- CSP implementation: `apps/web-platform/lib/csp.ts`
