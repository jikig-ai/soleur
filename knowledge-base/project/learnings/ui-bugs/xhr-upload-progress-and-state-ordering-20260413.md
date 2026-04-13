---
module: KB Upload
date: 2026-04-13
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Upload shows only indeterminate spinning wheel with no progress feedback"
  - "Invalid form data error on PDF upload with no diagnostic information"
  - "Processing spinner flashes briefly before error/duplicate state"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [xhr-upload, progress-indicator, formdata-error, state-machine, information-disclosure]
---

# Learning: XHR Upload Progress and State Ordering in React

## Problem

The KB file upload had three issues: (1) `fetch()` provides no upload progress events, so users saw only an indeterminate spinner for large files; (2) the `formData()` catch block swallowed error details, making PDF upload failures impossible to diagnose; (3) after switching to XHR, the processing state was set unconditionally before checking response status, causing a brief spinner flash on error/duplicate responses.

## Solution

1. **Replaced `fetch()` with `XMLHttpRequest`** wrapped in a Promise. XHR exposes `upload.onprogress` with `loaded`/`total` bytes. Used `Math.round((loaded / total) * 100)` for integer percentage, which naturally throttles React re-renders to ~101 updates max.

2. **Created `UploadProgress` SVG component** using `stroke-dasharray`/`stroke-dashoffset` with CSS `transition-[stroke-dashoffset] duration-300 ease-linear`. The `-1` sentinel triggers indeterminate mode (spinning animation). Same 12x12 dimensions as the replaced `UploadSpinner`.

3. **Added structured error logging** to the `formData()` catch block: `logger.error({ event, errName, errMsg, userId })` + `Sentry.captureException(err)`. Critically, the `errMsg` is logged server-side only -- returning it in the client response was an information disclosure risk (P2 review finding).

4. **Moved processing state after error branches** so it only shows for successful uploads during `refreshTree()`.

5. **Added type guards** before accessing XHR response body properties instead of bare `as` casts.

## Key Insight

When replacing `fetch()` with XHR for progress tracking, the response handling changes from `res.ok`/`res.json()` to manual status code checks on a pre-parsed `body: unknown`. This makes type safety worse unless you add explicit guards. Also, state machine transitions in upload flows must be ordered carefully -- set intermediate states (like "processing") only after confirming the response is a success path, not before branching on status codes.

## Session Errors

1. **Dev server startup failure during QA** -- Supabase env vars missing from Doppler dev config in worktree context. QA browser scenarios were skipped. **Recovery:** Graceful degradation -- unit tests verified correctness. **Prevention:** QA skill already handles this via its graceful degradation table; no workflow change needed.

2. **Processing state flash before error check (P1)** -- `setUploadState({ status: "processing" })` placed before 409/error branches. **Recovery:** Moved to after success confirmation during review resolution. **Prevention:** When adding intermediate states to a state machine, verify the transition only fires on the intended path. Review agents caught this.

3. **Information disclosure via `detail` field (P2)** -- `errMsg` from `request.formData()` exception returned to client. **Recovery:** Removed `detail` from response, kept server-side logging. **Prevention:** Never return raw error messages to clients in API responses. Log server-side, return generic error to client.

4. **Unsafe type assertions on XHR response body (P2)** -- `as` casts without runtime validation. **Recovery:** Added type guards (`typeof body === "object" && body && "sha" in body`). **Prevention:** When `xhrUpload` returns `body: unknown`, always guard before accessing properties. The `unknown` type is correct -- the cast sites need guards.

## Tags

category: ui-bugs
module: KB Upload
