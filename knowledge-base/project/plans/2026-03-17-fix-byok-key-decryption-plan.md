# fix: BYOK key decryption fails (#667)

**Type:** bug fix
**Priority:** P1
**Branch:** feat/web-platform-ux
**Issue:** #667

## Summary

AES-256-GCM decryption fails with "Unsupported state or unable to authenticate data" when the agent runner retrieves a user's stored API key. Root cause: `encrypted_key` column is `bytea` but the app reads/writes base64 strings. PostgREST returns `bytea` in PostgreSQL hex format (`\x...`), not base64.

## Changes

### 1. Migration: `003_fix_encrypted_key_column_type.sql`

**File:** `apps/web-platform/supabase/migrations/003_fix_encrypted_key_column_type.sql`

```sql
-- Fix encrypted_key column type: bytea -> text
-- PostgREST returns bytea in hex format (\x...) but the app
-- reads/writes base64 strings. Align with iv and auth_tag (both text).
--
-- Note: The stored bytea contains the ASCII bytes of the base64 string
-- (PostgREST interpreted the base64 text as raw bytes on write).
-- convert_from extracts the original base64 text. This conversion is
-- academic since all rows are invalidated below, but it preserves
-- data correctly in case invalidation is ever removed.

ALTER TABLE public.api_keys
  ALTER COLUMN encrypted_key TYPE text
  USING convert_from(encrypted_key, 'UTF8');

-- Invalidate existing keys — they were likely corrupted by the
-- bytea/base64 mismatch. Users will be prompted to re-save.
-- Also reset validated_at to prevent stale validation timestamps.
UPDATE public.api_keys SET is_valid = false, validated_at = NULL;
```

**Edge cases:**

- Empty table: both statements are no-ops on zero rows
- Not idempotent: `convert_from()` expects `bytea` input and would fail on a `text` column. Supabase migration tracking prevents re-execution.
- Multiple providers per user: `UPDATE` invalidates all rows, which is correct

### 2. Fix `ApiKey` type

**File:** `apps/web-platform/lib/types.ts:23-30`

Add missing fields to match the database schema:

```typescript
export interface ApiKey {
  id: string;
  user_id: string;
  encrypted_key: string;
  provider: "anthropic" | "bedrock" | "vertex";
  is_valid: boolean;
  validated_at: string | null;
  iv: string;
  auth_tag: string;
  updated_at: string;
  created_at: string;
}
```

### 3. Add encryption round-trip tests

**File:** `apps/web-platform/test/byok.test.ts`

Tests using **vitest** (per `package.json` — this app uses vitest, not bun:test):

```typescript
import { describe, test, expect } from "vitest";
import { encryptKey, decryptKey } from "../server/byok";

describe("BYOK encryption round-trip", () => {
  test("encrypts and decrypts a key correctly", () => {
    // Tests crypto primitives in isolation (Buffer-to-Buffer, no serialization)
    const plaintext = "sk-ant-api03-test-key-1234567890";
    const { encrypted, iv, tag } = encryptKey(plaintext);
    const decrypted = decryptKey(encrypted, iv, tag);
    expect(decrypted).toBe(plaintext);
  });

  test("base64 round-trip matches app data flow", () => {
    // Simulates the exact save/read path through Supabase:
    // route.ts writes Buffer.toString("base64") → DB stores text →
    // agent-runner.ts reads Buffer.from(text, "base64")
    const plaintext = "sk-ant-api03-another-key";
    const { encrypted, iv, tag } = encryptKey(plaintext);

    // Save path: Buffer → base64 string (as stored in DB)
    const storedEncrypted = encrypted.toString("base64");
    const storedIv = iv.toString("base64");
    const storedTag = tag.toString("base64");

    // Read path: base64 string → Buffer (as read from DB)
    const decrypted = decryptKey(
      Buffer.from(storedEncrypted, "base64"),
      Buffer.from(storedIv, "base64"),
      Buffer.from(storedTag, "base64"),
    );
    expect(decrypted).toBe(plaintext);
  });
});
```

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/supabase/migrations/003_fix_encrypted_key_column_type.sql` | **New** — column type migration + key invalidation |
| `apps/web-platform/lib/types.ts` | **Edit** — add `iv`, `auth_tag`, `updated_at`, `created_at` to `ApiKey` |
| `apps/web-platform/test/byok.test.ts` | **New** — encryption round-trip tests |

## No Application Code Changes Needed

The encryption logic in `byok.ts` is correct. The save path (`api/keys/route.ts:43`) and read path (`agent-runner.ts:49`) both use base64 correctly. The only problem is the column type — once `encrypted_key` is `text`, the existing code works.

## Deployment

1. Run migration `003_fix_encrypted_key_column_type.sql` on the Supabase dashboard (or via `supabase db push`)
2. All existing users' keys will be invalidated — they'll see the setup-key page on next login
3. No app code deployment needed for the core fix (type fix and tests are dev-only improvements)

## Verification

- [ ] `npx vitest run` passes in `apps/web-platform/`
- [ ] Migration runs without error on Supabase dashboard
- [ ] E2E: save API key → start chat → agent boots successfully (no decryption error)
- [ ] Existing user sees setup-key page (key invalidated by migration)
