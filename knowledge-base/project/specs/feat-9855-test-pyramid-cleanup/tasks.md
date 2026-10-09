# Tasks: Pyramid audit remediation — e2e marker backfill + demotions (#9855 PR 1)

Plan: `knowledge-base/project/plans/2026-10-09-test-pyramid-e2e-marker-backfill-demotion-plan.md`
Spec: `knowledge-base/project/specs/feat-9855-test-pyramid-cleanup/spec.md`

## Phase 1: Coverage ledger (precondition — gates all deletions)

- [ ] 1.1 Verify `middleware.ts` imports and invokes cleanly in vitest offline (fake/unreachable Supabase env, mirroring the e2e public project's `webServer.env` in `playwright.config.ts`). If a specific assertion proves un-invocable, it stays in e2e under a marker — record the deviation in the PR body.
- [ ] 1.2 Build the per-assertion coverage ledger for `team-membership.e2e.ts` (2 active tests): flag-off 404 → `covered-by test/team-membership-resolver.test.ts` AC-A; conversation-names reachability → `covered-by` or `demote-to`.
- [ ] 1.3 Build the ledger for `oauth.e2e.ts` (6 tests): `/callback` 307s → `covered-by test/e2e-oauth-tc-consent.test.ts` (or `demote-to` route-invocation); 4 DOM-contract tests → `covered-by test/oauth-buttons.test.tsx` + consent suite (or `demote-to` component test).
- [ ] 1.4 Build the ledger for `smoke.e2e.ts` (11 tests): each `request`-only test → `demote-to test/csp-middleware.test.ts`; each `page`-needing test → `keep-in-e2e` with reason.
- [ ] 1.5 Run the claimed-coverage tests to confirm they pass on this branch: `test/team-membership-resolver.test.ts`, `test/oauth-buttons.test.tsx`, `test/e2e-oauth-tc-consent.test.ts`, `test/csp.test.ts`, `test/conversation-names-settings.test.tsx`.

## Phase 2: Demotions

- [ ] 2.1 Create `apps/web-platform/test/csp-middleware.test.ts` (middleware-invocation, no `@playwright/test` import): CSP header on `/login` + `/signup`; `strict-dynamic` + nonce present; nonce rotates across invocations; `x-forwarded-host` connect-src accepted + spoofed (regression #1075); no CSP header on `/health`; `/dashboard` unauthenticated → `/login`.
- [ ] 2.2 Create any conditional demotion test files the Phase-1 ledger requires (name at that point; none created pre-emptively).
- [ ] 2.3 Run the new vitest file(s) — all green.
- [ ] 2.4 Delete `apps/web-platform/e2e/team-membership.e2e.ts` — only when every 1.2 ledger row is `covered-by`/`demote-to`-landed.
- [ ] 2.5 Delete `apps/web-platform/e2e/oauth.e2e.ts` — only when every 1.3 ledger row is landed.

## Phase 3: Split + markers

- [ ] 3.1 Edit `apps/web-platform/e2e/smoke.e2e.ts`: remove demoted `request`-only tests; keep browser-needing residue; add `pyramid-justified:` marker (nonce-on-script-tag DOM eval + console CSP-violation listener need real rendering).
- [ ] 3.2 Add `pyramid-justified:` marker to `cc-soleur-go-bubbles.e2e.ts` (ws-injector + `browser.newContext` + `page.locator` DOM assertions).
- [ ] 3.3 Add marker to `cc-soleur-go-routing.e2e.ts` (`page.route` interception + ws-injector).
- [ ] 3.4 Add marker to `cc-soleur-go-security.e2e.ts` (`browser.newContext` isolation + ws-injector).
- [ ] 3.5 Add marker to `nav-states-nav-pending.e2e.ts` (`page.route` timing interception, `waitForURL`, `goBack`).
- [ ] 3.6 Add marker to `nav-states-shell.e2e.ts` (`page.route`, `page.mouse`, `page.evaluate`).
- [ ] 3.7 Add marker to `otp-login.e2e.ts` (full OTP login flow through rendered UI).
- [ ] 3.8 Add marker to `start-fresh-conversations-rail.e2e.ts` (authenticated project + `page.route`).
- [ ] 3.9 Add marker to `start-fresh-onboarding.e2e.ts` (authenticated onboarding flow through rendered UI).

## Phase 4: Verification + bookkeeping

- [ ] 4.1 `git grep pyramid-justified apps/web-platform/e2e` → a marker in every surviving `.e2e.ts` (9 files).
- [ ] 4.2 `git grep -l "@playwright/test" -- apps/web-platform/test` → empty.
- [ ] 4.3 Re-run the Phase-1.5 coverage tests + new `csp-middleware.test.ts` — all green.
- [ ] 4.4 Coverage ledger pasted into PR body (per-assertion `covered-by`/`demote-to`/`keep-in-e2e`).
- [ ] 4.5 Wrap-up comment on #9855: PR-1 landed, PR-2 (CI wiring) remains open. PR body uses `Ref #9855`, never `Closes`.
