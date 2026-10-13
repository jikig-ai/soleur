# Tasks — feat-one-shot-9762-testing-strategy (#9762)

Plan: `knowledge-base/project/plans/2026-10-08-feat-testing-strategy-checks-plan.md`

## Phase 1 — Reviewer extension + skill instructions (FR-1, FR-2, FR-4)

- [x] 1.1 Extend `plugins/soleur/agents/engineering/review/test-design-reviewer.md`: add `## Pyramid & Fast-Feedback Check` — layer-classification table (unit/integration/e2e by path+import+cost signals), `pyramid-justified:` marker convention (file comment or PR-body `## Test Pyramid` block), FAIL/WARN verdict rules in a separate `### Pyramid` block (never folded into the Farley score), and the explicit "no measured runtime at review time — measured budgets are #9763" boundary line.
- [x] 1.2 Update the agent's `description:` to mention pyramid/fast-feedback (1–3 sentences, no `<example>` blocks; measured cumulative `agents/**/*.md` description total 2852w vs 2847w on main (+5w) — the ~2500 target was already breached pre-existing, tracked in #8692; new description is 40 words).
- [x] 1.3 `plugins/soleur/skills/plan/references/plan-issue-templates.md`: add the pyramid-layer label line to all three `## Test Scenarios` blocks (MINIMAL/MORE/A LOT).
- [x] 1.4 `plugins/soleur/skills/work/SKILL.md` RED-task block: each RED task names the test's pyramid layer in its title (`RED(unit): …`).
- [x] 1.5 Seat text: `plugins/soleur/skills/review/SKILL.md` agent-13 bullet + `plugins/soleur/skills/review/workflows/review.workflow.js` `'test-design'` `lens:` — append pyramid/budget scope.

## Phase 2 — Fixtures + pin suite + registration (FR-3)

- [x] 2.1 Create `plugins/soleur/test/fixtures/test-pyramid/slow-e2e-no-justification.diff` — unified diff adding `apps/web-platform/e2e/checkout-flow.e2e.ts` (`*.e2e.ts` convention, `@playwright/test`, `page.goto`, `page.waitForTimeout(15000)`, no marker).
- [x] 2.2 Create `plugins/soleur/test/fixtures/test-pyramid/fast-unit.diff` — unified diff adding `apps/web-platform/test/order-total.test.ts` (flat unit-test convention, pure unit test).
- [x] 2.3 Create `plugins/soleur/test/test-pyramid-fixtures.test.sh` — sources `test-helpers.sh`, composed EXIT trap (#8659), NOT `*.mutation.sh` naming (#7942); censuses `fixtures/test-pyramid/*.diff` (`== 2`), per-fixture parse + signal/marker assertions, vocabulary drift pin on `test-design-reviewer.md`, instrument self-check.
- [x] 2.4 Run `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` standalone → exit 0.
- [x] 2.5 `scripts/lib/test-affected-paths.sh`: add `AFFECTED_PLUGINS_SOLEUR_TEST_TEST_PYRAMID_FIXTURES_TEST_SH_PATHS` — entries: `plugins/soleur/agents/engineering/review/test-design-reviewer.md`, `plugins/soleur/test/fixtures/test-pyramid/`, `plugins/soleur/test/test-pyramid-fixtures.test.sh`, `scripts/lib/test-affected-paths.sh` (self-inclusion).
- [x] 2.6 `bash scripts/test-all.sh --print-selection` on this diff → suite shows AFFECTED_SELECTED 1.

## Phase 3 — Verification + records (FR-5)

- [x] 3.1 Apply the extended checklist to `slow-e2e-no-justification.diff` → verdict FAIL citing missing justification; record in `specs/feat-one-shot-9762-testing-strategy/fixture-verdicts.md`.
- [x] 3.2 Apply to `fast-unit.diff` → PASS, layer `unit`; record.
- [x] 3.3 Post both verdicts as a comment on #9762.
- [x] 3.4 Mutation-check the pin suite: Guard-Contract rows M1–M5 + M7 each drive it red; M6 stays green.
- [x] 3.5 Run suites referencing edited files: `rg -l 'test-design-reviewer|plan-issue-templates' plugins/soleur/test plugins/soleur/skills/*/test` → run each hit.

## Final

- [x] 4.1 Confirm AC-1..AC-7 in the plan all met; AC-1 verify comment 6063533523 still exists on #9762.
- [x] 4.2 Run lint + touched-file suites (per work Phase 2 exit rules).
