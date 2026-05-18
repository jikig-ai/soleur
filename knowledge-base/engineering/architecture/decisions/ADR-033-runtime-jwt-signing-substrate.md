---
adr: ADR-033
title: Runtime JWT signing substrate
status: Accepted
date: 2026-05-18
decision: Option C — Custom Access Token Hook
---

# ADR-033: Runtime JWT signing substrate

## Context

PR-B (#3244, #3395) shipped tenant-isolated Supabase access by minting per-founder JWTs on the Node side using a project-wide HS256 secret (`SUPABASE_JWT_SECRET`) read from Doppler and signed via `createHmac`. PostgREST verifies each minted JWT against the same shared secret. The substrate works but carries two well-known costs: (1) Soleur's process holds the signing key in env memory + Doppler, so a Sentry config dump, env-block leak, or compromised Doppler service token can mint arbitrary tenant JWTs; (2) the operator runbook for new Supabase projects requires a manual dashboard-paste step to seed the secret.

Supabase rolled out asymmetric JWT Signing Keys (ES256/RS256 managed by Supabase; private key never leaves the project) on 2025-10-01 as the default for new projects, with an opt-in for existing projects. Supabase has signaled HS256 verifier deprecation for 2026 (exact cutoff unannounced). Issue #3363 frames the substrate swap as the natural next hardening step after the PR-B/C/D/E continuation chain. Brand-survival threshold is **single-user incident** — a regression on this path locks every founder out of their own runtime data until rollback.

Four substrate paths have been evaluated; the decision between Option C and Option D is left to the operator before `/work` begins.

## Considered Options

- **Option A — `sb_secret_*` + `secret_jwt_template`.** Use Supabase's new opaque secret keys with a Kong-routing claim template. Pros: zero Node-side signing key. Cons: `secret_jwt_template` pins a STATIC template (e.g. `{"role":"service_role"}`); it does NOT support per-call claim injection — `sub`, `jti`, custom `aud` cannot be parameterized at request time. Kills Option A as a drop-in for per-founder runtime JWTs. **Rejected.**

- **Option B — `auth.admin.generateLink` + `auth.admin.verifyOtp` with a `runtime_jwt_binding` side table.** Mint sessions via Supabase Auth admin API (returning an asymmetrically-signed JWT) and bind our precheck-issued `jti` to Supabase's session `jti` in a side table; `is_jti_denied` consults the binding table. Pros: removes Node-side signing key; uses Supabase's asymmetric substrate. Cons: adds a per-mint INSERT to the hot path; couples deny-list semantics to a side table; schema-evolution coupling between `denied_jti`, `runtime_jwt_binding`, and `precheck_jwt_mint`. **Workable but superseded by Option C.**

- **Option C — Custom Access Token Hook (recommended path A).** Migration 047 adds a `public.runtime_jwt_mint_hook(event jsonb) → jsonb` SECURITY DEFINER function registered as Supabase Auth's Custom Access Token Hook. The hook gates on `event.authentication_method = 'otp'`, calls `precheck_jwt_mint` from inside the auth-issuance transaction, and injects the precheck-issued `jti`, `exp`, `iat`, and `aud='soleur-runtime'` directly into the JWT claims. Migration 048 recreates `precheck_jwt_mint` with custom ERRCODE `45001` for its rate-limit raise (to disambiguate from migration 037's WORM-trigger `P0001`). Node side: `auth.admin.generateLink` + `auth.admin.verifyOtp` exchange a hashed token for the asymmetrically-signed JWT; no signing material in process memory.

  Pros:
  - Soleur holds no signing material; `process.env.SUPABASE_JWT_SECRET` and `createHmac` removed from `lib/supabase/tenant.ts`.
  - One DB write per mint (precheck row only — unchanged from PR-B); no binding table.
  - `denied_jti` revocation continues to work against the JWT's own `jti` claim — no indirection.
  - Aligns with Supabase's own programming model for custom claims.
  - Removes the dashboard-paste step from new-project provisioning.

  Cons:
  - Hook fires on EVERY auth flow in the project; the `authentication_method='otp'` gate must be load-bearing correct.
  - Cold-start latency grows from ~1ms HS256 to ~200-500ms (generateLink + verifyOtp); PR-B's ALS lazy-fetch absorbs the hit on first tenant query per session only.
  - One new external dependency on Supabase Auth admin API (same SLA class as the existing `precheck_jwt_mint` RPC dependency).
  - Requires `Enable JWT Signing Keys` (Dashboard click — no API surface as of 2026-05-18).
  - 16-suite tenant-isolation re-run gated by `TENANT_INTEGRATION_TEST=1`.

- **Option D — Keep HS256, rotate quarterly via Doppler (recommended path B).** Retain the current substrate. Add a quarterly rotation runbook (or, if feasible, a dynamic-rotation tool) that generates a fresh `SUPABASE_JWT_SECRET`, writes it to Doppler, restarts Node, and updates the Supabase project's JWT secret. To rotate non-destructively, Soleur would verify against both old and new secrets app-side during a rotation window — effectively reimplementing kid-based key rotation in HS256 form.

  Pros:
  - Minimal code change; no migrations 047/048; no Dashboard clicks for JWT Signing Keys.
  - No GoTrue rate-limit dependency for runtime mints.
  - No 16-suite integration re-run.
  - Preserves a single signing substrate end-to-end; tenant-isolation contract unchanged.
  - Engineering cost concentrated in operational tooling, not in the security-critical hot path.

  Cons:
  - Soleur continues to hold the signing key in process memory + Doppler — the core leak surface this refactor was framed against remains.
  - Supabase HS256 rotation is destructive: one secret per project, rotating it invalidates every active session.
  - Non-destructive rotation requires dual-secret app-side verification (essentially reimplementing the kid-based rotation Supabase's asymmetric model provides natively).
  - Supabase has signaled HS256 verifier deprecation for 2026; choosing D today locks in a forced migration later (with less headroom than now).
  - The remaining leak surface (`SUPABASE_SERVICE_ROLE_KEY`) is unchanged either way — Option D does not improve it; Option C does not worsen it.

  Verdict on D: marginal-security-win-vs-engineering-cost trade-off. Recommended UNLESS the operator can ship Doppler dynamic-rotation tooling generically AND accept dual-secret app-side verification during rotation windows. If those two engineering investments are out of scope this quarter, Option C is the better one-shot bet.

## Decision

**Option C — Custom Access Token Hook.**

Selected by operator on 2026-05-18 after 5-agent plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) returned no BLOCK and consolidated cuts were applied. Option D (HS256 + quarterly rotation) was evaluated seriously as a deferral alternative and rejected: the rotation-tooling-plus-dual-secret-verification engineering burden is a known anti-pattern (rarely actually built), and Supabase's signaled HS256 deprecation makes D forward-looking debt rather than a stable resting point.

The decision overrides the recommendation to park-with-artifact-commit. Operator accepted single-user-incident blast radius in exchange for substrate consolidation onto Supabase-managed asymmetric keys before HS256 deprecation forces it.

## Consequences

### If Option C is selected

**Positive:**
- `SUPABASE_JWT_SECRET` removed from Doppler dev + prd; `createHmac` removed from `tenant.ts`. Soleur's blast radius narrows.
- New-project provisioning runbook drops the dashboard-paste step.
- Substrate moves to Supabase's default asymmetric posture; future auth-vendor swaps simpler.
- ADR-033 + migrations 047/048 + tests document the contract; the `authentication_method='otp'` gate is API-readable and grep-able.

**Negative:**
- Cold-start latency +200-500ms on first tenant query per session.
- Hook fires on every project-wide auth event; pass-through gate must remain correct as Supabase evolves `authentication_method` values.
- Mgmt API hook registration is a new operator step (gated `[ack-needed]`).
- `auth.sessions` row growth bounded by Supabase's session sweeper (default 7d refresh-token TTL).

**Neutral:**
- `precheck_jwt_mint` retains its rate-limit + jti role; signature shape unchanged (only ERRCODE shifts via migration 048).
- `denied_jti` revocation unchanged.
- `SUPABASE_SERVICE_ROLE_KEY` exposure unchanged.

### If Option D is selected

**Positive:**
- No migrations, no Dashboard clicks, no 16-suite re-run, no GoTrue rate-limit dependency for the hot path.
- Latency unchanged (~1ms HS256 sign).
- Tenant-isolation contract unchanged from PR-B.
- Rollback path simpler (no Supabase Mgmt API state to revert).

**Negative:**
- Soleur continues to hold signing material; the leak class this refactor was framed against remains.
- Quarterly rotation runbook must be authored AND exercised; dual-secret verification path must be implemented if non-destructive rotation is required.
- Supabase HS256 deprecation (signaled for 2026) will force a future migration with less headroom than the current window.
- ADR-033 itself becomes a forward-looking debt anchor — the substrate swap is deferred, not retired.

**Neutral:**
- `SUPABASE_SERVICE_ROLE_KEY` exposure unchanged.
- `precheck_jwt_mint` + `denied_jti` paths unchanged.
- New-project provisioning runbook unchanged.

## References

- Plan: `knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md`
- Umbrella issue: [#3244](https://github.com/jikigai/soleur/issues/3244)
- PR-B (HS256 substrate landed): [#3395](https://github.com/jikigai/soleur/pull/3395)
- Issue this ADR resolves: [#3363](https://github.com/jikigai/soleur/issues/3363)
- Supabase JWT Signing Keys: <https://supabase.com/docs/guides/auth/signing-keys>
- Supabase Custom Access Token Hook: <https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook>
- Supabase rotation guide (multi-verifier coexistence): <https://supabase.com/docs/guides/troubleshooting/rotating-anon-service-and-jwt-secrets-1Jq6yd>
- Sibling ADRs: ADR-004 (BYOK encryption), ADR-023 (Supabase env isolation)
