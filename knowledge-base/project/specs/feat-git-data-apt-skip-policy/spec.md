---
lane: cross-domain
brand_survival_threshold: single-user incident
closes: 9394
---

# Spec: git-data apt skip policy (#9394)

## Problem Statement

After PR #9383 bounded the in-container apt cycles, four git-data CI arms stay hard-fail during a sustained apt archive outage: T5 primary, T17 healthy, R4, and the ownership runtime arm. #9394 asks whether any should become skip-eligible.

## Goals

- Record the decision (Ruled by CTO agent): no arm becomes skip-eligible.
- Mark the ADR-188 User-Challenge resolved, with the flip condition.

## Non-Goals

- Any change to test code or arm_skip routing.
- A per-arm hold mechanism (parked until the flip condition fires).

## Functional Requirements

- FR1: ADR-188 carries a dated resolution of the User-Challenge naming the evidence, the flip condition and the PA-36 wording constraint.

## Technical Requirements

- TR1: Docs only; no behaviour change in `apps/web-platform/infra/`.
- TR2: Follow-up issue filed for repairing the #8856 probe (trigger 1 cannot fire while it returns TRANSIENT).
