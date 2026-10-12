---
title: "feat: BYOK HKDF per-user key derivation"
type: feat
date: 2026-03-20
semver: minor
---

# feat: BYOK HKDF Per-User Key Derivation

## Overview

Add per-user key derivation via HKDF to the existing BYOK AES-256-GCM encryption. Each user gets a unique encryption key derived from the master key + their user ID, providing cryptographic domain separation. The master key stays in `.env` (backed up to a password manager). No Vault, no new dependencies.

## Problem Statement

The current `byok.ts` uses one `BYOK_ENCRYPTION_KEY` from `.env` to encrypt all users' API keys. A single key means no cryptographic domain separation between users.

## Proposed Solution

### HKDF Parameters (per RFC 5869)

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `digest` | `"sha256"` | 32-byte output = AES-256 key size |
| `ikm` | Master key (32-byte Buffer from env) | High-entropy secret |
| `salt` | `Buffer.alloc(0)` (empty) | IKM is already uniform; varying salt downgrades security per RFC 5869 Section 3.1 |
| `info` | `"soleur:byok:<user_id>"` | Domain separation binding derived key to user identity |
| `keylen` | `32` | AES-256 key length |

**Note:** `salt` and `info` roles are defined by RFC 5869. Salt is for the Extract phase (empty is correct for high-entropy IKM). Info is for the Expand phase (binds to context/identity). User ID goes in info, not salt.

## Technical Considerations

### File Changes

| File | Change | Lines |
|------|--------|-------|
| `apps/web-platform/server/byok.ts` | Add `deriveUserKey(userId)` using `hkdfSync`, change `encryptKey`/`decryptKey` signatures to accept `userId`, add `decryptKeyLegacy()` for v1 rows | ~25 lines added/modified |
| `apps/web-platform/app/api/keys/route.ts:38` | `encryptKey(apiKey)` -> `encryptKey(apiKey, user.id)`, add `key_version: 2` to upsert | 2 lines |
| `apps/web-platform/server/agent-runner.ts:72-91` | Forward `userId` to `decryptKey()`, add lazy migration (check `key_version`, re-encrypt if v1) | ~12 lines |
| `apps/web-platform/test/byok.test.ts` | Update calls to pass userId, add cross-user isolation test, add lazy migration test | ~20 lines |
| `apps/web-platform/.env.example:29-35` | Add note to back up key to password manager | 2 lines |
| `apps/web-platform/supabase/migrations/009_byok_hkdf.sql` | Add `key_version` column | 3 lines |

### Migration (`009_byok_hkdf.sql`)

```sql
ALTER TABLE public.api_keys ADD COLUMN key_version integer NOT NULL DEFAULT 1;
-- v1 = legacy raw BYOK_ENCRYPTION_KEY (no HKDF)
-- v2 = HKDF-derived per-user key
```

### `byok.ts` Changes

`byok.ts` stays a pure `node:crypto` module with zero external dependencies. No Supabase imports, no Vault, no caching logic:

- **`deriveUserKey(masterKey: Buffer, userId: string): Buffer`** — `crypto.hkdfSync('sha256', masterKey, Buffer.alloc(0), 'soleur:byok:' + userId, 32)` wrapped in `Buffer.from()`
- **`encryptKey(plaintext: string, userId: string)`** — calls `deriveUserKey(getEncryptionKey(), userId)` then AES-256-GCM as before
- **`decryptKey(encrypted: Buffer, iv: Buffer, tag: Buffer, userId: string)`** — same derivation path
- **`decryptKeyLegacy(encrypted: Buffer, iv: Buffer, tag: Buffer)`** — uses raw master key without HKDF, for v1 rows during migration
- **`getEncryptionKey()`** — unchanged (reads from env var, dev fallback)

### Lazy Migration in `agent-runner.ts`

```text
getUserApiKey(userId):
  1. SELECT encrypted_key, iv, auth_tag, key_version FROM api_keys WHERE user_id = ...
  2. IF key_version === 1:
       plaintext = decryptKeyLegacy(encrypted, iv, tag)
       { encrypted, iv, tag } = encryptKey(plaintext, userId)
       UPDATE api_keys SET encrypted_key, iv, auth_tag, key_version = 2 WHERE id = ...
  3. ELSE:
       plaintext = decryptKey(encrypted, iv, tag, userId)
  4. RETURN plaintext
```

Race condition note: concurrent requests for the same v1 row both produce valid v2 ciphertext (HKDF is deterministic, random IV makes both valid). Second write wins. No locking needed.

### Rollback

Backward-compatible decryption (v1 uses raw key, v2 uses HKDF) means the code can handle both schemes simultaneously. Keep `BYOK_ENCRYPTION_KEY` in the environment. If reverting to old code, v2 rows would need manual re-encryption — but with a small row count, this is a one-shot script if needed, not pre-built tooling.

## Alternative Approaches Considered

1. **Supabase Vault envelope encryption** — rejected after review. Moving one secret to Vault while `SUPABASE_SERVICE_ROLE_KEY` stays in `.env` is inconsistent. Adds RPC dependency, SQL wrapper functions, caching logic, and fallback behavior for no coherent security improvement. Back up the key to a password manager instead
2. **Supabase Vault for per-user secrets** — rejected. Cardinality mismatch, loses RLS, pgsodium pending deprecation. See [brainstorm](../brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md)
3. **pgcrypto in-database encryption** — rejected. Harder to test, no portability gain
4. **Per-user random DEKs** — rejected. Requires storing N wrapped DEKs. HKDF is simpler (zero DEK storage)

## Acceptance Criteria

- [ ] AC1: New API keys are encrypted with HKDF-derived per-user keys (`key_version = 2`)
- [ ] AC2: Existing v1 keys are lazily re-encrypted on next access
- [ ] AC3: Different users' encrypted keys cannot be decrypted with each other's derived keys
- [ ] AC4: `key_version` column tracks encryption scheme per row
- [ ] AC5: Dev mode uses HKDF with deterministic fallback key (same code path as production)
- [ ] AC6: All existing `byok.test.ts` tests pass with updated signatures

## Test Scenarios

### Acceptance Tests

- Given a user encrypts an API key, when the key is stored, then `key_version` is `2` and the key round-trips correctly through encrypt/decrypt with the user's ID
- Given a v1 encrypted key exists, when `getUserApiKey(userId)` is called, then the key is decrypted with the raw master key, re-encrypted with HKDF, and `key_version` updated to `2`
- Given two users encrypt the same plaintext key, when comparing ciphertext, then the encrypted outputs differ (different derived keys)
- Given user A's ciphertext, when decrypting with user B's derived key, then decryption fails with an auth tag mismatch
- Given a row was partially migrated (decrypted but crash before re-encrypt), when the next access occurs, then `key_version` is still `1` and migration retries (idempotent)

## Dependencies and Risks

| Risk | Mitigation |
|------|------------|
| Master key loss | Back up `BYOK_ENCRYPTION_KEY` to password manager (1Password, Bitwarden). Document in `.env.example` |
| Migration interruption | Lazy migration is idempotent; `key_version` column prevents double-migration |
| Breaking change to encrypt/decrypt signatures | All call sites exhaustively verified (2 callers + 1 test file); TypeScript compiler catches missing args |

## Operational Task

**Back up `BYOK_ENCRYPTION_KEY`** to a password manager before deploying this change. This is the single most impactful risk mitigation — it takes 2 minutes and eliminates the "lost key = unrecoverable" scenario.

## References

### Internal

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-evaluate-supabase-vault-byok/spec.md`
- Current implementation: `apps/web-platform/server/byok.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts:72-91`
- API route: `apps/web-platform/app/api/keys/route.ts:38`

### External

- [RFC 5869 — HKDF](https://datatracker.ietf.org/doc/html/rfc5869) — parameter semantics for salt vs info
- [Node.js crypto.hkdfSync](https://nodejs.org/api/crypto.html) — API reference
- [Soatok — Understanding HKDF](https://soatok.blog/2021/11/17/understanding-hkdf/) — salt vs info guidance
