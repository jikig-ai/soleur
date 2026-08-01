# Tasks — #7136 release-outcome email step dies on unbound `R_DEPLOY`

Plan: `knowledge-base/project/plans/2026-08-01-release-outcome-email-step-env-refs-plan.md`

## Phase 1 — Workflow fix
- [ ] T1.1 Add `R_DEPLOY: ${{ needs.deploy.result }}` to the email step's own `env:`
- [ ] T1.2 Guard the reference as `${R_DEPLOY:-}` (unset → "NOT updated" branch)
- [ ] T1.3 Hoist run link + "What stopped" list so both branches carry them
- [ ] T1.4 Add `!cancelled()` to the Sentry mirror step's `if:` so it survives an email-step crash

## Phase 2 — Linter
- [ ] T2.1 `scripts/lint-workflow-step-env-refs.py` with the five measured discriminators
- [ ] T2.2 Fail loudly on zero files scanned (no silent clean sweep)
- [ ] T2.3 Verify: exactly 0 findings on the fixed tree, 1 finding pre-fix

## Phase 3 — Tests + registration
- [ ] T3.1 `scripts/lint-workflow-step-env-refs.test.sh` — fixture unit tests
- [ ] T3.2 Execution test: run the shipped step body under both `R_DEPLOY` branches + unset
- [ ] T3.3 Register in `scripts/test-all.sh` (else `lint-orphan-test-suites.sh` fails)
- [ ] T3.4 Wire the linter into the CI lint job
