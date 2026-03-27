---
adr: ADR-004
title: BYOK Encryption Model
status: active
date: 2026-03-27
---

# ADR-004: BYOK Encryption Model

## Context

Users provide their own Anthropic API keys. Need strong encryption and per-user isolation. Supabase pgcrypto has cardinality mismatch (one vault secret per user doesn't scale).

## Decision

AES-256-GCM encryption in application layer (Node.js crypto). HKDF per-user key derivation with empty salt and user_id in info field for domain separation. Envelope encryption for master key (future Supabase Vault, currently password-manager backup).

## Consequences

Per-user cryptographic isolation without database-level encryption dependency. RFC 5869 compliant. Master key is single point of failure — requires offline backup regardless. Column type alignment needed (bytea → text for encrypted_key to match iv and auth_tag).
