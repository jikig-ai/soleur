# Spec: BYOK Key Storage Enhancement

**Issue:** #676
**Branch:** feat-evaluate-supabase-vault-byok
**Date:** 2026-03-20

## Problem Statement

The current BYOK implementation uses a single `BYOK_ENCRYPTION_KEY` stored in `.env` to encrypt all users' API keys via AES-256-GCM. This creates two risks: (1) losing the env var makes all stored keys unrecoverable, and (2) a single key compromise exposes all users' encrypted data.

## Goals

- G1: Eliminate single point of failure for the master encryption key
- G2: Isolate per-user key material so one compromise doesn't expose all users
- G3: Enable master key rotation without re-deploying the application
- G4: Maintain existing RLS enforcement and PostgREST access patterns

## Non-Goals

- Migrating per-user secrets to Supabase Vault (evaluated and rejected -- see brainstorm)
- Moving encryption from Node.js to PostgreSQL (pgcrypto)
- Adopting pgsodium column-level encryption (pending deprecation)
- Supporting client-side encryption (users encrypt before upload)

## Functional Requirements

- **FR1:** Derive a unique encryption key per user using HKDF from the master key and user ID
- **FR2:** Store the master encryption key in Supabase Vault instead of `.env`
- **FR3:** Retrieve the master key from Vault at application startup and cache in memory
- **FR4:** Re-encrypt existing user keys with per-user derived keys during migration
- **FR5:** Support lazy migration: keys encrypted with the old scheme are re-encrypted on next access

## Technical Requirements

- **TR1:** HKDF derivation must use `node:crypto` HKDF with SHA-256, salt = user_id, info = "byok"
- **TR2:** Supabase Vault access via `supabase.rpc()` from the service client (not anon client)
- **TR3:** Master key cached in-process after first retrieval (Vault is not called per-request)
- **TR4:** Migration script must handle partial completion (idempotent, can resume)
- **TR5:** Existing `byok.test.ts` round-trip tests must pass with derived keys
- **TR6:** No changes to the `api_keys` table schema (encrypted_key, iv, auth_tag columns remain)

## Affected Files

| File | Change |
|------|--------|
| `apps/web-platform/server/byok.ts` | Add HKDF derivation, Vault master key retrieval |
| `apps/web-platform/server/agent-runner.ts` | Pass user_id to decryption for key derivation |
| `apps/web-platform/app/api/keys/route.ts` | Pass user_id to encryption for key derivation |
| `apps/web-platform/test/byok.test.ts` | Update tests for per-user derived keys |
| `apps/web-platform/.env.example` | Mark BYOK_ENCRYPTION_KEY as deprecated, add Vault instructions |
| `apps/web-platform/supabase/migrations/` | Migration to store master key in Vault, re-encrypt existing keys |

## Open Questions

1. Lazy migration vs. batch migration for existing keys?
2. HKDF salt: user_id only, or user_id + random salt (requires new column)?
3. Master key retrieval latency from Vault RPC -- needs benchmarking
4. Key rotation: re-encryption job design when master key changes
