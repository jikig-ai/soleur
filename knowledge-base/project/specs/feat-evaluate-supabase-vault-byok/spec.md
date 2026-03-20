# Spec: BYOK HKDF Per-User Key Derivation

**Issue:** #676
**Branch:** feat-evaluate-supabase-vault-byok
**Date:** 2026-03-20

## Problem Statement

The current BYOK implementation uses a single `BYOK_ENCRYPTION_KEY` stored in `.env` to encrypt all users' API keys via AES-256-GCM. No cryptographic domain separation exists between users — the same key encrypts everyone's data.

## Goals

- G1: Add per-user cryptographic domain separation via HKDF key derivation
- G2: Back up master key to password manager (eliminate "lost key = unrecoverable" risk)
- G3: Maintain existing RLS enforcement and PostgREST access patterns
- G4: Keep `byok.ts` as a pure `node:crypto` module with no external dependencies

## Non-Goals

- Supabase Vault envelope encryption (evaluated and rejected — adds complexity for one secret while others stay in `.env`)
- Migrating per-user secrets to Supabase Vault (cardinality mismatch, pgsodium pending deprecation)
- Moving encryption from Node.js to PostgreSQL (pgcrypto)
- Key rotation hot-reload (rotation requires process restart; hot reload is a future goal)

## Functional Requirements

- **FR1:** Derive a unique encryption key per user using HKDF from the master key and user ID
- **FR2:** Re-encrypt existing user keys with per-user derived keys via lazy migration
- **FR3:** Track encryption scheme version per row with a `key_version` column

## Technical Requirements

- **TR1:** HKDF derivation uses `node:crypto` hkdfSync with SHA-256, salt = empty (`Buffer.alloc(0)`), info = `"soleur:byok:<user_id>"`, keylen = 32. Per RFC 5869: salt is for Extract phase (empty when IKM is high-entropy), info is for Expand phase (binds derived key to user identity)
- **TR2:** `byok.ts` remains a pure crypto module — no Supabase imports, no network calls
- **TR3:** Migration is idempotent — `key_version` column prevents double-migration
- **TR4:** Existing `byok.test.ts` round-trip tests pass with updated signatures
- **TR5:** Add `key_version integer NOT NULL DEFAULT 1` column to `api_keys`. Existing columns unchanged

## Affected Files

| File | Change |
|------|--------|
| `apps/web-platform/server/byok.ts` | Add HKDF derivation, update function signatures |
| `apps/web-platform/server/agent-runner.ts` | Forward user_id to decrypt, add lazy migration |
| `apps/web-platform/app/api/keys/route.ts` | Pass user_id to encrypt, set key_version = 2 |
| `apps/web-platform/test/byok.test.ts` | Update tests, add cross-user isolation tests |
| `apps/web-platform/.env.example` | Add backup-to-password-manager note |
| `apps/web-platform/supabase/migrations/009_byok_hkdf.sql` | Add key_version column |

## Resolved Questions

1. **Migration strategy:** Lazy migration on access. v1 rows re-encrypted to v2 on next decrypt
2. **HKDF salt:** Empty (IKM is high-entropy). User identity goes in `info` per RFC 5869
3. **Sync vs async:** Use `hkdfSync` (sub-millisecond, no event loop concern)
4. **Vault:** Rejected after plan review. Back up key to password manager instead
5. **Dev environment:** HKDF applies in dev using deterministic fallback key. Same code path as production

## Rollback

Backward-compatible decryption (v1 = raw key, v2 = HKDF) means the code handles both schemes. Keep `BYOK_ENCRYPTION_KEY` in the environment. If reverting to old code, v2 rows need a one-shot re-encryption script.
