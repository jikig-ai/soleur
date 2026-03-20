# BYOK Key Decryption Fix — Brainstorm

**Date:** 2026-03-17
**Issue:** #667 (P1)
**Status:** Decided

## What We're Building

A fix for BYOK (Bring Your Own Key) decryption failure where AES-256-GCM throws "Unsupported state or unable to authenticate data" when the agent runner retrieves a user's stored API key.

## Why This Approach

### Root Cause

The `encrypted_key` column in the `api_keys` table is declared as `bytea` (binary) in migration 001, while `iv` and `auth_tag` (added in migration 002) are `text`. The application writes all three as base64 strings, but PostgREST returns `bytea` columns in PostgreSQL hex format (`\x4142...`), not the original base64. When `Buffer.from(hexString, "base64")` runs, it produces wrong bytes and GCM authentication fails.

### Chosen Approach: Migrate `encrypted_key` to `text` + Harden

A single migration aligns `encrypted_key` with how `iv` and `auth_tag` already work. Additionally:
- Fix the `ApiKey` TypeScript type to include `iv` and `auth_tag` fields
- Add tests for `encryptKey` / `decryptKey` round-trip
- File a follow-up issue for Supabase Vault migration

### Rejected Approaches

1. **Fix app code for `bytea`** — More invasive, changes both read/write paths, mixed conventions with `iv`/`auth_tag` already as `text`.
2. **Supabase Vault** — Vault is designed for infrastructure secrets, not per-user app-level secrets. No per-row RLS, SQL-only access, adds complexity. Filed as future improvement.

## Key Decisions

- **Column type:** `bytea` → `text` via `ALTER COLUMN ... TYPE text USING encode(encrypted_key, 'base64')`
- **Data preservation:** `USING` clause converts existing bytea values during migration, though they may already be corrupted
- **Type safety:** Add `iv` and `auth_tag` to `ApiKey` interface
- **Testing:** Add unit tests for encryption round-trip
- **Future:** File separate issue for Supabase Vault evaluation

## Open Questions

- Are there existing users with corrupted encrypted keys that need to re-save? (Likely yes — any user who saved a key before this fix)
- Should a migration include a cleanup step that marks potentially corrupted keys as `is_valid = false`?
