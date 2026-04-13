# Tasks: KB Upload Progress and PDF Validation Fix

## Phase 1: Fix PDF Upload (Body Size Limit)

- [ ] 1.1 Research Next.js App Router body size configuration (route segment config vs next.config.ts)
- [ ] 1.2 Add body size limit config to `apps/web-platform/app/api/kb/upload/route.ts`
- [ ] 1.3 Improve error message in `formData()` catch block -- distinguish body-too-large from malformed data
- [ ] 1.4 Add test case for large file upload (> 1MB PDF) in `apps/web-platform/test/kb-upload.test.ts`
- [ ] 1.5 Verify existing tests pass with `npx vitest run` from `apps/web-platform/`

## Phase 2: Upload Progress Indicator

- [ ] 2.1 Update `UploadState` type in `apps/web-platform/components/kb/file-tree.tsx` -- add `progress: number` to uploading variant
- [ ] 2.2 Replace `fetch()` with `XMLHttpRequest` in `uploadFile` callback, wire `upload.onprogress` to update progress state
- [ ] 2.3 Create `UploadProgress` component (circular SVG with `stroke-dasharray`/`stroke-dashoffset`, CSS transition)
- [ ] 2.4 Replace `UploadSpinner` with `UploadProgress` in the directory node render
- [ ] 2.5 Add tests for progress state transitions
- [ ] 2.6 Run full test suite and verify all tests pass

## Phase 3: Cleanup

- [ ] 3.1 Remove unused `UploadSpinner` component if fully replaced
- [ ] 3.2 Run `npx markdownlint-cli2 --fix` on changed markdown files
- [ ] 3.3 Final test run
