# Tasks — fix-concierge-attachment-upload

Plan: `knowledge-base/project/plans/2026-10-01-fix-concierge-attachment-upload-plan.md`
Branch: `fix-one-shot-attachment-upload-regression`

## Phase 1 — Failing tests (RED)

- [ ] 1.1 In `apps/web-platform/test/presign-route.test.ts`, add a case that stubs
  `NEXT_PUBLIC_SUPABASE_URL` (`vi.stubEnv`) to a host different from the mocked
  `signedUrl` host and asserts `body.uploadUrl` carries the public host with path and
  `?token=` preserved. Confirm it fails on the current code.
- [ ] 1.2 In `apps/web-platform/test/chat-input-attachments.test.tsx`, add cases asserting
  a failing storage PUT and a failing presign each invoke the client
  `reportSilentFallback` mock with `feature: "attachments"` and a stage-discriminating
  `op` (`storage` / `presign`), and that the reported message contains no `token=`.
  Confirm red.

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 `apps/web-platform/app/api/attachments/presign/route.ts`: import
  `toPublicStorageUrl` from `@/lib/supabase/public-storage-url` and return
  `uploadUrl: toPublicStorageUrl(data.signedUrl)`.
- [ ] 2.2 `apps/web-platform/components/chat/chat-input.tsx`: track the failure stage
  inside `uploadAttachments`'s per-file closure (presign fetch/json vs `await promise`);
  in `catch`, call `reportSilentFallback(sanitizedErr, { feature: "attachments",
  op: `chat-upload-${stage}` })` with the error sanitized to a fixed message (mirror
  `lib/upload-attachments.ts` `sanitizeErrorForLog` — never emit the signed URL).
- [ ] 2.3 Do NOT touch `lib/csp.ts`, `middleware.ts`, `lib/upload-attachments.ts`, or
  `lib/upload-with-progress.ts`.

## Phase 3 — Verification

- [ ] 3.1 `npx vitest run test/presign-route.test.ts
  test/chat-input-attachments.test.tsx test/upload-attachments.test.ts
  test/attachment-error-copy.test.ts` — all green (run from `apps/web-platform`).
- [ ] 3.2 Confirm `grep -c toPublicStorageUrl
  apps/web-platform/app/api/attachments/presign/route.ts` prints `2`.
- [ ] 3.3 Post-deploy operator verify: attach a `.md` in an in-progress Concierge
  conversation → `Uploaded` chip, agent receives file contents, no generic-copy toast;
  check Sentry for `feature:attachments` `op:chat-upload-*` events if anything still
  fails.
