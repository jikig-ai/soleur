---
title: "feat: secure third-party API token storage"
type: feat
date: 2026-04-07
---

# feat: secure third-party API token storage

## Overview

Extend the existing BYOK-grade AES-256-GCM encryption to support 11 new third-party service providers (Cloudflare, Stripe, Plausible, Hetzner, GitHub, X/Twitter, LinkedIn, Doppler, Bluesky, Buttondown, Resend) alongside the 3 existing LLM providers. Includes CRUD API routes, per-provider token validation, automatic env var injection into agent subprocesses, and a Connected Services settings page.

Issue: #1076 | Roadmap: Phase 3, item 3.5 (enables 3.4)

## Problem Statement

Users can only store their Anthropic API key. The 3-tier service automation architecture (roadmap 3.4) requires the agent to interact with Cloudflare (DNS), Stripe (billing), Plausible (analytics), and other services on behalf of the user. Without secure multi-provider token storage, the agent cannot act on these services.

## Proposed Solution

Reuse the proven `byok.ts` encryption module (AES-256-GCM + HKDF per-user key derivation) with the existing `api_keys` table. The crypto layer is already provider-agnostic — the work is in schema expansion, validation registry, CRUD API, env injection, and UI.

## Technical Approach

### Architecture

```text
┌─────────────────────────────────────────────────────┐
│                Connected Services UI                │
│  (dashboard)/dashboard/settings/services/page.tsx   │
└───────────────┬─────────────────────────────────────┘
                │ fetch()
┌───────────────▼─────────────────────────────────────┐
│              API Routes (CRUD)                       │
│  POST /api/services    — add/rotate token            │
│  GET  /api/services    — list connected providers    │
│  DELETE /api/services  — disconnect provider         │
└───────────────┬─────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────┐
│         Provider Validation Registry                 │
│  validateToken(provider, token) → boolean            │
│  PROVIDER_CONFIG: env var, validation URL, category  │
└───────────────┬─────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────┐
│           Encryption Layer (byok.ts)                 │
│  encryptKey(token, userId) → {encrypted, iv, tag}    │
│  decryptKey(encrypted, iv, tag, userId) → plaintext  │
│  (unchanged — already provider-agnostic)             │
└───────────────┬─────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────┐
│         Storage (api_keys table + RLS)               │
│  UNIQUE(user_id, provider) — upsert for rotation     │
│  CHECK(provider IN (...14 values...))                │
└─────────────────────────────────────────────────────┘

Session start:
  getUserTokens(userId) → decrypt all valid tokens
  buildAgentEnv(anthropicKey, serviceTokens) → env object
  agent subprocess receives only allowlisted env vars
```

### Bedrock/Vertex Exclusion

Bedrock (`AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`) and Vertex (`GOOGLE_APPLICATION_CREDENTIALS` JSON file) are multi-value or file-based credentials that do not fit the single-token `{ provider, token }` CRUD model. They remain in the CHECK constraint (existing values) but are **excluded from the Connected Services page and validation registry**. They are existing LLM providers handled by separate flows. If multi-value credential support is needed later, it requires a schema change (e.g., a JSONB `credentials` column).

### Implementation Phases

[Updated 2026-04-07 — collapsed from 5 phases to 3 per review feedback]

#### Phase 1: Schema, Types, Validation, and CRUD API

**Migration: expand CHECK constraint**

File: `apps/web-platform/supabase/migrations/<next>_expand_provider_check.sql`

```sql
ALTER TABLE api_keys
  DROP CONSTRAINT api_keys_provider_check,
  ADD CONSTRAINT api_keys_provider_check
  CHECK (provider IN (
    'anthropic', 'bedrock', 'vertex',
    'cloudflare', 'stripe', 'plausible', 'hetzner',
    'github', 'doppler', 'resend',
    'x', 'linkedin', 'bluesky', 'buttondown'
  ));
```

**TypeScript types update**

File: `apps/web-platform/lib/types.ts`

- Expand `ApiKey.provider` union to include all 14 providers
- Add missing `key_version` field to `ApiKey` interface (gap found during research — DB has it since migration 009 but TypeScript type omits it)

**Provider config constant**

File: `apps/web-platform/server/providers.ts` (new)

```typescript
export const PROVIDER_CONFIG = {
  anthropic: { envVar: "ANTHROPIC_API_KEY", category: "llm", label: "Anthropic" },
  cloudflare: { envVar: "CLOUDFLARE_API_TOKEN", category: "infrastructure", label: "Cloudflare" },
  stripe: { envVar: "STRIPE_SECRET_KEY", category: "infrastructure", label: "Stripe" },
  // ... all 14 (bedrock/vertex included in type but excluded from Connected Services UI)
} as const satisfies Record<Provider, ProviderConfig>;
```

This constant is the single source of truth for provider metadata — env var names, categories, labels, and validation endpoints. Used by the validation registry, buildAgentEnv, and UI.

**Provider validation registry**

File: `apps/web-platform/server/token-validators.ts` (new)

One validation function per provider. Each makes a lightweight API call with a **5-second timeout** to verify the token works. Pattern from existing `validateAnthropicKey` in `byok.ts:87-100`.

| Provider | Validation Call | Auth Header |
|----------|----------------|-------------|
| Anthropic | `GET /v1/models` | `x-api-key: <token>` |
| Cloudflare | `GET /client/v4/user/tokens/verify` | `Authorization: Bearer <token>` |
| Stripe | `GET /v1/balance` | `Authorization: Bearer <token>` |
| Plausible | `GET /api/v1/stats/realtime/visitors?site_id=soleur.ai` | `Authorization: Bearer <token>` |
| Hetzner | `GET https://api.hetzner.cloud/v1/servers` | `Authorization: Bearer <token>` |
| GitHub | `GET https://api.github.com/user` | `Authorization: Bearer <token>` |
| Doppler | `GET https://api.doppler.com/v3/me` | `Authorization: Bearer <token>` |
| Resend | `GET https://api.resend.com/api-keys` | `Authorization: Bearer <token>` |
| X/Twitter | `GET https://api.x.com/2/users/me` | `Authorization: Bearer <token>` |
| LinkedIn | `GET https://api.linkedin.com/v2/userinfo` | `Authorization: Bearer <token>` |
| Bluesky | `GET https://bsky.social/xrpc/com.atproto.server.describeServer` | `Authorization: Bearer <token>` |
| Buttondown | `GET https://api.buttondown.com/v1/emails` | `Authorization: Token <token>` |

**Bluesky note:** Uses `describeServer` instead of `createSession` to avoid the side effect of creating a real AT Protocol session during validation. If `describeServer` does not require auth, fall back to `getProfile` with the token as bearer.

Export a single entry point:

```typescript
export async function validateToken(provider: Provider, token: string): Promise<boolean>
```

Move `validateAnthropicKey` from `byok.ts` into this module. Check if anything imports it from `byok.ts` first — only re-export if needed.

**CRUD API routes**

Single route file: `apps/web-platform/app/api/services/route.ts` (GET, POST, DELETE in one file per Next.js App Router convention)

**POST** — Add or rotate a token

1. `validateOrigin(request)` + `rejectCsrf()`
2. Auth via `createClient().auth.getUser()`
3. Rate limit: per-user `SlidingWindowCounter` (prevents rapid validation calls to third-party APIs)
4. Parse body: `{ provider: string, token: string }`
5. Validate provider against `PROVIDER_CONFIG` keys (exclude `bedrock`, `vertex`)
6. Call `validateToken(provider, token)` — return `{ valid: false, error: "Token validation failed" }` on failure
7. Encrypt via `encryptKey(token, user.id)`
8. Upsert to `api_keys` with `onConflict: "user_id,provider"`, `key_version: 2`, `is_valid: true`, `validated_at: new Date().toISOString()`
9. Return `{ valid: true, provider }`

**GET** — List connected services

1. Auth via `createClient().auth.getUser()`
2. Query `api_keys` where `user_id = user.id`, select `provider, is_valid, validated_at, updated_at` (never select encrypted fields)
3. Return `{ services: [...] }` merged with `PROVIDER_CONFIG` metadata (category, label) for UI

**DELETE** — Disconnect a service

1. `validateOrigin(request)` + `rejectCsrf()`
2. Auth via `createClient().auth.getUser()`
3. Parse body: `{ provider: string }`
4. Delete from `api_keys` where `user_id = user.id AND provider = provider`
5. Return `{ deleted: true, provider }`

**Conventions to follow** (from repo research):

- CSRF: `validateOrigin(request)` + `rejectCsrf("api/services", origin)` on POST/DELETE
- Auth: inline `createClient().auth.getUser()` pattern (project convention, not extracted)
- Errors: `NextResponse.json({ error: "message" }, { status: N })` — never raw internal errors
- Logging: `logger.error({ err, userId }, "message")`
- Supabase: always destructure `{ data, error }` and check error (learning: silent discard)

#### Phase 2: Agent Env Expansion

**File: `apps/web-platform/server/agent-env.ts`**

Change `buildAgentEnv` signature:

```typescript
// Before:
export function buildAgentEnv(apiKey: string): Record<string, string>

// After:
export function buildAgentEnv(
  apiKey: string,
  serviceTokens?: Record<string, string>
): Record<string, string>
```

The `serviceTokens` parameter is a map of env var name to decrypted value (e.g., `{ CLOUDFLARE_API_TOKEN: "cf-...", STRIPE_SECRET_KEY: "sk_..." }`). Each entry is spread into the env object alongside `ANTHROPIC_API_KEY`. The allowlist philosophy is maintained — only tokens the user explicitly stored are injected, and the env var names come from `PROVIDER_CONFIG`, not user input.

**File: `apps/web-platform/server/agent-runner.ts`**

Add `getUserServiceTokens(userId)` function:

1. Query `api_keys` using `createServiceClient()` (agent-runner runs server-side without user session cookies — must use service client, not session client)
2. Filter: `user_id = userId AND is_valid = true AND provider NOT IN ('anthropic', 'bedrock', 'vertex')`
3. Decrypt each token synchronously via `decryptKey(encrypted, iv, authTag, userId)` in a loop (handles v1→v2 lazy migration). Note: `decryptKey` is synchronous (Node crypto) — do not wrap in `Promise.all`.
4. Map each provider to its env var name via `PROVIDER_CONFIG[provider].envVar`
5. Return `Record<string, string>`

Update the agent session start flow to call `getUserServiceTokens(userId)` alongside `getUserApiKey(userId)` and pass both to `buildAgentEnv()`.

**Batch fetch optimization:** Fetch all tokens in a single Supabase query, then decrypt synchronously in a loop.

#### Phase 3: Connected Services UI

**UX prerequisite:** Per AGENTS.md, user-facing pages need UX artifacts before implementation. The brainstorm offered visual design and the user deferred it. Before implementing this phase, run ux-design-lead or create wireframes.

**Page:** `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx` (server component)

- Fetch connected services via `createClient()` query (select `provider, is_valid, validated_at, updated_at`)
- Merge with `PROVIDER_CONFIG` for display metadata
- Pass to `ConnectedServicesContent` client component

**Component:** `apps/web-platform/components/settings/connected-services-content.tsx`

- Group providers by category (LLM Providers, Infrastructure, Social) from `PROVIDER_CONFIG`
- Each provider card shows: icon/label, connection status, validated_at, actions (Connect/Rotate/Remove)
- Connect action: opens a modal/inline form to paste token → POST `/api/services`
- Rotate action: same form, pre-labeled as "Replace token" → POST `/api/services` (upsert)
- Remove action: confirmation dialog → DELETE `/api/services`

**Styling conventions** (from repo research):

- Section card: `rounded-xl border border-neutral-800 bg-neutral-900/50 p-6`
- Section header: `text-lg font-semibold text-white`
- Input: `rounded-lg border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white focus:border-amber-600 focus:ring-1 focus:ring-amber-600`
- Button primary: `rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white`
- Status indicators: `text-green-400` (connected), `text-neutral-500` (not connected)
- Error: `text-sm text-red-400` with `role="alert"`

**Navigation:** Add "Connected Services" to dashboard sidebar `NAV_ITEMS` in `(dashboard)/layout.tsx`.

**Integration with existing setup-key flow:** The `/setup-key` onboarding page continues to handle the initial Anthropic key. The Connected Services page is a separate settings page for managing all providers. No changes to the auth callback flow.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Separate `service_tokens` table | Duplicates encryption storage pattern. Single `api_keys` table with expanded CHECK is simpler and reuses existing RLS, indexes, and cascade deletes. |
| Tool-based token retrieval (MCP `get-secret`) | More complex, requires new MCP server. Env injection matches existing pattern and is simpler. Deferred to 3.4 if MCP servers need tokens at connection time. |
| Per-user MCP server config | Significant lifecycle complexity (start/stop per-user MCP servers). Deferred to 3.4 implementation. |
| Drop CHECK, validate in app only | Loses DB-level integrity. For a curated ~14 provider list, CHECK is fine. Each new provider requires a migration, which is acceptable. |
| Supabase Vault for token storage | Rejected in prior brainstorm (#676). Vault is for infrastructure secrets (flat store), not per-user app secrets with N-users × M-providers cardinality. pgsodium pending deprecation. |

## Acceptance Criteria

### Functional Requirements

- [ ] Users can add a token for any of the 14 supported providers via Connected Services page
- [ ] Users can rotate (replace) an existing token by submitting a new one
- [ ] Users can delete (disconnect) a token for any provider
- [ ] Users can see which providers are connected with validation status and last-updated timestamp
- [ ] Tokens are validated against the provider's API before storage (invalid tokens rejected with clear error)
- [ ] All connected service tokens are injected into the agent subprocess env at session start
- [ ] Existing Anthropic key setup-key onboarding flow works unchanged
- [ ] Connected Services page is accessible from dashboard sidebar navigation

### Non-Functional Requirements

- [ ] Tokens encrypted with AES-256-GCM + HKDF per-user key derivation (existing `byok.ts`)
- [ ] Tokens never appear in server logs, error messages, or client responses (audit all log paths)
- [ ] CSRF protection on all mutating routes (`validateOrigin` + `rejectCsrf`)
- [ ] Supabase RLS enforces `auth.uid() = user_id` on all operations
- [ ] Error responses use sanitized messages, never raw internal errors
- [ ] Base64-encoded ciphertext stored in `text` columns (not `bytea`)

### Quality Gates

- [ ] CSRF coverage test (`csrf-coverage.test.ts`) passes with new routes included
- [ ] Unit tests for each provider validator (mock HTTP responses)
- [ ] Integration test for encrypt → store → fetch → decrypt → inject cycle
- [ ] No tokens in `console.log`, `console.error`, or `logger.*` output (grep audit)

## Test Scenarios

### Acceptance Tests

- Given a user with no Cloudflare token, when they submit a valid Cloudflare API token via Connected Services, then the token is encrypted and stored, and the provider shows as "Connected"
- Given a user with an existing Stripe token, when they submit a new Stripe token, then the old token is replaced (upsert) and validation runs on the new token
- Given a user with a connected GitHub token, when they click "Remove", then the token row is deleted and the provider shows as "Not connected"
- Given a user submits an invalid Plausible token, when validation fails, then the token is NOT stored and an error message is shown
- Given a user with 3 connected services, when an agent session starts, then `buildAgentEnv` returns env vars for all 3 services plus `ANTHROPIC_API_KEY`
- Given a user with no connected services, when an agent session starts, then `buildAgentEnv` returns only `ANTHROPIC_API_KEY` (backward compatible)

### Edge Cases

- Given a user submits a token for provider "invalid_provider", when the API route processes it, then return 400 with "Unsupported provider"
- Given a provider's validation endpoint is down (timeout), when the user submits a token, then return a clear error (not a 500 with leaked internal details)
- Given two concurrent requests to add the same provider token, when both hit the upsert, then one succeeds and the DB constraint prevents duplicates
- Given a user submits a token containing special characters, when it is encrypted and decrypted, then the original value is preserved exactly

### Integration Verification

- **API verify:** `curl -s -X POST /api/services -H "Content-Type: application/json" -d '{"provider":"cloudflare","token":"..."}' | jq '.valid'` expects `true`
- **API verify:** `curl -s /api/services | jq '.services | length'` expects correct count
- **Browser:** Navigate to `/dashboard/settings/services`, verify provider cards render with correct categories, connect a test token, verify status updates

## Dependencies & Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| `byok.ts` encryption module | Complete | Provider-agnostic, no changes needed |
| `api_keys` table with RLS | Complete | Needs CHECK constraint expansion |
| `buildAgentEnv()` pattern | Complete | Needs signature expansion |
| Error sanitizer | Complete | Needs new safe message entries |
| CSRF infrastructure | Complete | New routes auto-caught by coverage test |
| UX wireframes for Connected Services page | **Not started** | Required before Phase 3 per AGENTS.md |

## Risk Analysis & Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| Provider validation endpoints change | LOW | Validators are simple HTTP checks. Easy to update individually. |
| Token leaked in error message | HIGH | Error sanitizer is allowlist-based. Audit all log paths. Add grep check in CI. |
| HKDF parameter confusion | HIGH | Existing pattern documented in learnings. Tests verify encrypt/decrypt roundtrip. |
| Provider validation endpoint is slow/down | MEDIUM | Set 5-second timeout on all validation requests. Return clear error on timeout. |
| bytea/text column confusion | HIGH | Using text columns (existing convention since migration 003). Documented in learnings. |
| Rapid token submission hits third-party rate limits | MEDIUM | Per-user rate limiting via `SlidingWindowCounter` on POST `/api/services`. |
| Bluesky validation side effects | LOW | Use `describeServer` or `getProfile` instead of `createSession` to avoid creating real sessions during validation. |
| Bedrock/Vertex multi-value credentials | LOW | Explicitly excluded from Connected Services. Single-token model only. Tracked as future work if needed. |

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Low-risk extension of proven BYOK pattern. Key architecture decision (env injection) resolved. `byok.ts` is provider-agnostic; main work is validation registry, CRUD API, env expansion, and UI. Medium complexity (days). Carried forward from brainstorm.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Existing legal docs cover "encrypted API keys" generically. No structural changes needed. T&C Section 4.2 needs review to confirm automated agent-initiated API calls are covered. Minor transparency updates to Privacy Policy Section 4.7 and DPD Section 2.3(h) before shipping. No blocking issues. Carried forward from brainstorm.

## Key Learnings to Apply

| Learning | File | Application |
|----------|------|------------|
| HKDF salt vs info semantics | `2026-03-20-hkdf-salt-info-parameter-semantics.md` | Don't change HKDF pattern — salt=empty, info=`soleur:byok:<userId>` |
| PostgREST bytea corruption | `2026-03-17-postgrest-bytea-base64-mismatch.md` | Use `text` columns for encrypted data |
| CWE-526 env spread | `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` | Keep allowlist pattern in `buildAgentEnv` |
| CSRF three-layer defense | `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md` | `validateOrigin` + `rejectCsrf` on all POST/DELETE |
| Supabase silent errors | `2026-03-20-supabase-silent-error-return-values.md` | Always destructure `{ data, error }` |
| Middleware prefix bypass | `2026-03-20-middleware-prefix-matching-bypass.md` | Use exact-or-prefix-with-slash matching |
| Error sanitization CWE-209 | `2026-03-20-websocket-error-sanitization-cwe-209.md` | Never return raw Supabase errors to client |
| Column-level grant override | `2026-03-20-supabase-column-level-grant-override.md` | Whitelist model for column security |
| Typed error codes | `2026-03-18-typed-error-codes-websocket-key-invalidation.md` | Use discriminated union error codes in API responses |

## References & Research

### Internal References

- Encryption module: `apps/web-platform/server/byok.ts:41-85`
- Agent env: `apps/web-platform/server/agent-env.ts:34-48`
- Agent runner token fetch: `apps/web-platform/server/agent-runner.ts:72-108`
- API key POST route: `apps/web-platform/app/api/keys/route.ts:1-67`
- Settings page: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx:1-43`
- Settings content: `apps/web-platform/components/settings/settings-content.tsx:1-79`
- TypeScript types: `apps/web-platform/lib/types.ts:60-71`
- Error sanitizer: `apps/web-platform/server/error-sanitizer.ts:1-41`
- CSRF validation: `apps/web-platform/lib/auth/validate-origin.ts:10-32`
- Middleware: `apps/web-platform/middleware.ts:1-138`
- Dashboard layout: `apps/web-platform/app/(dashboard)/layout.tsx`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-secure-token-storage-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-secure-token-storage/spec.md`

### Related Work

- Issue: #1076
- Enables: #1050 (API + MCP service integrations, roadmap 3.4)
- Prior art: #676 (BYOK evaluation), HKDF upgrade (migration 009)
