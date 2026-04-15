# Plan: Consolidate KB Viewer Action Buttons (Download into header row)

**Type:** fix (UX / UI polish)
**Branch:** `feat-kb-viewer-action-buttons-ux`
**Target files:**

- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`
- `apps/web-platform/components/kb/file-preview.tsx`
- `apps/web-platform/components/kb/pdf-preview.tsx`
- `apps/web-platform/components/kb/kb-breadcrumb.tsx`
- `apps/web-platform/app/shared/[token]/page.tsx` (shared viewer passthrough)
- `apps/web-platform/test/file-preview.test.tsx`

## Problem

In the KB document viewer (see `/home/jean/Pictures/Screenshots/Screenshot From 2026-04-15 15-00-05.png`), the top action row shows `Share` and `Chat about this` on the right. Immediately below the breadcrumb header there is a **second row** containing the filename on the left and an isolated `Download` button on the right. This second row:

1. Duplicates information already present in the breadcrumb (the last segment IS the filename).
2. Splits the document's action buttons across two rows, which is inconsistent and takes vertical space.
3. The duplicated filename is actually uglier than the breadcrumb (e.g. `Au Chat Pôtan - Pitch Projet.pdf.pdf` below vs URL-encoded path in breadcrumb) -- see "Out of scope / adjacent fix" below, which addresses the breadcrumb encoding at the same time.

The result is ~56 px of vertical space above the PDF viewer that could go to the document itself.

## Goal

- A single header row in the dashboard KB viewer: `breadcrumb` on the left; `Download`, `Share`, `Chat about this` on the right (in that order).
- Remove the second filename/Download row from `PdfPreview` and `TextPreview` when rendered inside the dashboard viewer.
- Preserve download capability on the **shared** (`/shared/[token]`) viewer -- it has no header action row, so `PdfPreview`/`TextPreview` must still offer their internal download there.
- Decode breadcrumb segments so the in-header title is human-readable (it replaces the readable duplicated title we are removing).

## Non-Goals

- No change to the `SharePopover` UI, copy, or API.
- No change to the `chat about this` link or leader routing.
- No change to the `DownloadPreview` fallback used for unsupported extensions (CSV, DOCX) -- there, the download button IS the whole UI and belongs in the body.
- No change to PDF pagination, image lightbox, or markdown renderer.
- No styling overhaul of the header; match existing button sizes/colors (Share = neutral border, Chat = amber border).

## Current State (before)

Dashboard `page.tsx` non-markdown branch (lines 102-136):

```tsx
<header>
  <KbBreadcrumb path={joinedPath} />
  <SharePopover /> <Chat about this />
</header>
<FilePreview path extension />   // PdfPreview renders its own `filename + Download` row inside
```

`PdfPreview` (lines 48-59):

```tsx
<div className="flex items-center justify-between">
  <span>{filename}</span>
  <a href={src} download={filename}>Download</a>
</div>
```

`TextPreview` (lines 134-145): same pattern.

## Target State (after)

Dashboard `page.tsx` non-markdown branch:

```tsx
<header>
  <KbBreadcrumb path={joinedPath} />            {/* decoded */}
  <DownloadLink href={`/api/kb/content/${joinedPath}`} filename={filename} />
  <SharePopover />
  <ChatAboutThis />
</header>
<FilePreview ... showDownload={false} />
```

`PdfPreview` and `TextPreview` accept a `showDownload?: boolean` prop (default `true` to preserve shared viewer). When `false`, the filename/Download row is omitted entirely.

## Implementation

### Step 1 -- Decode breadcrumb segments

File: `apps/web-platform/components/kb/kb-breadcrumb.tsx`

Wrap each segment in `decodeURIComponent` with a try/catch fallback (malformed URI should not crash the page). This is the only change needed for the breadcrumb to render `Au Chat Pôtan - Pitch Projet.pdf.pdf` instead of `Au%20Chat%20P%C3%B4tan%20-%20Pitch%20Projet.pdf.pdf`.

```tsx
// kb-breadcrumb.tsx
function safeDecode(s: string): string {
  try { return decodeURIComponent(s); } catch { return s; }
}
// ...then use {safeDecode(segment)} instead of {segment}
```

**Why this is in scope:** we're removing the readable second-line title, so the breadcrumb becomes the only human title -- it must be readable.

### Step 2 -- Add `showDownload` prop to `PdfPreview`

File: `apps/web-platform/components/kb/pdf-preview.tsx`

```tsx
interface PdfPreviewProps {
  src: string;
  filename: string;
  showDownload?: boolean;  // NEW, default true
}

export function PdfPreview({ src, filename, showDownload = true }: PdfPreviewProps) {
  // ...existing error branch unchanged (keeps Download -- the page can't render the PDF, download IS the only affordance)
  // ...main branch:
  return (
    <div className="flex h-full flex-col gap-3 p-4">
      {showDownload && (
        <div className="flex items-center justify-between">
          <span className="text-sm text-neutral-400">{filename}</span>
          <a href={src} download={filename} className="...">Download</a>
        </div>
      )}
      <div ref={containerRef} ...>...</div>
      ...
    </div>
  );
}
```

Note: keep the download link in the **error branch** regardless of `showDownload` -- if the PDF fails to render, the download anchor is the user's only recovery path and the outer header may not be present (e.g. during render error fallback).

### Step 3 -- Add `showDownload` prop to `TextPreview`

File: `apps/web-platform/components/kb/file-preview.tsx`

```tsx
function TextPreview({ src, filename, showDownload = true }: { src: string; filename: string; showDownload?: boolean }) {
  // ...
  return (
    <div className="flex flex-col gap-3 p-4">
      {showDownload && (
        <div className="flex items-center justify-between">
          <span>{filename}</span>
          <a href={src} download={filename} className="...">Download</a>
        </div>
      )}
      <pre>...</pre>
    </div>
  );
}
```

### Step 4 -- Thread `showDownload={false}` through `FilePreview` for the dashboard

File: `apps/web-platform/components/kb/file-preview.tsx`

```tsx
interface FilePreviewProps {
  path: string;
  extension: string;
  showDownload?: boolean;   // NEW, default true for backwards compat
}

export function FilePreview({ path, extension, showDownload = true }: FilePreviewProps) {
  // ...
  if (ext === ".pdf") return <PdfPreview src={contentUrl} filename={filename} showDownload={showDownload} />;
  if (ext === ".txt") return <TextPreview src={contentUrl} filename={filename} showDownload={showDownload} />;
  // DownloadPreview and ImagePreview are unchanged -- DownloadPreview IS the download UI.
}
```

### Step 5 -- Add a `Download` link to the dashboard header and pass `showDownload={false}`

File: `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`

Add a small presentational helper (inline) that renders the download link styled to match `SharePopover`'s trigger (neutral border, `px-3 py-1.5 text-xs`). Insert it to the **left** of `<SharePopover />` so the order reads: Download, Share, Chat (from least to most committing action -- Download is idempotent / no state, Share mutates share state, Chat navigates away).

```tsx
// Inside both the non-markdown header (line ~118) and -- NO, only the non-markdown header
// (the markdown branch doesn't render a download; markdown files don't need one).

const filename = pathSegments[pathSegments.length - 1] ?? joinedPath;
const contentUrl = `/api/kb/content/${joinedPath}`;

// Place BEFORE <SharePopover />:
<a
  href={contentUrl}
  download={filename}
  aria-label={`Download ${filename}`}
  className="inline-flex items-center gap-1.5 rounded-lg border border-neutral-700 px-3 py-1.5 text-xs font-medium text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
>
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" strokeLinecap="round" strokeLinejoin="round" />
    <polyline points="7 10 12 15 17 10" strokeLinecap="round" strokeLinejoin="round" />
    <line x1="12" y1="15" x2="12" y2="3" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
  Download
</a>
```

Then:

```tsx
<FilePreview path={joinedPath} extension={extension} showDownload={false} />
```

**Markdown branch:** do NOT add a Download button -- markdown files have no meaningful "download" and the current UI does not offer one. Leave the markdown header as-is (Share + Chat only).

### Step 6 -- Preserve shared viewer behavior

File: `apps/web-platform/app/shared/[token]/page.tsx`

No change required. It passes no `showDownload` prop, so it defaults to `true`, which preserves today's behavior: the shared PDF viewer still shows the filename + Download row at the top of the PDF (this is the only affordance for a shared viewer, and there is no outer action row to hoist it into).

### Step 7 -- Update tests

File: `apps/web-platform/test/file-preview.test.tsx`

1. `renders download button for PDF files` (line 87) -- keep, but it remains passing because the **default** `showDownload={true}` is preserved for the direct component test.
2. Add a new test: `hides internal download row when showDownload is false`.
3. Add a new test: `PDF error fallback still renders a download link even with showDownload={false}` (verifies the error branch is unaffected).
4. Add a new test for `TextPreview`: `hides internal download row when showDownload is false`.

File: `apps/web-platform/test/kb-page-routing.test.tsx`

No change required -- FilePreview is mocked.

New file: `apps/web-platform/test/kb-page-header.test.tsx` (or add a `describe` block to an existing page test file if pattern matches)

Tests the dashboard non-markdown header renders three action elements in order: Download anchor, Share trigger, Chat link. Verifies `Download` anchor has `href="/api/kb/content/<path>"` and `download="<filename>"`.

File: `apps/web-platform/test/kb-breadcrumb.test.tsx` (create if it doesn't exist)

Tests: `decodes URL-encoded segments`, `returns raw segment when decoding throws`.

## Acceptance Criteria

- [ ] In the dashboard KB viewer for a PDF, the header row shows (left → right): breadcrumb, Download, Share, Chat about this. No second row above the PDF viewer.
- [ ] The breadcrumb segments are URL-decoded (e.g. `Au Chat Pôtan - Pitch Projet.pdf.pdf`, not `Au%20Chat...`).
- [ ] Clicking the header Download triggers a file download with the correct filename from the URL.
- [ ] In the dashboard KB viewer for a `.txt` file, the same applies: header has Download, body no longer has the filename/Download row, but the `<pre>` text content is still there.
- [ ] In the shared viewer (`/shared/<token>`), the PDF view **still** shows its internal filename + Download row at the top (no regression).
- [ ] Markdown files in the dashboard still render with just Share + Chat in the header (no Download added -- unchanged).
- [ ] `DownloadPreview` (CSV/DOCX fallback) is unchanged -- the centered download card still renders.
- [ ] PDF error fallback (when rendering fails) still shows a `Download <filename>` link regardless of `showDownload`.
- [ ] Existing `file-preview.test.tsx` tests pass; new tests for `showDownload={false}` and decoded breadcrumb pass.
- [ ] No visual regressions in the shared viewer or markdown viewer (QA with screenshots).

## Test Scenarios

1. **PDF in dashboard:** navigate to `/dashboard/kb/<encoded path>.pdf`; expect single header with Download/Share/Chat, PDF viewer begins directly below header.
2. **PDF in shared viewer:** visit a `/shared/<token>` link to a PDF; expect the inner filename/Download row to still be present.
3. **TXT in dashboard:** same consolidation as PDF.
4. **Markdown in dashboard:** header has only Share/Chat (unchanged).
5. **CSV/DOCX in dashboard:** header has Download/Share/Chat; body renders `DownloadPreview` centered card (unchanged). This means a CSV viewer now has TWO download affordances -- acceptable because the centered card is the primary empty-state CTA while the header is the always-available action row. If a reviewer objects, alternative: for extensions that render via `DownloadPreview`, skip the header Download. Default stance: keep the redundancy; it's cheap and self-documenting.
6. **PDF render error in dashboard:** confirm the fallback centered `Download <filename>` link still shows (the error branch keeps its own download unconditionally).
7. **Breadcrumb with special characters:** path `folder/Au Chat Pôtan - Pitch.pdf` renders `folder / Au Chat Pôtan - Pitch.pdf` in the breadcrumb.
8. **Breadcrumb with malformed URI:** a path with an invalid `%` escape must not throw (fallback to raw segment).

## Risks

- **Redundant download for CSV/DOCX.** The `DownloadPreview` fallback keeps a centered Download button; adding one to the header means two buttons. Mitigation: accept the redundancy as documented in Test Scenario 5, or narrow the header Download to types where the body doesn't already offer one. Lean toward accepting redundancy -- it's predictable (header always has it) and self-consistent.
- **Shared-page coupling.** A future contributor might remove `showDownload` default or change the default to `false` thinking it's dead code. Mitigation: add a short JSDoc on the prop explaining "default true preserves shared viewer affordance."
- **Breadcrumb decoding scope creep.** This is one line in `kb-breadcrumb.tsx` plus a safety try/catch. Low risk.

## Alternative Approaches Considered

| Approach | Pros | Cons | Chosen? |
|---|---|---|---|
| A. Add `showDownload` prop (default true), thread through FilePreview | Minimal API change, preserves shared page behavior, no duplication | Adds one prop | **Yes** |
| B. Remove internal Download from PdfPreview entirely, add separate Download to shared page | Cleaner PdfPreview API (no prop) | Requires touching shared page layout; every caller must re-implement the download | No |
| C. Lift `filename` into breadcrumb itself and hide it everywhere else | Single source of truth for the title | Adds knowledge-of-filename styling to breadcrumb; confusing responsibility | No |
| D. Keep both rows but tighten spacing | Zero risk | Doesn't address the core UX complaint | No |

## Domain Review

**Domains relevant:** Product (UX polish)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline, ADVISORY tier)
**Agents invoked:** none (pipeline mode, ADVISORY tier with no new user flow, no brand-copy changes, no new persuasive surfaces)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

- Modifies an existing page layout; no new user-facing surface or flow.
- No copy changes beyond button labels that already exist (`Download`).
- No navigation path changes (Chat, Share links are untouched).
- Mechanical escalation rule does NOT fire: no new files in `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` (only edits).
- Out of scope for BLOCKING tier.

## Out of Scope / Adjacent Fix Noted

- **Double `.pdf.pdf` suffix** on the example filename (`...Projet.pdf.pdf`) likely comes from the upload pipeline appending `.pdf` to an already-`.pdf`-suffixed user input. This is a data quality issue, not a viewer bug. If a reviewer wants it addressed, file a separate issue -- do NOT fix it in this PR.

## Rollout

- [ ] Implement per steps 1-7.
- [ ] Run `bun test` (or the project's test script per `package.json scripts.test`) in `apps/web-platform/`.
- [ ] Run the dev server, QA the four scenarios (PDF/TXT/markdown/CSV) in the dashboard + PDF in shared viewer, attach screenshots in PR.
- [ ] Ship via `/ship` with `patch` semver label (UX polish, no behavior-break).

## References

- Screenshot: `/home/jean/Pictures/Screenshots/Screenshot From 2026-04-15 15-00-05.png`
- Prior KB viewer plan: `knowledge-base/project/plans/2026-04-07-feat-kb-viewer-ui-plan.md`
- KB share button for PDFs: `knowledge-base/project/plans/2026-04-15-fix-kb-share-button-pdf-attachments-plan.md`
- Related fix (SSR crash on shared PDF): commit `c0b5ec8e` (dynamic-import PdfPreview)
