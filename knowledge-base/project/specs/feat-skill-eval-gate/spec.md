---
feature: skill-eval-gate
date: 2026-06-29
lane: single-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-06-29-skill-eval-gate-brainstorm.md
---

# Spec: Validation-Gated Skill-Edit Acceptance Loop

## Problem Statement

`compound` generates well-placed skill/rule edits but nothing measures whether an edit actually
improved behavior. `eval-harness` can measure classifier accuracy but is a disconnected, manual,
point-in-time tool. The result: every edit to a classifier skill is an unverified change that can
regress routing/triage (the "fix Task A, break Task B" problem) with no detection. We own both
halves of a verification gate; they are not wired together.

## Goals

- G1: When `compound` proposes an edit to a gated classifier skill, automatically run `eval-harness`
  before/after and apply the edit only if it clears the accept rule.
- G2: Grow an append-only synthesized regression corpus — each fix contributes a golden task.
- G3: Log rejected edits to a buffer so dead-ends are not re-proposed.

## Non-Goals

- NG1: Genetic/Pareto multi-candidate evolution (GEPA/EvoSkill) — disproportionate for 2 classifiers.
- NG2: Autonomous unattended self-editing — approval/governance gates stay.
- NG3: Gating subjective/open-ended skills (brainstorm, plan, legal, marketing) — no verifiable signal.
- NG4: Formal train/test split — corpus is a single append-only set at our N.
- NG5: CI backstop for manual (non-compound) edits — deferred follow-up.

## Functional Requirements

- FR1: Detect when a `compound` route-learning edit targets a gated skill (config-listed: `soleur:go`
  routing, `ticket-triage`).
- FR2: Run the relevant `eval-harness` arm against the current skill (baseline) and the proposed
  edit (candidate), using existing promptfoo configs.
- FR3: Accept iff held-out corpus score does not regress AND the targeted miss now passes; otherwise
  reject and do not apply.
- FR4: On accept, append a synthesized golden task encoding the fixed miss to the skill's corpus.
- FR5: On reject, append the rejected edit (skill, diff summary, reason, timestamp) to a rejected-edit
  buffer (JSONL, consistent with `.claude/.rule-incidents.jsonl`).
- FR6: Gate applies only to prose edits of gated skills — never displaces compound's hook-first
  enforcement hierarchy.

## Technical Requirements

- TR1: Reuse `eval-harness` promptfoo configs and `measure-classification.cjs` / `parse-label.cjs`;
  do not fork the measurement layer.
- TR2: Synthesized fixtures only — no real user data in the corpus (per `cq-test-fixtures-synthesized-only`).
- TR3: API-cost spend on gate runs must be disclosed (per autonomous-loop API budget disclosure rule).
- TR4: Headless vs interactive behavior follows the established mode-branch pattern.

## Acceptance Criteria

- A gated-skill edit proposed by compound that improves the target case without regressing the
  corpus is applied; one that regresses is rejected and logged.
- A rejected edit re-encountered in a later session is recognized from the buffer and not re-applied.
- A non-classifier skill edit is unaffected by the gate.
