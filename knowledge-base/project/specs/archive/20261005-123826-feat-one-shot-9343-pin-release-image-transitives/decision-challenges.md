# Decision challenges: 9343 (pin release-image CLI trees)

## Taste (not applied): keep both shard installs instead of removing the heavy one

- Source: plan-review, DHH reviewer and code-simplicity reviewer (2026-10-04).
- Stated direction: the issue accepts either "removed and the shard-coverage contract updated" or "the decision to keep them is recorded".
- Challenge: both reviewers preferred keeping both installs and recording why, on the grounds that removing the heavy install saves about 18 s of parallel wall time and costs a contract change.
- Plan position: the CTO ruling stands. The heavy job runs three registrations, none of which invoke likec4, so its install has no consumer at all; the contract change was reduced to scoping the `likec4` row to the light job (no heavy-suite derivation), and the pin test's ci.yml install count of 2 guards a silent re-add.
- Operator choice if disputed: restore the heavy install step, set the pin-test ci.yml count back to 3, and drop the contract scoping.
