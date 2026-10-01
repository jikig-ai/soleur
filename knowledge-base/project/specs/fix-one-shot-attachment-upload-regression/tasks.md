# Tasks — fix-concierge-attachment-upload

Plan: `knowledge-base/project/plans/2026-10-01-fix-concierge-attachment-upload-plan.md`
Branch: `fix-one-shot-attachment-upload-regression`
Deferred scope: composer presign-leg telemetry in `chat-input.tsx` → issue #9345.

## Phase 1 — Failing tests (RED)

- [ ] 1.1 In `apps/web-platform/test/presign-route.test.ts`, add a case that stubs
  `NEXT_PUBLIC_SUPABASE_URL` (`vi.stubEnv`) to a host different from the mocked
  `signedUrl` host and asserts `body.uploadUrl` carries the public host with path and
  `?token=` preserved. Confirm it fails on the current code.
- [ ] 1.2 Create `apps/web-platform/test/upload-with-progress.test.ts`: mock
  `XMLHttpRequest` and `@/lib/client-observability`; assert non-2xx `onload` AND `onerror`
  each reject AND call `reportSilentFallback` once with `feature: "attachments"`,
  `op: "storage-put"`, extras `status` + sanitized filename, and no `token=`/signed-URL
  substring in the reported payload. Confirm red (the report does not exist yet).

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 `apps/web-platform/app/api/attachments/presign/route.ts`: import
  `toPublicStorageUrl` from `@/lib/supabase/public-storage-url` and return
  `uploadUrl: toPublicStorageUrl(data.signedUrl)`.
- [ ] 2.2 `apps/web-platform/lib/upload-with-progress.ts`: on `xhr.onload` non-2xx and on
  `xhr.onerror`, call `reportSilentFallback(err, { feature: "attachments",
  op: "storage-put", extra: { status: xhr.status, filename:
  sanitizeAttachmentFilename(file.name) } })` before rejecting (import
  `sanitizeAttachmentFilename` from `@/lib/attachment-constants` and
  `reportSilentFallback` from `@/lib/client-observability`). No report on `onabort`.
- [ ] 2.3 Do NOT touch `lib/csp.ts`, `middleware.ts`, `components/chat/chat-input.tsx`, or
  `lib/upload-attachments.ts`.

## Phase 3 — Verification

- [ ] 3.1 `npx vitest run test/presign-route.test.ts test/upload-with-progress.test.ts
  test/upload-attachments.test.ts test/chat-input-attachments.test.tsx
  test/attachment-error-copy.test.ts` — all green (run from `apps/web-platform`).
- [ ] 3.2 Confirm `grep -c toPublicStorageUrl
  apps/web-platform/app/api/attachments/presign/route.ts` prints `2`.
- [ ] 3.3 Post-deploy operator verify: attach a `.md` in an in-progress Concierge
  conversation → `Uploaded` chip, agent receives file contents, no generic-copy toast;
  check Sentry for `feature:attachments op:storage-put` events if anything still fails.
