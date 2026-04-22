# Tasks: feat-app-url-hardening PR-A

Derived from `knowledge-base/project/plans/2026-04-22-chore-app-url-hardening-pr-a-plan.md`.

Closes `#2770`, `#2768`. Out-of-band closes `#2773`, `#2774` post-merge. `#2769` ships as PR-B (separate plan).

## Phase 1: TDD RED — failing tests first

- [x] 1.1 `test/api-checkout.test.ts`
  - [x] 1.1.1 Add `@sentry/nextjs` partial mock (`async (orig) => ({ ...(await orig()), captureException: vi.fn(), captureMessage: vi.fn() })`)
  - [x] 1.1.2 Degraded-path test: env unset → Sentry fires with `{feature: "checkout", op: "create-session"}` AND Stripe `success_url` uses `https://app.soleur.ai` fallback
  - [x] 1.1.3 Happy-path test: env set → Sentry NOT called AND Stripe `success_url` uses env-derived URL (anti-tautology)
- [x] 1.2 `test/api-billing-portal.test.ts` — symmetrical to 1.1, `feature: "billing"`, `op: "portal-session"`, assert `return_url`
- [x] 1.3 `test/notifications.test.ts`
  - [x] 1.3.1 Add Sentry partial mock
  - [x] 1.3.2 Read `server/notifications.ts` and decide op name (likely `"origin"` or `"webpush-base"`)
  - [x] 1.3.3 Degraded + happy-path pair with positive URL assertion
- [x] 1.4 `test/github-resolve.test.ts`
  - [x] 1.4.1 `beforeEach`: `delete process.env.NEXT_PUBLIC_SITE_URL` in every describe block (absence guard against shell leak)
  - [x] 1.4.2 Migrate all `NEXT_PUBLIC_SITE_URL` env stubs → `NEXT_PUBLIC_APP_URL`
- [x] 1.5 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-checkout.test.ts test/api-billing-portal.test.ts test/notifications.test.ts test/github-resolve.test.ts` — confirm RED

## Phase 2: TDD GREEN — implementation

- [x] 2.1 `app/api/checkout/route.ts` — add `if (!appUrl) reportSilentFallback(null, {feature: "checkout", op: "create-session", message})` above the literal fallback
- [x] 2.2 `app/api/billing/portal/route.ts` — same pattern, `feature: "billing"`, `op: "portal-session"`
- [x] 2.3 `server/notifications.ts` — same pattern + rewrite `||` to `??`
- [x] 2.4 `app/api/auth/github-resolve/route.ts` — `NEXT_PUBLIC_SITE_URL` → `NEXT_PUBLIC_APP_URL`, rename local `siteUrl` → `appUrl`
- [x] 2.5 `app/api/auth/github-resolve/callback/route.ts` — same migration in `redirectWithDeletedCookie`
- [x] 2.6 **Scope expansion surfaced by Phase 3.5 sweep:** add `reportSilentFallback` to both `github-resolve/route.ts` (feature: `"github-resolve"`, op: `"initiate"`) and `github-resolve/callback/route.ts` (op: `"callback-redirect"`) — the migration preserved an existing silent-fallback pattern; per `cq-silent-fallback-must-mirror-to-sentry` every `NEXT_PUBLIC_APP_URL` fallback site must mirror. Closes the class fully.
- [x] 2.7 Re-run 1.5 vitest command — confirm GREEN

## Phase 3: Typecheck, build, completeness sweeps

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/next build` (catches route-file export violations)
- [x] 3.3 `rg NEXT_PUBLIC_SITE_URL apps/ server/ lib/` → zero hits in production code
- [x] 3.4 `rg '"https://app\.soleur\.ai"' apps/ server/ lib/` → exactly 5 hits (one per touched file) — brute-force completeness guarantee
- [x] 3.5 Enumerated read-check: each remaining `process.env.NEXT_PUBLIC_APP_URL` hit is either gated by `reportSilentFallback` in enclosing `if` OR guaranteed-set
- [x] 3.6 Full suite: `cd apps/web-platform && ./node_modules/.bin/vitest run` — zero regressions

## Phase 4: Ship

- [ ] 4.1 Ensure PR #2793 body contains `Closes #2770`, `Closes #2768` (separate lines), `## Changelog` section
- [ ] 4.2 Set labels: `semver:patch`, `type/security`
- [ ] 4.3 Run `/soleur:ship` (handles markdownlint-fix, commit, push, QA, review, resolve, mark-ready, auto-merge, release verify)

## Phase 5: Post-merge operator actions (destructive prod writes)

- [ ] 5.1 Confirm Web Platform Release workflow for PR-A merge commit succeeded end-to-end
- [ ] 5.2 SSH diagnostic (deterministic code-running proof):
  - [ ] 5.2.1 `docker inspect soleur-web-platform | jq -r '.[0].Config.Labels["org.opencontainers.image.revision"]'` matches PR-A merge commit SHA
  - [ ] 5.2.2 `docker exec soleur-web-platform printenv NEXT_PUBLIC_APP_URL` returns `https://app.soleur.ai`
- [ ] 5.3 Present delete command verbatim + wait for explicit per-command ack: `doppler secrets delete NEXT_PUBLIC_SITE_URL --project soleur --config prd`
- [ ] 5.4 After ack, run the delete. Doppler CLI native confirmation will surface.
- [ ] 5.5 Verify absence: `doppler secrets get NEXT_PUBLIC_SITE_URL -p soleur -c prd --plain --silent` exits non-zero
- [ ] 5.6 Close `#2773` with Sentry passive-signal comment + link to learning `best-practices/2026-04-22-passive-sentry-signal-closes-followthrough-verification.md`
- [ ] 5.7 Close `#2774` as redundant: "Closing per issue body — #2773 confirmed Sentry silence; Phase 5.2 confirmed env var in prod container"

## Out of scope (tracked elsewhere)

- `#2769` CI guard for required `NEXT_PUBLIC_*` secrets → PR-B, separate plan
- `middleware.ts` `NEXT_PUBLIC_SUPABASE_URL ?? ""` — different feature, fails loud
- `server/github-app.ts` + `connect-repo/page.tsx` `NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai"` — fallback is correct prod slug
