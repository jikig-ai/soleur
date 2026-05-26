---
lane: procedural
plan: knowledge-base/project/plans/2026-05-20-feat-wg-block-pr-ready-on-undeferred-operator-steps-plan.md
---

# tasks: feat-one-shot-wg-block-undeferred-operator-steps-4117

Derived from `knowledge-base/project/plans/2026-05-20-feat-wg-block-pr-ready-on-undeferred-operator-steps-plan.md`. Phase ordering follows the plan body. The contract-changing edits (AGENTS.core.md rule additions) MUST land before the consumer edit (ship/SKILL.md gate body that references the rule ID) per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

## Phase 0 — Preconditions

- [ ] 0.1 Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` and capture B_ALWAYS baseline.
- [ ] 0.2 Verify #4114 OPEN + `type/chore` + `deferred-automation` sentinel; #4115 OPEN + `type/feature` + sentinel.
- [ ] 0.3 Re-grep `^## Phase 6.4` and `^### Retroactive Gate Application` in `plugins/soleur/skills/ship/SKILL.md`; confirm insertion-point line numbers.
- [ ] 0.4 Re-grep `grep -iE` precedent in sibling skill bodies.

## Phase 1 — TDD: write failing tests first (RED)

- [ ] 1.1 Create `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/pr-h-counterfactual.md` from PR #4066 verbatim.
- [ ] 1.2 Create `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/mixed-tracked-untracked.md` (synthetic, 2 untracked + 1 tracked).
- [ ] 1.3 Create `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts` with TC-1 through TC-6.
- [ ] 1.4 Run `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`. Confirm 6 failures.

## Phase 2 — Implement gate body (GREEN)

- [ ] 2.1 Insert `### Undeferred Operator-Step Gate` subsection into `plugins/soleur/skills/ship/SKILL.md` between Retroactive Gate Application and Phase 6.4.
- [ ] 2.2 Append Final Checklist line to Phase 5 (`- [ ] Undeferred operator-step gate passed (Phase 5.5 gate)`).
- [ ] 2.3 Edit `AGENTS.core.md:13` (`hr-never-label-any-step-as-manual-without`): add `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` and `**Why:**` cross-ref. Verify ≤600 B.
- [ ] 2.4 Append new `wg-block-pr-ready-on-undeferred-operator-steps` rule body to `AGENTS.core.md` `## Workflow Gates`. Verify ≤600 B.
- [ ] 2.5 Append pointer-index entry to `AGENTS.md`.
- [ ] 2.6 Run `bun test ...gate.test.ts`. All 6 GREEN.

## Phase 3 — AGENTS budget reckoning (INLINE FOLD-IN per deepen-plan)

- [ ] 3.1 Re-run budget linter; capture new B_ALWAYS (deepen-plan baseline: 24499).
- [ ] 3.2.a-i Trim `AGENTS.core.md:15` (`hr-tagged-build-workflow-needs-initial-tag-push`) from 1372 B → ≤580 B; offload `**Why:**`+`**How to apply:**` content to new learning at `knowledge-base/project/learnings/best-practices/2026-05-20-tagged-build-workflow-needs-initial-tag-push.md`.
- [ ] 3.2.a-ii Trim `AGENTS.core.md:55` (`wg-end-of-work-emit-resume-prompt`) from 1040 B → ≤580 B; verify or add the "Required fields" enumeration in `plugins/soleur/skills/work/SKILL.md` §Resume Prompt.
- [ ] 3.2.a-iii Pick at least one `wg-*` to retire from candidates: `wg-when-an-audit-identifies-pre-existing`, `wg-when-fixing-a-workflow-gates-detection`, or operator nomination. Add entry to `scripts/retired-rule-ids.txt`. Remove from `AGENTS.core.md` AND pointer in `AGENTS.md`.
- [ ] 3.3 Re-run both linters (`lint-agents-rule-budget.py` AND `lint-rule-ids.py --retired-file`). Both `[PASS]`. Iterate trim depth / retire one more `wg-*` if still over budget.

## Phase 4 — Self-test + counterfactual

- [ ] 4.1 Confirm TC-4 (PR-H counterfactual fixture) flags ≥3 matches.
- [ ] 4.2 Confirm `grep -cF wg-block-pr-ready-on-undeferred-operator-steps AGENTS.core.md` returns ≥2.
- [ ] 4.3 Confirm `emit_incident wg-block-pr-ready-on-undeferred-operator-steps` appears in ship/SKILL.md.

## Phase 5 — Ship

- [ ] 5.1 `skill: soleur:compound` (capture the AGENTS-budget-reckoning learning).
- [ ] 5.2 Stage explicit paths (no `git add -A`).
- [ ] 5.3 Commit `semver:patch`. Body: `Closes #4117`. Mention paired demotion PR by number in body.
- [ ] 5.4 Dry-run the gate's regex against this PR's own body. Confirm no false-positive self-block.
- [ ] 5.5 Push, `gh pr ready`, `gh pr merge --auto --squash`.

## Acceptance criteria — checkpoints

- [ ] AC1-AC12 (pre-merge) — see plan §Acceptance Criteria.
- [ ] AC-PM1 (post-merge operator subjective smoke-test) — operator-attestation acknowledged inline per plan §Sharp Edges.
