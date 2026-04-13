# Tasks: KB Upload Progress and PDF Validation Fix

## Phase 1: Diagnose and Fix "Invalid form data" Error

- [ ] 1.1 Add detailed error logging to `formData()` catch block in `apps/web-platform/app/api/kb/upload/route.ts` -- log `err.name`, `err.message`, send to Sentry
- [ ] 1.2 Attempt to reproduce the error locally by uploading a PDF > 1MB via the dev server (or write a test that simulates a large multipart body)
- [ ] 1.3 Based on diagnosis, apply the appropriate fix (body size, Content-Type, stream, or other)
- [ ] 1.4 Add test case for large file upload (> 1MB PDF) in `apps/web-platform/test/kb-upload.test.ts`
- [ ] 1.5 Verify existing tests pass with `npx vitest run` from `apps/web-platform/`

## Phase 2: Upload Progress Indicator

- [ ] 2.1 Update `UploadState` type in `apps/web-platform/components/kb/file-tree.tsx` -- add `progress: number` to uploading variant
- [ ] 2.2 Create `xhrUpload()` helper function wrapping XMLHttpRequest in a Promise with `upload.onprogress`
- [ ] 2.3 Replace `fetch()` with `xhrUpload()` in `uploadFile` callback, update progress state
- [ ] 2.4 Create `UploadProgress` component (circular SVG, 12x12, `stroke-dasharray`/`stroke-dashoffset`, CSS transition, rotate -90 for 12 o'clock start)
- [ ] 2.5 Replace `UploadSpinner` usage with `UploadProgress` in directory node render
- [ ] 2.6 Handle post-upload processing state (after 100%, before server responds)
- [ ] 2.7 Handle `lengthComputable=false` fallback to indeterminate animation
- [ ] 2.8 Add tests for XHR upload and progress state transitions
- [ ] 2.9 Run full test suite and verify all tests pass

## Phase 3: Cleanup

- [ ] 3.1 Remove unused `UploadSpinner` component if fully replaced
- [ ] 3.2 Run `npx markdownlint-cli2 --fix` on changed markdown files
- [ ] 3.3 Final test run from `apps/web-platform/` using `npx vitest run`
