---
feature: feat-one-shot-9398-plan-scope-check
plan: knowledge-base/project/plans/2026-10-01-chore-plan-time-scope-check-plan.md
issue: 9398
---

# Tasks — plan-time scope check (#9398)

## Phase 1: Canonical gate spec (foundation)

- [x] 1.1 Create `plugins/soleur/skills/plan/references/plan-scope-check.md` carrying the
  full gate spec per plan Phase 1: `## Scope Check` section schema (canonical), ask-extraction
  rule (issue body for `#N`; `<feature_description>` for freeform), both mapping directions,
  verbatim-quote rule for defaults/rungs/operator-direction phrases, `unmapped`/`inferred`
  verdicts + BLOCKED handling (interactive AskUserQuestion; headless `status: BLOCKED` +
  `decision-challenges.md` append), subsystem-root definition, three split thresholds
  (>= 4 subsystem roots OR > 25 planned files OR > 800 est. lines), placement note, `**Why:**`.

## Phase 2: plan/SKILL.md pointer + budget-neutral trim

- [x] 2.1 Insert `### 2.4. Scope Check Gate (Always)` between `### 2.` and `### 2.5.` with the
  `[skill-enforced: plan Phase 2.4 + deepen-plan Phase 4.12]` marker and the "Read
  `plugins/soleur/skills/plan/references/plan-scope-check.md` now" pointer (~340 B).
- [x] 2.2 Compensating trim (same commit): remove ALL THREE `<thinking>` scaffolding blocks —
  measured 201 B (line 274, `### 1.`), 135 B (line 429, `### 2.`), 121 B (line 845,
  `### 5.`), 457 B total against the ~340 B pointer (~117 B net negative). These carry no
  load-bearing conditions.
- [x] 2.3 Verify `python3 scripts/lint-skill-body-budget.py --base origin/main` → OK
  (plan ceiling 120000; was 119986 at plan time).

## Phase 3: deepen-plan halt

- [x] 3.1 Insert `### 4.12. Scope Check Halt (Always)` after §4.11, before `### 5.`,
  following the 4.11 five-step shape (Detect → Locate `grep -q '^## Scope Check'` →
  Mechanical verify → Adequacy read → Pass-through), ≤ ~3000 B (deepen-plan headroom 3414 B).
  Include the `SOLEUR_RULE_APPLIED rule=plan-scope-check-blocks-unmapped-asks` telemetry echo
  on every fire (halt-only; none on pass), matching the 4.5/4.6/4.8 convention.
- [x] 3.2 Verify `python3 scripts/lint-skill-body-budget.py --base origin/main` → still OK.

## Phase 4: Templates

- [x] 4.1 Add the `## Scope Check` block to all three tiers of
  `plugins/soleur/skills/plan/references/plan-issue-templates.md`, immediately before
  `## Acceptance Criteria` in each.

## Phase 5: plan-review consumer wiring

- [x] 5.1 `plugins/soleur/skills/plan-review/SKILL.md`: extend the code-simplicity feed to
  include `## Scope Check` (Ask Mapping + Plan-Item Provenance) alongside Property/Cut List.
- [x] 5.2 `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`: update the
  code-simplicity `lens` string, or extend the documented-divergence note.

## Phase 6: Contract test

- [x] 6.1 Write `plugins/soleur/test/plan-scope-check.test.ts` (bun:test, modeled on
  `observability-schema-parity.test.ts`) per plan Phase 6 assertions 1–5.
- [x] 6.2 Verify RED under each Guard-Contract mutation row (rows 1–5) and PASS on row 6.
- [x] 6.3 `bun test plugins/soleur/test/plan-scope-check.test.ts` green.

## Phase 7: ADR

- [x] 7.1 Author `knowledge-base/engineering/architecture/decisions/ADR-265-<slug>.md`
  (provisional — re-derive next-free ordinal against freshly-fetched `origin/*` refs before
  merge; ADR-264 is claimed on `origin/feat-one-shot-agent-runnable-operator-bootstrap`).
- [x] 7.2 If renumbered, sweep `grep -rn 'ADR-265' knowledge-base/project/{plans,specs}/`
  and the plan file in the same edit.

## Phase 8: Verify + commit

- [x] 8.1 `bash scripts/test-all.sh` green (or only pre-existing failures confirmed on
  origin/main).
- [x] 8.2 `npx markdownlint-cli2` clean on every edited/created `.md`.
- [x] 8.3 AC1–AC8 all verified against the final tree.

Last step before emitting any summary: `npx markdownlint-cli2 <plan> <tasks>` — both files
are linted by lefthook at the work phase's first commit (#8535 sharp edge).
