# Brainstorm: Make the sole-copy LUKS Guard 1 suite a required check (epic #9927 item 10)

Date: 2026-11-03. Ref #9927 (epic stays open; never `Closes`). Lane: cross-domain.

## What We're Building

Make a red Guard 1 (`apps/web-platform/infra/inngest-luks-sole-copy.test.sh`) block merge, without touching the CI ruleset, and record the result in ADR-282 and the two legal records that currently call Guard 1 "advisory".

Correction to the resume brief: Guard 1 is `inngest-luks-sole-copy.test.sh`. `inngest-redis-luks.test.sh` is a different suite.

## Why This Approach

Today Guard 1 runs only in the path-filtered `deploy-script-tests` job of `infra-validation.yml`, which is not a required context. One diff can weaken the Terraform pins and the guard that checks them and still merge green (ADR-282, "Enforcement posture"). Changing `infra/github/ruleset-ci-required.tf` is a Terraform apply to a ruleset and is excluded. Registering the suite in a shard that is already inside the required `test` aggregate closes the gap with no new required context.

## Key Decisions (CTO-ruled 2026-11-03, Ruled by CTO agent)

| Question | Decision | Evidence |
|---|---|---|
| Which shard | `test-scripts`: add `run_suite "apps/web-platform/infra/inngest-luks-sole-copy" bash ...` to the `want_scripts` block of `scripts/test-all.sh`, next to the privileged-tier census registration | `test-scripts` is in `test`'s `needs` and is not path-filtered. `test-scripts-heavy` is a 60-min one-suite-per-leg carve-out. A new CI step would need new required-context wiring |
| Flakiness | Low | Local run: 89/89 in 39.7s. No sudo, no network, no terraform call. Needs `python3` with PyYAML on the runner (unverified); absence fails closed |
| Double registration | Verify first | Guard 1 is also globbed by `run-registered-suites.sh`. If `lint-orphan-test-suites.sh` rejects both, use a thin `tests/scripts/test-*.sh` wrapper (census precedent) |
| CODEOWNERS rows | Add, as routing text only | `*` already names `@deruelle` and the ruleset has no `require_code_owner_review`. ADR wording must say "routing hint, not enforcement" |
| G2e sunset | Follow-up, not this PR | Deleting the independent anchor in the same diff that adds the new gate is the one-diff weakening the anchor exists to prevent. Amend the SUNSET comment to say G2e may stay as the independent anchor |
| Deregistration pin | Add to this PR | Small pin in `terraform-target-parity.test.ts` (runs in `test-bun`) asserting the `run_suite` line exists in `test-all.sh`, so one diff cannot drop the registration and the pins together |
| Legal records (CLO) | Update on merge, no gate | Article 30 register TOM (13) and `compliance-posture.md` say "advisory until promoted (#9927)". Amend in-cell with a dated `Superseded` marker, conditional on merge, citing the check by name. Do not touch the #8528 off-project-copy text |
| Ruleset | Unchanged | Out of scope |

## User-Brand Impact

- **Artifact:** the CI enforcement of the sole-copy Inngest LUKS volume guards.
- **Vector:** a weakened pin merges green and the only copy of user scheduler data is lost or unprotected.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering, Legal (CPO not spawned: no product surface; CMO/COO/CFO/CRO/CCO not relevant).

### Engineering
CTO ruled all four questions above; risk is low, fail-closed on a missing dependency.

### Legal
No new gate. Two records state Guard 1's advisory status in the present tense and need a conditional amendment on merge; published policies make no such claim.

## Open Questions

- Does `lint-orphan-test-suites.sh` accept the suite in both `test-all.sh` and the infra runner? (verify at plan/work time; wrapper fallback ruled)
- Is PyYAML present on the `test-scripts` runner image? (verify at plan time)
- Which `suite-shard-legs.tsv` leg takes the ~40s suite? (plan-time measurement)
- (out of scope) Item 8, `doppler_service_token.inngest_arm_write`: needs a plan-time check that the arm and rollback ops are retired.
- (out of scope) Operator-reserved holds stand: A6 owner sentence, off-project ciphertext copy, `apply_target=inngest-host-replace`, closing #9927.
