---
title: "Tasks — feat: property-based-testing guidance in shipped workflow (issue #10400)"
date: 2026-10-20
branch: feat-one-shot-10400-pbt-guidance
plan: knowledge-base/project/plans/2026-10-20-feat-property-testing-guidance-plan.md
---

# Tasks

Derived from `2026-10-20-feat-property-testing-guidance-plan.md` (post-review). AC numbers reference the plan's `## Acceptance Criteria`. No spec.md exists for this branch (one-shot path) — `lane:` defaulted to cross-domain (TR2 fail-closed).

## Phase 1: Reference first

- [ ] 1.1 Write `plugins/soleur/skills/work/references/property-testing.md` (~150 lines, `# Property-based testing`, no frontmatter): when-to-reach-for-it; the workflow (pure function → plain-English property → property shape by strength → generator over input alphabet → negative control); counterexample lifecycle (triage, shrink, permanent named regression fixture, never pin seeds); language→tool map (fast-check/Hypothesis/proptest/jqwik/QuickCheck/FsCheck); one minimal `fast-check` + one `@given` worked example; house-conventions paragraph naming `apps/web-platform/test/README.md` + `scripts/lib/property-harness.md` as text (AC3, AC7)
- [ ] 1.2 Verify zero fabricated API tokens — `fc.assert`/`fc.property`/`fc.string`/`@given`/`proptest!` only; `fc.jsonObject`/`fc.stringOf` must not appear (AC7); markdownlint clean (AC6)

## Phase 2: Wire the two skill surfaces + pin

- [ ] 2.1 `plugins/soleur/skills/work/SKILL.md` — widen `RED(unit|integration|e2e)` → `RED(unit|integration|e2e|property)` at the "Create Todo List (TDD-First Structure)" step and append ONE markdown link + ≤ ~100 B clause: "or `property` for a generated-input contract test — see [property-testing.md](./references/property-testing.md)". **Budget: 118 B total headroom** (`lint-skill-body-budget.py --base origin/main`, ceiling 359,189 vs 359,071); all guidance stays in the reference (AC1, AC3)
- [ ] 2.2 `plugins/soleur/skills/plan/references/plan-issue-templates.md` — add the "properties that must never break" sentence inside EACH of the 3 `## Test Scenarios` blocks, immediately after the pyramid-layer guidance sentence; stay inside existing blocks (no new headings) (AC2)
- [ ] 2.3 `plugins/soleur/test/test-pyramid-fixtures.test.sh` — extend the DRIFT-pin block to assert `property` membership in `work/SKILL.md`'s RED-layer naming; update the header vocabulary sentence; bump `MIN_ASSERTIONS` by the added assertion count (AC4)

## Phase 3: Verify

- [ ] 3.1 `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` exits 0 (AC4)
- [ ] 3.2 AC grep battery: `grep -nE 'RED\([^)]*property' plugins/soleur/skills/work/SKILL.md` hits; `grep -c 'properties that must never break' plugins/soleur/skills/plan/references/plan-issue-templates.md` = 3; `grep -n 'property-testing.md' plugins/soleur/skills/work/SKILL.md` hits (AC1–AC3)
- [ ] 3.3 `python3 scripts/lint-skill-body-budget.py --base origin/main` green; `git diff origin/main...HEAD -- README.md plugins/soleur/README.md` empty (AC5)
- [ ] 3.4 markdownlint on all touched `.md` files (AC6); `bun test plugins/soleur/test/components.test.ts` green (reachability + no-backtick conventions)

## Phase 4: Guard contract mutation spot-check

- [ ] 4.1 In a scratch copy, delete the `|property` member from `work/SKILL.md` → `test-pyramid-fixtures.test.sh` reports FAIL naming the missing member (Guard 1 matrix row 1); delete the new `property` assertion from the pin → FAIL against a token-less tree (row 3) (AC4)
