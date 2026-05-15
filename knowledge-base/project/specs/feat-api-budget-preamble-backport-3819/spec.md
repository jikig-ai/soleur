---
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: API-budget operator preamble backport to autonomous-loop skills

**Issue:** [#3819](https://github.com/jikig-ai/soleur/issues/3819)
**Branch:** feat-api-budget-preamble-backport-3819
**Date:** 2026-05-15
**Brainstorm:** [2026-05-15-api-budget-preamble-backport-brainstorm.md](../../brainstorms/2026-05-15-api-budget-preamble-backport-brainstorm.md)
**Parent PR:** [#3809](https://github.com/jikig-ai/soleur/pull/3809) (merged, source of canonical preamble)
**Draft PR:** [#3839](https://github.com/jikig-ai/soleur/pull/3839)

## Problem Statement

Parent docs PR #3809 introduced an API-budget operator disclosure paragraph on the new `/goal` docs page (`plugins/soleur/docs/pages/goal-primitive.md` §"What it consumes"), establishing the convention that any operator-facing primitive consuming Anthropic API budget must disclose: per-turn cost model, runaway risk, and the Soleur/Anthropic billing split + BSL 1.1 disclaimer. The same disclosure is missing from six pre-existing autonomous-loop skills that consume operator API budget under the same model. The asymmetry would, on a first runaway invocation, look like Soleur hid the cost surface on its own primitives while disclosing it on Claude Code's — a single-user incident threshold trust breach.

## Goals

- **G1:** Backport a uniform API-budget operator preamble to all six autonomous-loop skills.
- **G2:** Use a single auditable surface (fenced `<decision_gate>` block) across all six so a one-line grep can verify coverage.
- **G3:** Tailor the cost-model paragraph per skill (bounded iteration vs. parallel agent fan-out vs. wall-clock pipeline) without diverging the Soleur/Anthropic billing split prose.
- **G4:** Introduce a new AGENTS.md hard rule + CI assertion binding any future autonomous-loop skill to the same preamble.

## Non-Goals

- Adding a runtime billing-cap check (Anthropic dashboard concern; not Soleur's surface).
- Removing or rewording the existing `test-fix-loop` `<decision_gate>` block at lines 42-46 — it stays as the *pre-flight confirmation* gate. The new API-budget block is a sibling.
- Retrofitting `/goal` into any of the six skills (plugin AGENTS.md guidance forbids this).
- Collecting empirical per-skill cost telemetry (deferred; the disclosure prose is the deliverable).
- Per-skill PRs (single bundled PR per brainstorm decision).

## Functional Requirements

- **FR1:** Each of the six SKILL.md files contains a fenced `<decision_gate>` block whose body covers (a) cost-per-iteration model tailored to the skill, (b) runaway-cost risk, (c) Soleur/Anthropic billing split + BSL 1.1 disclaimer.
- **FR2:** The Soleur/Anthropic billing split + BSL 1.1 sentences are reused verbatim from `plugins/soleur/docs/pages/goal-primitive.md` §"What it consumes" (no paraphrase).
- **FR3:** Block placement: after the skill's intro paragraph, before its first "When to use" / "Phase 0" / "Workflow" section.
- **FR4:** For `test-fix-loop`, the new API-budget `<decision_gate>` block sits separately from the existing pre-flight confirmation `<decision_gate>` block (lines 42-46). Plan-phase decides whether two adjacent fenced blocks or a single merged block reads better.
- **FR5:** A new AGENTS.md hard rule (working slug: `hr-autonomous-loop-skill-must-disclose-api-budget`) is added to the correct sidecar tier (`AGENTS.core.md` or `AGENTS.rest.md`) per the change-class loader rules.
- **FR6:** A CI assertion in `plugins/soleur/test/components.test.ts` (or sibling test file) verifies every autonomous-loop skill (six named today) contains an API-budget `<decision_gate>` block.

## Technical Requirements

- **TR1:** Edits are body-text only — no `description:` frontmatter changes, no impact on the 1800-word cumulative skill-description budget.
- **TR2:** Single bundled PR (already opened as draft PR #3839) edits all six SKILL.md files + the AGENTS sidecar + the CI test.
- **TR3:** The CI assertion targets the literal `<decision_gate>` token + a disambiguating sentinel inside the block (e.g., "Soleur does not bill or proxy these calls") so a future *unrelated* `<decision_gate>` in one of these skills doesn't satisfy the budget-preamble check.
- **TR4:** Plan must include a precondition step measuring current SKILL.md description budgets and AGENTS sidecar tier budgets before authoring, per `cq-skill-description-budget-headroom` and `cq-agents-md-tier-gate` rules.
- **TR5:** Ship gate (preflight Check 6) must run because `brand_survival_threshold: single-user incident` propagates from the parent plan.

## Acceptance Criteria

- [ ] All six skills carry an API-budget `<decision_gate>` block (manual grep returns 6/6 matches).
- [ ] The Soleur/Anthropic billing split + BSL 1.1 disclaimer prose matches the canonical version in `goal-primitive.md` byte-for-byte.
- [ ] Each block's cost-model paragraph is tailored: `test-fix-loop` cites iteration cap; `drain-labeled-backlog` cites cluster × one-shot multiplier; `resolve-todo-parallel` + `resolve-pr-parallel` cite N-parallel-agents; `work` cites tier-cost framing; `one-shot` cites 30-90 min wall-clock.
- [ ] AGENTS sidecar rule `hr-autonomous-loop-skill-must-disclose-api-budget` is present in the correct tier with `Why:` + `How to apply:` lines.
- [ ] CI assertion in `plugins/soleur/test/components.test.ts` (or sibling) passes when all six skills carry the block; fails if any one is missing.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] Existing `test-fix-loop` pre-flight `<decision_gate>` at lines 42-46 (or its repositioned equivalent) is preserved with no functional change.
- [ ] PR #3839 carries `## Changelog` section + `semver:patch` label (docs-only change).
- [ ] user-impact-reviewer agent (conditional on `brand_survival_threshold`) reviews the PR and approves.

## Open Questions

- **OQ1 (plan):** Rule slug — `hr-autonomous-loop-skill-must-disclose-api-budget` or shorter? Constraint: slug + one-line description must stay under the AGENTS sidecar's per-rule description-line budget.
- **OQ2 (plan):** AGENTS sidecar tier — `core` (loaded every turn) or `rest` (loaded selectively)? The rule fires at skill-authoring time, not per-turn, so `rest` is the natural home unless it also belongs in the change-class load for `docs-only` and `rest` tiers.
- **OQ3 (plan):** For `test-fix-loop`, merge the two `<decision_gate>` blocks or keep adjacent? Two blocks are clearer (different concerns: API-budget disclosure vs. pre-flight confirmation), but adjacency may suggest merging. Plan-phase to read the actual file and decide.
- **OQ4 (plan or follow-up):** Should the AGENTS rule list the six skills by name (brittle to renames) or define an autonomous-loop skill via a regex/marker (e.g., any skill whose body contains the word "iteration" or "loop")? Latter is more robust; former is more readable.
