---
feature: feat-luks-guard-required-check-codeowners
lane: cross-domain
brand_survival_threshold: single-user incident
tracking: "Ref #9927"
draft_pr: 11998
brainstorm: knowledge-base/project/brainstorms/2026-11-03-luks-guard-required-check-codeowners-brainstorm.md
---

# Spec: Guard 1 inside the required `test` check

## Problem Statement

`apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (Guard 1) is not part of any required context, so a diff that weakens the sole-copy LUKS pins and the guard that checks them can merge green. Ref #9927 item 10.

## Goals

- A red Guard 1 blocks merge via the existing required `test` aggregate.
- No change to `infra/github/ruleset-ci-required.tf`.
- The registration cannot be dropped silently.
- ADR-282 and the two legal records state the new posture truthfully.

## Non-Goals

- Executing the G2e sunset (follow-up after the new leg soaks green on `main`).
- Any `require_code_owner_review` enforcement.
- The off-project ciphertext copy, A6 sentence, host replace, closing #9927.
- Item 8 (`doppler_service_token.inngest_arm_write`).

## Functional Requirements

- FR1: Register Guard 1 in the `want_scripts` block of `scripts/test-all.sh` (CTO-ruled shape), resolving any double-registration objection from `lint-orphan-test-suites.sh` with a thin wrapper if needed.
- FR2: Add the suite to `scripts/suite-shard-legs.tsv` on a lightly loaded leg.
- FR3: Add a pin in `plugins/soleur/test/terraform-target-parity.test.ts` asserting the `run_suite` registration exists.
- FR4: Add CODEOWNERS rows for `plugins/soleur/test/terraform-target-parity.test.ts`, `tests/scripts/test-infra-privileged-tier-census.sh`, `tests/scripts/lib/hcl-effective-text.sh` and the Inngest host-replace gate library.
- FR5: Append an ADR-282 addendum with measured before/after; say CODEOWNERS rows are a routing hint, not enforcement; amend the G2e SUNSET comment.
- FR6: Amend Article 30 register TOM (13) and `compliance-posture.md` with a dated `Superseded` marker, conditional on merge, citing the check by name.

## Technical Requirements

- TR1: Confirm `python3` + PyYAML on the `test-scripts` runner; a missing dependency must fail closed.
- TR2: Measure suite runtime on the runner and record it in the ADR addendum.
- TR3: Use `Ref #9927`, never `Closes`.
