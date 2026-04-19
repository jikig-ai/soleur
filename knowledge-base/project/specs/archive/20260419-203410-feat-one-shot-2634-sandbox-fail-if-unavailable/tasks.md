# Tasks — sec: sandbox.failIfUnavailable=true (#2634)

Plan: `knowledge-base/project/plans/2026-04-19-sec-sandbox-fail-if-unavailable-plan.md`

## Phase 1 — RED (failing regression test)

- [x] 1.1 Create `apps/web-platform/test/agent-runner-sandbox-config.test.ts` copying the `vi.mock()` preamble from `apps/web-platform/test/agent-runner-tools.test.ts` and reusing `createSupabaseMockImpl` + `createQueryMock` from `apps/web-platform/test/helpers/agent-runner-mocks.ts`.
- [x] 1.2 Test body: call `startAgentSession("user-1", "conv-1", "cpo")` (the real entry, NOT `runAgent`), then `expect(mockQuery.mock.calls[0][0].options.sandbox.failIfUnavailable).toBe(true)`. Use `.toBe(true)` (not `toBeTruthy`) per `cq-mutation-assertions-pin-exact-post-state`.
- [x] 1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts` — confirm it FAILS with `expected undefined to be true`.

## Phase 2 — GREEN (apply fix)

- [x] 2.1 Edit `apps/web-platform/server/agent-runner.ts`: inside the `sandbox:` block (currently starting at line 748), add `failIfUnavailable: true` on a new line directly after `enabled: true`, with a 4-line comment explaining purpose and referencing #2634.
- [x] 2.2 Edit `apps/web-platform/Dockerfile` at the comment block above `apt-get install ... bubblewrap socat qpdf`: extend to explicitly name `socat` as load-bearing for bwrap wrapping (not just networking) and reference #2634.
- [x] 2.3 Re-run the regression test: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts` — confirm it PASSES.
- [x] 2.4 Run the full agent-runner test surface: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-*.test.ts` — confirm no regressions vs main.

## Phase 3 — Pre-commit checks

- [x] 3.1 Run `npx markdownlint-cli2 --fix` on plan and tasks files.
- [ ] 3.2 Run `skill: soleur:compound` to capture any learnings (required per `wg-before-every-commit-run-compound-skill`).
- [ ] 3.3 Commit all three files (`agent-runner.ts`, `Dockerfile`, new test) + plan artifacts in one commit referencing #2634.

## Phase 4 — Ship

- [ ] 4.1 Push branch.
- [ ] 4.2 Run `skill: soleur:ship` — enforces review + QA gates.
- [ ] 4.3 PR body includes `Closes #2634` (body, not title) per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] 4.4 Apply semver label `semver:patch` (defensive hardening, no user-visible behavior change under normal operation).

## Phase 5 — Post-merge verification

- [ ] 5.1 After merge to main, monitor the next production deploy in Sentry. Zero "sandbox required but unavailable" events = deploy healthy (deps still installed). Any such events = rollback and investigate Dockerfile drift.
- [ ] 5.2 If the regression fires post-merge, file an immediate hotfix PR installing the missing dep.
- [ ] 5.3 Verify #2634 auto-closed by the PR merge.
