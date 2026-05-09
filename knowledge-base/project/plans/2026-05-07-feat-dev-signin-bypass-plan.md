---
title: "feat: dev-only sign-in bypass for multi-account QA"
type: feature
created: 2026-05-07
branch: feat-dev-signin-bypass
classification: app-only
requires_cpo_signoff: true
review_at_pr: user-impact-reviewer, security-sentinel, architecture-strategist, code-simplicity-reviewer
related: R1 (Resend custom SMTP) — separate plan, parallel PR
---

# feat: dev-only sign-in bypass for multi-account QA

## Overview

Eliminate developer friction caused by Supabase's built-in email-OTP rate limit (~4/hr on free tier) when testing multiple-account flows by adding a dev-only "Sign in as test user" panel to the login page. The panel renders only in local dev (strict `NODE_ENV === "development"` check) when a server-side feature flag is enabled, and lets developers one-click authenticate as one of three pre-seeded test users (`dev-1@example.com`, `dev-2@example.com`, `dev-3@example.com`) using passwords stored in Doppler `dev` config.

**Solves:** the screen at `apps/web-platform/lib/auth/error-messages.ts:18` ("Too many sign-in attempts. Please wait a few minutes and try again.") that blocks devs mid-QA when their OTP send rate exceeds Supabase's project-wide cap.

**Out of scope (parallel plan):** R1 — Resend custom SMTP + DNS + Supabase rate-limit raise. That fixes the underlying cap for production users; R3 (this plan) fixes the dev-loop ergonomic.

## Research Reconciliation — Spec vs. Codebase

| Spec / Brief Claim                                                | Reality (file:line)                                                                                  | Plan Response                                                                                                          |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `signInWithOtp` lives at `app/(auth)/login/page.tsx:45`           | Actual: `app/(auth)/login/page.tsx:51` (line 45 is `handleSendOtp` declaration)                      | Plan cites `:51` everywhere.                                                                                           |
| Use `@soleur.test` for test emails                                | Codebase convention is `@example.com` (RFC 2606 reserved); `@soleur.test` not used in `web-platform` | Plan uses `dev-1@example.com` etc.                                                                                     |
| Use `NODE_ENV !== "production"` for dev gate                      | Codebase + learning `2026-04-13-supabase-env-var-dev-mode-graceful-degradation` require `=== "development"` — `!= "production"` fires under `NODE_ENV=test` and breaks SDK-mocked suites | Plan uses strict `=== "development"` literal everywhere.                                                                |
| Use a new server action for dev sign-in                           | Codebase has **zero** `"use server"` server actions; pattern is API routes (`app/api/**/route.ts`)   | Plan uses an API route at `app/api/auth/dev-signin/route.ts`.                                                          |
| Use raw env-var lookups for the gate flag                         | Canonical pattern is `lib/feature-flags/server.ts` `FLAG_VARS` table with `=== "1"` strict-truthy    | Plan adds `dev-signin: "FLAG_DEV_SIGNIN"` to `FLAG_VARS`. Reuses existing `getFlag()`.                                 |
| Build a Node `seed-dev-users.ts` script                           | Closest precedent is bash `scripts/seed-qa-user.sh` using `curl + python3` against `auth/v1/admin/users` REST | Plan extends that pattern: bash `scripts/seed-dev-users.sh` (idempotent, multi-user) modeled on the existing precedent. |
| `app/(auth)/login/page.tsx` can be flipped to a Server Component  | The file is `"use client"` and uses `useSearchParams`/`useRouter`/`useState`/`useEffect`/`useRef` — every hook a server component cannot use | Plan extracts the body to `components/auth/login-form.tsx` (`"use client"` stays); new `page.tsx` is async server component that renders `<DevSignInPanel />` then `<LoginForm />`. Refactor lands in its own commit before the panel. |
| `instrumentation.ts` is the Sentry `beforeSend` edit target       | `beforeSend` actually lives in `apps/web-platform/sentry.server.config.ts` (verified at line 12)     | Plan edits `sentry.server.config.ts`.                                                                                  |
| Service-role import — no allowlist concern                        | `.service-role-allowlist` + `service-role-allowlist-gate.sh` (PR-B) gate any `createServiceClient` import | Plan uses bash + curl in the seed script (no TS import) and anon-key + password in the runtime route — neither requires an allowlist entry. |

## User-Brand Impact

**If this lands broken, the user experiences:** an unauthenticated visitor on `https://soleur.ai/login` sees buttons reading "Sign in as dev-1" and clicks one → authenticated session as `dev-1@example.com`. This requires three independent gates to fail simultaneously: (1) the build-time `NODE_ENV === "development"` literal does not eliminate the panel server-rendering, AND (2) `FLAG_DEV_SIGNIN=1` is set in the prd Doppler config, AND (3) the prd Supabase project contains a `dev-N@example.com` user (`hr-dev-prd-distinct-supabase-projects` violation). Each gate has its own enforcement point; one gate failing is detected by routine CI, two failing requires a Doppler config typo plus a forgotten preflight, three failing means the entire enforcement chain has been bypassed.

**If this leaks, the user's data is exposed via:** any clicker of the visible button → authenticated session as `dev-1@example.com` → reads whatever rows RLS lets a `dev-1` session read in the prd Supabase project. Bounded blast radius if (3) holds (no `dev-N` users exist in prd by construction); unbounded if (3) fails.

**Concrete artifacts the dev-1 session would expose if (3) failed AND a permissive RLS policy exists:** `auth.users.email`, `public.users.email/workspace_path/repo_status/tc_accepted_*`, `public.conversations.*`, `public.messages.body/role`, `public.api_keys.encrypted_key/iv/tag` (BYOK envelope — `auth_tag` shape is enumerated in `apps/web-platform/server/sensitive-keys.ts`). Mitigation per artifact: existing RLS policies in `apps/web-platform/supabase/migrations/**` scope every cross-tenant read with `auth.uid() = user_id` predicates. Verify before merge: no migration on this branch widens an `authenticated` role policy. (`git diff origin/main...HEAD -- apps/web-platform/supabase/` returns zero hits for this branch.)

**Brand-survival threshold:** `single-user incident` — the threshold is set per `hr-weigh-every-decision-against-target-user-impact` for any auth-touching change; the chain-of-three-gates makes a true incident unlikely but the framework treats auth-bypass discoverability as the gate, not the realized exploit.

**Layer-A is build-time-baked (not runtime-overridable):** Next.js's SWC compiler inlines `process.env.NODE_ENV` to a string literal at `next build` time via DefinePlugin equivalence. The compiled `.next/server/app/api/auth/dev-signin/route.js` carries the literal `"production" !== "development"` (always true), short-circuiting before flag/CSRF/Zod evaluation. A runtime `docker run -e NODE_ENV=development` against the prd image does NOT re-introduce the dev path — Layer A is **immutable post-build**. The Dockerfile additionally sets `ENV NODE_ENV=production` for the runner stage as belt-and-suspenders for any non-Next.js code reading the variable at runtime.

**Telemetry side-channel (acknowledged, scope-out):** post-Layer-A the route returns three distinct 5xx/4xx bodies (`"dev sign-in misconfigured"`, `"invalid slot"`, `"dev sign-in failed"`). An attacker who somehow bypassed Layer A (only via downgrading the prd image — Layer A is build-time-baked per above) could probe `slot=1..3` and partially diagnose Doppler state. Accepted scope-out: Layer A is the load-bearing gate; once it fails, full session bypass is the exposure, not body disambiguation. Collapsing all 5xx to 404 would harm dev usability (operators rely on the bodies to debug FLAG/Doppler typos).

**Doppler config-coverage scope:** the `verify-required-secrets.sh` forbidden-in-prd block runs against the `prd` config only. Other Doppler configs (`ci`, `prd_terraform`) are **out of scope** because they don't drive the public web runtime: `ci` config feeds vitest under `NODE_ENV=test` (Layer A returns 404 regardless), and `prd_terraform` configures Hetzner provisioning (no Next.js runtime). If a future preview/staging Doppler config is introduced that DOES drive a public-reachable Next.js host, extend the gate in the same PR.

**Sign-off chain:**
- Plan-time: CPO sign-off **required** (this plan; advisory captured in `## Domain Review` below).
- Review-time: `user-impact-reviewer` agent **required** per `hr-weigh-every-decision-against-target-user-impact`. `security-sentinel` re-runs on the diff.
- Ship-time: preflight Check 6 verifies this section is non-empty + `threshold` is valid.

## Domain Review

**Domains relevant:** Product (BLOCKING — modifies `app/(auth)/login/page.tsx`), Engineering (security-sentinel — auth surface).

### Product (CPO advisory — captured at plan time)

**Status:** reviewed
**Assessment:** Conditional sign-off, conditions folded into the plan: (e) CI build-output grep for forbidden tokens; (f) preflight assertion that `FLAG_DEV_SIGNIN` is absent in Doppler `prd`. CPO's tracking-issue list (multi-account harness, lifecycle policy, preview deploys, CODEOWNERS pin) was reviewed by plan-review and dropped — none was a deferral of in-scope work, all four were speculative.

### Engineering — security-sentinel (advisory captured at plan time)

**Status:** reviewed
**Highest-severity finding (P0):** Server-side endpoints (whether server actions or API routes) are stable RPC entry points compiled into `.next/server/`. A runtime `if (NODE_ENV !== "development") return 404` check is fail-open if `FLAG_DEV_SIGNIN=1` is ever set in prd Doppler. **Mitigation woven into plan:** triple-defense — (i) build-time `process.env.NODE_ENV === "development"` literal at the top of every dev-only module (Next.js webpack DefinePlugin replaces and DCEs the body in client bundles; for server bundles the literal still short-circuits at request time); (ii) `getFlag("dev-signin")` runtime check before any side effect; (iii) preflight-asserted Doppler `prd` invariant that `FLAG_DEV_SIGNIN` is absent. Plus (iv) post-`next build` CI grep for forbidden source-level identifiers.

**Other findings folded into Acceptance Criteria & Risks:**
- P1-2: Sentry/pino redaction — add `DEV_USER_*_PASSWORD` to `Sentry.beforeSend` env-var redaction in `sentry.server.config.ts`.
- P1-4: Strict Zod literal-union for `slot` parameter (`z.union([z.literal(1), z.literal(2), z.literal(3)])`).
- P0-3: Seed script asserts (a) `DOPPLER_CONFIG === "dev"`, (b) JWT `ref` claim from `SUPABASE_SERVICE_ROLE_KEY` matches the host in `NEXT_PUBLIC_SUPABASE_URL`. Three Doppler-derived signals agreeing is stronger than a static pinned file.

### Product/UX Gate

**Tier:** blocking (mechanical escalation: new file at `components/auth/dev-sign-in-panel.tsx`).
**Decision:** reviewed (partial)
**Agents invoked:** cpo, security-sentinel
**Skipped specialists:** ux-design-lead — internal dev-only panel never visible to end users; aesthetic conformance to the existing login page is achieved by reusing the same `<Button>` and `<Card>` primitives. User explicitly approved the R3 direction in the preceding `/soleur:go` exchange.
**Pencil available:** N/A (skipped).

## Open Code-Review Overlap

1 open scope-out touches files in this plan's edit list:

- **#3184: review: extract useOtpFlow hook + OtpCodeStep component (login/signup duplication)** — overlaps `app/(auth)/login/page.tsx`.

**Disposition: Acknowledge.** R3 extracts the existing `"use client"` body to a sibling `<LoginForm />` component, then adds a `<DevSignInPanel />` above it in a new server-rendered `page.tsx`. R3 does not modify the OTP flow logic, the `signInWithOtp` call site, or the `handleVerifyOtp` handler — those move verbatim into `<LoginForm />`. #3184 stays open and remains tractable; a future refactor can extract `useOtpFlow` from `<LoginForm />` cleanly.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  apps/web-platform/app/(auth)/login/page.tsx   (async server)      │
│                                                                    │
│  1. Server: await isDevSignInEnabled()                             │
│  2. If true: render <DevSignInPanel /> (server component)          │
│  3. Always: render <LoginForm /> (client — current code, extracted)│
└──────────┬─────────────────────────────────────────────────────────┘
           │  user clicks "Sign in as dev-N" — vanilla form POST
           ▼
┌────────────────────────────────────────────────────────────────────┐
│  POST /api/auth/dev-signin                                          │
│  apps/web-platform/app/api/auth/dev-signin/route.ts                 │
│                                                                    │
│  Layer A:  if (NODE_ENV !== "development") return 404               │
│  Layer B:  if (!getFlag("dev-signin"))     return 404               │
│  Layer C:  parse body via slotSchema (Zod)                          │
│  Layer D:  password = getPasswordForSlot(slot); if missing → 500    │
│  Layer E:  const response = NextResponse.redirect(new URL("/", req))│
│            const supabase = createServerClient(url, key, {          │
│              cookies: {                                             │
│                getAll: () => req.cookies.getAll(),                  │
│                setAll: cs => cs.forEach(c =>                        │
│                  response.cookies.set(c.name, c.value, c.options))  │
│              }                                                      │
│            })                                                       │
│            await supabase.auth.signInWithPassword({email, password})│
│            return response                                          │
└────────────────────────────────────────────────────────────────────┘

  Doppler  config        keys present
  ──────────────────────────────────────────────────────────────────
  dev      FLAG_DEV_SIGNIN=1, DEV_USER_1_PASSWORD..3
  prd      (none of the above — preflight invariant proves absence)

  Supabase project        seeded users
  ──────────────────────────────────────────────────────────────────
  dev project ref         dev-1@example.com, dev-2@.., dev-3@..
  prd project ref         (none — seed script refuses to run on prd)
```

**Honest framing of the layered defense:** Webpack DefinePlugin + DCE works on **client** bundles — not server bundles. Server components and API routes ship to the Node server runtime regardless. The load-bearing gates are the runtime `NODE_ENV === "development"` literal at the top of each entry point + the `getFlag("dev-signin")` check + the prd-Doppler-absence preflight. The post-build grep is a tripwire that catches future refactors leaking dev-only symbols into shared client code.

## Files to Edit

- `apps/web-platform/app/(auth)/login/page.tsx` — currently `"use client"`. Convert to `async function Page()` (server component); imports `<DevSignInPanel />` (conditionally rendered) and `<LoginForm />` (current body, extracted).
- `apps/web-platform/lib/feature-flags/server.ts` — add `"dev-signin": "FLAG_DEV_SIGNIN"` to `FLAG_VARS`.
- `apps/web-platform/.env.example` — document `FLAG_DEV_SIGNIN`, `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD` under a `# Dev-only — DO NOT SET IN PRD` section.
- `apps/web-platform/sentry.server.config.ts` — extend the `beforeSend` env-var redaction to include `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD`.
- `apps/web-platform/scripts/verify-required-secrets.sh` (or sibling preflight) — add prd-invariant block: assert `FLAG_DEV_SIGNIN`, `DEV_USER_1_PASSWORD..3` are NOT set in Doppler `prd`. Exit non-zero if any present.
- `apps/web-platform/README.md` — document the dev-signin panel under "Local development" with the seed-script command and the verification steps.

## Files to Create

- `apps/web-platform/components/auth/login-form.tsx` — `"use client"`. Receives the entire current body of `app/(auth)/login/page.tsx` verbatim (state, hooks, form handlers, JSX). Wrapped in `<Suspense>` at the call site because it uses `useSearchParams`.
- `apps/web-platform/components/auth/dev-sign-in-panel.tsx` — async server component. First line of body: `if (process.env.NODE_ENV !== "development") return null;` then `if (!getFlag("dev-signin")) return null;`. Returns three `<form action="/api/auth/dev-signin" method="post"><input type="hidden" name="slot" value={N} /><Button>Sign in as dev-N</Button></form>` blocks inside a `<Card>`.
- `apps/web-platform/lib/auth/dev-mode.ts` — server-only module exporting `isDevSignInEnabled(): boolean`. Body: `if (process.env.NODE_ENV !== "development") return false; return getFlag("dev-signin");`. Check is INSIDE the function — never at module top (per learning `2026-04-28-module-load-throw-collapses-auth-surface`). Two callers: route handler + login page.
- `apps/web-platform/app/api/auth/dev-signin/route.ts` — POST-only API route. Imports helpers from `_helpers.ts` sibling. Layered checks → cookie-aware redirect (see Architecture diagram).
- `apps/web-platform/app/api/auth/dev-signin/_helpers.ts` — exports `slotSchema` (`z.object({ slot: z.union([z.literal(1), z.literal(2), z.literal(3)]) })`), `getPasswordForSlot(slot: 1|2|3): string | undefined`, `getEmailForSlot(slot: 1|2|3): string`. Underscore-prefixed module is excluded from App Router routing per Next.js convention. Per `cq-nextjs-route-files-http-only-exports`, the route file itself only exports `POST`.
- `apps/web-platform/scripts/seed-dev-users.sh` — bash, mirrors `seed-qa-user.sh`. Usage: `doppler run -p soleur -c dev -- bash scripts/seed-dev-users.sh`. Idempotent.
  - Pre-flight assertions:
    1. `DOPPLER_CONFIG === "dev"` (Doppler injects this).
    2. JWT decode of `SUPABASE_SERVICE_ROLE_KEY`: extract `ref` claim, assert it matches the host prefix in `NEXT_PUBLIC_SUPABASE_URL` (e.g., URL `https://abc123.supabase.co` → host prefix `abc123` must equal JWT `ref` claim).
  - Read `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD` from env (set by the operator via Doppler, never by the script).
  - For each slot 1..3: `POST auth/v1/admin/users` with `{email, password, email_confirm: true}`. Treat 422 unique-constraint as success (idempotent). On existing user, `PUT` to refresh the password.
- `apps/web-platform/scripts/assert-dev-signin-eliminated.sh` — bash. Runs AFTER `next build` in CI's prd-mode build job. Greps `apps/web-platform/.next/server/**`, `apps/web-platform/.next/static/chunks/**`, `apps/web-platform/.next/**/*.map`, AND `apps/web-platform/.next/server/server-reference-manifest.js` for the forbidden-token list: `dev-1@example.com`, `dev-2@example.com`, `dev-3@example.com`, `DEV_SIGNIN`, `DEV_USER_`, `dev-sign-in-panel`, `isDevSignInEnabled`, `dev-signin`. Any hit → exit 1 with the offending file path. Wired into the existing prd-build CI job (NO separate workflow).
- `apps/web-platform/test/auth/dev-mode.test.ts` — vitest. Asserts `isDevSignInEnabled()` returns `false` when `NODE_ENV === "production"` regardless of flag, returns `false` when `NODE_ENV === "test"`, returns `false` when flag is unset in dev, returns `true` only when `NODE_ENV === "development"` AND flag set. Uses `vi.stubEnv`.
- `apps/web-platform/test/auth/dev-signin-route.test.ts` — vitest. Asserts the route returns 404 in production env, 404 in test env, 404 with flag unset, 400 on invalid slot, 500 on missing password env var (with the env-var key SCRUBBED from the error message), 303 on valid slot in dev with flag set. **Cookie-writer regression test:** asserts response has `Set-Cookie` header matching the Supabase auth-token pattern (`/sb-[a-z0-9]+-auth-token=/`) AND `Location: /`. Mocks Supabase client.

## Implementation Phases

### Phase 1 — Foundation (one PR, multiple commits)

1. **Sentry redaction first** (cheap, isolated, eliminates a leak window before the route ships): edit `sentry.server.config.ts` to add `DEV_USER_*_PASSWORD` to the env-var redaction list. Commit: `chore: sentry redaction for dev-signin env vars`.
2. **Preflight prd-invariant** (catches the highest-impact misconfig before the rest of the work lands): edit `verify-required-secrets.sh` to assert `FLAG_DEV_SIGNIN`/`DEV_USER_*_PASSWORD` absent in `prd`. Commit: `chore: preflight prd invariant for dev-signin keys`.
3. **TDD harness:** write `dev-mode.test.ts` and `dev-signin-route.test.ts` (with cookie-writer assertion) — all cases failing. Commit: `test: failing harness for dev-signin gate`.
4. **Flag + dev-mode helper:** add `"dev-signin"` to `FLAG_VARS`; create `lib/auth/dev-mode.ts`. `dev-mode.test.ts` passes; `feature-flags/server.test.ts` still passes. Commit: `feat: dev-mode gate helper + FLAG_DEV_SIGNIN`.
5. **Login page refactor (separate commit, reviewable in isolation):** extract current `app/(auth)/login/page.tsx` body verbatim to `components/auth/login-form.tsx` (`"use client"`). New `page.tsx` is async server component that wraps `<LoginForm />` in `<Suspense>` (still needed for `useSearchParams`). No behavioral change. Commit: `refactor: extract <LoginForm /> from login page`.
6. **Route handler + helpers:** create `_helpers.ts` and `route.ts` with the cookie-aware redirect pattern from Architecture. `dev-signin-route.test.ts` passes including cookie-writer regression test. Commit: `feat: POST /api/auth/dev-signin with cookie-aware redirect`.
7. **Panel + integration:** create `components/auth/dev-sign-in-panel.tsx`; render it from `page.tsx` above `<LoginForm />`. Verify locally: panel shows in dev with flag, hidden without flag, hidden in `next start` prd-mode build. Commit: `feat: <DevSignInPanel /> + login page integration`.
8. **CI grep gate:** create `assert-dev-signin-eliminated.sh`; wire into existing prd-build CI job (post-`next build` step). Run locally to confirm zero hits in current prd build. Commit: `chore: post-build grep for dev-signin token leakage`.
9. **Docs:** update `.env.example` and `README.md`. Commit: `docs: dev-signin panel local-dev guide`.

### Phase 2 — Operator runbook (post-merge, not a code phase)

Operator (separate terminal, never via `! ` prefix per `hr-never-paste-secrets-via-bang-prefix`):
- Sets in Doppler `dev`: `FLAG_DEV_SIGNIN=1`, `DEV_USER_1_PASSWORD=<random-32>`, `DEV_USER_2_PASSWORD=<random-32>`, `DEV_USER_3_PASSWORD=<random-32>`.
- Verifies presence via length-only check.
- Runs `doppler run -p soleur -c dev -- bash apps/web-platform/scripts/seed-dev-users.sh`.
- Confirms via `doppler secrets -p soleur -c prd | grep -E "^(FLAG_DEV_SIGNIN|DEV_USER_)" && echo FAIL || echo OK` → expects `OK`.
- Runs the dev-signin flow locally and verifies authentication.
- Verifies via `vercel env ls preview` that `NODE_ENV` is unset (Vercel default = production) AND `FLAG_DEV_SIGNIN` is absent.

### Phase 3 — Close-out

- File `Ref #3184` in PR body (acknowledge the OTP-extraction overlap).
- After merge, mark plan archived per `archive-kb` skill.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `dev-mode.test.ts`: returns `false` for production, test, and dev-without-flag; returns `true` only for development + flag set.
- [ ] `dev-signin-route.test.ts`: 404 in production, 404 in test, 404 without flag, 400 on invalid slot, 500 on missing password (error message scrubbed), 303 redirect with `Set-Cookie` matching `/sb-[a-z0-9]+-auth-token=/` AND `Location: /` on valid slot.
- [ ] `assert-dev-signin-eliminated.sh` runs in the existing prd-build CI job and exits 0 (zero forbidden-token hits) on a prd build of the current branch.
- [ ] Forbidden-token grep covers `dev-1@example.com`, `dev-2@example.com`, `dev-3@example.com`, `DEV_SIGNIN`, `DEV_USER_`, `dev-sign-in-panel`, `isDevSignInEnabled`, `dev-signin`.
- [ ] Grep scope: `apps/web-platform/.next/server/**`, `apps/web-platform/.next/static/chunks/**`, `apps/web-platform/.next/**/*.map`, `apps/web-platform/.next/server/server-reference-manifest.js`.
- [ ] `lib/feature-flags/server.test.ts`: passes with `dev-signin` added to `FLAG_VARS`.
- [ ] `service-role-allowlist-gate.sh` returns unchanged output (no new TS service-role import sites).
- [ ] `next build` (production mode) succeeds with zero new errors and zero new warnings.
- [ ] CodeQL / SAST scan returns no new findings on the auth surface.
- [ ] `## User-Brand Impact` section is non-empty and threshold = `single-user incident` (preflight Check 6).
- [ ] CPO sign-off recorded in `## Domain Review` (this section).
- [ ] `user-impact-reviewer` agent invoked at PR review time and approves.
- [ ] `security-sentinel` agent invoked at PR review time and approves the diff.
- [ ] `Ref #3184` in PR body (do NOT use `Closes`).
- [ ] Login page refactor (`<LoginForm />` extraction) and panel integration are in **separate commits** so the refactor is reviewable in isolation.

### Post-merge (operator)

- [ ] Operator sets `FLAG_DEV_SIGNIN=1`, `DEV_USER_{1,2,3}_PASSWORD` in Doppler `dev` (separate terminal).
- [ ] Operator verifies presence via length-only check: `for k in FLAG_DEV_SIGNIN DEV_USER_1_PASSWORD DEV_USER_2_PASSWORD DEV_USER_3_PASSWORD; do echo -n "$k: "; doppler secrets get "$k" -p soleur -c dev --plain | wc -c; done` — expects `2` for the flag and `≥32` for each password.
- [ ] Operator runs `doppler run -p soleur -c dev -- bash apps/web-platform/scripts/seed-dev-users.sh`. Asserts three users created/updated in dev Supabase.
- [ ] Operator confirms `doppler secrets -p soleur -c prd | grep -E "^(FLAG_DEV_SIGNIN|DEV_USER_)"` returns nothing.
- [ ] Operator runs `npm run dev`, opens `/login`, verifies the panel renders, clicks "Sign in as dev-1", lands on `/` authenticated.
- [ ] Operator verifies via `vercel env ls preview` that `NODE_ENV` is unset (Vercel default = production) AND `FLAG_DEV_SIGNIN` is absent in the preview environment.

## Test Scenarios

| Scenario                                                                  | Expected                                                                                  |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `NODE_ENV=production` + `FLAG_DEV_SIGNIN=1`                               | Panel hidden; route returns 404; CI grep finds no forbidden tokens.                       |
| `NODE_ENV=production` + flag unset                                        | Panel hidden; route returns 404.                                                          |
| `NODE_ENV=test` + `FLAG_DEV_SIGNIN=1`                                     | Panel hidden; route returns 404 (strict `=== "development"`).                              |
| `NODE_ENV=development` + flag unset                                       | Panel hidden; route returns 404.                                                          |
| `NODE_ENV=development` + `FLAG_DEV_SIGNIN=1` + valid slot                 | Panel renders; clicking slot-N → 303 with `Set-Cookie: sb-…-auth-token` AND `Location: /`. |
| Invalid `slot` (4, 0, "x")                                                | Route returns 400 with Zod error.                                                         |
| `slot=1` but `DEV_USER_1_PASSWORD` env var unset                          | Route returns 500; the env-var key is scrubbed from the error response and from Sentry.   |
| Two devs running the seed script simultaneously                           | Both succeed; `email_confirm: true` + 422-as-success makes the create idempotent.         |
| Seed script invoked with `DOPPLER_CONFIG=prd`                             | Refuses with non-zero exit; no Supabase write.                                            |
| Seed script with `SUPABASE_SERVICE_ROLE_KEY` ref ≠ URL host prefix        | Refuses with non-zero exit; no Supabase write.                                            |
| Operator pushes `FLAG_DEV_SIGNIN=1` to Doppler `prd` by mistake           | Next CI run of `verify-required-secrets.sh` exits non-zero, blocking deploy.              |

## Risks & Mitigations

| Risk                                                                                                                                                              | Severity | Mitigation                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1.** Dev-only artifact reaches production: `FLAG_DEV_SIGNIN=1` lands in prd Doppler, OR webpack inlines a dev path into a shared client chunk, OR a future refactor extracts the panel into a prd-imported module. | Critical | Layered runtime guards (NODE_ENV literal + `getFlag()` + Zod) — each fails closed independently. Preflight `verify-required-secrets.sh` blocks deploy if `FLAG_DEV_SIGNIN` is in prd. Post-build `assert-dev-signin-eliminated.sh` greps the prd build for forbidden source-level identifiers — tripwire for refactor leaks. |
| **R2.** Build output (including source maps) contains forbidden tokens (`dev-1@example.com`, identifier names) in the prd bundle.                                  | High     | `assert-dev-signin-eliminated.sh` grep scope explicitly includes `.next/**/*.map` AND `.next/server/server-reference-manifest.js`. CI fails if any token present. Considered alternative: disable `productionBrowserSourceMaps` globally — declined (debugging cost) since the grep covers them.                            |
| **R3.** Cookie-writer footgun: `NextResponse.redirect()` discards cookies set via `cookies()` from `next/headers`; user lands authenticated server-side but logged out client-side.                                       | High     | Architecture diagram + Files-to-Create explicitly specify constructing the `NextResponse` BEFORE the supabase client and passing a `setAll` that calls `response.cookies.set`. Cookie-writer regression test in `dev-signin-route.test.ts` asserts `Set-Cookie` matches the Supabase auth-token pattern. |
| **R4.** Password leaks to Sentry via an error event captured in the route handler.                                                                                | Medium   | Sentry `beforeSend` redaction list updated in commit 1 (lands BEFORE the route ships). Route handler explicitly scrubs the env-var key from any error message. Length-only verification in operator runbook prevents accidental leak via `! ` shell prefix. |

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 and `/preflight` Check 6.** This plan's section is filled.
- **Cookie-writer footgun (R3).** `cookies().set()` from `next/headers` writes onto the request bag, NOT the redirect response's `Set-Cookie` headers. The route MUST construct `const response = NextResponse.redirect(...)` first and pass a `cookies.setAll: cs => cs.forEach(c => response.cookies.set(c.name, c.value, c.options))` to `createServerClient`. If you skip this, the user lands authenticated-on-server, unauthenticated-in-cookies, middleware bounces them back to `/login`.
- **Webpack DCE applies to client bundles, not server.** The "panel returns null in prd" check is a runtime short-circuit — the panel module is still in the server bundle. The load-bearing defense layer is the runtime literal + the prd-Doppler-absence preflight. Don't reframe this as a bundling guarantee at /work or in PR description.
- **Login page refactor lands in its own commit.** The current file is `"use client"` with five hooks; it cannot be flipped to a server component. The body must move verbatim to `<LoginForm />`. Do not bundle the refactor commit with the panel commit — the refactor is reviewable in isolation, the panel commit is reviewable in isolation, mixing them blows up review surface.
- **Module-load throws collapse the auth surface** (learning `2026-04-28-module-load-throw-collapses-auth-surface.md`). Every gate check must be inside a function body. NEVER throw at module top.
- **`!= "production"` fires under `NODE_ENV=test`** and breaks SDK-mocked tests (learning `2026-04-13-supabase-env-var-dev-mode-graceful-degradation.md`). Use `=== "development"` strict literal everywhere.
- **App Router route file may only export HTTP handlers** (`cq-nextjs-route-files-http-only-exports`). The route file must NOT export Zod schemas or helpers — those live in `_helpers.ts` (underscore-prefixed module excluded from routing).
- **Operator must use a separate terminal for Doppler set commands** (`hr-never-paste-secrets-via-bang-prefix`). Verify presence with `wc -c` length-only.
- **Don't paraphrase file paths or line numbers from this plan during /work** — verify each in the worktree first (the brief had a `:45` vs `:51` drift; the plan corrected it via Research Reconciliation).

## Out of Scope

| #     | Deferred capability                                       | Tracking issue                                                                |
| ----- | --------------------------------------------------------- | ----------------------------------------------------------------------------- |
| IS-1  | Resend custom SMTP + Supabase rate-limit raise (R1)       | Tracked under the parallel R1 plan — not duplicated here.                     |

No other deferrals. Plan-review (DHH + simplicity) flagged speculative tracking issues (multi-account harness, lifecycle policy, preview-deploy support, CODEOWNERS pin) and cut all four — none was a deferral of in-scope work; if a real need emerges, file at that point.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-07-feat-dev-signin-bypass-plan.md
Branch: feat-dev-signin-bypass.
Worktree: /home/harry/Documents/Stage/Soleur/soleur/.worktrees/feat-dev-signin-bypass.
Plan reviewed (DHH + Kieran + simplicity, all 15 corrections applied).
Implementation order — Phase 1 (one PR, sequenced commits):
  1. Sentry redaction → 2. Preflight prd-invariant → 3. TDD harness →
  4. Flag+helper → 5. Login page refactor (own commit) →
  6. Route+helpers (cookie-aware redirect) → 7. Panel+integration →
  8. CI grep gate → 9. Docs.
Critical traps: cookie-writer wiring (R3), `=== "development"` strict literal,
no module-top throws, refactor before panel.
R1 (Resend SMTP) is a separate plan/PR — do NOT bundle.
```
