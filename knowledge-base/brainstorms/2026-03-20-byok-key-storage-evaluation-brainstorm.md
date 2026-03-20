# BYOK Key Storage Evaluation Brainstorm

**Date:** 2026-03-20
**Issue:** #676
**Status:** Decision reached

## What We're Building

Enhanced BYOK (Bring Your Own Key) encryption with two improvements to the existing AES-256-GCM implementation:

1. **HKDF per-user key derivation** -- derive a unique encryption key per user from the master key using `HKDF(master_key, user_id, "byok")`, limiting blast radius if any single key is compromised
2. **Envelope encryption via Supabase Vault** -- wrap the master `BYOK_ENCRYPTION_KEY` with Supabase Vault (one infrastructure secret), eliminating the "lost .env = unrecoverable keys" risk and enabling key rotation

## Why This Approach

### Supabase Vault rejected for per-user secrets

The original proposal (#676) evaluated migrating all per-user API keys to Supabase Vault (pgsodium). Research revealed this is the wrong tool:

- **Cardinality mismatch**: Vault is a flat secret store for infrastructure secrets (connection strings, service keys). Per-user BYOK keys are N-users x M-providers cardinality -- Vault has no concept of "owner" on a secret
- **Loses RLS**: Current `api_keys` table has RLS enforcing `auth.uid() = user_id`. Vault's `decrypted_secrets` view has no per-row access control. Would need `SECURITY DEFINER` SQL functions to reimplement what RLS gives for free
- **pgsodium pending deprecation**: Supabase does not recommend new usage of pgsodium. Column-level encryption features are being deprecated due to operational complexity and misconfiguration risk. Vault's API will survive, but building new per-user crypto on pgsodium is inadvisable
- **SQL-only access**: All operations become RPC calls, losing PostgREST/SDK patterns. Harder to test, harder to debug
- **Vendor lock-in**: pgsodium ties to Supabase. Current Node.js `crypto` is portable

### Vault IS appropriate for the master key

Supabase Vault is designed for exactly one thing well: storing infrastructure secrets. The `BYOK_ENCRYPTION_KEY` master key IS an infrastructure secret. Using Vault for this single purpose aligns with its design intent while keeping per-user crypto in the application layer where it belongs.

### HKDF adds per-user isolation

Current implementation uses one key for all users. HKDF derivation creates a unique key per user from the master key + user ID. Benefits:
- Compromise of one user's derived key doesn't expose other users
- Master key loss is recoverable (derivation is deterministic from master + user_id)
- No additional key storage needed -- derived keys are computed on demand

## Key Decisions

1. **Keep crypto in Node.js** -- existing `byok.ts` AES-256-GCM implementation is correct and portable. Add HKDF derivation, don't move to pgcrypto
2. **No Supabase Vault** -- [Updated 2026-03-20] plan review rejected Vault for one secret while other secrets stay in `.env`. Back up master key to password manager instead
3. **HKDF key derivation per user** -- `hkdfSync('sha256', masterKey, Buffer.alloc(0), 'soleur:byok:' + userId, 32)`. [Updated 2026-03-20] Per RFC 5869: empty salt (IKM is high-entropy), user_id in info (domain separation)
4. **No pgsodium column encryption** -- pending deprecation, do not adopt
5. **Migration path needed** -- existing encrypted keys must be re-encrypted with per-user derived keys via lazy migration with `key_version` column

## Open Questions

1. **Migration strategy**: Re-encrypt existing keys in a single migration script or lazy-migrate on next access? Lazy migration avoids downtime but leaves some keys on the old scheme until accessed
2. **HKDF salt**: Should the salt include anything beyond `user_id`? Adding a random salt per user increases security but requires storing the salt (adding a column)
3. **Master key retrieval latency**: How much latency does Supabase Vault RPC add vs. reading from env var? Needs benchmarking, but can be mitigated with caching (master key changes rarely)
4. **Key rotation procedure**: When the master key is rotated in Vault, all derived keys change. Need a re-encryption job that processes all users

## Motivators Addressed

| Motivator | How Addressed |
|-----------|--------------|
| Key-loss risk | Master key in Vault (backed by Supabase infrastructure), not `.env` |
| Defense-in-depth | Per-user key derivation limits blast radius; master key never in application config |
| Operational simplicity | Vault manages the one secret that matters; no custom key infrastructure |
| Compliance (future) | KMS-wrapped master key + per-user isolation is audit-friendly when needed |

## Research Sources

- [Supabase pgsodium docs (pending deprecation)](https://supabase.com/docs/guides/database/extensions/pgsodium)
- [Supabase Vault docs](https://supabase.com/docs/guides/database/vault)
- [pgsodium/auth with RLS discussion](https://github.com/orgs/supabase/discussions/13316)
- [PostgreSQL pgcrypto docs](https://www.postgresql.org/docs/current/pgcrypto.html)
