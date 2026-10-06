---
feature: runner-sut-registration-narrowing
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [9564, 9307, 9552]
brainstorm: knowledge-base/project/brainstorms/2026-10-06-runner-sut-registration-narrowing-brainstorm.md
status: deferred
created: 2026-10-06
---

# Spec — registration-only second-stage narrowing (#9564)

## Problem Statement

A registration-only runner edit takes the bounded selection (ADR-242 decision 20): ~58.6 min at manifest weights against 91.4 min for the full battery. 13.6 min of its 43 edge suites are four heavy mutation batteries. The brainstorm found the issue's "reach the runner only through self-inclusion" premise holds for at most one of them as an accident; two are deliberately armed by ADR-262 and one genuinely reads the runner.

## Goals

- None scheduled. The work stays deferred until a measured trigger fires.

## Non-Goals

- A per-suite declared runner-SUT set (hand-list, conflicts with ADR-193 §5; guard contract costs more than the saving).
- Any change to the plugin-generic gate for users' repos (epic #9307 PR 2).

## Re-evaluation trigger (replaces the issue's)

Build only when a registration-only run is observed at the bounded cost and a contributor's measured wait is dominated by the 13.6 min, or the gate is again the slowest step of a suite-adding PR.

## If built — requirements

- FR1: generator ignores comment-only path mentions when deriving declared arrays (drops the `registry-delivery-change-mutation-battery` runner edge).
- FR2: under `registration-only`, skip the `PR_GATE_MACHINERY_PATHS` runner arm for PR-gated batteries only, with rows in `scripts/test-all-affected.test.sh`.
- TR1: every path fails toward coverage; `orphan-process-reaper-mutations` and corpus-reading suites stay selected.
- TR2: wording stays "affected-suite gate passed"; CI's full battery stays the merge gate.
