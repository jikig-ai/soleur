# Tasks: BYOK Decryption Fix (#667)

## Phase 1: Schema Fix

- [x] 1.1 Create `apps/web-platform/supabase/migrations/003_fix_encrypted_key_column_type.sql`
  - [x] 1.1.1 ALTER COLUMN encrypted_key TYPE text USING convert_from(encrypted_key, 'UTF8')
  - [x] 1.1.2 UPDATE api_keys SET is_valid = false, validated_at = NULL

## Phase 2: Type Safety

- [x] 2.1 Update `ApiKey` interface in `apps/web-platform/lib/types.ts`
  - [x] 2.1.1 Add `iv: string` field
  - [x] 2.1.2 Add `auth_tag: string` field
  - [x] 2.1.3 Add `updated_at: string` field
  - [x] 2.1.4 Add `created_at: string` field

## Phase 3: Testing

- [x] 3.1 Create `apps/web-platform/test/byok.test.ts`
  - [x] 3.1.1 Test encrypt → decrypt round-trip (Buffer-to-Buffer)
  - [x] 3.1.2 Test base64 save/read path simulation (matches app data flow)
- [x] 3.2 Run `npx vitest run` and verify all tests pass

## Phase 4: Deployment

- [ ] 4.1 Run migration on Supabase dashboard
- [ ] 4.2 E2E verify: save key → start chat → agent boots
