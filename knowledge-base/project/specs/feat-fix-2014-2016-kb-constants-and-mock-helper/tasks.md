# Tasks: Extract shared KB constants and Supabase mock helper

## Phase 1: KB Constants Extraction

- [ ] 1.1 Create `apps/web-platform/lib/kb-constants.ts` with `KB_MAX_FILE_SIZE`, `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES`
- [ ] 1.2 Update `apps/web-platform/server/kb-reader.ts` to import `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`, remove local constant
- [ ] 1.3 Update `apps/web-platform/server/context-validation.ts` to import `KB_MAX_FILE_SIZE` from `@/lib/kb-constants`, remove local `MAX_CONTEXT_CONTENT_LENGTH`
- [ ] 1.4 Update `apps/web-platform/app/api/attachments/presign/route.ts` to import `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES` from `@/lib/kb-constants`, remove local constants
- [ ] 1.5 Update `apps/web-platform/components/chat/chat-input.tsx` to import `ATTACHMENT_ALLOWED_TYPES`, `ATTACHMENT_MAX_FILE_SIZE`, `ATTACHMENT_MAX_FILES` from `@/lib/kb-constants`, remove local constants
- [ ] 1.6 Run tests to verify no regressions: `cd apps/web-platform && npx vitest run`

## Phase 2: Supabase Mock Helper

- [ ] 2.1 Create `apps/web-platform/test/helpers/mock-supabase.ts` with `createMockSupabaseClient` and `mockQueryChain` helpers
- [ ] 2.2 Migrate `test/vision-route.test.ts` to use shared helper (replace inline `mockQueryBuilder`)
- [ ] 2.3 Migrate `test/presign-route.test.ts` to use shared helper (replace `setupConversationOwnership` chain)
- [ ] 2.4 Migrate `test/disconnect-route.test.ts` to use shared helper
- [ ] 2.5 Migrate `test/account-delete.test.ts` to use shared helper
- [ ] 2.6 Run tests to verify no regressions: `cd apps/web-platform && npx vitest run`

## Phase 3: Verification and Cleanup

- [ ] 3.1 Grep for remaining duplicate constant definitions to confirm none remain
- [ ] 3.2 Verify all modified test files pass individually
- [ ] 3.3 Run full test suite one final time
