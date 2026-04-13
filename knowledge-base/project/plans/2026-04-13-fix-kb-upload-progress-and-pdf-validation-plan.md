---
title: "fix: KB upload progress indicator and PDF form data validation"
type: fix
date: 2026-04-13
semver: patch
---

# fix: KB upload progress indicator and PDF form data validation

## Overview

Two issues with the KB file upload feature need fixing: (1) the upload shows only a spinning wheel with no progress feedback, and (2) PDF uploads fail with "Invalid form data" because Next.js App Router enforces a default 1MB body size limit on route handlers, and the upload route does not override it.

## Problem Statement

### Issue 1: No upload progress feedback

When a user uploads a file via the KB file tree, the `UploadSpinner` component (`file-tree.tsx:351-358`) renders an indeterminate spinning circle. For large files (up to 20MB), this provides no indication of how far along the upload is. The upload uses `fetch()` (`file-tree.tsx:74-77`) which does not expose upload progress events natively.

### Issue 2: "Invalid form data" on PDF upload

The upload route handler (`app/api/kb/upload/route.ts:96-101`) calls `request.formData()` inside a try/catch. When this throws, it returns `{ error: "Invalid form data" }` with status 400. The root cause: Next.js App Router route handlers have a **default body size limit of 1MB**. The route does not export a route segment config to increase this limit. Any file over 1MB (common for PDFs) causes `request.formData()` to throw a body-too-large error, which the catch block surfaces as the generic "Invalid form data" message.

**Evidence:** The route has `MAX_FILE_SIZE = 20 * 1024 * 1024` (20MB) on line 29, but no `export const config` or route segment config to raise Next.js's body parsing limit to match.

## Proposed Solution

### Fix 1: Add upload progress indicator

Replace the indeterminate `UploadSpinner` with a circular progress indicator that fills based on upload percentage. Since `fetch()` does not support upload progress, switch to `XMLHttpRequest` which exposes the `upload.onprogress` event with `loaded` and `total` bytes.

**Files to modify:**

- `apps/web-platform/components/kb/file-tree.tsx` -- Replace `fetch()` in `uploadFile` with `XMLHttpRequest`, track progress percentage in state, pass to a new `UploadProgress` component

**Approach:**

1. Add a `progress` field (0-100) to the `UploadState` type's `uploading` variant
2. Replace the `fetch()` call in `uploadFile` with an `XMLHttpRequest` wrapped in a Promise
3. Attach an `upload.onprogress` handler that updates progress state
4. Replace the `UploadSpinner` SVG with a circular progress indicator (SVG circle with `stroke-dasharray`/`stroke-dashoffset` animated by CSS transition)
5. Show percentage text only when progress > 0 (avoids flicker for fast uploads)

### Fix 2: Configure body size limit for upload route

Export a route segment config from the upload route to allow bodies up to 20MB (matching the existing `MAX_FILE_SIZE` constant).

**Files to modify:**

- `apps/web-platform/app/api/kb/upload/route.ts` -- Add route segment config

**Code change:**

```typescript
// Add at the top of route.ts, after imports:
export const config = {
  api: {
    bodyParser: {
      sizeLimit: "20mb",
    },
  },
};
```

**Note:** For Next.js App Router (not Pages Router), the correct approach may differ. Verify via Next.js docs whether App Router uses `export const config` with `api.bodyParser.sizeLimit` or a different mechanism. The App Router route segment config uses `export const maxDuration`, `export const dynamic`, etc. -- body size may need a different pattern. Check if `request.formData()` respects a different limit configuration.

**Alternative for App Router:** If App Router does not support `config.api.bodyParser`, the fix may require using the `experimental.serverActions.bodySizeLimit` in `next.config.ts` or handling streaming parsing manually. Research the exact Next.js App Router body size configuration before implementing.

## Technical Considerations

### Progress indicator implementation

- `XMLHttpRequest.upload.onprogress` provides `loaded` and `total` -- percentage = `Math.round((loaded / total) * 100)`
- The XHR must set no explicit `Content-Type` header so the browser auto-sets `multipart/form-data` with the correct boundary (same as `fetch()` behavior with `FormData`)
- The response handling (409 duplicate, error, success) must be preserved in the XHR `onload` handler
- CSS transitions on `stroke-dashoffset` provide smooth animation without JavaScript animation frames

### Body size limit

- The existing `MAX_FILE_SIZE` constant (20MB) must match the server-side body limit
- The client already validates file size before upload (`file-tree.tsx:118-120`), so the server limit is defense-in-depth
- The error message should be more specific than "Invalid form data" -- catch the specific body-too-large error if possible

### Existing patterns

- The codebase uses `fetch()` everywhere for API calls -- XHR is only needed for upload progress
- The `ALLOWED_ATTACHMENT_TYPES` in `attachment-constants.ts` includes `application/pdf` -- the type allowlist is not the issue
- The upload route already validates by file extension (line 125-131), not MIME type

### Relevant learnings

- `2026-04-12-file-upload-arraybuffer-memory-copy.md`: The route already uses streaming chunks for base64 encoding (not `file.arrayBuffer()`)
- `kb-upload-missing-credential-helper-20260413.md`: Credential helper was recently fixed; the workspace sync path is working
- Test runner is vitest, not bun test (check `package.json` scripts)

## Acceptance Criteria

- [ ] Uploading a file shows a circular progress indicator that fills from 0% to 100%
- [ ] The progress indicator shows the percentage numerically for files that take more than ~1 second
- [ ] PDF files up to 20MB upload successfully without "Invalid form data" error
- [ ] Files over 20MB are still rejected with a clear size error message (client-side validation)
- [ ] The duplicate detection flow (409 response) still works correctly with XHR
- [ ] Error states (network error, server error) still display correctly
- [ ] The upload button is hidden during upload (existing behavior preserved)
- [ ] Existing tests pass; new tests cover the progress and body size scenarios

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## Test Scenarios

### Progress indicator

- Given a user selects a 5MB PNG file for upload, when the upload starts, then a circular progress bar appears in place of the folder chevron, filling from 0% toward 100%
- Given a user is uploading a file, when the upload reaches 50%, then the circular indicator shows approximately half filled
- Given a user uploads a small file (< 100KB), when the upload completes quickly, then the indicator briefly shows and returns to idle without jarring animation

### PDF upload fix

- Given a user selects a 2MB PDF file, when the upload is submitted, then the server accepts the form data and returns 201 (not 400 "Invalid form data")
- Given a user selects a 15MB PDF file, when the upload is submitted, then the server accepts the form data and the file is committed to GitHub
- Given a user selects a 25MB file, when the file is selected, then the client rejects it before sending (existing client-side validation)

### Regression

- Given a user uploads a file that already exists, when the server returns 409, then the duplicate confirmation dialog appears correctly
- Given the GitHub API returns an error during upload, when the server returns 502, then the error message displays correctly
- Given a network error occurs during upload, when fetch/XHR fails, then a "Network error" message displays

## Non-Goals

- Drag-and-drop upload (separate feature)
- Multi-file upload (separate feature)
- Upload cancellation button (could be added later with `XMLHttpRequest.abort()`)
- Server-sent progress events for the GitHub API commit step (the progress indicator covers the upload to the Next.js server; the subsequent GitHub API call and git pull are fast relative to the upload)

## MVP

### Implementation phases

**Phase 1: Fix PDF upload (body size limit)**

1. Research the correct Next.js App Router body size configuration
2. Add the appropriate config export to `app/api/kb/upload/route.ts`
3. Improve the error message in the `formData()` catch block to distinguish body-too-large from malformed data
4. Add test case for large file upload

**Phase 2: Add upload progress indicator**

1. Update `UploadState` type to include `progress: number` in the uploading variant
2. Replace `fetch()` with `XMLHttpRequest` in the `uploadFile` function
3. Create `UploadProgress` component (circular SVG with animated stroke)
4. Replace `UploadSpinner` usage with `UploadProgress` when uploading
5. Add tests for the XHR upload and progress state transitions

## References

- `apps/web-platform/app/api/kb/upload/route.ts` -- Server-side upload route
- `apps/web-platform/components/kb/file-tree.tsx` -- Client-side file tree with upload UI
- `apps/web-platform/test/kb-upload.test.ts` -- Existing server-side tests (19 tests)
- `apps/web-platform/lib/attachment-constants.ts` -- Shared attachment validation constants
- `apps/web-platform/next.config.ts` -- Next.js configuration (no body size override present)
- Next.js App Router Route Segment Config docs for body size limits
