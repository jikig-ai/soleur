# Tasks: BYOK HKDF Per-User Key Derivation

**Issue:** #676
**Plan:** `knowledge-base/project/plans/2026-03-20-feat-byok-hkdf-envelope-encryption-plan.md`

## Phase 1: Database Migration

- [x] 1.1 Create `009_byok_hkdf_per_user_keys.sql` migration
  - [x] 1.1.1 Add `key_version integer NOT NULL DEFAULT 1` column to `api_keys`

## Phase 2: Core Implementation — `byok.ts`

- [x] 2.1 Add `deriveUserKey(masterKey: Buffer, userId: string): Buffer`
  - [x] 2.1.1 Use `crypto.hkdfSync('sha256', masterKey, Buffer.alloc(0), 'soleur:byok:' + userId, 32)`
  - [x] 2.1.2 Wrap result in `Buffer.from()` (hkdfSync returns ArrayBuffer)
- [x] 2.2 Update `encryptKey(plaintext, userId)` signature
  - [x] 2.2.1 Call `deriveUserKey(getEncryptionKey(), userId)` instead of `getEncryptionKey()` directly
- [x] 2.3 Update `decryptKey(encrypted, iv, tag, userId)` signature
  - [x] 2.3.1 Same derivation as encrypt path
- [x] 2.4 Add `decryptKeyLegacy(encrypted, iv, tag)` for v1 rows
  - [x] 2.4.1 Uses raw master key without HKDF (existing behavior preserved)

## Phase 3: Wire Callers

- [x] 3.1 Update `app/api/keys/route.ts:38`
  - [x] 3.1.1 Change `encryptKey(apiKey)` to `encryptKey(apiKey, user.id)`
  - [x] 3.1.2 Add `key_version: 2` to upsert payload
- [x] 3.2 Update `server/agent-runner.ts:72-91` (`getUserApiKey`)
  - [x] 3.2.1 Select `key_version` column in query
  - [x] 3.2.2 If `key_version === 1`: decrypt with `decryptKeyLegacy()`, re-encrypt with `encryptKey(plaintext, userId)`, update row with `key_version: 2`
  - [x] 3.2.3 If `key_version === 2`: decrypt with `decryptKey(encrypted, iv, tag, userId)`

## Phase 4: Tests

- [x] 4.1 Update existing `byok.test.ts` tests to pass userId
- [x] 4.2 Add cross-user isolation test (same plaintext, different users = different ciphertext)
- [x] 4.3 Add wrong-user decryption test (should throw auth tag mismatch)
- [x] 4.4 Add lazy migration test (v1 decrypt + re-encrypt + version bump)
- [x] 4.5 Add HKDF determinism test (same userId + same master key = same derived key)

## Phase 5: Documentation

- [x] 5.1 Update `.env.example` — add backup-to-password-manager note
- [x] 5.2 Update spec.md — remove Vault references, mark as HKDF-only (done in planning phase)
