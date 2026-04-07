# Tasks: Secure Third-Party API Token Storage

**Issue:** #1076
**Plan:** `knowledge-base/project/plans/2026-04-07-feat-secure-third-party-token-storage-plan.md`

[Updated 2026-04-07 — collapsed from 5 phases to 3 per review feedback]

## Phase 1: Schema, Types, Validation, and CRUD API

- [x] 1.1 Create migration to expand provider CHECK constraint (14 providers)
  - File: `apps/web-platform/supabase/migrations/<next>_expand_provider_check.sql`
  - DROP existing CHECK, ADD new CHECK with all 14 provider values
- [x] 1.2 Update `ApiKey` interface in `apps/web-platform/lib/types.ts`
  - Expand `provider` union type to include all 14 providers
  - Add missing `key_version: number` field
- [x] 1.3 Create provider config constant
  - File: `apps/web-platform/server/providers.ts` (new)
  - Export `PROVIDER_CONFIG` with envVar, category, label per provider
  - Export `Provider` type derived from config keys
  - Bedrock/Vertex included in type but excluded from Connected Services UI and validation
- [x] 1.4 Create token validation module
  - File: `apps/web-platform/server/token-validators.ts` (new)
  - Export `validateToken(provider, token): Promise<boolean>`
  - 5-second timeout on all validation requests
- [x] 1.5 Implement validators for each provider (11 new + move existing Anthropic)
  - [x] 1.5.1 Move `validateAnthropicKey` from `byok.ts` (check imports first, re-export only if needed)
  - [x] 1.5.2 Cloudflare: `GET /client/v4/user/tokens/verify`
  - [x] 1.5.3 Stripe: `GET /v1/balance`
  - [x] 1.5.4 Plausible: `GET /api/v1/stats/realtime/visitors`
  - [x] 1.5.5 Hetzner: `GET /v1/servers`
  - [x] 1.5.6 GitHub: `GET /user`
  - [x] 1.5.7 Doppler: `GET /v3/me`
  - [x] 1.5.8 Resend: `GET /api-keys`
  - [x] 1.5.9 X/Twitter: `GET /2/users/me`
  - [x] 1.5.10 LinkedIn: `GET /v2/userinfo`
  - [x] 1.5.11 Bluesky: `GET describeServer` (avoid `createSession` side effect)
  - [x] 1.5.12 Buttondown: `GET /v1/emails`
- [x] 1.6 Write unit tests for validators (mock HTTP responses)
  - File: `apps/web-platform/__tests__/token-validators.test.ts`
- [x] 1.7 Create CRUD API route (single file, all methods)
  - File: `apps/web-platform/app/api/services/route.ts` (GET, POST, DELETE)
  - POST: CSRF + auth + rate limit + validate + encrypt + upsert (include `validated_at`)
  - GET: auth + query (never select encrypted fields) + merge with PROVIDER_CONFIG
  - DELETE: CSRF + auth + delete by (user_id, provider)
- [x] 1.8 Add error sanitizer entries for token-related errors
  - File: `apps/web-platform/server/error-sanitizer.ts`
- [x] 1.9 Verify CSRF coverage test catches new route
  - Run `csrf-coverage.test.ts` — should auto-detect new POST/DELETE handlers

## Phase 2: Agent Env Expansion

- [x] 2.1 Update `buildAgentEnv()` signature to accept service tokens
  - File: `apps/web-platform/server/agent-env.ts`
  - Add optional `serviceTokens?: Record<string, string>` parameter
  - Spread service tokens into env object
- [x] 2.2 Add `getUserServiceTokens(userId)` function
  - File: `apps/web-platform/server/agent-runner.ts`
  - Use `createServiceClient()` (not session client — agent-runner has no user cookies)
  - Fetch all valid non-LLM tokens in single query
  - Decrypt synchronously in a loop (`decryptKey` is sync Node crypto — no `Promise.all`)
  - Map providers to env var names via `PROVIDER_CONFIG`
- [x] 2.3 Wire service tokens into agent session start flow
  - Call `getUserServiceTokens(userId)` alongside `getUserApiKey(userId)`
  - Pass both to `buildAgentEnv(apiKey, serviceTokens)`
- [x] 2.4 Write integration test for encrypt → store → fetch → decrypt → inject cycle

## Phase 3: Connected Services UI

- [x] 3.0 **UX prerequisite:** Create wireframes/design before implementing (per AGENTS.md workflow gate)
- [x] 3.1 Create server component page
  - File: `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx`
  - Fetch connected services from Supabase, merge with `PROVIDER_CONFIG`
- [x] 3.2 Create `ConnectedServicesContent` client component
  - File: `apps/web-platform/components/settings/connected-services-content.tsx`
  - Group providers by category (LLM, Infrastructure, Social)
  - Exclude bedrock/vertex from display
  - Provider cards with Connect/Rotate/Remove actions
  - Token input form (modal or inline)
- [x] 3.3 ~~Add to sidebar~~ → Added link from Settings page instead (consistent with existing nav pattern)
- [x] 3.4 Add link from existing settings page to Connected Services
  - File: `apps/web-platform/components/settings/settings-content.tsx`

## Security Audit (runs during each phase, not a separate phase)

- [x] Audit all log paths for token leakage (grep `console.log`, `console.error`, `logger.*`)
- [x] Verify RLS policies cover new provider rows
- [ ] Run security-sentinel agent on changed files
- [ ] Legal document updates before shipping (T&C 4.2, Privacy Policy 4.7, DPD 2.3(h))
