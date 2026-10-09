# Tasks — Pyramid audit remediation (#9855 PR 1)

Plan: `knowledge-base/project/plans/2026-10-09-feat-pyramid-audit-remediation-plan.md`

## Phase 1 — Marker backfill

- [ ] 1.1 Add `// pyramid-justified: <reason>` to `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (ws-injector + `page.route` `**/ws` interception)
- [ ] 1.2 Add marker to `cc-soleur-go-routing.e2e.ts` (same ws-injector surface; lifecycle-bar DOM signals)
- [ ] 1.3 Add marker to `cc-soleur-go-security.e2e.ts` (two `browser.newContext` isolation assertions)
- [ ] 1.4 Add marker to `nav-states-nav-pending.e2e.ts` (`page.route` hold-and-release soft-nav timing)
- [ ] 1.5 Add marker to `nav-states-shell.e2e.ts` (real-CSS layout invariant jsdom cannot see)
- [ ] 1.6 Add marker to `otp-login.e2e.ts` (`**/auth/v1/otp*` route interception + real form DOM)
- [ ] 1.7 Add marker to `start-fresh-conversations-rail.e2e.ts` (authenticated project + storageState)
- [ ] 1.8 Add marker to `start-fresh-onboarding.e2e.ts` (authenticated onboarding flow)

## Phase 2 — smoke.e2e.ts split

- [ ] 2.1 Create `apps/web-platform/test/middleware.csp.test.ts` (vitest, `middleware()` + `NextRequest`, mock recipe from `middleware.fail-closed.test.ts`): CSP on `/login` w/ nonce + strict-dynamic + hardening directives; nonce uniqueness across invocations; trusted/spoofed `x-forwarded-host`; `/health` CSP-free; unauth `/dashboard`+`/setup-key` 307→`/login` — add only what existing suites do not assert
- [ ] 2.2 Delete the 9 request-only tests from `smoke.e2e.ts`; keep the 2 `page.` tests
- [ ] 2.3 Add marker to `smoke.e2e.ts` naming the browser need (nonce on rendered `<script>` tags + console CSP-violation scan)

## Phase 3 — oauth.e2e.ts + team-membership.e2e.ts

- [ ] 3.1 Delete `apps/web-platform/e2e/team-membership.e2e.ts`
- [ ] 3.2 Delete `/callback` describe + T&C-gate describe from `oauth.e2e.ts`; keep login-page button-render describe; add marker

## Phase 4 — Machinery fixes

- [ ] 4.1 `test-design-reviewer.md`: 6a named-dir clarification + 6b `*.test.sh` cost-cell exception note
- [ ] 4.2 `review.workflow.js`: `hasTests` `\.e2e` → `\.e2e\.[jt]sx?$`; sync docstrings at ~line 204 and ~291
- [ ] 4.3 `git mv test/mu1-integration.test.ts test/mu1.integration.test.ts`; update `fixture-env-adoption.test.sh` WAIVED entry, `mu1-cleanup-guard.mjs` comment, in-file header comment
- [ ] 4.4 Comment on #9771 with 6a–6e dispositions

## Verification

- [ ] V.1 `grep -rl pyramid-justified apps/web-platform/e2e/*.e2e.ts | wc -l` == 10
- [ ] V.2 `vitest run test/middleware.csp.test.ts` green; `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` + `fixture-env-adoption.test.sh` green
- [ ] V.3 `grep -rn "mu1-integration.test" .` (excl. node_modules, synthetic-email prefix) → zero
- [ ] V.4 PR body: `Ref #9855` (not `Closes`), `## Test Pyramid` block not needed (file markers cover), coverage-map for every deleted assertion
