---
title: "Supabase pgsodium pending deprecation and Vault limitations for per-user secrets"
date: 2026-03-20
category: integration-issues
tags: [supabase, pgsodium, vault, encryption, vendor-lock-in]
module: apps/web-platform
symptoms:
  - "Evaluating Supabase Vault for per-user API key storage"
  - "Building on pgsodium column encryption features"
---

# Learning: Supabase pgsodium deprecation and Vault limitations

## Problem

Issue #676 proposed migrating BYOK per-user API key storage to Supabase Vault (pgsodium). Two problems discovered:

1. **pgsodium is pending deprecation.** Supabase does not recommend new usage of pgsodium. Column-level encryption and server key management features are being deprecated due to "high operational complexity and misconfiguration risk." Vault's API will survive (internals shifting away from pgsodium), but building new per-user crypto on pgsodium is inadvisable.

2. **Vault is for infrastructure secrets, not per-user app secrets.** Vault is a flat secret store with no concept of "owner." Per-user BYOK keys have N-users x M-providers cardinality. `vault.decrypted_secrets` has no per-row RLS — you'd need `SECURITY DEFINER` SQL functions to reimplement what the existing `api_keys` table gives with RLS for free. SQL-only access (no PostgREST/JS SDK) means all operations become `supabase.rpc()` calls.

## Solution

Keep application-layer AES-256-GCM encryption (existing `byok.ts`) and add HKDF per-user key derivation. Use Vault only for infrastructure secrets (the use case it was designed for). Back up the master key to a password manager instead of moving it to Vault.

## Key Insight

Before building on a Supabase extension, check its deprecation status at supabase.com/docs. The pgsodium docs page title includes "(pending deprecation)" — easy to miss if you only read blog posts or community discussions. Also: moving one secret to Vault while `SUPABASE_SERVICE_ROLE_KEY` stays in `.env` is inconsistent — evaluate secrets management holistically, not per-secret.

## References

- [Supabase pgsodium docs (pending deprecation)](https://supabase.com/docs/guides/database/extensions/pgsodium)
- [Supabase Vault docs](https://supabase.com/docs/guides/database/vault)
