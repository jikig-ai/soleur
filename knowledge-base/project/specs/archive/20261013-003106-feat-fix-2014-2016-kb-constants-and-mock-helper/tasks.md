# Tasks: Extract shared KB constants and Supabase mock helper

## Phase 1: KB Constants Extraction

- [ ] 1.1 Create `apps/web-platform/lib/kb-constants.ts` with `KB_MAX_FILE_SIZE`, `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES` (no `"use client"` directive)
- [ ] 1.2 Update `apps/web-platform/server/kb-reader.ts` to import `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`, remove local `MAX_FILE_SIZE` constant
- [ ] 1.3 Update `apps/web-platform/server/context-validation.ts` to import `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`, remove local `MAX_CONTEXT_CONTENT_LENGTH` and its comment
- [ ] 1.4 Update `apps/web-platform/app/api/attachments/presign/route.ts` to import `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES` from `@/lib/kb-constants`, remove local `ALLOWED_CONTENT_TYPES`, `MAX_FILE_SIZE`, `MAX_FILES_PER_MESSAGE`
- [ ] 1.5 Update `apps/web-platform/components/chat/chat-input.tsx` to import `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES` from `@/lib/kb-constants`, remove local `ALLOWED_TYPES`, `MAX_FILE_SIZE`, `MAX_FILES`
- [ ] 1.6 Run tests: `cd apps/web-platform && npx vitest run`

## Phase 2: Supabase Mock Helper

- [ ] 2.1 Create `apps/web-platform/test/helpers/mock-supabase.ts` with `mockQueryChain` helper (must be thenable -- implement `.then()` for PromiseLike compatibility)
- [ ] 2.1.1 Ensure `mockQueryChain` supports: `.select()`, `.eq()`, `.neq()`, `.in()`, `.is()`, `.order()`, `.limit()`, `.range()`, `.insert()`, `.update()`, `.upsert()`, `.delete()` as chaining methods (all return `this`)
- [ ] 2.1.2 Ensure `.single()` returns a separate thenable resolving to `{ data, error }`
- [ ] 2.1.3 Ensure `await chain.select().eq()` (no terminal) resolves via `.then()` on the chain itself
- [ ] 2.2 Create `apps/web-platform/test/helpers/mock-supabase.test.ts` with unit tests for `mockQueryChain`
- [ ] 2.3 Migrate `test/vision-route.test.ts` -- replace inline `mockQueryBuilder` (lines 61-70) with `mockQueryChain` import
- [ ] 2.4 Migrate `test/presign-route.test.ts` -- replace `setupConversationOwnership` chain mock (lines 77-91) with `mockQueryChain`
- [ ] 2.5 Migrate `test/disconnect-route.test.ts` -- use `mockQueryChain` for `mockFrom` implementation
- [ ] 2.6 Migrate `test/account-delete.test.ts` -- use `mockQueryChain` where chain mocks are built inline
- [ ] 2.7 Run tests: `cd apps/web-platform && npx vitest run`

## Phase 3: Verification and Cleanup

- [ ] 3.1 Grep for remaining duplicate KB constant definitions: `grep -rn 'const MAX_FILE_SIZE\|const ALLOWED_CONTENT_TYPES\|const ALLOWED_TYPES\|const MAX_FILES' apps/web-platform/` -- only `lib/kb-constants.ts` and unrelated `agent-runner.ts` (20MB attachment) should match
- [ ] 3.2 Verify all modified test files pass individually
- [ ] 3.3 Run full test suite one final time: `cd apps/web-platform && npx vitest run`
