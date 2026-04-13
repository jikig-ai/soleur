---
module: web-platform
date: 2026-04-13
problem_type: runtime_error
component: tooling
symptoms:
  - "TypeError: Failed to parse body as FormData."
  - "KB file uploads >10 MB fail with 400 Invalid form data"
  - "Sentry breadcrumb: Unrecognized key(s) in object: 'serverActions'"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [nextjs, middleware, upload, formdata, body-size, truncation]
---

# Troubleshooting: Next.js middleware silently truncates upload bodies >10 MB

## Problem

PDF uploads >10 MB through the KB tree failed with "Invalid form data" (HTTP 400). The multipart FormData was valid on the client side but `request.formData()` threw `TypeError: Failed to parse body as FormData` in the route handler.

## Environment

- Module: web-platform (Next.js App Router)
- Next.js Version: 15.5.15
- Node.js Version: 22.22.1
- Affected Component: `/api/kb/upload` route handler + Next.js middleware pipeline
- Date: 2026-04-13

## Symptoms

- `TypeError: Failed to parse body as FormData.` from `node:internal/deps/undici/undici` (`consumeBody` → `fullyReadBody`)
- Only affects files >10 MB; smaller files upload successfully
- Sentry event shows correct `Content-Type: multipart/form-data; boundary=...` and `Content-Length: 11254383`
- Conversation uploads (which use presigned URLs to Supabase Storage, bypassing the Next.js pipeline) work fine for all sizes

## What Didn't Work

**Direct solution:** Root cause was identified through Sentry analysis and Next.js source code inspection. No failed attempts.

The initial plan subagent's analysis was partially inaccurate — it described the root cause as "1 MB server action limit" when the actual limit is 10 MB middleware body clone. However, the config key it suggested (`experimental.middlewareClientMaxBodySize`) was correct.

## Solution

Set `experimental.middlewareClientMaxBodySize` in `next.config.ts` to 25 MB (20 MB route handler cap + 5 MB multipart overhead):

**Code changes:**

```typescript
// Before (broken):
const nextConfig: NextConfig = {
  serverActions: {          // ← IGNORED by Next.js 15.5 at top level
    allowedOrigins: [...],
  },
};

// After (fixed):
const nextConfig: NextConfig = {
  experimental: {
    serverActions: {        // ← Correct location for Next.js 15.5
      allowedOrigins: [...],
    },
    // Next.js clones the request body when middleware modifies headers.
    // Default limit is 10 MB — bodies exceeding it are silently truncated.
    middlewareClientMaxBodySize: 25 * 1024 * 1024,
  },
};
```

## Why This Works

1. **ROOT CAUSE:** Next.js `body-streams.js` (`getCloneableBody`) creates two `PassThrough` streams when middleware returns `NextResponse.next({ request: { headers } })`. The `cloneBodyStream()` method tracks `bytesRead` against `DEFAULT_BODY_CLONE_SIZE_LIMIT` (10 MB). When exceeded, it calls `p1.push(null)` and `p2.push(null)`, **silently truncating** both streams with only a `console.warn`.

2. **WHY TRUNCATION BREAKS FORMDATA:** The multipart body is incomplete after truncation — the closing boundary (`------geckoformboundary...--`) is missing. When undici's `consumeBody` tries to parse the truncated body, the Busboy multipart parser fails because it never finds the closing boundary.

3. **WHY `serverActions` MOVED:** The `serverActions` config was at the top level of `nextConfig`, but Next.js 15.5 expects it under `experimental`. Sentry breadcrumbs confirmed: `Unrecognized key(s) in object: 'serverActions'`. This means the `allowedOrigins` CSRF restriction was silently not being enforced.

4. **WHY 25 MB:** The route handler enforces a 20 MB `MAX_FILE_SIZE` limit. The 5 MB overhead accounts for multipart boundary markers, Content-Disposition headers, and form field metadata (`file`, `targetDir`, `sha`).

## Prevention

- When adding upload routes that pass through Next.js middleware, verify `experimental.middlewareClientMaxBodySize` accommodates the max file size plus multipart overhead.
- Watch for "Unrecognized key(s)" warnings in Next.js startup logs — they indicate config keys at the wrong nesting level being silently ignored.
- When Next.js body parsing fails with "Failed to parse body as FormData" but the Content-Type is correct, suspect body truncation rather than malformed input.
- The `DEFAULT_BODY_CLONE_SIZE_LIMIT` (10 MB) is not documented in Next.js user-facing docs — it lives only in `node_modules/next/dist/server/body-streams.js`. The config key `experimental.middlewareClientMaxBodySize` IS documented.

## Related Issues

- See also: [xhr-upload-progress-and-state-ordering-20260413.md](../ui-bugs/xhr-upload-progress-and-state-ordering-20260413.md) — same upload flow, different bug (progress indicator and error logging)
