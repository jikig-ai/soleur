---
title: "fix: KB upload progress indicator and PDF form data validation"
type: fix
date: 2026-04-13
semver: patch
deepened: 2026-04-13
---

# fix: KB upload progress indicator and PDF form data validation

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, MVP)
**Research sources:** Context7 Next.js docs, Next.js 15.5.15 source code analysis, institutional learnings

### Key Improvements

1. **Root cause correction:** The `export const config = { api: { bodyParser } }` pattern is **Pages Router only**. App Router route handlers use the native Web Request API with no built-in body size limit. The "Invalid form data" error needs investigation via improved error logging before prescribing a fix.
2. **XHR implementation details:** Concrete code patterns for XMLHttpRequest with FormData, including proper error handling for all response codes (409, 4xx, 5xx, network errors).
3. **SVG circular progress:** Exact `stroke-dasharray`/`stroke-dashoffset` math and CSS transition pattern for the progress ring.

### New Considerations Discovered

- Next.js App Router does NOT enforce a 1MB body limit on route handlers (only Server Actions have `bodySizeLimit` at 1MB default). The "Invalid form data" error may have a different root cause than originally hypothesized.
- The custom server (`server/index.ts`) uses `http.createServer()` with no body size limits. The request flows through `handle(req, res, parsedUrl)` to the App Router route handler.
- The middleware runs on `/api/kb/upload` but does NOT consume the request body (only reads cookies and headers).

## Overview

Two issues with the KB file upload feature need fixing: (1) the upload shows only a spinning wheel with no progress feedback, and (2) PDF uploads fail with "Invalid form data". The root cause of issue 2 needs investigation -- the original hypothesis of a 1MB body limit was based on Pages Router behavior that does not apply to App Router route handlers.

## Problem Statement

### Issue 1: No upload progress feedback

When a user uploads a file via the KB file tree, the `UploadSpinner` component (`file-tree.tsx:351-358`) renders an indeterminate spinning circle. For large files (up to 20MB), this provides no indication of how far along the upload is. The upload uses `fetch()` (`file-tree.tsx:74-77`) which does not expose upload progress events natively.

### Issue 2: "Invalid form data" on PDF upload

The upload route handler (`app/api/kb/upload/route.ts:96-101`) calls `request.formData()` inside a try/catch. When this throws, it returns `{ error: "Invalid form data" }` with status 400.

**Root cause analysis (updated after deep research):**

The original hypothesis was that Next.js App Router enforces a 1MB body limit. This is **incorrect**:

- The `export const config = { api: { bodyParser: { sizeLimit } } }` pattern is for **Pages Router** (`docs/02-pages/`). It does NOT work in App Router route handlers.
- App Router route handlers receive a Web `Request` object. `request.formData()` uses the native Web API implementation with no built-in size limit.
- The `serverActions.bodySizeLimit` setting (1MB default) applies only to **Server Actions**, not route handlers.
- The custom server (`server/index.ts`) uses `http.createServer()` with no body size limits.
- The middleware runs on `/api/kb/upload` but only reads cookies/headers, not the body.

**Likely actual causes to investigate:**

1. **Node.js IncomingMessage-to-Web-Request stream conversion:** Next.js converts the Node.js IncomingMessage to a Web Request for App Router. Large file uploads may encounter stream buffering issues during this conversion.
2. **Content-Type header issues:** If the `multipart/form-data` boundary is missing or malformed, `formData()` throws. Check if any proxy/middleware strips or modifies the Content-Type header.
3. **Undici/Node.js FormData parser limits:** Node.js 21.x uses undici's FormData parser internally, which may have undocumented size limits on fields or files.
4. **Memory pressure:** For a 20MB file, the entire body must be buffered in memory. If the server is under memory pressure, the stream can fail.

**Investigation approach:** Add detailed error logging in the catch block to capture the actual exception type and message before prescribing a fix.

### Research Insights

**Next.js version context:**

- Installed version: `next@15.5.15` with Node.js v21.7.3
- Uses custom server (`server/index.ts`) with `http.createServer()` -- NOT standalone output mode
- The `proxyClientMaxBodySize` experimental config (default 10MB) is for the proxy feature, not route handlers

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

### Research Insights: XMLHttpRequest with FormData

**XHR pattern for file upload with progress:**

```typescript
function xhrUpload(
  url: string,
  formData: FormData,
  onProgress: (percent: number) => void,
): Promise<{ status: number; body: unknown }> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);

    // Do NOT set Content-Type -- browser auto-sets multipart/form-data with boundary
    // Setting it manually breaks the boundary parameter

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    };

    xhr.onload = () => {
      try {
        const body = JSON.parse(xhr.responseText);
        resolve({ status: xhr.status, body });
      } catch {
        resolve({ status: xhr.status, body: { error: "Invalid response" } });
      }
    };

    xhr.onerror = () => reject(new Error("Network error"));
    xhr.ontimeout = () => reject(new Error("Upload timed out"));

    xhr.send(formData);
  });
}
```

**Edge cases for XHR:**

- `lengthComputable` can be `false` if the server or proxy strips `Content-Length` -- fall back to indeterminate spinner in this case
- `xhr.upload.onprogress` fires for the upload phase only (client-to-server). After upload completes (100%), the server still needs to process the file (base64 encode, GitHub API call, git pull). Consider showing "Processing..." after 100%
- XHR does not include credentials by default -- `xhr.withCredentials` is not needed since cookies are same-origin
- `xhr.timeout` can be set for very large files (e.g., 120000ms for 20MB on slow connections)

### Research Insights: SVG Circular Progress

**SVG circle progress ring pattern:**

```typescript
function UploadProgress({ percent }: { percent: number }) {
  const radius = 4.5;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percent / 100) * circumference;

  return (
    <svg width="12" height="12" viewBox="0 0 12 12" className="shrink-0">
      {/* Background circle (track) */}
      <circle
        cx="6" cy="6" r={radius}
        fill="none" stroke="currentColor" strokeWidth="1.5"
        className="text-amber-400/30"
      />
      {/* Progress arc */}
      <circle
        cx="6" cy="6" r={radius}
        fill="none" stroke="currentColor" strokeWidth="1.5"
        className="text-amber-400 transition-[stroke-dashoffset] duration-300 ease-linear"
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        transform="rotate(-90 6 6)"
      />
    </svg>
  );
}
```

**Key details:**

- `transform="rotate(-90 6 6)"` starts the arc at 12 o'clock instead of 3 o'clock
- `transition-[stroke-dashoffset] duration-300 ease-linear` provides smooth animation between progress updates
- The track circle uses 30% opacity of the same amber color for visual consistency
- At `percent=0`, `offset=circumference` (no arc visible). At `percent=100`, `offset=0` (full circle)
- Same dimensions (12x12) as the existing `UploadSpinner` for drop-in replacement

### Fix 2: Investigate and fix "Invalid form data" error

**Phase 1: Diagnostic (before fixing):**

Add detailed error logging to the `formData()` catch block to capture the actual exception:

```typescript
// Replace current catch block (lines 98-101):
try {
  formData = await request.formData();
} catch (err) {
  const errMsg = err instanceof Error ? err.message : String(err);
  const errName = err instanceof Error ? err.name : "Unknown";
  logger.error(
    { event: "kb_upload_formdata_error", errName, errMsg, userId: user?.id },
    "kb/upload: formData parsing failed",
  );
  Sentry.captureException(err);
  return NextResponse.json(
    { error: "Invalid form data", detail: errMsg },
    { status: 400 },
  );
}
```

**Phase 2: Apply fix based on diagnosis.**

Possible fixes depending on what the logging reveals:

1. **If body size limit:** Add explicit body size limit awareness. Since `export const config` does not work in App Router, the fix would be to stream-parse the body manually or add `experimental.proxyClientMaxBodySize` to `next.config.ts` if the proxy feature is involved.
2. **If Content-Type issue:** Check if the middleware or custom server modifies headers.
3. **If Node.js stream issue:** Use `request.arrayBuffer()` then manually parse multipart data, or upgrade Node.js.
4. **If memory issue:** Already addressed by the streaming chunks approach in the route (lines 203-209).

**Files to modify:**

- `apps/web-platform/app/api/kb/upload/route.ts` -- Improve error logging and apply fix

## Technical Considerations

### Progress indicator implementation

- `XMLHttpRequest.upload.onprogress` provides `loaded` and `total` -- percentage = `Math.round((loaded / total) * 100)`
- The XHR must set no explicit `Content-Type` header so the browser auto-sets `multipart/form-data` with the correct boundary (same as `fetch()` behavior with `FormData`)
- The response handling (409 duplicate, error, success) must be preserved in the XHR `onload` handler
- CSS transitions on `stroke-dashoffset` provide smooth animation without JavaScript animation frames
- After upload reaches 100%, show a brief "Processing..." state while the server handles the GitHub API call and git pull (these are fast but non-zero)

### Research Insights: Performance

- The XHR `upload.onprogress` event fires frequently (potentially every few KB). React state updates should be debounced or use `requestAnimationFrame` to avoid excessive re-renders. However, since only a single number (0-100) changes and the SVG update is minimal, this is unlikely to be a bottleneck in practice.
- The SVG `stroke-dashoffset` animation via CSS transition offloads rendering to the GPU compositor, so even frequent progress updates produce smooth animation.

### Body size investigation

- **Key finding:** Next.js App Router route handlers do NOT have a configurable `bodySizeLimit`. The `export const config = { api: { bodyParser } }` pattern is Pages Router only and will be silently ignored in App Router.
- The `serverActions.bodySizeLimit` (default 1MB) applies only to Server Actions, not route handlers.
- The custom server passes requests through `handle(req, res, parsedUrl)` with no body interception.
- Investigation must proceed empirically: add logging, reproduce the error, read the actual exception.

### Existing patterns

- The codebase uses `fetch()` everywhere for API calls -- XHR is only needed for upload progress
- The `ALLOWED_ATTACHMENT_TYPES` in `attachment-constants.ts` includes `application/pdf` -- the type allowlist is not the issue
- The upload route already validates by file extension (line 125-131), not MIME type
- The attachment presign route (`app/api/attachments/presign/route.ts`) is a separate upload path for chat attachments and does not use the same mechanism

### Relevant learnings

- `2026-04-12-file-upload-arraybuffer-memory-copy.md`: The route already uses streaming chunks for base64 encoding (not `file.arrayBuffer()`). The current approach streams `Uint8Array` chunks via `file.stream().getReader()` to avoid intermediate `ArrayBuffer` allocation.
- `kb-upload-missing-credential-helper-20260413.md`: Credential helper was recently fixed; the workspace sync path is working. The credential helper pattern now exists in 4 places -- a future refactor should extract `withGitCredentials(installationId, fn)`.
- `2026-04-12-binary-content-serving-security-headers.md`: Content-Disposition header injection and nosniff headers were fixed in the content serving route. Verify the upload route does not introduce similar issues.
- Test runner is vitest (not bun test). Run tests from `apps/web-platform/` directory using `npx vitest run`.

### Research Insights: Edge Cases

- **Network interruption during upload:** XHR `onerror` fires. The UI should show "Network error. Please try again." (matching existing behavior).
- **Server timeout:** The upload route has no explicit timeout on the GitHub API call. For very large files, the base64 encoding + GitHub PUT could take significant time. The git pull has a 30s timeout (line 239). Consider adding a total route timeout.
- **Concurrent uploads:** Each folder has independent `uploadState`. Two concurrent uploads to different folders work. Two uploads to the same folder are prevented by the `isUploading` check that hides the upload button.
- **Browser tab close during upload:** XHR is automatically aborted. No cleanup needed server-side since the GitHub API call hasn't started yet (the file hasn't been fully received).

## Acceptance Criteria

- [ ] Uploading a file shows a circular progress indicator that fills from 0% to 100%
- [ ] The progress indicator shows the percentage numerically for files that take more than ~1 second
- [ ] The progress indicator smoothly animates between progress updates (CSS transition)
- [ ] After upload reaches 100%, a brief processing state is shown before returning to idle
- [ ] PDF files up to 20MB upload successfully without "Invalid form data" error
- [ ] The `formData()` catch block logs the actual exception type and message to Sentry
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
- Given a user is uploading a file, when the upload reaches 50%, then the circular indicator shows approximately half filled with a smooth CSS transition
- Given a user uploads a small file (< 100KB), when the upload completes quickly, then the indicator briefly shows and returns to idle without jarring animation
- Given a user uploads a file, when the upload progress reaches 100%, then a processing indicator shows briefly before the tree refreshes
- Given a user uploads a file on a connection where `lengthComputable` is false, when the upload starts, then the indicator falls back to an indeterminate animation (spinning)

### PDF upload fix

- Given a user selects a 2MB PDF file, when the upload is submitted, then the server accepts the form data and returns 201 (not 400 "Invalid form data")
- Given a user selects a 15MB PDF file, when the upload is submitted, then the server accepts the form data and the file is committed to GitHub
- Given a user selects a 25MB file, when the file is selected, then the client rejects it before sending (existing client-side validation)
- Given `request.formData()` throws an error, when the error is caught, then the actual exception name and message are logged to the server logger and Sentry

### Regression

- Given a user uploads a file that already exists, when the server returns 409, then the duplicate confirmation dialog appears correctly
- Given the GitHub API returns an error during upload, when the server returns 502, then the error message displays correctly
- Given a network error occurs during XHR upload, when the connection fails, then a "Network error" message displays
- Given the user is uploading and the XHR timeout fires, when the connection is slow, then an appropriate timeout error displays

## Non-Goals

- Drag-and-drop upload (separate feature)
- Multi-file upload (separate feature)
- Upload cancellation button (could be added later with `XMLHttpRequest.abort()`)
- Server-sent progress events for the GitHub API commit step (the progress indicator covers the upload to the Next.js server; the subsequent GitHub API call and git pull are fast relative to the upload)
- Extracting `withGitCredentials()` helper (tracked in the credential-helper learning; separate refactor)

## MVP

### Implementation phases

**Phase 1: Diagnose and fix "Invalid form data" error**

1. Add detailed error logging to the `formData()` catch block in `apps/web-platform/app/api/kb/upload/route.ts`:
   - Log `err.name`, `err.message`, `err.stack` to pino logger
   - Send exception to Sentry with `Sentry.captureException(err)`
   - Include `userId` in log context for correlation
2. Attempt to reproduce the error locally by uploading a PDF > 1MB via the dev server
3. Based on the error diagnosis, apply the appropriate fix:
   - If body size limit: investigate Node.js/undici FormData parser limits
   - If Content-Type: check header forwarding through custom server
   - If stream error: consider alternative body reading approach
4. Add test case verifying large file upload in `apps/web-platform/test/kb-upload.test.ts`
5. Run `npx vitest run` from `apps/web-platform/` to verify all tests pass

**Phase 2: Add upload progress indicator**

1. Update `UploadState` type in `apps/web-platform/components/kb/file-tree.tsx`:

   ```typescript
   | { status: "uploading"; progress: number }
   ```

2. Create `xhrUpload()` helper function wrapping XMLHttpRequest in a Promise with `upload.onprogress`
3. Replace `fetch()` call in `uploadFile` callback with `xhrUpload()`, updating progress state via `setUploadState`
4. Create `UploadProgress` component using SVG circle with `stroke-dasharray`/`stroke-dashoffset`:
   - Same 12x12 dimensions as existing `UploadSpinner`
   - Amber color matching existing theme
   - CSS `transition-[stroke-dashoffset] duration-300 ease-linear` for smooth animation
   - `transform="rotate(-90 6 6)"` to start at 12 o'clock
5. Replace `<UploadSpinner />` with `<UploadProgress percent={uploadState.progress} />` in directory node render
6. Handle post-upload processing state (after 100%, before server responds)
7. Handle `lengthComputable=false` fallback to indeterminate animation
8. Add tests for XHR upload and progress state transitions
9. Remove `UploadSpinner` component if fully replaced

**Phase 3: Cleanup and validation**

1. Run full test suite: `npx vitest run` from `apps/web-platform/`
2. Run `npx markdownlint-cli2 --fix` on changed markdown files
3. Verify the upload flow end-to-end (if dev server is available)

## References

- `apps/web-platform/app/api/kb/upload/route.ts` -- Server-side upload route (lines 96-101: formData catch block)
- `apps/web-platform/components/kb/file-tree.tsx` -- Client-side file tree with upload UI (lines 65-101: uploadFile, lines 351-358: UploadSpinner)
- `apps/web-platform/test/kb-upload.test.ts` -- Existing server-side tests (19 tests)
- `apps/web-platform/lib/attachment-constants.ts` -- Shared attachment validation constants
- `apps/web-platform/next.config.ts` -- Next.js configuration (no body size override present)
- `apps/web-platform/server/index.ts` -- Custom server with http.createServer()
- `apps/web-platform/middleware.ts` -- Middleware (runs on /api/kb/upload, does not consume body)
- `knowledge-base/project/learnings/performance-issues/2026-04-12-file-upload-arraybuffer-memory-copy.md` -- Streaming chunks pattern
- `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md` -- Credential helper fix
- Next.js App Router Route Handler docs: route handlers use Web Request API, not Pages Router `config.api.bodyParser`
- MDN XMLHttpRequest.upload.onprogress: <https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest/upload>
