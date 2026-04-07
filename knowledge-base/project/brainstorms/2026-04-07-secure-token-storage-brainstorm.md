# Secure Third-Party API Token Storage Brainstorm

**Date:** 2026-04-07
**Issue:** #1076
**Roadmap:** Phase 3, item 3.5 (enables 3.4)

## What We're Building

A secure storage system for third-party API tokens (Cloudflare, Stripe, Plausible, Hetzner, GitHub, X/Twitter, LinkedIn, Doppler, Bluesky, Buttondown, Resend) using the same BYOK-grade AES-256-GCM encryption pattern already in place for LLM provider keys. Includes a "Connected Services" settings page for managing all 14 providers (3 existing LLM + 11 new service integrations).

## Why This Approach

The existing `byok.ts` module (101 lines, zero external deps) already provides AES-256-GCM with HKDF per-user key derivation. The `api_keys` table already has a `(user_id, provider)` unique constraint. Extending this pattern is low-risk and avoids introducing a second encryption stack. The architecture decisions (Vault rejected, HKDF chosen, app-layer encryption, text columns for ciphertext) are documented and battle-tested.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Token consumption model | Env injection via `buildAgentEnv()` | Matches existing pattern. All decrypted tokens injected as env vars at session start. Simplest option. |
| Schema strategy | Expand CHECK constraint on existing `api_keys` table | Single table, DB-level integrity. Fine for a curated list of ~14 providers. Migration per new provider is acceptable. |
| Token validation | Validate per provider before storage | Each provider gets a lightweight API call to verify the token works. Catches bad tokens upfront. |
| Provider scope | All 11 Soleur service providers | Cloudflare, Stripe, Plausible, Hetzner, GitHub, X/Twitter, LinkedIn, Doppler, Bluesky, Buttondown, Resend. Matches the services Soleur already uses. |
| UI | Connected Services settings page | New page with provider categories (LLM Providers, Service Integrations, Social). Connect/disconnect/rotate actions per provider. Keeps existing setup-key flow for Anthropic onboarding. |
| HKDF info parameter | Reuse existing `soleur:byok:<userId>` | Same derived key for all providers per user. Random IV per encryption prevents collisions. No per-provider key derivation needed. |
| Error handling | Existing error-sanitizer pattern | `error-sanitizer.ts` already strips unknown errors. Audit log output paths to ensure tokens never appear in server-side logs. |

## Provider Registry

| Provider | Env Var | Validation Endpoint | Category |
|----------|---------|-------------------|----------|
| Anthropic | `ANTHROPIC_API_KEY` | `GET /v1/models` | LLM |
| AWS Bedrock | `AWS_ACCESS_KEY_ID` | (existing) | LLM |
| Google Vertex | `GOOGLE_APPLICATION_CREDENTIALS` | (existing) | LLM |
| Cloudflare | `CLOUDFLARE_API_TOKEN` | `GET /client/v4/user/tokens/verify` | Infrastructure |
| Stripe | `STRIPE_SECRET_KEY` | `GET /v1/balance` | Infrastructure |
| Plausible | `PLAUSIBLE_API_KEY` | `GET /api/v1/stats/realtime/visitors` | Infrastructure |
| Hetzner | `HETZNER_API_TOKEN` | `GET /v1/servers` | Infrastructure |
| GitHub | `GITHUB_TOKEN` | `GET /user` | Infrastructure |
| Doppler | `DOPPLER_TOKEN` | `GET /v3/me` | Infrastructure |
| Resend | `RESEND_API_KEY` | `GET /api-keys` | Infrastructure |
| X/Twitter | `X_BEARER_TOKEN` | `GET /2/users/me` | Social |
| LinkedIn | `LINKEDIN_ACCESS_TOKEN` | `GET /v2/userinfo` | Social |
| Bluesky | `BLUESKY_APP_PASSWORD` | AT Protocol `createSession` | Social |
| Buttondown | `BUTTONDOWN_API_KEY` | `GET /v1/emails` | Social |

## Open Questions

- Should Bluesky use app password or OAuth token? AT Protocol supports both, but app passwords are simpler for BYOK.
- Should the Connected Services page show which services the agent has actually used (usage tracking)?
- Token scope validation: should we warn users if a Cloudflare token has overly broad permissions?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Low-risk extension of proven BYOK pattern. Key architecture decision (env injection vs tool-based retrieval vs per-user MCP config) resolved in favor of env injection. The `byok.ts` crypto module is provider-agnostic; main work is in validation registry, CRUD API, env expansion, and UI. CHECK constraint expansion preferred over application-layer-only validation. Medium complexity estimate (days, not weeks).

### Legal (CLO)

**Summary:** Existing legal documents already cover "encrypted API keys" generically with AES-256-GCM. No structural legal changes needed. Key flag: when tokens are used automatically via MCP tier (item 3.4), Soleur transitions from storing credentials to acting as an agent with those credentials. T&C Section 4.2 ("Third-Party API Interactions") needs review to confirm it covers automated/agent-initiated API calls, not just user-initiated ones. Minor transparency updates recommended for Privacy Policy Section 4.7 and Data Protection Disclosure Section 2.3(h) before shipping. No blocking legal issues.

## Operational Follow-up

Missing services need to be added to `knowledge-base/operations/expenses.md`: LinkedIn, Doppler, Bluesky, Buttondown, Resend.
