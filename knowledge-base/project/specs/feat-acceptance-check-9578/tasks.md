# Tasks: founder-defined acceptance check (#9578)

Plan: knowledge-base/project/plans/2026-10-06-feat-founder-acceptance-check-plan.md

## Phase 0 — Preconditions

- [ ] 0.1 Re-verify the next free ADR ordinal against `origin/main`
- [ ] 0.2 Re-measure body ceilings and the description budget; record in the PR body
- [ ] 0.3 Dogfood five realistic founder checks through Step 10.5; if more than three of five cannot be a runnable command, stop and report to the operator

## Phase 1 — Failing tests and fixtures (RED)

- [ ] 1.1 Create `plugins/soleur/test/preflight-founder-check.test.ts` (drives the production script, `gitFixture()` for histories)
- [ ] 1.2 Create fixtures under `plugins/soleur/test/fixtures/founder-check/` (list in plan Phase 1.2)
- [ ] 1.3 Register the suite in `preflight-check10-suite-integrity.test.sh`; add the Check 13 section assertion; extend `plan-skeleton-checkpoint.test.ts`
- [ ] 1.4 Run the suites and record that every new case is RED for the right reason

## Phase 2 — `founder-check.py` (GREEN)

- [ ] 2.1 `verify` (resolve, parse, canonical hash, freeze comparison, authorship anchor, `pins`)
- [ ] 2.2 `classify` (pure; INVALID set; `creates` rule; sandbox-health input)
- [ ] 2.3 `log` (`--mode interactive|headless`, append-only, refusals) and `summary`
- [ ] 2.4 Wording constants (pass, judgement, first-use notice, banner, no-sandbox line)

## Phase 3 — preflight Check 13

- [ ] 3.1 `preflight/references/check-13-founder-check.md` (wrapper, outcome mapping table, roll-up)
- [ ] 3.2 Check 13 section, Phase 2 aggregate row, fast-path row, headless paragraph, `--founder-check-baseline`, Sharp Edges entry in `preflight/SKILL.md`
- [ ] 3.3 Interactive prompt loop in the Phase 2 "If any FAIL" branch

## Phase 4 — Capture (plan side)

- [ ] 4.1 `plan/references/plan-founder-check.md`
- [ ] 4.2 One pointer line in `plan/SKILL.md` (at most 130 bytes); `lint-skill-body-budget.py` green
- [ ] 4.3 HTML-comment pointer in the three templates of `plan-issue-templates.md`

## Phase 5 — Decision record and architecture

- [ ] 5.1 ADR-274 and the ADR-175 amendment
- [ ] 5.2 `model.c4` + regenerated `model.likec4.json`; c4 tests green

## Phase 6 — Verification

- [ ] 6.1 Run the suites and lints (plan Phase 6.1–6.2)
- [ ] 6.2 Trace `soleur:ship` staging of `founder-check-log.md`
- [ ] 6.3 CLO review of prompt, notice, banner and result wording
