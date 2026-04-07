# Tasks: Secure Third-Party API Token Storage

**Issue:** #1076
**Plan:** `knowledge-base/project/plans/2026-04-07-feat-secure-third-party-token-storage-plan.md`

[Updated 2026-04-07 — collapsed from 5 phases to 3 per review feedback]

## Phase 1: Schema, Types, Validation, and CRUD API

- [ ] 1.1 Create migration to expand provider CHECK constraint (14 providers)
  - File: `apps/web-platform/supabase/migrations/<next>_expand_provider_check.sql`
  - DROP existing CHECK, ADD new CHECK with all 14 provider values
- [ ] 1.2 Update `ApiKey` interface in `apps/web-platform/lib/types.ts`
  - Expand `provider` union type to include all 14 providers
  - Add missing `key_version: number` field
- [ ] 1.3 Create provider config constant
  - File: `apps/web-platform/server/providers.ts` (new)
  - Export `PROVIDER_CONFIG` with envVar, category, label per provider
  - Export `Provider` type derived from config keys
  - Bedrock/Vertex included in type but excluded from Connected Services UI and validation
- [ ] 1.4 Create token validation module
  - File: `apps/web-platform/server/token-validators.ts` (new)
  - Export `validateToken(provider, token): Promise<boolean>`
  - 5-second timeout on all validation requests
- [ ] 1.5 Implement validators for each provider (11 new + move existing Anthropic)
  - [ ] 1.5.1 Move `validateAnthropicKey` from `byok.ts` (check imports first, re-export only if needed)
  - [ ] 1.5.2 Cloudflare: `GET /client/v4/user/tokens/verify`
  - [ ] 1.5.3 Stripe: `GET /v1/balance`
  - [ ] 1.5.4 Plausible: `GET /api/v1/stats/realtime/visitors`
  - [ ] 1.5.5 Hetzner: `GET /v1/servers`
  - [ ] 1.5.6 GitHub: `GET /user`
  - [ ] 1.5.7 Doppler: `GET /v3/me`
  - [ ] 1.5.8 Resend: `GET /api-keys`
  - [ ] 1.5.9 X/Twitter: `GET /2/users/me`
  - [ ] 1.5.10 LinkedIn: `GET /v2/userinfo`
  - [ ] 1.5.11 Bluesky: `GET describeServer` (avoid `createSession` side effect)
  - [ ] 1.5.12 Buttondown: `GET /v1/emails`
- [ ] 1.6 Write unit tests for validators (mock HTTP responses)
  - File: `apps/web-platform/__tests__/token-validators.test.ts`
- [ ] 1.7 Create CRUD API route (single file, all methods)
  - File: `apps/web-platform/app/api/services/route.ts` (GET, POST, DELETE)
  - POST: CSRF + auth + rate limit + validate + encrypt + upsert (include `validated_at`)
  - GET: auth + query (never select encrypted fields) + merge with PROVIDER_CONFIG
  - DELETE: CSRF + auth + delete by (user_id, provider)
- [ ] 1.8 Add error sanitizer entries for token-related errors
  - File: `apps/web-platform/server/error-sanitizer.ts`
- [ ] 1.9 Verify CSRF coverage test catches new route
  - Run `csrf-coverage.test.ts` — should auto-detect new POST/DELETE handlers

## Phase 2: Agent Env Expansion

- [ ] 2.1 Update `buildAgentEnv()` signature to accept service tokens
  - File: `apps/web-platform/server/agent-env.ts`
  - Add optional `serviceTokens?: Record<string, string>` parameter
  - Spread service tokens into env object
- [ ] 2.2 Add `getUserServiceTokens(userId)` function
  - File: `apps/web-platform/server/agent-runner.ts`
  - Use `createServiceClient()` (not session client — agent-runner has no user cookies)
  - Fetch all valid non-LLM tokens in single query
  - Decrypt synchronously in a loop (`decryptKey` is sync Node crypto — no `Promise.all`)
  - Map providers to env var names via `PROVIDER_CONFIG`
- [ ] 2.3 Wire service tokens into agent session start flow
  - Call `getUserServiceTokens(userId)` alongside `getUserApiKey(userId)`
  - Pass both to `buildAgentEnv(apiKey, serviceTokens)`
- [ ] 2.4 Write integration test for encrypt → store → fetch → decrypt → inject cycle

## Phase 3: Connected Services UI

- [ ] 3.0 **UX prerequisite:** Create wireframes/design before implementing (per AGENTS.md workflow gate)
- [ ] 3.1 Create server component page
  - File: `apps/web-platform/app/(dashboard)/dashboard/settings/services/page.tsx`
  - Fetch connected services from Supabase, merge with `PROVIDER_CONFIG`
- [ ] 3.2 Create `ConnectedServicesContent` client component
  - File: `apps/web-platform/components/settings/connected-services-content.tsx`
  - Group providers by category (LLM, Infrastructure, Social)
  - Exclude bedrock/vertex from display
  - Provider cards with Connect/Rotate/Remove actions
  - Token input form (modal or inline)
- [ ] 3.3 Add "Connected Services" to dashboard sidebar navigation
  - File: `apps/web-platform/app/(dashboard)/layout.tsx`
  - Add entry to `NAV_ITEMS` array
- [ ] 3.4 Add link from existing settings page to Connected Services
  - File: `apps/web-platform/components/settings/settings-content.tsx`

## Security Audit (runs during each phase, not a separate phase)

- [ ] Audit all log paths for token leakage (grep `console.log`, `console.error`, `logger.*`)
- [ ] Verify RLS policies cover new provider rows
- [ ] Run security-sentinel agent on changed files
- [ ] Legal document updates before shipping (T&C 4.2, Privacy Policy 4.7, DPD 2.3(h))
