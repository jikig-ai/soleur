# Feature: BYOK Decryption Fix

## Problem Statement

BYOK key decryption fails with "Unsupported state or unable to authenticate data" (AES-256-GCM error) when the agent runner retrieves a user's stored API key after chat session start. The root cause is a PostgreSQL column type mismatch: `encrypted_key` is `bytea` while `iv` and `auth_tag` are `text`. PostgREST returns `bytea` in hex format, but the app expects base64.

## Goals

- Fix the `encrypted_key` column type so encryption round-trips correctly
- Add missing `iv` and `auth_tag` fields to the `ApiKey` TypeScript type
- Add unit tests for `encryptKey` / `decryptKey` round-trip
- Invalidate potentially corrupted keys so users are prompted to re-enter

## Non-Goals

- Migrating to Supabase Vault (tracked separately)
- Changing the encryption algorithm (AES-256-GCM is sound)
- Adding key rotation support
- Client-side encryption

## Functional Requirements

### FR1: Column type migration

A new SQL migration changes `encrypted_key` from `bytea` to `text` with a `USING encode(encrypted_key, 'base64')` clause to preserve any existing data.

### FR2: Corrupted key invalidation

The migration sets `is_valid = false` on any existing `api_keys` rows, since keys saved before this fix are likely corrupted. Users will be prompted to re-save their API key.

### FR3: Type safety

The `ApiKey` interface in `lib/types.ts` includes `iv`, `auth_tag`, and `updated_at` fields.

## Technical Requirements

### TR1: Migration safety

The migration must be idempotent and safe to run on both empty and populated databases.

### TR2: Test coverage

Unit tests verify `encryptKey` → `decryptKey` round-trip with both the dev fallback key and a custom hex key.

### TR3: No application code changes

The fix is schema-only for the core bug. The app already writes and reads base64 strings — once the column type matches, the existing code works correctly.
