---
title: "fix: Replace dead embed-based PDF preview with react-pdf viewer"
type: fix
date: 2026-04-14
deepened: 2026-04-14
---

# fix: Replace dead embed-based PDF preview with react-pdf viewer

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 6 (Technical Considerations, Acceptance Criteria, Test Scenarios, Files to Modify, Dependencies, Implementation Details)
**Research sources:** Context7 react-pdf docs, npm registry, 5 project learnings, codebase pattern analysis

### Key Improvements

1. Added concrete code examples for `pdf-preview.tsx` and dynamic import pattern
2. Verified react-pdf v10.4.1 peer deps explicitly support React 19 (`^19.0.0`)
3. Identified testing sharp edge: esbuild in vitest does not support React 19 `<Context value>` shorthand -- must use `.Provider` pattern
4. Added canvas mock requirement for vitest (react-pdf renders to `<canvas>`)
5. Identified `next/dynamic` as first usage in codebase -- no existing patterns to follow
6. Confirmed both `bun.lock` (repo root) and `package-lock.json` (app-level) lockfile locations

### Applicable Learnings

- `2026-04-10-react-context-provider-breaks-existing-tests.md`: Use `.Provider` pattern, mock new dependencies in all affected test files
- `2026-03-30-npm-latest-tag-crosses-major-versions.md`: Install `react-pdf@10` not `react-pdf@latest` to avoid future major version drift
- `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`: CSP and rendering mode must agree; verify worker-src change works in production build
- `2026-04-12-binary-content-serving-security-headers.md`: Backend already hardened with nosniff + async I/O -- no backend changes needed
- `2026-04-07-kb-viewer-react-context-layout-patterns.md`: Existing dark theme patterns (neutral-800, amber accents) must be followed

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

#### Research Insights

**Learning applied** (`2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`): CSP and rendering mode must agree. The root layout already forces dynamic rendering (fixed in PR #1213), so the nonce propagates correctly. The `worker-src` change only affects web worker loading, not script execution. Verify in production build that the worker loads without CSP violations by checking the browser console.

**Verification step:** After implementation, run `npm run build` and serve locally to confirm no CSP errors in the browser console. CSP violations in happy-dom tests are not detectable -- this must be verified in a real browser.

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

#### Research Insights

**First `next/dynamic` usage in codebase:** No existing patterns to follow. This establishes the convention for future dynamic imports. The pattern is straightforward: separate the heavy component into its own file, import via `dynamic()`, provide a skeleton loading state.

**Critical from react-pdf docs:** "The `workerSrc` must be set in the **same module** where you use React-PDF components. Setting it in a separate file and then importing React-PDF in another component may cause the default value to overwrite your custom setting due to module execution order." This is why the worker config and the `Document`/`Page` usage must be in `pdf-preview.tsx`, not in `file-preview.tsx`.

**Loading skeleton pattern** (from codebase analysis): The KB viewer uses this spinner pattern consistently: `<div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />`. Use the same for the PDF loading state.

### React 19 Compatibility

react-pdf v10.4.1 (latest) supports React 19. Peer dependencies verified via npm registry:

```text
react: ^16.8.0 || ^17.0.0 || ^18.0.0 || ^19.0.0
react-dom: ^16.8.0 || ^17.0.0 || ^18.0.0 || ^19.0.0
@types/react: ^16.8.0 || ^17.0.0 || ^18.0.0 || ^19.0.0
```

The project uses `react: ^19.1.0`. No `swcMinify: false` workaround needed for Next.js 15+ (that was for pre-v15 only).

**Learning applied** (`2026-03-30-npm-latest-tag-crosses-major-versions.md`): Install with `npm install react-pdf@10` not `react-pdf@latest` to pin to the current major and avoid future cross-major jumps.

### Worker File Strategy

The `import.meta.url` approach is recommended by react-pdf docs and works with Next.js's webpack bundler. The worker file from `pdfjs-dist/build/pdf.worker.min.mjs` is resolved at build time. No need to manually copy the worker to `public/` -- the bundler handles it.

If the bundler approach fails (e.g., in production build), fall back to copying the worker to `public/pdf.worker.min.mjs` via a `postinstall` script.

#### Concrete Implementation

```typescript
// apps/web-platform/components/kb/pdf-preview.tsx
import { pdfjs } from "react-pdf";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();
```

**Note from react-pdf docs:** This MUST be in the same file that renders `<Document>` and `<Page>`. Module execution order can cause the default value to overwrite the custom setting if configured in a separate file.

### Mobile Memory

Page-by-page rendering (one `<Page>` component at a time) prevents loading all pages into memory simultaneously. This is critical for mobile PWA users with limited RAM.

### Bundle Impact

pdf.js core is ~500KB gzipped. Dynamic import ensures this only loads when a user opens a PDF file. Non-PDF routes are unaffected.

## Implementation Reference

### pdf-preview.tsx (new file)

```tsx
// apps/web-platform/components/kb/pdf-preview.tsx
"use client";

import { useState } from "react";
import { Document, Page, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();

interface PdfPreviewProps {
  src: string;
  filename: string;
}

export function PdfPreview({ src, filename }: PdfPreviewProps) {
  const [numPages, setNumPages] = useState(0);
  const [pageNumber, setPageNumber] = useState(1);
  const [error, setError] = useState(false);

  if (error) {
    return <PdfDownloadFallback src={src} filename={filename} />;
  }

  return (
    <div className="flex h-full flex-col gap-3 p-4">
      <div className="flex items-center justify-between">
        <span className="text-sm text-neutral-400">{filename}</span>
        <a
          href={src}
          download={filename}
          className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800"
        >
          Download
        </a>
      </div>

      <div className="flex-1 overflow-auto rounded-lg border border-neutral-800 bg-neutral-900/50">
        <Document
          file={src}
          onLoadSuccess={({ numPages: n }) => setNumPages(n)}
          onLoadError={() => setError(true)}
          loading={
            <div className="flex items-center justify-center p-8">
              <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
            </div>
          }
        >
          <Page
            pageNumber={pageNumber}
            renderTextLayer={false}
            renderAnnotationLayer={false}
            className="mx-auto"
          />
        </Document>
      </div>

      {numPages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={() => setPageNumber((p) => Math.max(p - 1, 1))}
            disabled={pageNumber <= 1}
            className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Previous
          </button>
          <span className="text-xs text-neutral-400">
            Page {pageNumber} of {numPages}
          </span>
          <button
            onClick={() => setPageNumber((p) => Math.min(p + 1, numPages))}
            disabled={pageNumber >= numPages}
            className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}

function PdfDownloadFallback({ src, filename }: { src: string; filename: string }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
      <p className="text-sm text-neutral-400">Unable to preview this PDF</p>
      <a
        href={src}
        download={filename}
        className="inline-flex items-center gap-2 rounded-lg border border-amber-500/50 px-4 py-2 text-sm font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
      >
        Download {filename}
      </a>
    </div>
  );
}
```

### file-preview.tsx changes

```tsx
// Replace the inline PdfPreview function with:
import dynamic from "next/dynamic";

const PdfPreview = dynamic(
  () => import("./pdf-preview").then((mod) => mod.PdfPreview),
  {
    ssr: false,
    loading: () => (
      <div className="flex items-center justify-center p-8">
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
      </div>
    ),
  },
);
// Remove the old PdfPreview function entirely (lines 82-103)
```

### csp.ts change

```diff
-    "worker-src 'self'",
+    "worker-src 'self' blob:",
```

## Acceptance Criteria

- [x] PDF files render correctly in the KB viewer with visible page content
- [x] Page navigation (prev/next) works, showing current page and total pages
- [x] Download button remains functional
- [x] Loading state shown while PDF loads
- [x] Error state with download fallback shown when PDF fails to load
- [x] CSP `worker-src` updated to allow pdf.js worker (no other CSP relaxation)
- [x] `object-src 'none'` and `frame-src 'none'` remain unchanged
- [x] Component is dynamically imported (no pdf.js in non-PDF route bundles)
- [x] Both `bun.lock` and `package-lock.json` regenerated
- [x] Existing tests updated to reflect new component structure
- [x] Works on mobile viewport (PWA)

## Test Scenarios

- Given a PDF file in the KB, when the user opens it in the viewer, then the first page renders visibly
- Given a multi-page PDF, when the user clicks "Next", then the next page renders and the page indicator updates
- Given a multi-page PDF on page 1, when the user clicks "Previous", then the button is disabled
- Given a multi-page PDF on the last page, when the user clicks "Next", then the button is disabled
- Given a PDF file, when it fails to load, then an error message and download fallback are shown
- Given a PDF file, when it is loading, then a loading spinner is shown
- Given a PDF file, when the user clicks "Download", then the file downloads with correct filename
- Given a non-PDF file, when opened in the viewer, then the PDF component is NOT loaded (dynamic import)

### Testing Sharp Edges

**Canvas mocking:** react-pdf renders to `<canvas>`. happy-dom provides a basic canvas element but does not implement the 2D rendering context. Tests should mock `react-pdf` at the module level rather than trying to render actual PDFs:

```typescript
vi.mock("react-pdf", () => ({
  Document: ({ children, onLoadSuccess }: any) => {
    // Simulate successful load
    onLoadSuccess?.({ numPages: 3 });
    return <div data-testid="pdf-document">{children}</div>;
  },
  Page: ({ pageNumber }: any) => (
    <div data-testid="pdf-page">Page {pageNumber}</div>
  ),
  pdfjs: { GlobalWorkerOptions: { workerSrc: "" } },
}));
```

**Dynamic import mocking:** `next/dynamic` with `ssr: false` makes testing harder since the component is loaded asynchronously. Mock the dynamic import to render the component synchronously:

```typescript
vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: (loader: () => Promise<any>) => {
    // Resolve the dynamic import synchronously for tests
    const Component = (props: any) => {
      const [Loaded, setLoaded] = useState<any>(null);
      useEffect(() => { loader().then(setLoaded); }, []);
      return Loaded ? <Loaded {...props} /> : null;
    };
    return Component;
  },
}));
```

**Learning applied** (`2026-04-10-react-context-provider-breaks-existing-tests.md`): When adding new module-level dependencies (react-pdf, next/dynamic), search all test files that render `FilePreview` and add appropriate mocks. Use `.Provider` pattern, not React 19 `<Context value>` shorthand (esbuild limitation in vitest).

**Test runner** (from `package.json`): `vitest` is the configured runner. In worktrees, use `node node_modules/vitest/vitest.mjs run` not `npx vitest run`.

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

This modifies an existing (broken) UI component. The visual design is minimal -- prev/next buttons and a page counter in the same style as existing KB viewer components. No new pages or user flows are introduced.

## Dependencies and Risks

| Risk | Mitigation | Status |
|------|-----------|--------|
| react-pdf v10 incompatible with React 19 | Verified: v10.4.1 peer deps include `^19.0.0` | Resolved |
| pdf.js worker blocked by CSP | Add `blob:` to `worker-src`; verify in browser after build | Open -- verify post-impl |
| Large bundle size from pdf.js (~500KB gz) | Dynamic import isolates to PDF routes only | Mitigated by design |
| `import.meta.url` fails in production build | Fallback: copy worker to `public/` with postinstall script | Low risk -- recommended approach |
| pdfjs-dist peer dependency conflict | Verified: transitive dep of react-pdf, no conflicts | Resolved |
| CSS imports for annotation/text layers | Import `react-pdf/dist/Page/AnnotationLayer.css` and `TextLayer.css` in the component file; these are small and only loaded via dynamic import | Noted |
| Canvas not available in happy-dom | Mock react-pdf at module level in tests (see Testing Sharp Edges) | Mitigated by design |

### Research Note: AnnotationLayer and TextLayer CSS

react-pdf ships two optional CSS files for rendering text selection overlays and link annotations. The plan disables both layers (`renderTextLayer={false}`, `renderAnnotationLayer={false}`) to keep the initial implementation simple. The CSS imports are included but inert when layers are disabled. If text selection is added later, these imports are already in place.

## Files to Modify

| File | Action | Details |
|------|--------|---------|
| `apps/web-platform/package.json` | Edit | Add `react-pdf@10` to dependencies |
| `apps/web-platform/components/kb/pdf-preview.tsx` | **Create** | New file: react-pdf component with worker config, page nav, error handling |
| `apps/web-platform/components/kb/file-preview.tsx` | Edit | Replace inline `PdfPreview` (lines 82-103) with `next/dynamic` import; add loading skeleton |
| `apps/web-platform/lib/csp.ts` | Edit | Line 59: `worker-src 'self'` to `worker-src 'self' blob:` |
| `apps/web-platform/test/file-preview.test.tsx` | Edit | Mock `react-pdf` and `next/dynamic`; update PDF test case; add nav tests |
| `bun.lock` (repo root) | Regenerate | `bun install` from repo root |
| `apps/web-platform/package-lock.json` | Regenerate | `npm install` from `apps/web-platform/` (Dockerfile uses `npm ci`) |

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
