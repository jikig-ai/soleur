---
date: 2026-05-18
feature: feat-one-shot-issue-3363-jwt-asymmetric-keys
issue: "#3363"
type: refactor
classification: security-hardening
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: "#3244 (umbrella issue, OPEN), #3395 (PR-B merged), #3854 (PR-C merged), #3883 (PR-D merged), #3922 (PR-E merged)"
related_issues: "#3370 (default-privileges audit, open)"
related_adrs: "ADR-023 (Supabase env isolation), ADR-004 (BYOK encryption), ADR-007 (Doppler)"
deepened: 2026-05-18
---

# Refactor — Runtime JWT minting substrate: HS256 secret → Supabase asymmetric signing

> One-shot pipeline plan derived directly from issue **#3363**. No prior brainstorm document exists for this issue; the issue body itself enumerates two candidate paths (Option A: `sb_secret_*` + `secret_jwt_template`, Option B: `auth.admin.generateLink` + `verifyOtp`). The original plan resolved Option B with a `runtime_jwt_binding` side table. **Deepen-pass discovered a third, cleaner path: Custom Access Token Hook** (see Enhancement Summary § C). The plan now adopts Option C; Options A and B are retained as alternatives in ADR-033.

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** Overview, Research Reconciliation, Phases 0-2, Files to Edit/Create, AC, Risks, Sharp Edges
**Research surfaces consulted (live):** Supabase docs (signing-keys, rate-limits, jwts, auth-hooks/custom-access-token-hook, generateLink reference, self-hosted-auth-keys), Supabase blog (JWT Signing Keys announcement), Catjam.fi PKCE-fix article, Razikus admin-impersonation pattern, GitHub issues `supabase/auth#1357`, `supabase/auth-js#767`, `supabase#41947`, `supabase#11854` (Allow admin to generate auth user sessions), Terraform Registry (supabase_settings resource), GitHub gh CLI for verifying citations (#3244 issue, #3395 PR, #3370 issue, #3854/#3883/#3922 PRs).
**Citations live-verified:** all `#N` references resolved via `gh issue view` / `gh pr view` / `git log --grep`. #3244 confirmed as the **umbrella issue** (not a PR); PR-B merged as #3395; PR-C/D/E merged as #3854/#3883/#3922.

### Key Improvements

1. **Design pivot: Custom Access Token Hook replaces `runtime_jwt_binding`.** Supabase Auth supports a `custom_access_token_hook` Postgres function that runs synchronously during token issuance and can inject custom claims (including `jti`). This eliminates the side-table binding (Option B.1) — our precheck-issued jti goes directly into the asymmetrically-signed JWT, so `denied_jti` revocation continues to work against the JWT's own `jti` claim. **Net delta vs. original plan: −1 migration (047), −1 binding-table INSERT per mint, +1 Postgres function (hook), +1 Supabase Auth Hook config row. Simpler, fewer DB writes, no schema-evolution coupling.** This is the dominant change in this deepen pass.

2. **`verifyOtp` `type` parameter corrected.** Original plan body said `type: "magiclink"`. Razikus's working pattern and Supabase's PKCE-fix article both use `type: "email"` for the verify call (the `magiclink` literal in `generateLink` produces a `token_hash` that `verifyOtp` consumes with `type: "email"`). The `magiclink` type for `verifyOtp` is deprecated. Implementation phase 2.1 corrected.

3. **PKCE-flow concern surfaced.** `supabase.auth.admin.generateLink` returns an `action_link` whose code-parameter is missing under PKCE flow (issue supabase/auth-js#767, repo archived 2026-01-23). For our server-side flow we do NOT use the `action_link`; we use only `properties.hashed_token` → `verifyOtp(token_hash)`, so the PKCE bug does not apply. Documented in Risks.

4. **Asymmetric-signing transition timeline verified.** Supabase rolled out asymmetric ES256 / RS256 as default for new projects on 2025-10-01; existing projects opt-in via dashboard → API Keys → "Enable JWT Signing Keys". Our project's enablement status MUST be probed in Phase 0.1. If not yet enabled, the precondition is to enable it FIRST (still a runbook step; no production impact because session JWTs are verified against the JWKS endpoint and remain valid through rotation per the official rotation guidance).

5. **`sb_secret_*` opacity confirmed.** Per Supabase self-hosting docs, `sb_secret_*` keys are **opaque random keys with a checksum** (not JWTs). Kong-internal routing replaces them with pre-signed ES256 JWTs for `service_role`. They are NOT a per-call claim-template mechanism. Original plan's Research Reconciliation row was correct; this enhancement adds the citation. **`secret_jwt_template` field on these keys is a Kong-routing concept, NOT a per-call claim injection mechanism.**

6. **Rate-limit reality check.** Supabase's RATE_LIMIT_TOKEN_REFRESH default is **10 requests/IP/hour**, NOT 30/5min as the original plan asserted. RATE_LIMIT_EMAIL_SENT default is **10/hour**. `generateLink` does not send email so it bypasses EMAIL_SENT; but `verifyOtp` shares IP-rate-limit with `/auth/v1/verify` (specific number undocumented in current Supabase docs as of 2026-05; the rate-limits table is pulled from a partial doc file). **The 60/hour `precheck_jwt_mint` ceiling remains our durable canary — if mints regularly hit 24-60/hour and Supabase silently tightens the GoTrue rate-limit, we get a clear failure signal before service degrades.** Acceptance Criteria 4 strengthened to require a probe at Phase 0.4 with the EXACT count, not just "below the budget".

7. **Terraform provider reality.** The `supabase/supabase` provider exposes a single `supabase_settings` resource with a JSON `auth` field (NOT individual fields per setting); v1.9.1 (2026-05-15) is the current version. Auth config attributes supported include `site_url`, `mailer_otp_exp`, `mfa_phone_otp_length`, `sms_otp_length`. **It does NOT (as of 2026-05-18) expose `rate_limit_token_refresh` or `rate_limit_email_sent` as Terraform-managed fields.** Plan Phase 3.2 is downgraded: runbook documentation now mandatory; Terraform pinning of rate limits is deferred to a follow-up tracking issue.

8. **Custom Access Token Hook documented at full depth.** The hook receives a jsonb `{user_id, claims, authentication_method}`, returns `{claims}` with modifications. Required claims that CANNOT be removed: `iss, aud, exp, iat, sub, role, aal, session_id, email, phone, is_anonymous`. Optional claims that CAN be added: `jti, nbf, app_metadata, user_metadata, amr`. **This is exactly the surface we need — `jti` is in the optional-add list.** Hook is registered via Supabase Dashboard → Authentication → Hooks → "Custom Access Token Hook", or programmatically via Management API.

### New Considerations Discovered

- **Hook timing semantics:** The Custom Access Token Hook fires on EVERY token issuance event — `signInWithPassword`, `signInWithOtp`, `verifyOtp`, `refreshToken`, AND `admin.generateLink → verifyOtp`. This means our hook will fire even on user-driven login flows (not just our service-role minted runtime sessions). We must early-return when `authentication_method` is NOT one of the runtime mint paths (the hook gets it for free in the input). **Required edge case:** if a founder logs into the Dashboard via password, the hook MUST NOT call `precheck_jwt_mint` (would consume from the 60/hour ceiling on every Dashboard login). Hook function design must include this gate.

- **Hook failure mode:** If the hook function errors, Supabase Auth aborts token issuance with HTTP 500. This is appropriate for our use case (no jti = no revocation surface). Hook must use the `is_jti_denied` pattern: REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO supabase_auth_admin (the hook-invoker role).

- **Session row pollution.** `verifyOtp` creates a row in `auth.sessions`. At our cache TTL/4 (~150s remint), a single founder generates ~24 session rows/hour. Original plan understated this — the row creation happens in `auth.sessions`, NOT `auth.audit_log_entries` (which was the original assumption). Mitigation: in Phase 2.1, after `verifyOtp` succeeds and we have the access_token, immediately call `supabase.auth.admin.signOut({ scope: 'others' })` filtered to that session_id — OR — accept the session-row growth as bounded by Supabase's own session retention (which is paired with refresh-token TTL, default 7d). Plan adopts the **accept** strategy; row-count cap is per-founder × 24 × 24 × 7 ≈ 4032 sessions/founder/week, garbage-collected by Supabase's session sweeper. Documented in Risks.

- **Project-level enablement gate.** Asymmetric signing keys must be enabled on the Supabase project BEFORE this PR's code rolls out. If we ship the code first, `verifyOtp` returns an HS256-signed JWT and AC8 (alg != HS256) fails. Phase 0.1 includes a probe of `/auth/v1/.well-known/jwks.json` to confirm asymmetric keys are active; if not, a Phase 0.5 step is added to enable them (1-click in Dashboard, no downtime per Supabase's rotation guarantee).

- **`@supabase/supabase-js` version**: project ships `^2.49.0`. The `admin.generateLink` + `verifyOtp` admin pattern landed in v2.0+; available in our version. No SDK upgrade needed. Verified via `grep -E "@supabase/supabase-js" apps/web-platform/package.json`.

Sources:
- [JWT Signing Keys | Supabase Docs](https://supabase.com/docs/guides/auth/signing-keys)
- [Introducing JWT Signing Keys | Supabase Blog](https://supabase.com/blog/jwt-signing-keys)
- [Custom Access Token Hook | Supabase Docs](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
- [JWT Claims Reference | Supabase Docs](https://supabase.com/docs/guides/auth/jwt-fields)
- [auth-admin-generatelink | Supabase JS Reference](https://supabase.com/docs/reference/javascript/auth-admin-generatelink)
- [New API Keys and Asymmetric Authentication | Supabase Self-Hosting](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys)
- [Migrating to PKCE-compatible generateLink | catjam.fi](https://catjam.fi/articles/supabase-generatelink-fix)
- [Admin login as user | Razikus Substack](https://razikus.substack.com/p/supabase-admin-login-as-user-get-his-session-d35eedb50e75)
- [Allow admin to generate auth user sessions | Supabase Discussions #11854](https://github.com/orgs/supabase/discussions/11854)
- [supabase-js admin.generateLink + PKCE | supabase/auth-js#767](https://github.com/supabase/auth-js/issues/767)
- [supabase_settings | Terraform Registry](https://registry.terraform.io/providers/supabase/supabase/latest/docs/resources/settings)

## Overview

PR-B (#3244, #3395) shipped tenant-isolated Supabase access via **Resolution A**: Node-side HS256 minting using `SUPABASE_JWT_SECRET` from Doppler. `apps/web-platform/lib/supabase/tenant.ts` holds the secret, calls `public.precheck_jwt_mint(p_founder_id, p_ttl_sec)` for atomic rate-limit + `jti` generation, then `createHmac("sha256", secret).update(...)` signs the JWT. PostgREST verifies the same HS256 signature on every tenant read/write.

This plan replaces the HS256 substrate with Supabase asymmetric signing keys (ECC/RSA managed by Supabase; private key never leaves Supabase). After this lands:

- `SUPABASE_JWT_SECRET` is removed from Doppler (dev + prd).
- `apps/web-platform/lib/supabase/tenant.ts:131-139` (`getJwtSecret`) and the `createHmac` block at `:218-224` are deleted.
- `public.precheck_jwt_mint` continues to own the atomic `jti` + rate-limit gate but the Node side no longer signs — it calls a Supabase admin endpoint that returns a fully-signed JWT.
- Operator runbook for Supabase project provisioning drops the "copy JWT secret from dashboard → Doppler" step (the secret is no longer dashboard-readable in the new key model anyway).

Brand-survival threshold is **single-user incident**: a regression in JWT minting blocks every founder's access to their own runtime data (the same data the user-impact-reviewer flagged at PR-B). The substrate swap MUST preserve the same tenant-isolation invariants PR-B / PR-C / PR-D / PR-E shipped — including the `denied_jti` revocation path and the WORM-audit `Art. 5(2)` posture.

## Design choice (post-deepen): Option C — Custom Access Token Hook

The original plan's Option B (admin generateLink + verifyOtp + `runtime_jwt_binding` side-table) is functionally workable but adds an INSERT per mint and couples deny-list semantics to a side table. The deepen pass discovered Supabase's **Custom Access Token Hook**: a Postgres function called synchronously during every Auth token-issuance flow, with permission to add a `jti` claim to the JWT payload.

**Why Option C wins:**

| Concern | Option B (binding table) | Option C (custom access token hook) |
| --- | --- | --- |
| jti revocation surface | `denied_jti` + `runtime_jwt_binding` (two tables) | `denied_jti` only — unchanged from PR-B |
| Per-mint DB writes | 2 (precheck + binding) | 1 (precheck — unchanged from PR-B) |
| Where the jti lives | Side table; PostgREST sees Supabase's session jti | Inside the JWT payload itself |
| `is_jti_denied(jti)` parameter | Supabase session jti (binding lookup required) | Our precheck jti directly (no indirection) |
| Schema-evolution coupling | New table + new fn signature | Hook function only, no schema change |
| Plan complexity | Migration 047 + binding-table tests + 2-grep verification | One Postgres function + one Auth Hook config |

Option C is also more aligned with Supabase's own programming model — they built the hook precisely so applications can add custom claims at issuance time.

**Trade-offs of Option C:**

- The hook fires on EVERY auth-issuance event in the project, not just our runtime mint. The hook function MUST early-return when the `authentication_method` is not one of the runtime mint signals. Detail in Phase 2.4 below.
- Hook errors block ALL token issuance (Dashboard login, password reset, etc.). Defense-in-depth: hook must handle every error path with a safe pass-through (return claims unchanged), reserving the hard-fail only for our runtime mint path.
- The hook's `jti` injection happens AFTER the precheck row exists; we still need a way to communicate the precheck jti from the Node-side call to the hook. The cleanest path: the hook calls `precheck_jwt_mint` itself (it's a SECURITY DEFINER Postgres function — the hook IS Postgres). Removes an entire round-trip from Node.

The Phase 2 implementation below adopts Option C with the hook calling `precheck_jwt_mint` directly.

## Research Reconciliation — Spec vs. Codebase

Issue body claims vs. live state at plan-write time:

| Issue body claim | Reality (verified 2026-05-18) | Plan response |
| --- | --- | --- |
| "Deferral of #3219 / #2962 closure validated against new substrate" | Both issues are **CLOSED** (verified via `gh issue view`). #3219 closed at PR-B follow-through; #2962 closed via `getServiceClient` memoization in PR-A. | Acceptance criterion dropped. They are no longer load-bearing on this PR. |
| "Migration 037's `mint_founder_jwt` RPC either deleted or reshaped" | The RPC is **`precheck_jwt_mint`** (not `mint_founder_jwt`). `mint_founder_jwt` never landed — it was renamed during PR-B's Resolution A pivot. Verified at `apps/web-platform/supabase/migrations/037_audit_byok_use.sql:precheck_jwt_mint`. | Plan retargets the AC to `precheck_jwt_mint`. The function keeps its atomic rate-limit + jti supplier role; the Node-side signing call is what changes. |
| "Supabase rolled out new key formats (`sb_secret_*`)" with `secret_jwt_template` for `service_role` | Option A's `sb_secret_*` is Kong-routing only, not per-call claim injection; rejected. | Plan adopts Option C (Custom Access Token Hook). |
| "`auth.admin.generateLink` + `auth.admin.verifyOtp`" pattern | Pattern is valid in `@supabase/supabase-js` v2; it goes through GoTrue. **Side effects to characterize:** (a) per-email magiclink rate limits in Supabase Auth Settings (default 4/hour, increasable but not unbounded); (b) `auth.audit_log_entries` writes one row per generate + one per verify (NOT to `auth.sessions` — verify creates a session row only if `Token` is exchanged, which we then sign-out to avoid pollution); (c) latency: empirical 200-500ms per mint vs. ~1ms HS256; (d) interacts with `auth.users.banned_until` (verifyOtp returns 400). Latency dominates the analysis. | Plan adopts Option B but introduces a **mint-rate adjustment**: drop the cache TTL/2 boundary from 5min to TTL/4 (~150s) so cache hit-rate stays high under the latency hit; preserve the 60/hour `precheck_jwt_mint` ceiling (now even more important: 60 GoTrue calls/hr per founder is far below Supabase's per-project rate limits). Auth rate limits raised via Supabase project settings as a Terraform-managed `supabase_project_setting` resource (per `hr-all-infrastructure-provisioning-servers`). |
| Issue body Option A claim: "`request.jwt.claims` overrides via PostgREST's signing-key system" | No such mechanism exists in PostgREST as of 2026-05. Per-call claims are signed-by-caller; PostgREST verifies the signature only. | Confirms Option A is unsuitable for per-founder JWTs without us holding a signing key. |
| Sensitive-keys allowlist | `apps/web-platform/server/sensitive-keys.ts:51-58` lists `jwt_secret`, `supabase_jwt_secret`. | Plan removes the entries cleanly post-#3363; the substrate no longer produces or consumes these keys. |

## User-Brand Impact

**If this lands broken, the user experiences:** every founder is locked out of their own runtime data — `apps/web-platform/server/agent-runner.ts:182,213,256,289,329,376,528,1071,1315-1456` and 16 sibling tenant-isolated query sites in PR-C/PR-D/PR-E throw `RuntimeAuthError` on every call. The Dashboard shows "Authentication unavailable; retry shortly" with no recovery path until rollback. This is the same single-user-incident blast radius that PR-B was framed against.

**If this leaks, the user's session is exposed via:** the new substrate **eliminates** a class of leak that the HS256 substrate carried — Soleur no longer holds a signing key, so a `process.env` dump, a Sentry config-block leak, or a compromised Doppler service token cannot mint arbitrary tenant JWTs. The remaining exposure surface narrows to the `SUPABASE_SERVICE_ROLE_KEY` (which can call `auth.admin.generateLink` and thus impersonate any founder) — same blast-radius class as before, no widening.

**Phase-4 amendment — additional user-facing failure modes named after the marker-table pivot (ADR-033 §0.7):**

- **Race-window dashboard session shortening.** Probability ~0.02% of dashboard OTP logins under steady-state founder load (24 mints/hr × ~700ms UPSERT→hook window). A losing dashboard verifyOtp consumes the runtime intent row → founder's dashboard session arrives with `aud=soleur-runtime`, `exp=600s`. PostgREST does not enforce `aud` today; the user-visible harm is a 10-minute auto-logout. **Self-recovering** via re-login. Accepted residual per single-user-incident threshold.
- **Cascade-deletion-during-mint.** If an admin deletes a founder's `auth.users` row while a runtime mint is in flight, ON DELETE CASCADE removes the intent row before the hook fires → hook pass-through → tenant.ts's UUID-shape `jti` defensive check throws `RuntimeAuthError("Authentication unavailable; retry shortly")`. **Acceptable scope-out**: the user no longer exists post-cascade; the brief in-flight error is bounded and tied to admin action.
- **Multi-device concurrent mint contention.** Two devices for the same founder UPSERTing within the ~700ms window: one consumes the intent (legit runtime claims), the other gets a pass-through JWT lacking precheck-issued `jti` → tenant.ts's UUID-shape `jti` check throws `RuntimeAuthError`, the losing device retries and the next UPSERT cycle succeeds. **Mitigated**: existing defensive check + retry. No `denied_jti` revocation bypass — the losing JWT is rejected at tenant.ts boundary before it enters the cache.
- **Latency budget.** +30-50ms per mint for the extra UPSERT roundtrip (p95 mint = 753ms baseline). Within PR-B's 1s session-start SLO; cache hit-rate ≈99% post-warmup confines the cost to once-per-session.

**Brand-survival threshold:** `single-user incident` — a regression on this path = "every founder loses access until rollback". CPO sign-off required at plan time before `/work` begins. CPO carry-forward from PR-B's plan applies: brand-survival framing already locked in.

## Hypotheses

> No SSH / network keywords in scope. Network-outage checklist (`plan-network-outage-checklist.md`) does not apply.

**H1: `auth.admin.generateLink({ type: "magiclink" })` + `auth.admin.verifyOtp({ token_hash, type })` produces a JWT with `role=authenticated` and `sub=auth.users.id` that PostgREST verifies via Supabase's managed asymmetric key — without Soleur holding any signing material.** Verified by Phase 0 live probe against dev project.

**H2: `precheck_jwt_mint` remains load-bearing.** Without it, magiclink rate-limit and `jti` revocation move out of our control. The RPC keeps the rate-limit + denied_jti coordination.

**H3: `auth.audit_log_entries` writes will increase substantially.** Each runtime mint = 2 audit rows (generate + verify). At cache TTL/4 (~150s) per founder, that's ~24 rows/hour per active founder. The audit log is a `auth.*` schema table managed by Supabase — retention is bounded by Supabase's own settings (default 60d). Plan declares this an accepted side-effect and tracks it in §Risks.

**H4: Latency hit at session start is bounded.** PR-B's plan §1.6 ALS lazy-fetch means the JWT mint is on the critical path of the FIRST tenant query in a session, not on every query (cache hit-rate ≈ 99% after warmup). 200-500ms one-time per session is below PR-B's 1s session-start SLO.

## Implementation Phases

### Phase 0 — Live-probe + ADR (precondition gate)

**Owner: this PR. Must complete before any code edit.**

0.1 **Probe asymmetric-keys enablement on the project.** Against `dev` Supabase project:
```bash
curl -sS "$SUPABASE_URL/auth/v1/.well-known/jwks.json" | jq .
```
- If the response contains `keys[]` with `alg=ES256` or `alg=RS256` and `kid` values → asymmetric is enabled, proceed to 0.2.
- If response is empty `{"keys":[]}` or 404 → asymmetric NOT enabled. Add Phase 0.1.a step: enable in Supabase Dashboard → API → "JWT Signing Keys" → "Enable". This is a 1-click no-downtime operation per Supabase's [rotation guarantee](https://supabase.com/docs/guides/troubleshooting/rotating-anon-service-and-jwt-secrets-1Jq6yd). Repeat 0.1 to confirm.

Capture the exact `alg` and `kid` values in ADR-033. The hard-rule `hr-no-dashboard-eyeball-pull-data-yourself` is satisfied by the curl probe + jq parsing.

0.2 **Probe Option B (generateLink+verifyOtp) live** against `dev` Supabase project:
```bash
# Step 1: generateLink (no email sent — we read the hashed_token directly)
curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/generate_link" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"type":"magiclink","email":"<dev-fixture-email>"}' \
  -o /tmp/gen.json
HT=$(jq -r '.properties.hashed_token' /tmp/gen.json)

# Step 2: verifyOtp (type='email', NOT 'magiclink' — see Razikus + PKCE-fix)
curl -sS -X POST "$SUPABASE_URL/auth/v1/verify" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"token_hash\":\"$HT\",\"type\":\"email\"}" \
  -o /tmp/ver.json
AT=$(jq -r '.access_token' /tmp/ver.json)

# Decode header — expect alg=ES256 or RS256, NOT HS256.
echo "$AT" | cut -d. -f1 | base64 -d 2>/dev/null | jq .

# Decode payload — capture sub, aud, role, exp, iat, jti, kid.
echo "$AT" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```
Capture: exact `alg`, default `aud` value (likely `authenticated`), and whether `jti` is present by default (Supabase's docs list jti as **optional** — likely absent without our hook).

0.3 **Probe Custom Access Token Hook registration channel.** Verify the API-readable surface for hook registration. Two probes:
```bash
# Read currently-registered hooks via Management API.
curl -sS "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer $SUPABASE_MGMT_API_TOKEN" \
  | jq '.hook_custom_access_token_uri, .hook_custom_access_token_enabled'

# OR read auth.hooks table directly via service-role psql.
psql "$DATABASE_URL" -c "SELECT * FROM auth.hooks;" 2>&1 | head -20
```
**Goal:** confirm we have an API channel for registering `public.runtime_jwt_mint_hook` post-merge — NOT a dashboard-only operation. If only the dashboard supports hook registration, add a Phase 5 operator step with `[ack-needed]` per `hr-menu-option-ack-not-prod-write-auth`.

0.4 **Verify pre-committed hook gate channel: `authentication_method = 'otp'`.** The 5-agent plan-review panel directed a pre-commit decision rather than a Phase-0 fork. Decision: the hook's pass-through gate triggers on `event->>'authentication_method' = 'otp'` (the only path that runtime mints take via `generateLink + verifyOtp`). Probe verifies the gate's robustness — call the verifyOtp surface from Phase 0.2 and confirm the hook input shows `authentication_method = 'otp'` (Supabase docs list this as a known value). Capture the exact string in the ADR. Footnote (single paragraph, future-optimization-only): if a future PR needs to mint runtime sessions for multiple distinct aud values per founder, two alternative channels exist — (a) `auth.users.app_metadata.target_aud` propagation into claims, (b) `verifyOtp` audience request parameter. Neither is exercised by this PR; the `'otp'` gate is sufficient for the single-runtime-aud surface.

0.5 **Latency baseline.** Time 10 sequential generate+verify cycles against dev. Median + p95 in the ADR. If p95 > 1000ms, fall back to a hybrid that pre-mints sessions on the WebSocket connect handshake (deferred to V2 if observed).

0.6 **GoTrue rate-limit probe.** Run 60 sequential generate+verify cycles against the SAME fixture email in 1 minute. Expected outcomes per the deepen-pass research:
- **EMAIL_SENT (default 10/hour)** — should NOT trip since `generateLink` doesn't send.
- **TOKEN_REFRESH (default 10/IP/hour)** — may trip. If it does, this is our hard ceiling and we MUST keep the cache TTL/4 strict (max 24 mints/hour/founder < 10/IP/hour means we trip before our own ceiling — concerning).
- **VERIFY (rate of /auth/v1/verify)** — undocumented in current Supabase docs; this probe is the authoritative measurement.

Capture: number of attempts before first 429, time-to-recover, whether the limit is per-IP or per-email. **If TOKEN_REFRESH trips at < 60/hour per IP/founder**, add a Phase 3.2 step to request a per-project rate-limit bump via Supabase support (operator-acknowledged per `hr-menu-option-ack-not-prod-write-auth`). This is a known practice — Supabase exposes RATE_LIMIT_TOKEN_REFRESH only via support request.

0.7 **Authoring deliverable: ADR-033.** Write `knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md` per template at `plugins/soleur/skills/architecture/references/adr-template.md`. **Status: Proposed** — the ADR enumerates Option C (Custom Access Token Hook) and Option D (keep HS256, rotate quarterly via Doppler) as serious-considered alternatives; the operator decides between them BEFORE `/work` begins. Context, Considered Options (A, B-with-binding-table, **C**, **D**), Decision (blank — `[OPERATOR DECISION REQUIRED]`), Consequences for both C and D, References (PR-B, this plan, sibling ADR-004 / ADR-023, Supabase JWT Signing Keys docs). Reviewed inline by `architecture-strategist` during plan-review.

### Phase 1 — Test-first: prove the new contract end-to-end (RED)

1.1 **[RED] `apps/web-platform/test/server/tenant-jwt-asymmetric.test.ts`** (NEW). Asserts at unit level:
- `mintFounderJwt(userId)` returns a `MintedJwt` whose `jwt` has `alg=RS256` (or `ES256` — whichever Phase 0.2 confirmed) in the JWT header — NOT `HS256`. Decode the header without verification and assert the `alg` field.
- The JWT payload still satisfies the shape contract from PR-B: `sub === userId`, `role === "authenticated"`, `jti` is a uuid, `exp - iat` is within 5s of `ttlSec`.
- `precheck_jwt_mint` is still called for jti supply (mock the service client, assert RPC invocation count = 1 per mint).
- On `precheck_jwt_mint` returning `mint_rate_exceeded`, `RuntimeAuthError({ cause: "rotation" })` is thrown — **identical** to pre-PR behavior. This is the regression seam.
- On `auth.admin.generateLink` failure, `RuntimeAuthError({ cause: "jwt_mint" })` is thrown.
- The minted JWT contains a `jti` that equals `precheck_jwt_mint.jti` (the load-bearing coupling — `denied_jti` must continue to gate revocation).

1.2 **[RED] `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts`** (extend existing per `precheck_jwt_mint` reshape). Existing tests assert `denied_jti` revocation against an HS256-signed JWT. After this PR they must pass with the asymmetric-signed JWT — semantically identical via the `jti` claim. Run as-is; expect RED until Phase 2 wires the new mint path.

1.3 **[RED] `apps/web-platform/test/server/tenant-jwt-refresh.test.ts`** (extend). Add 3 new test rows: cache TTL/4 boundary (NEW), latency-failed-mint resilience (mock `generateLink` to throw, assert `RuntimeAuthError({cause: "jwt_mint"})`), GoTrue rate-limit (mock `generateLink` to return `429`, assert `RuntimeAuthError({cause: "jwt_mint"})` with body context surfaced via Sentry `mirrorWithDebounce` — does NOT collapse to `rotation` since the existing `rotation` cause is reserved for the `precheck_jwt_mint` ceiling).

1.4 **[RED] Tenant-isolation integration regressions** — re-run the 16 existing `*.tenant-isolation.test.ts` suites under the new substrate. These are gated by `TENANT_INTEGRATION_TEST=1` and run against dev Supabase; they should be RED only because the substrate change has not landed yet. Plan ACs include these going GREEN.

1.5 **[RED] Migration 047 behavioral test:** `apps/web-platform/test/supabase-migrations/047-custom-access-token-hook.test.ts`. Two test cases (alongside file-parse assertions mirroring `037-audit-byok-use.test.ts`):
   - **Pass-through:** invoke `public.runtime_jwt_mint_hook(event)` with `event = {user_id: '<fixture-uuid>', claims: {<arbitrary-claims>}, authentication_method: 'password'}`. Assert the returned `claims` jsonb is byte-identical to the input claims (no mutation, no precheck call, no DB writes).
   - **Function signature:** assert via `SELECT pg_get_function_arguments(p.oid), pg_get_function_result(p.oid) FROM pg_proc p WHERE p.proname = 'runtime_jwt_mint_hook' AND pronamespace = 'public'::regnamespace` that the signature is exactly `(event jsonb) -> jsonb`. Mirrors the contract that GoTrue's hook caller expects.

1.6 **[RED] Migration 048 SQLSTATE test:** `apps/web-platform/test/supabase-migrations/048-precheck-jwt-mint-sqlstate.test.ts`. Calls `precheck_jwt_mint` 61 times for the same founder_id within 1h to trip the rate-limit ceiling; asserts the raised exception has `SQLSTATE = '45001'` (NOT P0001). Wrap the 61st call in `BEGIN ... EXCEPTION WHEN SQLSTATE '45001' THEN got_45001 := true; END` and assert.

### Phase 2 — Code change: GREEN (Option C — Custom Access Token Hook)

2.1 **Migration 047:** `apps/web-platform/supabase/migrations/047_custom_access_token_hook.sql`. Adds a `public.runtime_jwt_mint_hook(event jsonb)` SECURITY DEFINER function. Pseudocode:

```sql
-- 047_custom_access_token_hook.sql
-- Per cq-pg-security-definer-search-path-pin-pg-temp.
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: no CONCURRENTLY.

CREATE OR REPLACE FUNCTION public.runtime_jwt_mint_hook(event jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id       uuid;
  v_claims        jsonb;
  v_auth_method   text;
  v_precheck      record;
  v_ttl_sec       int  := 600;
  -- Custom SQLSTATE for precheck_jwt_mint rate-limit signal. See sibling
  -- migration 048 which recreates precheck_jwt_mint with ERRCODE = '45001'
  -- to disambiguate from the WORM-trigger P0001 raise in migration 037.
  -- DOC: constant must stay in sync with migration 048's RAISE EXCEPTION
  -- USING ERRCODE = '45001'.
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  -- Pass-through gate: only inject runtime claims when this is the OTP
  -- verify path used by tenant.ts:mintFounderJwt (generateLink + verifyOtp).
  -- Other auth flows (password login, oauth, true magiclink email-delivery
  -- with non-otp authentication_method, etc.) get default claims unchanged.
  -- Rationale: Phase 0.4 pre-commit decision — gate on authentication_method
  -- = 'otp' rather than aud=soleur-runtime, because the audience-injection
  -- channel (app_metadata.target_aud or verifyOtp audience param) is not
  -- guaranteed to flow into the hook input. The 'otp' gate is robust and
  -- API-readable from event payload directly. Footnote: (a) app_metadata
  -- propagation and (b) verifyOtp audience param remain future optimizations
  -- if we later need to mint distinct runtime aud values per founder.
  IF v_auth_method <> 'otp' THEN
    RETURN jsonb_build_object('claims', v_claims);
  END IF;

  -- Pull the precheck row (atomic rate-limit + jti generation).
  -- precheck_jwt_mint raises with custom ERRCODE '45001' on ceiling trip
  -- (see migration 048). No EXCEPTION WHEN OTHERS catch — security-critical
  -- functions fail loud. Any other error here propagates: GoTrue returns
  -- 500 to Node, tenant.ts:mintFounderJwt raises RuntimeAuthError("jwt_mint")
  -- naturally via the verified.error path.
  SELECT jti, exp_epoch, iat_epoch INTO v_precheck
  FROM public.precheck_jwt_mint(v_user_id, v_ttl_sec);

  -- Overwrite the JWT's standard claims with our runtime-scoped values:
  -- jti = precheck-issued; aud := 'soleur-runtime'; exp/iat from precheck.
  v_claims := jsonb_set(v_claims, '{jti}', to_jsonb(v_precheck.jti::text));
  v_claims := jsonb_set(v_claims, '{exp}', to_jsonb(v_precheck.exp_epoch));
  v_claims := jsonb_set(v_claims, '{iat}', to_jsonb(v_precheck.iat_epoch));
  v_claims := jsonb_set(v_claims, '{aud}', '"soleur-runtime"');
  v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

COMMENT ON FUNCTION public.runtime_jwt_mint_hook(jsonb) IS
  'Custom Access Token Hook for runtime JWTs (Resolution C, #3363). '
  'Gates on authentication_method=otp; calls precheck_jwt_mint and injects '
  'jti+exp+iat+aud into the JWT claims so denied_jti revocation continues '
  'to work against the JWT''s own jti claim (no binding table required). '
  'Errors propagate (no WHEN OTHERS pass-through) — security-critical.';
```

**Sibling migration 048:** `apps/web-platform/supabase/migrations/048_precheck_jwt_mint_sqlstate.sql`. In-place `CREATE OR REPLACE FUNCTION public.precheck_jwt_mint(uuid, int)` that recreates the function body from migration 037 with one change: the rate-limit raise becomes `RAISE EXCEPTION USING ERRCODE = '45001', MESSAGE = 'mint_rate_exceeded'`. Rationale: migration 037's WORM-trigger on `audit_byok_use` already raises with default ERRCODE `P0001` (line 56); migration 047's hook must be able to distinguish "precheck-rate-limit" from "WORM-trigger-violation" via SQLSTATE alone. Custom class `45` is in the user-defined range per Postgres docs (classes 00-42 reserved). Migration 048 includes a `DO $$ ... ASSERT ... $$` block asserting the function compiles AND raising the rate-limit signal yields SQLSTATE 45001 (via `BEGIN ... EXCEPTION WHEN SQLSTATE '45001' THEN ... END`). Surgical — no signature change, no behavioral change for callers except the SQLSTATE value.

**Register the hook** via Supabase Management API per Phase 0.3 probe result (NOT dashboard — see Deploy-Order Runbook §c). **Verify per `hr-no-dashboard-eyeball-pull-data-yourself`:** registration is API-readable; Phase 5.1 includes the API probe.

2.2 **Edit `apps/web-platform/lib/supabase/tenant.ts`** — replace the HS256 sign block. New `mintFounderJwt`:

```ts
// apps/web-platform/lib/supabase/tenant.ts:168 (Resolution C)
export async function mintFounderJwt(
  userId: UserId,
  opts: MintFounderJwtOpts = {},
): Promise<MintedJwt> {
  const ttlSec = opts.ttlSec ?? DEFAULT_TTL_SEC;
  const service = getServiceClient();

  // Look up the founder's email — required for generateLink.
  // Service-role-only; founders cannot read each other's auth.users rows.
  const email = await resolveFounderEmail(userId, service);

  // Supabase-mediated mint. generateLink returns a hashed token;
  // verifyOtp exchanges it for an asymmetrically-signed JWT without sending
  // any email. The Custom Access Token Hook (migration 047) injects our
  // precheck-issued jti into the JWT's claims when aud=soleur-runtime.
  //
  // Note: type='magiclink' for generateLink, type='email' for verifyOtp
  // — this asymmetry is intentional in supabase-js. Per Razikus pattern
  // + Supabase PKCE-fix article. The 'magiclink' literal for verifyOtp
  // is deprecated as of 2025.
  const link = await service.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { redirectTo: undefined }, // No client redirect — server-side only.
  });
  if (link.error || !link.data?.properties?.hashed_token) {
    throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
  }

  // Per Phase 0.4 pre-commit decision: the hook gates on
  // event.authentication_method = 'otp' (the verifyOtp path). No audience
  // injection from Node is required — the hook sets aud=soleur-runtime
  // unconditionally inside its body.
  const verified = await service.auth.verifyOtp({
    token_hash: link.data.properties.hashed_token,
    type: "email", // NOT "magiclink" — per Razikus pattern + Supabase docs.
  });
  if (verified.error || !verified.data?.session?.access_token) {
    if (verified.error?.message?.includes("rate_limit") || verified.error?.message?.includes("429")) {
      // GoTrue rate-limit collapse to RuntimeAuthError("jwt_mint")
      // — distinct from precheck rate-limit which is the "rotation" cause.
      throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
    }
    if (verified.error?.message?.includes("mint_rate_exceeded")) {
      // The hook bubbled this from precheck_jwt_mint via the GoTrue layer.
      throw new RuntimeAuthError("rotation", "Authentication unavailable; retry shortly");
    }
    throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
  }

  const jwt = verified.data.session.access_token;

  // Decode the JWT (header.payload.signature, no verification — we trust
  // Supabase's signature) to extract OUR jti, exp, iat for the cache layer.
  // The hook injected these; if they're absent the hook didn't fire — the
  // precheck row was either consumed by another concurrent mint or the
  // hook wasn't registered. Throw, evict cache, retry on next call.
  const payload = decodeJwtPayloadUnsafe(jwt); // tiny helper — see 2.3.
  if (typeof payload.jti !== "string" || typeof payload.exp !== "number") {
    throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
  }

  return {
    jwt,
    ttlSec,
    mintedAt: Date.now(),
    jti: payload.jti, // Hook-injected, from precheck_jwt_mint.
  };
}
```

2.3 **Add `decodeJwtPayloadUnsafe(jwt: string): Record<string, unknown>`** helper to `tenant.ts`. Splits on `.`, base64url-decodes the middle segment, `JSON.parse`. NO signature verification (PostgREST does that; this is just claim extraction). 4-line function; no new dependency. The "Unsafe" suffix is load-bearing — a future developer reading the helper sees immediately that this is NOT a JWT verifier.

2.4 **Add `resolveFounderEmail(userId, service)` helper** to `apps/web-platform/lib/supabase/tenant.ts`. Calls `service.auth.admin.getUserById(userId)` and returns `data.user.email`. Cached per-process via a `Map<UserId, string>` (rotated only on process restart). Throws `RuntimeAuthError("jwt_mint", ...)` on lookup failure. Email rotation is rare; cache invalidation acceptable as next-session-only.

2.5 **Update the TTL/2 → TTL/4 boundary** at `apps/web-platform/lib/supabase/tenant.ts:430`:
```ts
// Was: now - entry.mintedAt < (entry.ttlSec * 1000) / 2
// New: now - entry.mintedAt < (entry.ttlSec * 1000) / 4
```
At ttlSec=600 → 150s remint window → ≤24 mints/hour/founder ≤ precheck ceiling of 60. Bounded.

2.6 **Drop the HS256 signing code path entirely:**
- `getJwtSecret()` at `tenant.ts:131-139` — DELETE.
- `b64url()` at `tenant.ts:122-129` — DELETE (becomes unreachable; if `decodeJwtPayloadUnsafe` needs base64url decoding, it uses `Buffer.from(seg.replace(/-/g, '+').replace(/_/g, '/'), 'base64')` inline).
- `createHmac` import at `tenant.ts:33` — DELETE.
- The static-claim assembly + sign block at `tenant.ts:208-224` — DELETE (replaced by the verifyOtp call + jwt extraction above).
- `JWT_AUDIENCE = "soleur-runtime"` const at `tenant.ts:119` — RETAIN as the literal value the hook sets via `jsonb_set(v_claims, '{aud}', '"soleur-runtime"')`. The constant is documented in Node for parity with PostgREST's audience validation; the hook is the actual write site (per Phase 0.4 pre-commit decision: gate on `authentication_method='otp'`, then unconditionally set `aud` inside the hook).

2.7 **Update header docblock at `tenant.ts:1-31`** to describe Option C: "Resolution C (#3363, this PR): Supabase asymmetric signing keys. Node holds no signing material. `precheck_jwt_mint` continues to own atomic rate-limit + jti supply; the `runtime_jwt_mint_hook` Custom Access Token Hook (migration 047) calls it from inside the auth-issuance transaction so the precheck-issued jti lands directly in the JWT's `jti` claim. PostgREST sees the same jti our `denied_jti` table indexes — no binding table required."

2.8 **Defensive seam for hook-not-registered:** if the hook is unregistered (e.g., post-rollback, or fresh Supabase project), `verifyOtp` returns a JWT with default claims — no `jti`, no `aud=soleur-runtime`. Phase 2.2's defensive `if (typeof payload.jti !== "string") throw` catches this. The error message MUST surface to Sentry via `mirrorWithDebounce` so operators see the hook-not-registered failure mode distinctly from generic mint failures. Add a hook-registration probe in `lib/supabase/service.ts:getServiceClient` initialization. In production NODE_ENV, the probe queries `auth.hooks` (or the Mgmt API `config/auth.hook_custom_access_token_*` surface) for the registered `runtime_jwt_mint_hook` and **hard-fails** (throws on first `getServiceClient()` call OR `process.exit(1)` at boot) when the hook is absent. Forensics-only path: `auth.audit_log_entries` already records every token-issuance event including hook outcomes; no parallel WORM table is added by this PR — `auth.audit_log_entries` is the audit substrate (Supabase-managed, 60d retention per H3 above).

### Phase 3 — Doppler + IaC cleanup

3.1 **Doppler — remove `SUPABASE_JWT_SECRET` from `dev` and `prd` configs.** Owner: operator (sensitive write per `hr-menu-option-ack-not-prod-write-auth`). The plan's `/work` Phase 3 prescribes printing a clear `[ack-needed] doppler secrets delete SUPABASE_JWT_SECRET -p soleur -c dev` and a paired `prd` line, gated on a `[y/N]` prompt per the hard rule. Removal happens AFTER PR merge (post-merge operator step in AC) since the running prod process still references it until the new image rolls out.

3.2 **Supabase Auth settings — runbook only.** The `supabase/supabase` Terraform provider does not (as of 2026-05-18, v1.9.1) expose `RATE_LIMIT_TOKEN_REFRESH` or `RATE_LIMIT_EMAIL_SENT` as managed fields. Document the required Auth panel state (`JWT_EXP=3600`, `EXTERNAL_EMAIL_ENABLED=true`, `RATE_LIMIT_TOKEN_REFRESH` value from Phase 0.6 probe) in `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` and file a follow-up tracking issue per `hr-all-infrastructure-provisioning-servers` + `wg-when-deferring-a-capability-create-a`.

3.3 **GitHub Actions secrets — verify no `SUPABASE_JWT_SECRET` reference.** Run `gh secret list --json name | jq` and confirm absence. If present, remove via `gh secret delete` post-merge.

3.4 **`apps/web-platform/server/sensitive-keys.ts` cleanup.** Remove the `jwt_secret` and `supabase_jwt_secret` entries from the allowlist. The substrate no longer produces or consumes these keys.

### Phase 4 — Plan review + deepen

4.1 Run `/plan_review` (DHH + Kieran + Code Simplicity). The deepen-plan skill follows immediately.

4.2 Resolve all P0/P1 findings inline; file P2/P3 as scope-out issues with explicit Folds-in / Acknowledge / Defer per Phase 1.7.5.

### Phase 5 — Ship

5.0 **prd-side mirror of Phase 0 probes (BEFORE prd cutover) `[ack-needed]`.** Each step gated on operator ack per `hr-menu-option-ack-not-prod-write-auth`:
   - **5.0.a [ack-needed]** Repeat Phase 0.1 (JWKS asymmetric-keys probe) against **prd** Supabase. Capture exact `alg` and `kid` in PR body. If asymmetric not enabled, do NOT proceed — operator enables via Dashboard (Deploy-Order Runbook §a) first.
   - **5.0.b [ack-needed]** Repeat Phase 0.2 (generateLink + verifyOtp live probe) against **prd** Supabase with a synthesized fixture email. Decode JWT header; assert `alg != HS256`. Decode payload; capture default `aud` and `jti` presence.
   - **5.0.c [ack-needed]** Repeat Phase 0.4 (`authentication_method = 'otp'` gate verification) against **prd**. Hook input payload from a test invocation must show `authentication_method = 'otp'` so the gate fires.

5.1 Standard `/soleur:ship` flow. Special operator-acknowledged steps:
- `doppler secrets delete SUPABASE_JWT_SECRET -p soleur -c dev` (sensitive write)
- `doppler secrets delete SUPABASE_JWT_SECRET -p soleur -c prd` (sensitive write)
- Verify post-deploy by `gh secret list` and `doppler secrets get SUPABASE_JWT_SECRET -p soleur -c prd --plain` (latter MUST 404).

5.2 Rollback path: see **Rollback Runbook** section below.

## Deploy-Order Runbook (prd)

Ordered, gated checklist for production cutover. Each step is `[ack-needed]` per `hr-menu-option-ack-not-prod-write-auth`. After each step, run the listed verification probe (API-readable per `hr-no-dashboard-eyeball-pull-data-yourself`).

**(a) [ack-needed] Enable JWT Signing Keys on prd Supabase project.**
   - Action: Supabase Dashboard → API → "JWT Signing Keys" → Enable. (No CLI/API surface as of 2026-05-18; this is the one Dashboard click — `hr-exhaust-all-automated-options-before` satisfied: probed the Mgmt API surface, no `POST /v1/projects/<ref>/config/auth/signing-keys` endpoint exists.)
   - Verify: `curl -sS "$SUPABASE_URL/auth/v1/.well-known/jwks.json" | jq '.keys[] | {alg, kid}'` returns a key with `alg = ES256` (or RS256). Capture in PR body.

**(b) [ack-needed] Apply migrations 047 + 048 to prd.**
   - Action: prefer `mcp__plugin_supabase_supabase__apply_migration` (per `hr-exhaust-all-automated-options-before`). Fallback chain per AGENTS.md: Doppler `DATABASE_URL_POOLER` direct `psql -f`, then operator-supervised Supabase SQL Editor as last resort.
   - Verify: `psql "$DATABASE_URL_POOLER" -c "SELECT proname FROM pg_proc WHERE proname IN ('runtime_jwt_mint_hook','precheck_jwt_mint') AND pronamespace='public'::regnamespace;"` returns both rows. Trip the rate-limit and assert SQLSTATE 45001.

**(c) [ack-needed] Register the Custom Access Token Hook via Supabase Management API.**
   - Action (NOT dashboard — per Phase 0.3 probe result):
     ```bash
     curl -sS -X PATCH "https://api.supabase.com/v1/projects/<prd-ref>/config/auth" \
       -H "Authorization: Bearer $SUPABASE_MGMT_API_TOKEN" \
       -H "Content-Type: application/json" \
       -d '{"hook_custom_access_token_enabled": true, "hook_custom_access_token_uri": "pg-functions://postgres/public/runtime_jwt_mint_hook"}'
     ```
   - Verify: `curl -sS "https://api.supabase.com/v1/projects/<prd-ref>/config/auth" -H "Authorization: Bearer $SUPABASE_MGMT_API_TOKEN" | jq '.hook_custom_access_token_enabled, .hook_custom_access_token_uri'` returns `true` + the URI. AND `psql -c "SELECT * FROM auth.hooks;"` shows the row.

**(d) [ack-needed] Deploy Node code (image roll).**
   - Action: standard `/soleur:deploy` flow. Image must include the new `mintFounderJwt` + the `getServiceClient` hook-registration probe.
   - Verify: a fresh tenant query from a real-founder session returns data without `RuntimeAuthError`. Sentry shows zero `hook_unregistered_at_startup` events.

**(e) [ack-needed] Delete `SUPABASE_JWT_SECRET` from Doppler dev + prd.**
   - Action: `doppler secrets delete SUPABASE_JWT_SECRET -p soleur -c dev` then `... -c prd`.
   - Verify: `doppler secrets get SUPABASE_JWT_SECRET -p soleur -c prd --plain` returns 404. `gh secret list` shows no `SUPABASE_JWT_SECRET` reference in GitHub Actions.

## Rollback Runbook

Ordered steps to revert if a regression surfaces post-(d) but before (e):

1. **Revert the merge commit on `main`.** `gh pr revert <#>` or `git revert -m 1 <merge-sha> && git push`. Triggers redeploy of the pre-#3363 image which still references `SUPABASE_JWT_SECRET`.
2. **Doppler-secret restoration assertion.** Confirm `doppler secrets get SUPABASE_JWT_SECRET -p soleur -c prd --plain` returns the archived value (Doppler retains deleted secrets; if Phase 5.1 step (e) already ran, restore from password-manager-archived copy and re-add via `doppler secrets set SUPABASE_JWT_SECRET=<value> -p soleur -c prd`). The archived secret is expected to still be valid because **the legacy HS256 verifier coexists with the new asymmetric verifier in Supabase post-`Enable JWT Signing Keys`**. Cite: [Supabase rotation guide](https://supabase.com/docs/guides/troubleshooting/rotating-anon-service-and-jwt-secrets-1Jq6yd) and [JWT Signing Keys docs](https://supabase.com/docs/guides/auth/signing-keys) on multi-verifier coexistence during the migration window.
3. **Hook deregistration** (so subsequent runtime mints stop trying to inject claims via a now-stale hook contract):
   ```bash
   curl -sS -X PATCH "https://api.supabase.com/v1/projects/<prd-ref>/config/auth" \
     -H "Authorization: Bearer $SUPABASE_MGMT_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"hook_custom_access_token_enabled": false}'
   ```
   Alternative (direct): `DELETE FROM auth.hooks WHERE hook_name = 'custom_access_token_hook';` via Mgmt-supervised psql. Verify via `auth.hooks` SELECT returning zero rows.
4. **Verification: legacy HS256 verifier still active.** Mint an HS256 JWT manually using the restored secret, hit any PostgREST tenant endpoint, assert 200. This confirms the rollback is functional. If this fails, Supabase has fully deprecated HS256 verification — at that point rollback is impossible; forward-fix only.
5. **Calendar reminder — HS256 deprecation tracking.** Supabase has signaled HS256 verifier deprecation for **2026**. The exact cutoff date is not yet published; file a tracking issue ("HS256 rollback path expiration window") with quarterly review until Supabase confirms. After the cutoff, this rollback runbook becomes invalid and ADR-033 must be revisited (forward-only posture).
6. **Migrations 047 + 048 are forward-compatible** (function additions / replacements only, no schema state); no down-migration needed. They can remain in place after rollback — `runtime_jwt_mint_hook` simply is not invoked by GoTrue once the hook is deregistered in step 3.

## Files to Edit

- `apps/web-platform/lib/supabase/tenant.ts` (gut HS256 path, wire Supabase admin generate-session, add `decodeJwtPayloadUnsafe` + `resolveFounderEmail` helpers)
- `apps/web-platform/lib/supabase/service.ts` — or wherever `getServiceClient` lives (grep at /work-time). Add a startup probe in production NODE_ENV: query `auth.hooks` for the registered `runtime_jwt_mint_hook` row. If absent, **hard-fail** — throw on first `getServiceClient()` call OR `process.exit(1)` at boot. Plan-phase only; implementation deferred to /work.
- `apps/web-platform/server/sensitive-keys.ts` (remove `jwt_secret` and `supabase_jwt_secret` entries)
- `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` (drop dashboard-paste step, document Auth hook registration via Mgmt API, document required Auth-config settings)
- `apps/web-platform/test/server/tenant-jwt-refresh.test.ts` (new TTL/4 boundary tests + GoTrue rate-limit tests + hook-not-registered defensive seam)
- `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts` (re-run after substrate swap; assert revocation parity against hook-injected jti)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md` (Status: **Proposed** — operator decides between Option C and Option D before /work)
- `apps/web-platform/test/server/tenant-jwt-asymmetric.test.ts` (alg!=HS256, hook-injected jti present, aud=soleur-runtime, sub=userId)
- `apps/web-platform/supabase/migrations/047_custom_access_token_hook.sql` (`runtime_jwt_mint_hook` function)
- `apps/web-platform/supabase/migrations/048_precheck_jwt_mint_sqlstate.sql` (in-place CREATE OR REPLACE; switches rate-limit raise to ERRCODE `45001` to disambiguate from WORM-trigger P0001)
- `apps/web-platform/test/supabase-migrations/047-custom-access-token-hook.test.ts` (file-parse + behavioral tests — see Phase 1.5)
- `apps/web-platform/test/supabase-migrations/048-precheck-jwt-mint-sqlstate.test.ts` (assert rate-limit raise yields SQLSTATE 45001)
- `knowledge-base/project/specs/feat-one-shot-issue-3363-jwt-asymmetric-keys/spec.md` (created by parent pipeline)

## Acceptance Criteria

### Pre-merge (PR)

1. **ADR-033 lands.** File exists at `knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md`. At PR-merge time, status is `active` and the Decision section names whichever option the operator selected (Option C or Option D). The pre-`/work` Proposed-status version remains in git history. References this plan + PR.
2. **Phase 0 live probe captured.** ADR includes: exact `alg` from JWKS endpoint (`ES256` or `RS256`), JWKS URL, `kid` value, default `aud` and presence/absence of `jti` in baseline verifyOtp output, hook-registration channel (Mgmt API endpoint OR dashboard ack), audience-injection channel (app_metadata vs. authentication_method gate), generateLink+verifyOtp p50/p95 latency from dev, and the precheck rate-limit / GoTrue rate-limit / TOKEN_REFRESH probe results — each with the EXACT count from the probe.
3. **All `tenant.ts` HS256 code is gone.** `rg "createHmac|HS256|getJwtSecret" apps/web-platform/lib/supabase/tenant.ts` returns zero matches. The only base64url-related code is inside `decodeJwtPayloadUnsafe` (claim extraction only, no signing).
4. **`process.env.SUPABASE_JWT_SECRET` is unreferenced in `apps/web-platform/` production code.** `rg "SUPABASE_JWT_SECRET" apps/web-platform/ --type ts` returns matches ONLY in `test/**` (historical fixtures retained for replay). Production code paths zero; `server/sensitive-keys.ts` entries removed.
5. **Migration 047 lands** with file-parse test passing; `precheck_jwt_mint` continues to return `(jti, exp_epoch, iat_epoch)` unchanged. Hook function uses `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`. REVOKE pattern matches migration 037: `REVOKE ALL FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE TO supabase_auth_admin`. No `CONCURRENTLY`.
6. **Hook is registered against the project.** Phase 5.1 API probe confirms `auth.hooks` table (or Mgmt API `config/auth.hook_custom_access_token_*`) reflects `public.runtime_jwt_mint_hook` as the active hook. Cited in PR body with the probe command and output.
7. **All 16 existing `*.tenant-isolation.test.ts` suites GREEN** under `TENANT_INTEGRATION_TEST=1` against dev Supabase. No tenant-isolation regression.
8. **`tenant-jwt-refresh.test.ts` GREEN** with new TTL/4 boundary assertions (≤24 mints/hour/founder confirmed by 1-hour deterministic-clock test).
9. **`tenant-jwt-asymmetric.test.ts` GREEN** asserting (a) `alg != "HS256"` on every minted JWT, (b) `payload.jti` matches a recently-issued `precheck_jwt_mint` row, (c) `payload.aud == "soleur-runtime"`, (d) `payload.sub == userId`.
10. **`tenant-jwt-deny.tenant-isolation.test.ts` GREEN** asserting `denied_jti` continues to revoke active sessions against the JWT's own `jti` claim (no binding-table indirection — the hook puts our jti directly into the JWT).
11. **Sensitive-keys allowlist updated.** `jwt_secret` and `supabase_jwt_secret` entries removed from `apps/web-platform/server/sensitive-keys.ts`.
12. **PR body uses `Closes #3363`** (per `wg-use-closes-n-in-pr-body-not-title-to`; this is a code-shipping PR with no operator post-merge prerequisite for issue closure; the post-merge Doppler deletion is a hygiene step, not the issue's load-bearing fix). Reconcile against `hr-menu-option-ack-not-prod-write-auth` post-merge ack pattern: the issue closes on merge; Doppler cleanup is tracked as a follow-up.
13. **CPO carry-forward sign-off.** PR-B's CPO framing covers this; the deepen-pass pivot (Option B → Option C) does NOT change brand-survival framing — same "single-user incident" threshold, same blast radius. If any deviation surfaces during plan-review, re-invoke CPO domain leader.
14. **`bun run typecheck && bun test && bun run build` GREEN** in `apps/web-platform/`.
15. **Hook-not-registered Sentry probe.** Confirm `apps/web-platform/lib/supabase/service.ts` `getServiceClient` emits a structured Sentry event of class `hook_unregistered_at_startup` when the hook is missing. Test via mocking `auth.hooks` to return empty; assert Sentry event captured.
16. **GDPR gate execution.** `/soleur:gdpr-gate` invoked against the diff per AGENTS.md `hr-gdpr-gate-on-regulated-data-surfaces` (canonical regex matches DDL + auth flow); findings documented in PR body or filed as `compliance/critical` issues.
17. **Tenant-provisioning runbook updated.** `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` reflects (a) no SUPABASE_JWT_SECRET paste step, (b) Custom Access Token Hook registration step (API or dashboard), (c) JWT Signing Keys enablement check.

### Post-merge (operator)

14. **Operator removes `SUPABASE_JWT_SECRET` from Doppler** (`dev` then `prd`) per Phase 3.1 `[ack-needed]` prompts.
   - **Automation feasibility:** `doppler secrets delete` is CLI-automatable, but per `hr-menu-option-ack-not-prod-write-auth` prod-write requires explicit ack. /work prints the exact two commands; operator runs after PR merges and verifies the running deployment uses the new substrate. Not feasible to fully automate without ack.
15. **Operator verifies removal** via `doppler secrets get SUPABASE_JWT_SECRET -p soleur -c prd --plain` returning 404.
16. **Operator updates `tenant-provisioning.md` runbook** post-merge if Phase 3.2 deferred IaC items resolved. (Inline edit in PR is preferred; this step exists only if the runbook edit is deferred per Phase 3.2's downgrade clause.)

## Test Strategy

### RED → GREEN

- Unit (`apps/web-platform/test/server/`) via `vitest` (existing test runner; no new framework).
- Integration (`*.tenant-isolation.test.ts`) gated by `TENANT_INTEGRATION_TEST=1`, run against dev Supabase per PR-B precedent.
- Migration file-parse (`apps/web-platform/test/supabase-migrations/047-runtime-jwt-binding.test.ts`) mirrors `037-audit-byok-use.test.ts` shape (28-test contract).
- All fixtures synthesized per `cq-test-fixtures-synthesized-only`. No production data.

### Schema-version assertion

`precheck_jwt_mint` return shape is a cross-process contract: Node consumes `{jti, exp_epoch, iat_epoch}`. Plan retains the shape — no version bump — but the consumer-boundary assertion is now between `precheck_jwt_mint` and its sole caller `runtime_jwt_mint_hook` (migration 047). The Node side no longer calls `precheck_jwt_mint` directly. Migration 048's SQLSTATE change (`P0001` → `45001` for rate-limit) is the only behavioral diff and is asserted in `048-precheck-jwt-mint-sqlstate.test.ts`.

### Determinism

No LLM-mediated tests in this PR (per `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`). All assertions go through `service.rpc` / `service.auth.admin` direct calls.

## Domain Review

**Domains relevant:** Engineering (CTO), Security, Compliance/Legal

### Engineering (CTO) — carry-forward from PR-B brainstorm

**Status:** carry-forward
**Assessment:** PR-B's brainstorm CTO assessment already framed the Resolution A → asymmetric migration as the correct hardening trajectory. This PR executes that trajectory. New CTO-level concerns to call out:
- Option C eliminates the per-mint binding-table INSERT (vs. Option B.1's `runtime_jwt_binding`). Hot path is unchanged from PR-B: one `precheck_jwt_mint` SELECT per mint, now invoked from inside the auth-issuance transaction by the hook.
- Latency on first tenant query of a session grows from ~1ms to ~200-500ms. PR-B's ALS lazy-fetch already absorbs this (cache hits after the first call).
- Supabase Auth admin API is the new external dependency. Outage → no mints → every session locked. Severity SAME as the current `service.rpc("precheck_jwt_mint")` dependency (also Supabase-managed); no new SLA risk.

### Security

**Status:** to be invoked at /work-time Phase 4 (plan-review).
**Assessment (planner pre-write):** This PR is unambiguously net-positive for security posture. Removes `SUPABASE_JWT_SECRET` from Soleur's blast radius — same class of secret as `SUPABASE_SERVICE_ROLE_KEY` but one less surface (per issue body §1). The remaining service-role exposure is unchanged. No new attack surface introduced.

### Compliance/Legal (CLO) — carry-forward from PR-B

**Status:** carry-forward
**Assessment:** Substrate change does NOT affect Art. 30 records of processing, DSAR export shape, or audit retention. `auth.audit_log_entries` writes increase but those rows are inside `auth.*` schema managed by Supabase under their DPA — same legal posture as today's auth flow. No new Art. 9 special-category data. No new cross-controller transfer.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no user-facing UI/UX surface change. Infrastructure substrate swap behind unchanged public boundary (`getFreshTenantClient`).

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

This plan touches `apps/web-platform/supabase/migrations/047_custom_access_token_hook.sql` + `048_precheck_jwt_mint_sqlstate.sql` (DDL) and `apps/web-platform/lib/supabase/tenant.ts` (auth flow). Canonical regex matches. Brand-survival threshold = `single-user incident`. Both gates fire.

**Plan-time advisory findings** (subject to /work-time gdpr-gate skill execution):

- **TS-01 (Storage minimization):** Migration 047 adds **no new tables** — only the `runtime_jwt_mint_hook` function. Migration 048 is an in-place function replacement. No new founder-readable storage; no PII written.
- **AP-04 (Audit logging):** Existing migration 037 WORM audit unchanged. `auth.audit_log_entries` write volume increases per H3 above. No change to retention; bounded by Supabase's defaults (60d) which match PR-B's CLO carry-forward.
- **DL-01 (DSAR):** No new founder-readable data. DSAR export shape unchanged.

Gate is advisory; full execution at /work Phase 0.5 per skill convention.

## Infrastructure (IaC)

### Terraform changes

- **Conditional on Phase 3.2 outcome.** If Supabase provider supports `supabase_auth_config`, add `apps/web-platform/infra/supabase-auth.tf` resource pinning the required Auth settings.
- If not, **runbook update** at `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` documents the required Auth Settings panel state per Supabase project, with a follow-up tracking issue per `hr-all-infrastructure-provisioning-servers` and `wg-when-deferring-a-capability-create-a`.

### Apply path

- Migration 047: applied via existing `apps/web-platform/scripts/apply-migrations.mjs` flow (sibling of 037, see PR-B Phase 1.2.3). No `terraform apply` required.
- Doppler secret deletion: operator-acknowledged CLI per Phase 3.1.

### Distinctness / drift safeguards

- `dev != prd` Supabase projects per ADR-023 and `hr-dev-prd-distinct-supabase-projects`. Both environments execute the same migration; both lose `SUPABASE_JWT_SECRET` from Doppler.
- No `lifecycle.ignore_changes` needed (no in-place provider state to mask).

### Vendor-tier reality check

- Supabase Auth admin API is included in all paid tiers. Free tier limits apply per-project (auth.users count); not relevant here.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# (To be run at /work Phase 0 — files-to-edit list above, jq pipeline per Phase 1.7.5.)
```

Plan-time best estimate from PR-B / PR-C / PR-D / PR-E continuation:

- `tenant.ts` overlap with #3370 (default-privileges audit follow-up): **Acknowledge** — #3370 is a broader public-schema fn audit; this PR's narrow scope (substrate swap) does not bound it. The new `runtime_jwt_mint_hook` in migration 047 uses the REVOKE-from-PUBLIC/anon/authenticated/service_role + GRANT-to-`supabase_auth_admin` pattern (the hook-invoker role); migration 048's `precheck_jwt_mint` retains its existing GRANT to `service_role`. #3370 is a separate audit motion.
- No other known open code-review issues touch `tenant.ts` or `precheck_jwt_mint`.

(Verified during plan-review pass; this section will be re-run mechanically by the plan skill's Phase 1.7.5.)

## Risks

- **Supabase Auth admin API rate limits.** Original plan's "30/5min/user" was incorrect. Reality (per deepen-pass research): `RATE_LIMIT_TOKEN_REFRESH` default is **10/IP/hour** (NOT per-user); `RATE_LIMIT_EMAIL_SENT` is **10/hour**. `generateLink` does NOT send email so EMAIL_SENT bypassed. `/auth/v1/verify` rate-limit is undocumented in current Supabase docs (the rate-limit table is in a partial that wasn't loaded). **The Phase 0.6 probe is load-bearing — if VERIFY trips < 60/hour/IP, our TTL/4 strategy may collide with the IP-shared budget when multiple founders are active concurrently.** Mitigation: precheck ceiling 60/hour canary; Phase 3.2 escalation path documents requesting a higher TOKEN_REFRESH via Supabase support.
- **Hook fires on EVERY auth flow.** The Custom Access Token Hook is project-wide — Dashboard login, password reset, and OAuth flows all invoke it. The hook's pass-through gate (`if authentication_method <> 'otp' → return claims unchanged`) MUST be load-bearing correct, OR all auth flows degrade together. Per the 5-agent panel directive, the hook does NOT include a `WHEN OTHERS` defensive catch — security-critical functions fail loud, propagating errors so the Node call site sees a 500 from Supabase Auth and raises `RuntimeAuthError("jwt_mint")` naturally. Defensive measures: `LANGUAGE plpgsql` with explicit type casts; Phase 1.5 migration test asserts the pass-through case (non-otp `authentication_method` returns claims byte-identical).
- **Hook drops `app_metadata`.** The hook receives `event->'claims'` and modifies a subset. If we use `jsonb_set` (additive) we keep existing claims; if we use `jsonb_build_object` we replace. **Phase 2.1 design uses `jsonb_set` — additive only.** A future plan that wants to STRIP claims (e.g., remove `email` from runtime JWTs for PII minimization) is a separate concern not addressed here. Documented in ADR-033 alternatives.
- **`auth.sessions` row growth.** `verifyOtp` creates one row per mint. At TTL/4 cache + ~10 concurrent founders: ~24 rows/hour/founder × 24h × 10 ≈ 5,760 rows/day → 40,320 rows/week. Bounded by Supabase's refresh-token TTL (default 7d); auto-cleaned by GoTrue. Track row count at #3363 follow-up if growth exceeds projection.
- **Cold-start latency.** First tenant query per session adds 200-500ms (generateLink+verifyOtp p95 from Phase 0.5). Below PR-B's 1s session-start SLO; subjective UX assessment N/A. PR-B's ALS lazy-fetch absorbs the hit — only one mint per session.
- **PKCE-flow concern (server-side only).** `supabase-js admin.generateLink` has a known PKCE-flow bug (issue supabase/auth-js#767, repo archived 2026-01-23) where the `action_link` lacks the `code` parameter. **This does NOT affect us** because we never consume `action_link` — we read only `properties.hashed_token` and pass it to a server-side `verifyOtp` call. No browser-PKCE handshake in our path. Documented to prevent a future implementer from "fixing" what isn't broken.
- **Hook-not-registered failure mode.** If the hook is unregistered (rollback, fresh Supabase project, Mgmt API misconfiguration), `verifyOtp` returns a JWT without our `jti` and without `aud=soleur-runtime`. Phase 2.8's `getServiceClient` init probe detects this and emits a Sentry event; Phase 2.2's `decodeJwtPayloadUnsafe`-then-throw is the runtime catch. Two defenses, both observable.
- **Supabase asymmetric keys not yet enabled on prd.** If prd has asymmetric keys disabled and we ship this code, every mint returns HS256-signed JWTs (which PostgREST still verifies via the legacy JWT secret — same secret we're removing from Doppler — so the system breaks twice). Phase 0.1 verifies dev; Phase 5.1 verifies prd before shipping. Phase 5.1 is the gate; if prd is not asymmetric-enabled, do NOT merge — enable first (1-click no-downtime per Supabase rotation guarantee).
- **Supabase Auth API behavior drift.** `generateLink` + `verifyOtp` are not officially stable for admin-impersonation use (per supabase/discussions #11854 — "Unanswered" as of 2026). We're using a community-discovered pattern. Mitigation: ADR-033 captures exact API endpoints + auth-header shape; rollback path documented (revert merge + re-add `SUPABASE_JWT_SECRET` to Doppler from password-manager-archived copy). The pattern has worked since 2023; deprecation risk is low but non-zero.
- **Tenant-provisioning runbook drift.** Adding the hook-registration step to the runbook does NOT update existing prd or dev projects — those are one-time-already-provisioned. The runbook update is forward-looking for any future Supabase project provisioning. Phase 5.1 explicitly enables + registers the hook on prd as part of this PR's deploy sequence.

## Sharp Edges

- **Hook + precheck atomicity.** The `runtime_jwt_mint_hook` calls `precheck_jwt_mint` synchronously from inside the auth-issuance transaction. If the hook is replaced by a tier-1 implementer with `BEGIN; CALL precheck; COMMIT;` thinking, they break atomicity — the hook IS the transaction boundary; Postgres function bodies run in the caller's transaction. Code review must reject any subtransaction or `pg_background` substitution.
- **`verifyOtp` accepts `type: "email"`, NOT `type: "magiclink"`.** Original plan body was wrong on this; corrected at Phase 2.2. The `magiclink` literal works for `generateLink` (to indicate which template to use) but is deprecated for `verifyOtp`. A future contributor reading the Supabase docs page in isolation will be confused by this asymmetry — the inline comment in Phase 2.2's pseudocode is load-bearing for that confusion.
- **`@supabase/supabase-js` v2.49 vs. future versions.** The `admin.generateLink({type:"magiclink"})` shape is stable since v2.0. If someone bumps the SDK during /work, verify the call shape against the new version's TypeScript types (per `2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`): `grep -A20 "generateLink" node_modules/@supabase/supabase-js/dist/module/lib/GoTrueAdminApi.d.ts`.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Pro-forma: this plan's `User-Brand Impact` is filled with `single-user incident` threshold; CPO sign-off carry-forward from PR-B applies.)
- **Required claims that can't be removed.** Supabase Auth's hook spec forbids removing `iss, aud, exp, iat, sub, role, aal, session_id, email, phone, is_anonymous` — attempting to drop any of these returns HTTP 500 from the hook invocation. Migration 047's `jsonb_set` is additive; we OVERWRITE only `jti`, `exp`, `iat`, `role` (already-present required claims). Verify in the migration test that the hook output's claim list is a superset of input.
- **Hook gate channel pre-committed.** Phase 0.4 pre-commit decision: the hook gates on `event->>'authentication_method' = 'otp'`. The `aud` claim is set inside the hook (not injected from Node). If a future probe surfaces a case where `authentication_method` is something other than `'otp'` on the verifyOtp path (Supabase Auth API drift), the gate must be updated and migration 049 issued. Plan-review reviewers should treat the `authentication_method` value as the load-bearing contract with GoTrue.
- **Latency probe at Phase 0.5 is the gate.** If p95 > 1s, plan deviates: introduce session-warmup mint on WebSocket connect (deferred to scope-out for V2 if observed).
- **Hook function PR-B `precheck_jwt_mint` signature drift.** Per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`: if migration 047 changes the `precheck_jwt_mint` signature (it shouldn't, but a future iteration might), all consumers must be updated in the SAME PR — currently `tenant.ts:175` calls `service.rpc("precheck_jwt_mint", {p_founder_id, p_ttl_sec})`. After this PR, that call site disappears (the hook owns the call). The signature contract becomes: `precheck_jwt_mint(uuid, int) → TABLE(jti uuid, exp_epoch int, iat_epoch int)`, called only from `runtime_jwt_mint_hook`. Document the contract change in ADR-033.
- **`auth.users` email lookup is the new dependency.** `resolveFounderEmail` is the only NEW Node-side caller of `service.auth.admin.getUserById`. If a founder's email is changed via Supabase Dashboard or auth.admin.updateUserById, the cached email in `tenant.ts`'s `Map<UserId, string>` goes stale. Cache invalidation happens on process restart only. For the closed-preview alpha this is acceptable; for V2 (multi-tenant prod), add a TTL or eviction-on-error.
- Plan-prescribed CLI invocations (`doppler secrets delete`, `gh secret delete`, Supabase Auth admin `curl` form, JWKS endpoint): the `--plain` flag, the `apikey`+`Authorization` dual header on the Auth API, and the `.well-known/jwks.json` endpoint path are all verified by live web-fetches against Supabase's documentation during the deepen pass. <!-- verified: 2026-05-18 via WebFetch against supabase.com/docs/guides/auth/signing-keys and other Supabase doc pages -->
- **Citations live-verified:** `gh issue view 3244` (umbrella, OPEN), `gh pr view 3395` (PR-B, MERGED), `gh issue view 3370` (default-privileges audit, OPEN), `git log --grep="#3854"` (PR-C, MERGED), `git log --grep="#3883"` (PR-D, MERGED), `git log --grep="#3922"` (PR-E, MERGED). No fabricated PR numbers or memory-derived attributions. <!-- verified: 2026-05-18 -->
- **AGENTS.md rule citations.** This plan cites: `hr-menu-option-ack-not-prod-write-auth`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-dev-prd-distinct-supabase-projects`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-weigh-every-decision-against-target-user-impact`, `hr-all-infrastructure-provisioning-servers`, `cq-pg-security-definer-search-path-pin-pg-temp`, `cq-test-fixtures-synthesized-only`, `cq-union-widening-grep-three-patterns`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-when-deferring-a-capability-create-a`. All cross-checked against AGENTS.md index. No retired or fabricated IDs.

## Why now / Why this scope

PR-B (#3244) chose Resolution A explicitly knowing the HS256 substrate was an operational footgun; the planned-removal note lives at `tenant.ts:11-14`. PR-C/PR-D/PR-E continuation work has now shipped, the tenant-isolation contract is proven, and the alpha threat model has moved from "operator-trusted, no public attack surface" to "preparing for closed-preview growth". The substrate swap is the natural next hardening step:

- It removes a secret class from Soleur's process env.
- It eliminates a manual operator step from new-project provisioning.
- It moves Soleur closer to Supabase's default auth posture (which simplifies future auth-related vendor swaps).

Not blocking on PR-F (Inngest IaC, #3960/#3973 just landed) or PR-G (DSAR export substrate, future). This PR is self-contained substrate work behind an unchanged public boundary.
