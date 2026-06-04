---
feature: operator-cc-oauth
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-feat-operator-cc-oauth-credential-plan.md
closes: 4825
status: ready-for-work  # P0 fork resolved by deepen-plan triad (two-row consumer-class model)
---

# Tasks: Operator CC OAuth Credential

> **Model (resolved):** TWO rows by provider — `anthropic` (api_key, raw-REST consumers) + `anthropic_oauth` (oauth, Agent-SDK path). NO `credential_type` column. Selection by consumer class; the REST/SDK boundary is structural (different rows). See plan § Deepen-Plan Resolution.

## Phase 1 — Schema (migration 096)
- [x] 1.1 `096_anthropic_oauth_provider.sql`: expand `api_keys` provider CHECK to add `'anthropic_oauth'` (mirror `014_expand_provider_check.sql`). No new column.
- [x] 1.2 `.down.sql`: delete/guard any surviving `anthropic_oauth` rows, THEN restore the prior CHECK list.
- [x] 1.3 Predicate-locked `SECURITY DEFINER` RPC for the oauth write (mirror `033`, `search_path = public, pg_temp`, REVOKE authenticated/anon + GRANT service_role; provider `'anthropic_oauth'` hardcoded + service_role-only grant; operator-identity at the route via `ADMIN_USER_IDS`).

## Phase 2 — Lease: two accessors + structural boundary
- [x] 2.1 `getRestApiKey()` → queries ONLY `provider='anthropic'` (raw-REST cannot read oauth by construction).
- [x] 2.2 `getAgentCredential()` → prefer `provider='anthropic_oauth'`, fall back to `'anthropic'`; returns `{ value, scheme }`.
- [x] 2.3 Gates fire ONLY on the oauth read: date (`CC_OAUTH_EFFECTIVE_DATE`), owner (`delegationId==null && keyOwnerUserId===workspaceContextUserId`), kill-switch (`CC_OAUTH_ENABLED`). Owner guard runs on the `anthropic_oauth` query path.
- [x] 2.4 `subscription_limit` cause in `mapByokLeaseCauseToErrorCode` (kept `: never`).
- [x] 2.5 Cross-consumer sweep: 2 raw-REST sites (`agent-on-spawn-requested.ts:452`, `agent-runner.ts:2540` routeMessage/domain-router) → `getRestApiKey()`; 2 Agent-SDK sites (`agent-runner.ts:925`, `cc-dispatcher.ts:937`) → `getAgentCredential()`.

## Phase 3 — Env injection (single site)
- [x] 3.1 `buildAgentEnv(credential:{value,scheme})` mutually-exclusive auth branch (exactly one of `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`; auth var set LAST + non-selected deleted).
- [x] 3.2 Kept `AGENT_ENV_OVERRIDES` (telemetry-off) outside the branch; service-token loop cannot clobber them (asserted in property test).
- [x] 3.3 Threaded the single `credential` object through `buildAgentQueryOptions` args (`AgentQueryOptionsArgs.credential`, `buildAgentEnv` call).

## Phase 4 — Raw-REST call sites + write gate
- [x] 4.1 `agent-on-spawn-requested.ts:452` + `agent-runner.ts:2540` (routeMessage → classify → domain-router `x-api-key`) → `getRestApiKey()` (provider='anthropic').
- [x] 4.2 `app/api/keys/route.ts`: accept `credential_type`; 403 unless operator (`ADMIN_USER_IDS`) AND kill-switch on; oauth write through `store_oauth_credential` RPC.

## Phase 5 — Error mapping + observability
- [x] 5.1 Threaded `subscription_limit` to `WSErrorCode` + zod enum + WS send (`resolveSessionErrorCode`) + `ws-client.ts` non-retryable branch (distinct from `key_invalid`).
- [x] 5.2 Sentry: gate-throws reach Sentry via the runner catch `else { captureException }` (AC3/AC4 fail-loud). `subscription_limit` producer + debounced mirror land together on first real hit per plan (deferred-with-rationale; type/render/capture path pre-wired).

## Phase 6 — UI toggle + kill-switch
- [x] 6.1 `key-rotation-form.tsx` credential-type toggle (operator-gated visibility via `canUseOauthCredential` from `settings/page.tsx`) → POSTs `credential_type:'oauth_token'`.
- [x] 6.2 `CC_OAUTH_ENABLED` env kill-switch checked with the date gate (lease) + route gate + UI gate; documented in `.env.example`.

## Phase 7 — Tests
- [x] 7.1 agent-env property test: exactly-one auth var + telemetry overrides on both schemes (non-clobberable). `test/agent-env-credential-type.test.ts`
- [x] 7.2 lease: date-gate + owner-routing throw on the oauth read; `getRestApiKey()` never returns oauth. `test/byok-lease-credential-type.test.ts`
- [x] 7.3 `grep -L` test: no module outside `agent-env.ts` references `CLAUDE_CODE_OAUTH_TOKEN`. `test/oauth-token-injection-site.test.ts`
- [x] 7.4 `/api/keys` oauth-write 403 for non-operator (route-level). `test/api-keys-oauth-gate.test.ts`
- [x] 7.5 migration 096 up/down validated against the LIVE dev schema via a transactional dry-run (BEGIN→up→assert→down→assert→ROLLBACK, drift-free): up adds `anthropic_oauth` to the real `api_keys_provider_check`; `store_oauth_credential` created SECURITY DEFINER with authenticated/anon EXECUTE denied + service_role granted; down restores the CHECK + drops the fn. Real apply runs via the automated deploy pipeline on merge (`run-migrations.sh`; the unmerged-apply gate funnels there — applying unmerged to dev would create #4241-class drift).

## Phase 0 (advisory)
- [x] ADR-048 — "Operator CC OAuth credential — selection by consumer class + structural REST/SDK boundary" (absorbed inline at review time per the review sharp-edge for already-shipping-architecture ADRs).
