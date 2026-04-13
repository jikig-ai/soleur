---
title: "fix: KB PDF upload fails with FormData parse error for files > 10MB"
type: fix
date: 2026-04-13
---

# fix: KB PDF upload fails with FormData parse error for files > 10MB

## Problem

Uploading a PDF (or any file exceeding ~10 MB) through the KB file tree triggers a
`TypeError: Failed to parse body as FormData.` on the server (Sentry ID:
`f81823a3f8e34225b2da67ec8515d901`, 2026-04-13 17:29 CEST).

The client sends a valid `multipart/form-data` request (correct boundary, correct
Content-Type), but the server's `request.formData()` call throws before any
application-level validation runs.

## Root Cause

Next.js 15 internally clones the request body stream when middleware runs
(`getCloneableBody` in `next/dist/server/body-streams.js`). The clone operation
enforces a default size limit of **10 MB**
(`DEFAULT_BODY_CLONE_SIZE_LIMIT = 10 * 1024 * 1024`).

When a request body exceeds this limit:

1. The clone stream is truncated at 10 MB (both `PassThrough` streams get `push(null)`)
2. The truncated stream is passed to the App Router route handler
3. `request.formData()` receives an incomplete multipart body -- the final boundary
   marker is missing
4. The multipart parser throws `TypeError: Failed to parse body as FormData.`

The middleware matcher (`/((?!_next/static|_next/image|favicon.ico|sw\\.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)`)
does NOT exclude `/api/kb/upload`, so middleware runs for every upload request and
triggers the body clone.

**Evidence from Sentry event:**

- Content-Length: `11254383` (~10.7 MB) -- exceeds 10 MB limit
- Content-Type: `multipart/form-data; boundary=----geckoformboundarydbe36d6ab5176611fa7ceaf971798f91` -- valid
- File: `Au Chat Potan - Pitch Projet .pptx-1.pdf` (PDF, ~10.7 MB)
- Browser: Firefox 149.0 (gecko boundary format confirms XHR path is correct)
- The raw body data captured by Sentry starts with valid multipart structure

**Why the 10 MB default is a problem:**

The route already validates `MAX_FILE_SIZE = 20 * 1024 * 1024` (20 MB) and the client
mirrors this limit. Files between 10--20 MB pass client validation but fail server-side
before the route handler even runs, producing a confusing "Invalid form data" error
instead of the expected size-related error.

## Fix

Two changes, both in `apps/web-platform/`:

### 1. Increase `middlewareClientMaxBodySize` in `next.config.ts`

Add `experimental.middlewareClientMaxBodySize` to match the application's 20 MB file
size limit (plus overhead for multipart headers/boundaries):

```typescript
// next.config.ts
const nextConfig: NextConfig = {
  experimental: {
    middlewareClientMaxBodySize: 25 * 1024 * 1024, // 25 MB -- covers 20 MB file + multipart overhead
  },
  // ... existing config
};
```

The 25 MB value provides ~5 MB headroom for multipart boundary markers, form field
names (`file`, `targetDir`, `sha`), and Content-Disposition headers. This is the
recommended approach per Next.js documentation:
<https://nextjs.org/docs/app/api-reference/config/next-config-js/middlewareClientMaxBodySize>.

**Why not exclude the route from middleware?** The middleware handles CSP nonce
injection and Supabase auth cookie refresh. Excluding `/api/kb/upload` from the matcher
would skip CSP headers on the response, which is acceptable for an API route, but also
skip T&C enforcement and billing status checks. The config-based approach is safer and
maintains all middleware protections.

### 2. Add a test for large file upload

Add a test case to `apps/web-platform/test/kb-upload.test.ts` that verifies a file
slightly over 10 MB (but under the 20 MB limit) succeeds:

```typescript
test("returns 201 for file slightly over 10MB (body clone limit)", async () => {
  setupFullMocks();

  const file = makeTestFile("large.pdf", 11 * 1024 * 1024); // 11 MB
  const formData = createFormData(file, "uploads");
  const res = await POST(createRequest(formData, "https://app.soleur.ai"));
  expect(res.status).toBe(201);
});
```

**Note:** This test exercises the route handler in isolation (without middleware), so it
validates the route handler works with large files but does not reproduce the middleware
body-clone truncation. The config change is the fix; the test is a regression guard for
the route handler's own size handling.

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/next.config.ts` | Add `experimental.middlewareClientMaxBodySize: 25 * 1024 * 1024` |
| `apps/web-platform/test/kb-upload.test.ts` | Add test for 11 MB file upload success |

## Acceptance Criteria

- [ ] Uploading a PDF between 10--20 MB through the KB file tree succeeds (201 response)
- [ ] `next.config.ts` sets `experimental.middlewareClientMaxBodySize` to 25 MB
- [ ] Existing upload tests still pass
- [ ] New test covers the 10--20 MB file size range
- [ ] Files over 20 MB are still rejected (413 response) by the route handler

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/configuration fix for an
existing feature.

## Test Scenarios

- Given a 11 MB PDF, when uploaded through KB file tree, then server returns 201
  (not 400 "Invalid form data")
- Given a 5 MB PNG, when uploaded through KB file tree, then server returns 201
  (regression check -- files under 10 MB still work)
- Given a 21 MB file, when uploaded through KB file tree, then server returns 413
  (size limit still enforced)
- Given a valid 15 MB PDF, when middleware runs (CSP, auth), then the full body is
  available to the route handler (no truncation)

## MVP

This is a two-file fix:

1. Config change in `next.config.ts` (1 line)
2. Test in `kb-upload.test.ts` (1 test case)

No database changes, no new dependencies, no UI changes.

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| Exclude `/api/kb/upload` from middleware matcher | Rejected -- would skip T&C and billing enforcement for upload requests |
| Stream the body without cloning (skip middleware entirely) | Rejected -- requires Next.js architectural changes, not configurable |
| Use `serverActions.bodySizeLimit` | Not applicable -- this is a route handler, not a Server Action |
| Client-side chunked upload | Over-engineered for this fix -- the 20 MB limit is well within reasonable single-request size |
