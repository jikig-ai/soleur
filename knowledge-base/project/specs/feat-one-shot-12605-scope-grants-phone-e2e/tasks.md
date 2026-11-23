# Tasks: phone-width e2e for the Scope Grants web-egress disclosures

Plan: `knowledge-base/project/plans/2026-11-22-test-scope-grants-web-egress-phone-e2e-plan.md`
Issue: #12605. Draft PR: #13017. Follow-up: #13018. Release blocker: #12937.

## 1. Setup (RED)

- [x] 1.1 Add `EGRESS_E2E_USERS` (ids `...12c1` true, `...12c2` false, fixed `jti` values `...12d1`, `...12d2`) and their workspace rows (`organization_id: null`, `name`, `web_egress`) to `apps/web-platform/e2e/mock-supabase.ts`.
- [x] 1.2 Create `apps/web-platform/e2e/nav-states-scope-grants-web-egress.e2e.ts` with the `pyramid-justified:` header, inline storage state from `heldSessionFor`, and shell-route stubs.
- [x] 1.3 Write the ON and OFF tests in the plan's order: wait for the switch (90-second cold-compile bound), prove state, assert first-render counts, hide `nextjs-portal`, wait for hydration (OFF: the click retry opens the dialog, then the count is 2), then measure. The paragraph check reads visible paragraphs only.
- [x] 1.4 Run the spec and confirm both tests fail on the state assertions.

## 2. Core Implementation (GREEN)

- [x] 2.1 Add `notFound()` beside `sendRows` with the once-per-actor-method-path stderr line, keep the catch-all body verbatim, and route the catch-all through it.
- [x] 2.2 Add `withJsonBody()`, and write every body branch as `return withJsonBody(...)`.
- [x] 2.3 Add the optional `jti` argument to `mintMockJwt`.
- [x] 2.4 Add the mint branches for fixtures only: `/auth/v1/user`, `/auth/v1/admin/users/<id>`, `runtime_mint_intent`, `generate_link` (flat `hashed_token`), `verify` (`access_token`, `refresh_token`, `expires_in`, `user`), `is_jti_denied`.
- [x] 2.5 Add the data branches: `user_session_state`, `workspace_members` with `role: "owner"`, `workspaces`, and `get_workspace_web_egress` reading the fixture's row.
- [x] 2.6 POST a non-JSON body to each body branch and confirm the catch-all's 404. POST a non-fixture body and confirm the same 404, except `get_workspace_web_egress`, which returns 200 with body `null` for a fixture bearer and another `p_workspace_id`.
- [x] 2.7 Run the new spec plus `settings-kb-sync-held` and `nav-states-inbox-legal`.

## 3. Testing (mutation pass)

- [x] 3.1 Commit, then apply each of the 15 Guard Contract rows as a temporary edit and restore with `git restore`. Never use `git stash`.
- [x] 3.2 Run each row from `apps/web-platform` with `CI=1 npx playwright test e2e/nav-states-scope-grants-web-egress.e2e.ts --project=authenticated --retries=0`.
- [x] 3.3 Record each row in `knowledge-base/project/specs/feat-one-shot-12605-scope-grants-phone-e2e/mutation-results.md` and commit it.

## 4. Ship

- [ ] 4.1 Confirm the diff has no production source, `docs/`, legal document, `playwright.config.ts` or approval-queue flag change.
- [ ] 4.2 PR body uses `Closes #12605`, links #13018, and carries the mutation results table. CI is the test gate.
- [ ] 4.3 After merge, run `soleur:postmerge`, then branch on `deploy-arm.sh find` as the plan's Post-merge criterion states. On `MATCH=exact DEPLOY=blocked` with `[skip_reason=release_failed]`, comment on #12937 and do not emit DONE, whatever `served` reads. Every other outcome follows the plan's `served` rule.
