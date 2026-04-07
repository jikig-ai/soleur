# Secure Third-Party API Token Storage

**Issue:** #1076
**Branch:** secure-token-storage
**Status:** Draft

## Problem Statement

Soleur users can only store their Anthropic API key. To enable the 3-tier service automation architecture (roadmap 3.4), users need to securely store tokens for all services the agent interacts with (Cloudflare, Stripe, Plausible, Hetzner, GitHub, X/Twitter, LinkedIn, Doppler, Bluesky, Buttondown, Resend).

## Goals

- G1: Extend BYOK-grade AES-256-GCM encryption to 11 new third-party service providers
- G2: Provide CRUD operations (add, list, rotate, delete) for all provider tokens
- G3: Automatically inject decrypted tokens into agent subprocess environment
- G4: Build a Connected Services settings page for managing all providers
- G5: Validate tokens against provider APIs before storage

## Non-Goals

- NG1: Per-user MCP server lifecycle management (deferred to 3.4 implementation)
- NG2: Token scope/permission validation (store whatever the user provides)
- NG3: Token usage tracking or analytics
- NG4: OAuth flows for providers that support them (BYOK pattern only)
- NG5: Per-provider key derivation (existing HKDF info parameter is sufficient)

## Functional Requirements

- FR1: Users can add a token for any supported provider via the Connected Services page
- FR2: Users can rotate (replace) an existing token for any provider
- FR3: Users can delete (disconnect) a token for any provider
- FR4: Users can see which providers are connected and their validation status
- FR5: Tokens are validated against the provider's API before being stored
- FR6: All connected service tokens are injected into the agent subprocess env at session start
- FR7: The existing Anthropic key onboarding flow (setup-key) continues to work unchanged

## Technical Requirements

- TR1: Encryption uses existing `byok.ts` AES-256-GCM + HKDF per-user key derivation
- TR2: Storage uses existing `api_keys` table with expanded CHECK constraint
- TR3: Tokens are never logged or exposed in error messages (audit all log paths)
- TR4: `buildAgentEnv()` expanded to fetch and inject all valid tokens for a user
- TR5: RLS policy unchanged — `auth.uid() = user_id` on all operations
- TR6: Provider validation registry maps each provider to its validation endpoint
- TR7: Base64-encoded ciphertext stored in `text` columns (not `bytea` — PostgREST gotcha)

## Providers

14 total (3 existing LLM + 11 new service integrations). See brainstorm document for full registry with env vars and validation endpoints.

## Key Learnings to Apply

- HKDF: salt = empty, info = `soleur:byok:<userId>`. Never swap (silent data corruption).
- Store ciphertext in `text` columns, not `bytea` (PostgREST corrupts base64 round-trips).
- Subprocess env must be allowlist-based (`buildAgentEnv`). Never spread `process.env`.
- Supabase JS client does not throw — always destructure and check `{ error }`.
- Table-level grants silently override column-level revokes (whitelist model for RLS).
