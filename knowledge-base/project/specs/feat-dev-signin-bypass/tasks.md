---
title: "Tasks — feat-dev-signin-bypass"
spec: 2026-05-07-feat-dev-signin-bypass-plan.md
branch: feat-dev-signin-bypass
created: 2026-05-07
---

# Tasks — Dev-Only Sign-In Bypass

Derived from `knowledge-base/project/plans/2026-05-07-feat-dev-signin-bypass-plan.md`. Sequence is load-bearing — do not reorder. Each numbered group lands as one commit; the whole plan ships in one PR.

## Setup (lands first — eliminates leak windows before code that could leak)

1.1 — Sentry redaction
- 1.1.1. Edit `apps/web-platform/sentry.server.config.ts`: extend `beforeSend` env-var redaction list with `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD`.
- 1.1.2. Verify existing Sentry tests pass.
- 1.1.3. Commit: `chore: sentry redaction for dev-signin env vars`.

1.2 — Preflight prd invariant
- 1.2.1. Edit `apps/web-platform/scripts/verify-required-secrets.sh`: add prd-invariant block — exit non-zero if any of `FLAG_DEV_SIGNIN`, `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD` is set in Doppler `prd`.
- 1.2.2. Run the script locally against current state — expect `OK`.
- 1.2.3. Commit: `chore: preflight prd invariant for dev-signin keys`.

## Core Implementation

2.1 — TDD harness (failing tests first per `cq-write-failing-tests-before`)
- 2.1.1. Create `apps/web-platform/test/auth/dev-mode.test.ts` — four cases (production×any-flag, test×any-flag, dev×flag-unset, dev×flag-set). All fail (file under test doesn't exist).
- 2.1.2. Create `apps/web-platform/test/auth/dev-signin-route.test.ts` — 404/400/500/303 cases including the cookie-writer regression (`Set-Cookie: /sb-[a-z0-9]+-auth-token=/` AND `Location: /`). All fail.
- 2.1.3. Run vitest, confirm both files fail.
- 2.1.4. Commit: `test: failing harness for dev-signin gate`.

2.2 — Feature flag + dev-mode helper
- 2.2.1. Edit `apps/web-platform/lib/feature-flags/server.ts`: add `"dev-signin": "FLAG_DEV_SIGNIN"` to `FLAG_VARS`.
- 2.2.2. Create `apps/web-platform/lib/auth/dev-mode.ts` exporting `isDevSignInEnabled()`. Body: `if (process.env.NODE_ENV !== "development") return false; return getFlag("dev-signin");`. Check INSIDE the function.
- 2.2.3. Run `dev-mode.test.ts` — passes. Run `feature-flags/server.test.ts` — still passes.
- 2.2.4. Commit: `feat: dev-mode gate helper + FLAG_DEV_SIGNIN`.

2.3 — Login page refactor (its own commit, reviewable in isolation)
- 2.3.1. Create `apps/web-platform/components/auth/login-form.tsx` (`"use client"`). Move the entire current body of `app/(auth)/login/page.tsx` verbatim — state, hooks, handlers, JSX. No behavioral change.
- 2.3.2. Rewrite `apps/web-platform/app/(auth)/login/page.tsx` as `async function Page()` (server component). Wraps `<LoginForm />` in `<Suspense>` (still required by `useSearchParams` inside `LoginForm`).
- 2.3.3. Run `npm run dev`, exercise the OTP flow end-to-end — must work identically to before.
- 2.3.4. Run `next build` — succeeds with zero new warnings.
- 2.3.5. Commit: `refactor: extract <LoginForm /> from login page`.

2.4 — Route handler + helpers (cookie-aware redirect)
- 2.4.1. Create `apps/web-platform/app/api/auth/dev-signin/_helpers.ts`. Exports `slotSchema` (`z.object({ slot: z.union([z.literal(1), z.literal(2), z.literal(3)]) })`), `getPasswordForSlot(slot): string | undefined`, `getEmailForSlot(slot): string`.
- 2.4.2. Create `apps/web-platform/app/api/auth/dev-signin/route.ts`. POST handler:
  - Layer A: `if (process.env.NODE_ENV !== "development") return new Response(null, { status: 404 });`
  - Layer B: `if (!isDevSignInEnabled()) return new Response(null, { status: 404 });`
  - Parse body, validate slot via Zod (400 on invalid).
  - Look up password (500 on missing — error message must NOT include the env-var key).
  - Construct `const response = NextResponse.redirect(new URL("/", req.url), 303);` FIRST.
  - Construct supabase client with `cookies.setAll: cs => cs.forEach(c => response.cookies.set(c.name, c.value, c.options))`.
  - `await supabase.auth.signInWithPassword({email, password});` — on error, return 500 with scrubbed message.
  - Return `response`.
- 2.4.3. Run `dev-signin-route.test.ts` — all cases pass including cookie-writer regression.
- 2.4.4. Commit: `feat: POST /api/auth/dev-signin with cookie-aware redirect`.

2.5 — Panel + login integration
- 2.5.1. Create `apps/web-platform/components/auth/dev-sign-in-panel.tsx` — async server component. First two lines of body: `if (process.env.NODE_ENV !== "development") return null; if (!getFlag("dev-signin")) return null;`. Returns three `<form action="/api/auth/dev-signin" method="post"><input type="hidden" name="slot" value={N} /><Button>Sign in as dev-N</Button></form>` blocks inside a `<Card>`.
- 2.5.2. Edit `apps/web-platform/app/(auth)/login/page.tsx`: render `<DevSignInPanel />` above `<Suspense><LoginForm /></Suspense>`.
- 2.5.3. Local verification (operator confirms): set `FLAG_DEV_SIGNIN=1` in Doppler dev, run `npm run dev`, panel renders, click "Sign in as dev-1", land on `/` authenticated.
- 2.5.4. Local verification: unset flag, panel hidden.
- 2.5.5. Local verification: `NODE_ENV=production next build && next start` — panel does NOT render.
- 2.5.6. Commit: `feat: <DevSignInPanel /> + login page integration`.

2.6 — CI grep gate
- 2.6.1. Create `apps/web-platform/scripts/assert-dev-signin-eliminated.sh`. Greps `apps/web-platform/.next/server/**`, `.next/static/chunks/**`, `.next/**/*.map`, `.next/server/server-reference-manifest.js` for forbidden tokens: `dev-1@example.com`, `dev-2@example.com`, `dev-3@example.com`, `DEV_SIGNIN`, `DEV_USER_`, `dev-sign-in-panel`, `isDevSignInEnabled`, `dev-signin`. Any hit → exit 1 with file path.
- 2.6.2. Wire into existing prd-build CI job (post-`next build` step). NO new workflow file.
- 2.6.3. Run locally: `NODE_ENV=production npm run build` then `bash scripts/assert-dev-signin-eliminated.sh` — expect zero hits.
- 2.6.4. Commit: `chore: post-build grep for dev-signin token leakage`.

2.7 — Docs + env example
- 2.7.1. Edit `apps/web-platform/.env.example`: add `# Dev-only — DO NOT SET IN PRD` block listing `FLAG_DEV_SIGNIN`, `DEV_USER_1_PASSWORD`, `DEV_USER_2_PASSWORD`, `DEV_USER_3_PASSWORD`.
- 2.7.2. Edit `apps/web-platform/README.md`: add "Dev-only sign-in panel" section under Local development. Document the seed-script command, verification steps, and the Vercel-preview-NODE_ENV invariant.
- 2.7.3. Commit: `docs: dev-signin panel local-dev guide`.

2.8 — Seed script
- 2.8.1. Create `apps/web-platform/scripts/seed-dev-users.sh`. Mirror `seed-qa-user.sh` structure. Add:
  - `DOPPLER_CONFIG === "dev"` assertion.
  - JWT decode of `SUPABASE_SERVICE_ROLE_KEY`: extract `ref` claim, assert it matches the host prefix in `NEXT_PUBLIC_SUPABASE_URL`.
  - Loop slots 1..3: `POST auth/v1/admin/users` with `{email, password, email_confirm: true}`. 422 unique-constraint = success. On existing user, `PUT` to refresh password.
- 2.8.2. Operator-side: set `DEV_USER_*_PASSWORD` in Doppler dev (separate terminal — never via `! ` prefix), then run the script.
- 2.8.3. Commit: `feat: seed-dev-users.sh (multi-user)`.

## Testing

3.1 — Pre-merge verification
- 3.1.1. `bun test apps/web-platform/test/auth/dev-mode.test.ts` — passes.
- 3.1.2. `bun test apps/web-platform/test/auth/dev-signin-route.test.ts` — passes (including cookie-writer regression).
- 3.1.3. `bun test apps/web-platform/lib/feature-flags/` — passes.
- 3.1.4. `NODE_ENV=production npm run build` — succeeds with zero new errors/warnings.
- 3.1.5. `bash apps/web-platform/scripts/assert-dev-signin-eliminated.sh` — exits 0.
- 3.1.6. `bash apps/web-platform/scripts/service-role-allowlist-gate.sh` — output unchanged from main.
- 3.1.7. PR body contains `Ref #3184` (NOT `Closes`).

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
