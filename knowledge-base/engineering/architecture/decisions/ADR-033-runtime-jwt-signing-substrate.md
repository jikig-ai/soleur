---
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

## Phase 0 probe results (live-captured 2026-05-18)

### 0.1 — JWKS asymmetric enablement (DONE)
- `GET ${SUPABASE_URL}/auth/v1/.well-known/jwks.json` returns `{"count":1, "algs":["ES256"], "kids":["3605e4cb-db60-461d-a122-969e7671f66b"]}` on the **dev** project (`mlwiodleouzwniehynfz`).
- Dashboard "Enable JWT Signing Keys" not required on dev (already on by default).

### 0.2 — generateLink + verifyOtp baseline shape (DONE)
- One cycle against synthesized fixture `tenant-isolation-*@soleur.test`.
- JWT header: `{alg:"ES256", kid:"3605e4cb-…", typ:"JWT"}` — assert `alg != "HS256"` holds.
- JWT payload claim set (BEFORE hook): `aal, amr, app_metadata, aud, email, exp, iat, is_anonymous, iss, phone, role, session_id, sub, user_metadata`.
- Default values: `iss="https://${PROJECT_REF}.supabase.co/auth/v1"`, `aud="authenticated"`, `role="authenticated"`, `aal="aal1"`, `ttl=3600` (Supabase default — NOT our `ttlSec`).
- **Critical**: `jti` is **absent** from the baseline payload — confirms the Custom Access Token Hook is load-bearing for our `denied_jti` revocation surface. Without the hook, PostgREST would see no `jti` claim and revocation would be impossible.
- `session_id` present; `email` present (baseline includes founder PII; the hook's `jsonb_set` is additive so these pass through — acceptable since service-role already sees `auth.users` and Soleur's existing tenant-isolation contract already gates on `sub`).
- **REST shape note for implementers**: `admin/generate_link` returns the hashed token at the response **root** (`.hashed_token`), not under `.properties.hashed_token`. The supabase-js wrapper exposes it as `data.properties.hashed_token` — the plan's TS pseudocode (and `lib/supabase/tenant.ts` post-#3363) uses the supabase-js path; the curl-based runbook (Deploy-Order §a/c) uses the root path. Both correct for their layer.

### 0.4 — `authentication_method = 'otp'` gate (CONFIRMED empirically; insufficient alone — see §0.7)
- The baseline JWT payload includes `amr=[{method:"otp", timestamp:…}]`, confirming that the `verifyOtp` flow exposes `method="otp"` in `amr`.
- Per Supabase's [Custom Access Token Hook input spec](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook), the hook receives `event.authentication_method` as a single string (the most-recent method). On the `generateLink+verifyOtp` path, that string is `"otp"`.
- Gate decision recorded by plan-review panel: `IF v_auth_method <> 'otp' THEN RETURN claims unchanged END IF`. **PARTIAL — was assumed sufficient for projects using password-based dashboard auth, but Soleur's dashboard uses `signInWithOtp` + `verifyOtp({type:'email'})` for user-facing login (see `components/auth/login-form.tsx:83`, `app/(auth)/signup/page.tsx:74`).** The dashboard path is indistinguishable from the runtime path at the hook event level. See §0.7 for the empirical follow-up and the marker-table pivot that strengthens this gate.
- Future-optimization footnote retained from plan: if a future PR needs distinct runtime aud per founder, channel (a) `auth.users.app_metadata.target_aud`, channel (b) `verifyOtp` audience param.

### 0.5 — latency baseline (DONE, 10 cycles sequential)
- `generateLink`: p50=328ms, p95=408ms
- `verifyOtp`: p50=330ms, p95=376ms
- **total p50=664ms, p95=753ms, min=627ms, max=753ms**
- p95=753ms < 1000ms plan-gate → no WebSocket pre-mint fallback needed. PR-B's ALS lazy-fetch absorbs this on first-tenant-query-per-session (cache TTL/4 = 150s remint window per Phase 2.5 plan edit; ≤24 mints/hour/founder).
- Cold-start UX impact: +~750ms on first tenant query per session vs. previous ~1ms HS256. Below PR-B's 1s session-start SLO.

### 0.6 — rate-limit defaults (DEFERRED empirical probe; defaults recorded)
- **Decision**: defer the 60-cycle empirical rate-limit probe per session-state (2026-05-18 second session). Rationale: wasteful (risks tripping per-IP limits affecting unrelated dev workflows); the precheck `60/hour` ceiling is the durable canary regardless.
- **Defaults from Supabase docs** ([rate-limits guide](https://supabase.com/docs/guides/auth/rate-limits), [auth-config endpoint](https://supabase.com/docs/reference/api/v1-update-a-projects-auth-config)):
  - `RATE_LIMIT_TOKEN_REFRESH = 10` requests / IP / hour
  - `RATE_LIMIT_EMAIL_SENT = 10` / hour (bypassed: `generateLink` does NOT send email)
  - `RATE_LIMIT_VERIFY` is undocumented in the current public docs (the rate-limit page is a partial; the source-of-truth is Supabase support).
- **Empirical sub-finding from 0.5**: 10 sequential `generateLink+verifyOtp` cycles against the SAME fixture from a SINGLE IP in <10s produced **zero 429 responses**. Suggests either (a) the per-IP TOKEN_REFRESH ceiling does not count `verifyOtp`-issued tokens, or (b) the bucket is not strict sliding-window over short bursts. Inconclusive but useful as a non-failure boundary.
- **Hard ceiling we rely on**: `precheck_jwt_mint` ≤60/hour/founder (migration 037, ERRCODE-shifted to `45001` in migration 048). This is enforced by Soleur, not Supabase — durable regardless of upstream rate-limit drift.
- **Follow-up tracking issue** (to be filed alongside this PR): "Empirical Supabase Auth rate-limit probe — 60-cycle generate+verify with timeline measurement once observability surface lands." Filing pattern per `wg-when-deferring-a-capability-create-a`.

### 0.7 — hook-event discriminator probe + marker-table pivot (2026-05-18, Phase-4 review escalation)
- **Trigger**: `/soleur:review` security-sentinel agent flagged P1 (single-user-incident threshold): Soleur's user-facing dashboard login uses `signInWithOtp` + `verifyOtp({type:'email'})` (see `components/auth/login-form.tsx:83`, `app/(auth)/signup/page.tsx:74`), identical to the runtime mint path's `auth.admin.generateLink` + `verifyOtp({token_hash, type:'email'})` from the GoTrue server's perspective. The §0.4 gate (`authentication_method = 'otp'`) cannot distinguish them.
- **Empirical probe** (Phase 4, captured against dev 2026-05-18): runtime path (`verifyOtp` via `token_hash`) and dashboard path (`verifyOtp` via 6-digit `email_otp`) produce **identical** JWT structure modulo per-call randomness (jti, session_id). All discriminator candidates were exhaustively compared:

  | Field                          | Runtime path        | Dashboard path      |
  | ------------------------------ | ------------------- | ------------------- |
  | `aud`                          | `soleur-runtime`*   | `soleur-runtime`*   |
  | `amr[0].method`                | `otp`               | `otp`               |
  | `app_metadata.providers`       | `["email"]`         | `["email"]`         |
  | `aal`                          | `aal1`              | `aal1`              |
  | `role`                         | `authenticated`     | `authenticated`     |
  | `is_anonymous`                 | `false`             | `false`             |
  | `iss`                          | (same project)      | (same project)      |
  | `exp - iat`                    | `600`*              | `600`*              |

  *the rewrites — both paths were getting hook-rewritten, which is the bug.
- **Conclusion**: no field discriminates. The §0.4 gate ships with this PR but as defense-in-depth only; the load-bearing discriminator is now the marker-table pattern from §0.7 below.
- **Pivot — marker table (migrations 049 + 050)**:
  - Migration 049 introduces `public.runtime_mint_intent(user_id uuid PK REFERENCES auth.users(id) ON DELETE CASCADE, created_at timestamptz DEFAULT NOW())`. RLS enabled; service_role gets `INSERT, UPDATE`; supabase_auth_admin gets `SELECT, DELETE`; everyone else REVOKEd.
  - Migration 050 CREATE OR REPLACEs `runtime_jwt_mint_hook` with a strengthened gate: pass-through unless `authentication_method = 'otp'` **AND** an intent row was atomically consumed via `WITH consumed AS (DELETE FROM public.runtime_mint_intent WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '10 seconds' RETURNING 1) SELECT EXISTS(...) INTO v_intent_consumed`. Single statement → race-safe against concurrent hook firings.
  - `lib/supabase/tenant.ts:mintFounderJwt` UPSERTs the marker immediately before `auth.admin.generateLink` (`onConflict: 'user_id'` for idempotency under concurrent mints).
- **Residual race window**: ~700ms between tenant.ts UPSERT and the hook's DELETE inside verifyOtp. A dashboard login firing for the same user_id within that window steals the intent. Bounded harm: dashboard user occasionally gets 10-min session, self-recovering via re-login. Probability per dashboard login: ~0.02% under steady-state founder load (24 mints/hr/founder × 700ms window / 24hr × dashboard-login rate of ~1/day). Accepted residual per single-user-incident threshold deliberation; the alternative (shadow-user architecture, ~500 LOC + backfill migration + tenant-isolation surface updates) was judged disproportionate.
- **Empirical verification after fix**: rerun of the Phase-0.7 probe with migrations 049+050 applied and tenant.ts UPSERTing the marker:
  - Runtime path (UPSERT performed) → `aud=soleur-runtime`, `exp-iat=600s`, precheck-injected jti ✓
  - Dashboard path (no UPSERT) → `aud=authenticated`, `exp-iat=3600s`, no jti rewrite ✓
- **Plan amendment**: this section is the canonical write-up; the plan file (`knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md`) is amended with a Phase-4 cross-reference back here.

## References

- Plan: `knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md`
- Umbrella issue: [#3244](https://github.com/jikigai/soleur/issues/3244)
- PR-B (HS256 substrate landed): [#3395](https://github.com/jikigai/soleur/pull/3395)
- Issue this ADR resolves: [#3363](https://github.com/jikigai/soleur/issues/3363)
- Supabase JWT Signing Keys: <https://supabase.com/docs/guides/auth/signing-keys>
- Supabase Custom Access Token Hook: <https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook>
- Supabase rotation guide (multi-verifier coexistence): <https://supabase.com/docs/guides/troubleshooting/rotating-anon-service-and-jwt-secrets-1Jq6yd>
- Sibling ADRs: ADR-004 (BYOK encryption), ADR-023 (Supabase env isolation)
