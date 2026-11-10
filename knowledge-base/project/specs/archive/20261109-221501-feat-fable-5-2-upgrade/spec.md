---
feature: feat-fable-5-2-upgrade
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-11-09-fable-5-2-upgrade-brainstorm.md
pr: 12513
issue: 12514 (deferred CLI bump)
---

# Spec: Fable 5.2 upgrade

## Problem Statement

Fable 5.2 (`claude-fable-5-2`) shipped 2026-11-09 at $8/$40 per MTok. Soleur's model-launch tooling and policy docs still describe Fable 5.1 ($10/$50), and the audit's stale-ID map still targets `claude-fable-5-1`.

## Goals

- Retarget the model-ID autofix map to `claude-fable-5-2` (single hop).
- Record the Fable 5.2 pricing basis and re-tier review in ADR-053 and `plugins/soleur/AGENTS.md`.
- Record the explicit non-adoptions (fast mode, preserved thinking, orchestrator role) in an ADR-083/110 addendum.

## Non-Goals

- No `claude-code` CLI bump in this PR (follow-up issue).
- No fast mode, preserved thinking, orchestrator role or effort change.
- No edit to `MODEL_PRICING` (billing constant, operator authorization).
- No Mythos 5.2 integration (no public API ID).

## Functional Requirements

- FR1: `AUTOFIX_PAIRS` maps every same-tier Fable predecessor to `claude-fable-5-2`; `assert_single_hop` passes.
- FR2: `model-launch-review.test.ts` and SKILL.md release list reflect the 5.2 launch.
- FR3: ADR-053 gains a "Fable 5.2 re-tier review" section with every price row re-derived from the official pricing page.
- FR4: `plugins/soleur/AGENTS.md` pricing basis is refreshed and dated.
- FR5: ADR-083 or ADR-110 addendum lists the rejected article items with reasons.

## Technical Requirements

- TR1: `audit-models.sh` rerun shows no findings; `model-launch-review.test.ts` passes.
- TR2: Vendor speed and block-rate claims are labelled as vendor claims.
- TR3: Follow-up issue records the 2.1.321 bundle check and the flip condition for the CLI bump.
