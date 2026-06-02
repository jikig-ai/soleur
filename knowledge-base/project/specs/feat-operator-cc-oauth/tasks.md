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
- [ ] 1.1 `096_anthropic_oauth_provider.sql`: expand `api_keys` provider CHECK to add `'anthropic_oauth'` (mirror `014_expand_provider_check.sql`). No new column.
- [ ] 1.2 `.down.sql`: delete/guard any surviving `anthropic_oauth` rows, THEN restore the prior CHECK list.
- [ ] 1.3 Predicate-locked `SECURITY DEFINER` RPC for the oauth write (mirror `033`, `search_path = public, pg_temp`, REVOKE authenticated/anon + GRANT service_role, operator-identity predicate baked in).

## Phase 2 — Lease: two accessors + structural boundary
- [ ] 2.1 `getRestApiKey()` → queries ONLY `provider='anthropic'` (raw-REST cannot read oauth by construction).
- [ ] 2.2 `getAgentCredential()` → prefer `provider='anthropic_oauth'`, fall back to `'anthropic'`; returns `{ value, scheme }`.
- [ ] 2.3 Gates fire ONLY on the oauth read: date (`CC_OAUTH_EFFECTIVE_DATE`), owner (`delegationId==null && keyOwnerUserId===workspaceContextUserId`), kill-switch (`CC_OAUTH_ENABLED`). Owner guard MUST run on the `anthropic_oauth` query path.
- [ ] 2.4 `subscription_limit` cause in `mapByokLeaseCauseToErrorCode` (keep `: never`).
- [ ] 2.5 Cross-consumer sweep (`hr-type-widening-cross-consumer-grep`): grep all `getApiKey()` sites; route raw-REST callers to `getRestApiKey()`.

## Phase 3 — Env injection (single site)
- [ ] 3.1 `buildAgentEnv(credential:{value,scheme})` mutually-exclusive auth branch (exactly one of `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`).
- [ ] 3.2 Keep `AGENT_ENV_OVERRIDES` (telemetry-off) outside the branch; assert the service-token loop (`:54+`) cannot clobber them.
- [ ] 3.3 Thread the single `credential` object through `buildAgentQueryOptions` args (`:62`,`:136`).

## Phase 4 — Raw-REST call sites + write gate
- [ ] 4.1 `domain-router.ts` classify + `agent-on-spawn-requested.ts:452` → `getRestApiKey()` (provider='anthropic').
- [ ] 4.2 `app/api/keys/route.ts`: accept oauth credential; 403 unless operator/internal (server-side); route oauth write through the Phase-1.3 RPC.

## Phase 5 — Error mapping + observability
- [ ] 5.1 Thread `subscription_limit` to WS + `ws-client.ts` + existing non-retryable UI branch.
- [ ] 5.2 Sentry mirror (reportSilentFallback / mirrorWithDebounce `cc-oauth:subscription_limit`).

## Phase 6 — UI toggle + kill-switch
- [ ] 6.1 `key-rotation-form.tsx` credential-type toggle (operator-gated visibility) → writes the `anthropic_oauth` row.
- [ ] 6.2 `CC_OAUTH_ENABLED` env kill-switch checked with the date gate.

## Phase 7 — Tests
- [ ] 7.1 agent-env property test: exactly-one auth var + telemetry overrides on both schemes (non-clobberable).
- [ ] 7.2 lease: date-gate + owner-routing throw on the oauth read; `getRestApiKey()` never returns oauth.
- [ ] 7.3 `grep -L` test: no module outside `agent-env.ts` references `CLAUDE_CODE_OAUTH_TOKEN`.
- [ ] 7.4 `/api/keys` oauth-write 403 for non-operator (route-level).
- [ ] 7.5 migration 096 up/down (DEV); down guards surviving oauth rows.

## Phase 0 (post-merge / advisory)
- [ ] ADR via `/soleur:architecture create` — "BYOK credential-selection by consumer class + structural REST/SDK boundary".
