---
feature: operator-cc-oauth
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-feat-operator-cc-oauth-credential-plan.md
closes: 4825
status: blocked-on-deepen-plan  # P0 design fork (direct-API consumers) must resolve first
---

# Tasks: Operator CC OAuth Credential

> ⚠️ **Resolve Open Design Question P0 (direct-API consumers cannot use an OAuth token) in deepen-plan BEFORE starting Phase 1.** It may reopen the credential_type-vs-provider decision.

## Phase 0 — Deepen-plan (blocking)
- [ ] 0.1 Resolve P0: force-all-through-SDK vs. api_key fallback vs. reject+degrade for `domain-router.ts:127` + `agent-on-spawn-requested.ts:453`.
- [ ] 0.2 Resolve P1: token validation probe shape (route through lease/`buildAgentEnv`, never direct `process.env`).
- [ ] 0.3 Precedent-diff for the predicate-locked write + `: never` rails (deepen-plan Phase 4.4).

## Phase 1 — Schema
- [ ] 1.1 `096_api_keys_credential_type.sql` + `.down.sql` (mirror `014`; default `api_key`).

## Phase 2 — Lease chokepoint (load-bearing)
- [ ] 2.1 Select `credential_type` in `fetchAndDecryptIntoSlot` (`byok-lease.ts:294`).
- [ ] 2.2 `getApiKey()` → atomic `{ value, type }` (`:263-284`).
- [ ] 2.3 Date gate (`CC_OAUTH_EFFECTIVE_DATE`, exported) — throw `OauthNotYetPermittedError` for oauth before 2026-06-15.
- [ ] 2.4 Owner-only routing — throw `OauthDelegationForbiddenError` if delegated / owner≠workspaceContextUser.
- [ ] 2.5 `subscription_limit` cause in `mapByokLeaseCauseToErrorCode` (keep `: never`).

## Phase 3 — Env injection (single site)
- [ ] 3.1 `buildAgentEnv(credential:{value,type})` mutually-exclusive auth branch.
- [ ] 3.2 Keep `AGENT_ENV_OVERRIDES` (telemetry-off) outside the branch.
- [ ] 3.3 Thread single `credential` object through `buildAgentQueryOptions` args (`:62`,`:136`).

## Phase 4 — Write path + operator gate
- [ ] 4.1 `app/api/keys/route.ts` accept `credential_type`; 403 oauth unless operator/internal.

## Phase 5 — Error mapping + observability
- [ ] 5.1 Thread `subscription_limit` to WS + `ws-client.ts` + existing non-retryable UI branch.
- [ ] 5.2 Sentry mirror (reportSilentFallback / mirrorWithDebounce `cc-oauth:subscription_limit`).

## Phase 6 — UI toggle + kill-switch
- [ ] 6.1 `key-rotation-form.tsx` credential-type toggle (operator-gated visibility).
- [ ] 6.2 `CC_OAUTH_ENABLED` env kill-switch checked with the date gate.

## Phase 7 — Tests
- [ ] 7.1 agent-env property test (exactly-one auth var + telemetry overrides both branches).
- [ ] 7.2 lease date-gate + owner-routing throw tests.
- [ ] 7.3 `/api/keys` oauth-gate 403 test (route-level).
- [ ] 7.4 migration up/down (DEV).
