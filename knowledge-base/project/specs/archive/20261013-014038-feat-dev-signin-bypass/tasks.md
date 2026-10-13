---
title: "Tasks — feat-dev-signin-bypass"
spec: 2026-05-07-feat-dev-signin-bypass-plan.md
branch: feat-dev-signin-bypass
created: 2026-05-07
---

# Tasks — Dev-Only Sign-In Bypass

Derived from `knowledge-base/project/plans/2026-05-07-feat-dev-signin-bypass-plan.md`. Sequence is load-bearing — do not reorder. Each numbered group lands as one commit; the whole plan ships in one PR.

## Setup (lands first — eliminates leak windows before code that could leak)

1.1 — Sentry redaction ✓
- [x] 1.1.1. Add `DEV_USER_{1,2,3}_PASSWORD` to `apps/web-platform/server/sensitive-keys.ts` `SENTRY_SENSITIVE_KEYS` (canonical redaction list; `sentry.server.config.ts` `beforeSend` delegates to `scrubSentryEvent` which reads this list — the plan's "edit `sentry.server.config.ts`" was a paraphrase resolved to the actual codebase pattern).
- [x] 1.1.2. Existing Sentry tests pass; added explicit `DEV_USER_*_PASSWORD` redaction-at-depth assertion.
- [x] 1.1.3. Commit: `chore: sentry redaction for dev-signin env vars` (db99dd6c).

1.2 — Preflight prd invariant ✓
- [x] 1.2.1. Edit `verify-required-secrets.sh`: prd-invariant block exits non-zero if any of `FLAG_DEV_SIGNIN` or `DEV_USER_{1,2,3}_PASSWORD` is set.
- [x] 1.2.2. Verified locally: forbidden present → exit 1; absent → exit 0 + notice.
- [x] 1.2.3. Commit: `chore: preflight prd invariant for dev-signin keys` (f25bf6bf).

## Core Implementation

2.1 — TDD harness ✓
- [x] 2.1.1. `test/auth/dev-mode.test.ts` — 5 cases.
- [x] 2.1.2. `test/auth/dev-signin-route.test.ts` — 11 cases incl. cookie-writer regression (`/sb-[a-z0-9]+-auth-token=/` + Location pathname `/`). Vitest stubEnv pattern (TS strict-readonly NODE_ENV).
- [x] 2.1.3. RED verified — 11 tests fail at module import (route doesn't exist yet).
- [x] 2.1.4. Commit: `test: failing harness for dev-signin gate` (9e0e0872).

2.2 — Feature flag + dev-mode helper ✓
- [x] 2.2.1. `"dev-signin": "FLAG_DEV_SIGNIN"` added to `FLAG_VARS`; `getFeatureFlags` test updated for 3-flag dictionary.
- [x] 2.2.2. `lib/auth/dev-mode.ts` exports `isDevSignInEnabled()`; gate inside function body.
- [x] 2.2.3. dev-mode + feature-flags tests pass.
- [x] 2.2.4. Commit: `feat: dev-mode gate helper + FLAG_DEV_SIGNIN` (f2d604c0).

2.3 — Login page refactor ✓
- [x] 2.3.1. `components/auth/login-form.tsx` ("use client") — verbatim move of prior page body.
- [x] 2.3.2. `app/(auth)/login/page.tsx` rewrites to async server component wrapping LoginForm in Suspense.
- [x] 2.3.3. (Deferred to operator runbook — full E2E OTP flow needs live Supabase.)
- [x] 2.3.4. `next build` (production mode) succeeded with zero new warnings.
- [x] 2.3.5. Commit: `refactor: extract <LoginForm /> from login page` (c9685c37).

2.4 — Route handler + helpers (cookie-aware redirect) ✓
- [x] 2.4.1. `_helpers.ts` exports `slotSchema`, `getEmailForSlot`, `getPasswordForSlot`, `DevSlot` type. Underscore-prefixed module excluded from App Router routing per Next convention; route file remains HTTP-handlers-only per `cq-nextjs-route-files-http-only-exports`.
- [x] 2.4.2. `route.ts` POST: NODE_ENV literal → 404, isDevSignInEnabled → 404, validateOrigin → 403 (CSRF gate from `lib/auth/csrf-coverage.test.ts`), Zod slot parse → 400, missing password → 500 ("dev sign-in misconfigured" — env-var key NOT in body), redirect-FIRST → cookies.setAll wires onto `response.cookies` → `signInWithPassword` → return response.
- [x] 2.4.3. dev-signin-route.test.ts — 12 tests pass incl. cookie-writer regression (`sb-<ref>-auth-token` matches) and CSRF 403.
- [x] 2.4.4. Commits: `feat: POST /api/auth/dev-signin with cookie-aware redirect` (d8ba5f6f) + follow-up `fix(api): add validateOrigin CSRF gate to dev-signin route` (d7a4bce7).

2.5 — Panel + login integration ✓
- [x] 2.5.1. `components/auth/dev-sign-in-panel.tsx` — server component, two inline gates (NODE_ENV literal + getFlag) at top of body, three slot forms inside `<Card>` reusing existing `bg-soleur-*` palette.
- [x] 2.5.2. `app/(auth)/login/page.tsx` renders `<DevSignInPanel />` above `<Suspense><LoginForm /></Suspense>`.
- [x] 2.5.3-2.5.5. Operator-runbook verifications (deferred to post-merge runbook in README.md).
- [x] 2.5.6. Commit: `feat: <DevSignInPanel /> + login page integration` (872b742a).

2.6 — CI grep gate ✓ (with documented scope adjustment)
- [x] 2.6.1. `scripts/assert-dev-signin-eliminated.sh` greps for the listed forbidden tokens. **Scope adjustment** (deviation from the literal task line; aligns with the plan's "Honest framing" paragraph): scans `.next/static/**` (client chunks + maps) and `.next/server/server-reference-manifest.js` only. App Router compiles route handlers into `.next/server/**` UNCONDITIONALLY — the dev-signin route is by design in the server bundle and the load-bearing defenses against server-side residual are the request-time NODE_ENV literal + Doppler-prd-absence preflight. The CLIENT-leak threat (a future refactor pulling the panel into a shared client module) is what this gate catches. Token list also tightened: bare `dev-signin` replaced with quoted `"dev-signin"` to suppress false positives from worktree paths whose names contain the feature-branch substring (pdfjs-dist's `createRequire(file:///...)` bakes the absolute build path into a client chunk).
- [x] 2.6.2. Wired into the Dockerfile builder stage immediately after `RUN npm run build` — fails the prd image build on any hit.
- [x] 2.6.3. Local prd build verified clean (zero hits in `.next/static/**` + RSC manifest).
- [x] 2.6.4. Commit: `chore: post-build grep for dev-signin token leakage` (582c8df3).

2.7 — Docs + env example ✓
- [x] 2.7.1. `.env.example` has the `# Dev-only — DO NOT SET IN PRD` block.
- [x] 2.7.2. `README.md` adds "Dev-only sign-in panel" section with seed-script command, length-only verification, prd-absence check, and the Vercel-preview-NODE_ENV invariant.
- [x] 2.7.3. Commit: `docs: dev-signin panel local-dev guide` (97125563).

2.8 — Seed script ✓
- [x] 2.8.1. `scripts/seed-dev-users.sh` — DOPPLER_CONFIG=dev assertion, JWT-ref-vs-URL-host check, slots 1..3 loop, idempotent (existing user → PUT password refresh; new user → POST with email_confirm). Local refusal verified for prd config and ref-mismatch.
- [x] 2.8.2. Operator-side runbook documented in README.md.
- [x] 2.8.3. Commit: `feat: seed-dev-users.sh (multi-user)` (47f53858).

## Testing

3.1 — Pre-merge verification ✓
- [x] 3.1.1. `vitest test/auth/dev-mode.test.ts` — 5/5 pass.
- [x] 3.1.2. `vitest test/auth/dev-signin-route.test.ts` — 12/12 pass (cookie-writer + CSRF regression).
- [x] 3.1.3. `vitest lib/feature-flags/` — 9/9 pass.
- [x] 3.1.4. `NODE_ENV=production npm run build` — succeeded.
- [x] 3.1.5. `bash scripts/assert-dev-signin-eliminated.sh` — exits 0 against the prd build.
- [x] 3.1.6. `bash scripts/service-role-allowlist-gate.sh` — 18 importer(s), unchanged.
- [x] 3.1.7. Pending PR-creation step (handled by `/ship`).
- [x] 3.1.8. Full vitest suite: 3786 passed | 36 skipped (3822) — zero failures.
- [x] 3.1.9. `tsc --noEmit` clean.

3.2 — Review-time
- 3.2.1. `user-impact-reviewer` agent invoked, approves.
- 3.2.2. `security-sentinel` agent invoked, approves the diff.
- 3.2.3. CodeQL/SAST scan: no new findings on auth surface.

3.3 — Post-merge operator
- 3.3.1. Operator sets dev-side env vars via Doppler (separate terminal). Length-only verification.
- 3.3.2. Operator runs seed script. Three users in dev Supabase confirmed via dashboard.
- 3.3.3. Operator confirms prd-side absence: `doppler secrets -p soleur -c prd | grep -E "^(FLAG_DEV_SIGNIN|DEV_USER_)"` returns nothing.
- 3.3.4. Operator runs end-to-end dev-signin flow locally, confirms authenticated session.
- 3.3.5. Operator verifies `vercel env ls preview`: `NODE_ENV` unset (default = production), `FLAG_DEV_SIGNIN` absent.

## Critical Traps (read before /work)

- **Cookie-writer (R3):** construct `NextResponse.redirect()` BEFORE the supabase client; pass `cookies.setAll` that calls `response.cookies.set`. Otherwise authenticated server-side, logged out client-side, middleware bounces back to `/login`.
- **Strict `=== "development"`:** never `!== "production"` (fires under `NODE_ENV=test`).
- **No module-top throws:** every gate inside a function body.
- **Refactor before panel:** task 2.3 lands its own commit; task 2.5 builds on top.
- **Operator secrets via separate terminal:** never via `! ` shell prefix (`hr-never-paste-secrets-via-bang-prefix`).
- **`Ref #3184`, not `Closes`:** the OTP-extraction overlap stays open.
