---
title: "ADR-238: TEST_GROUP taxonomy carries the CI matrix topology — a new group is a new job, not a new filter"
status: Accepted
date: 2026-09-22
supersedes: []
amends:
  - ADR-183
tags: [ci, test-sharding, fail-closed, matrix]
---

# ADR-238: TEST_GROUP taxonomy carries the CI matrix topology — a new group is a new job, not a new filter

## Status

Accepted — 2026-09-22. Implements the `test-scripts` leg-balance fix for
#8006; the positional-sharding diagnosis it sits on is #7931.

## Context

`test-scripts (2/3)` measured 31–39 minutes on every sampled CI run while legs
1 and 3 finished in 11–15. Three causes, all measured:

1. `scripts/test-all.sh` runs its ~480 registered bash suites serially per leg.
2. `SCRIPTS_SHARD=k/K` assigns suites to legs positionally by registration
   ordinal — leg membership is a positional accident, and the three heaviest
   suites (`tests/scripts/registry-gate-mutation-battery` 523 s,
   `scripts/battery-tag-authorship-mutations` 380 s,
   `.github/scripts/test/run-all.sh` 371 s) had landed on the same leg.
3. The battery is a floor: no value of K beats the longest single suite, and
   simulation over the CI-measured suite timings showed K=5 still yielding a
   ~21.5-minute worst leg and K=8 a ~13.6-minute one.

Duration-aware partition (LPT) was evaluated and rejected: the shard
chokepoint cannot compute it (assignment happens inside a per-leg runner
invocation with no cross-leg coordination channel), and a weights table would
be a second, driftable copy of the suite registry.

## Decision

1. **The `TEST_GROUP` taxonomy, not the shard count, is the partition
   mechanism.** A new group `scripts-heavy` is added carrying exactly the
   three heavy registrations. `want_scripts_heavy` is true for
   `TEST_GROUP=all` and `TEST_GROUP=scripts-heavy`; the light `scripts` group
   no longer contains them. `TEST_GROUP=all` semantics are unchanged — a
   local full-gate run still executes every registration.

2. **A group is a CI job, so the taxonomy and the matrix move together.**
   The heavy group gets its own `test-scripts-heavy` matrix job in `ci.yml`
   (K=3, one heavy suite per leg, `SCRIPTS_SHARD` reused as the per-leg
   selector), and the light `test-scripts` matrix widens K=3→K=5. Worst leg
   becomes the battery floor plus setup ≈ 10 minutes, versus 31–39 today.

3. **Totality is asserted against an independently derived reference, never
   assumed.** `plugins/soleur/test/scripts-shard-totality.test.sh` extracts
   the heavy reference set by parsing the runner's top-level
   `if want_scripts_heavy; then ... fi` blocks and asserts the workflow's
   declared heavy legs union exactly to it — no dropped registration, no
   duplicate, no valid-but-empty assignment. The same guard keeps the light
   partition total, and the runner's zero-assignment refusal stays armed for
   shard specs owning no registration.

4. **The synthetic `test` check widens to five legs.** `test-scripts-heavy`
   joins the aggregator's `needs:`/`env:`/`entries=()` wiring; a failed or
   skipped heavy matrix fails the required check.

5. **Duplicated workflow pins are guarded for all occurrences, not the
   first.** The heavy job clones the gitleaks/likec4 toolchain;
   `required-checks-canonical-parity.test.sh` and
   `c4-likec4-version-pin.test.ts` were extended so every in-file occurrence
   must agree, closing the first-occurrence blindness.

## Consequences

- `TEST_GROUP` values are now `all`, `webplat`, `bun`, `scripts`,
  `scripts-heavy`, `infra`. Every consumer that derives group count,
  group-name shape, or shard scope was enumerated in the plan
  (`knowledge-base/project/plans/archive/20260923-182911-2026-09-22-feat-ci-test-shard-speedup-plan.md`)
  — the taxonomy is load-bearing in ~10 surfaces beyond the runner and
  workflow.
- `SCRIPTS_SHARD` is now scoped to `scripts` AND `scripts-heavy`; unrelated
  groups still refuse it with exit 2.
- The heavy job's timing artifacts upload under a distinct
  `suite-timings-scripts-heavy-*` prefix — `upload-artifact` v4 names are
  immutable per run, and a shared name would red every leg.
- #8006 stayed open under a follow-through probe
  (`scripts/followthroughs/ci-leg-durations-8006.sh`): the close criterion
  was measured post-merge leg durations, auto-closing once ≥3 qualifying
  main runs showed every `test-scripts*` leg under 900 s. (Closed
  2026-09-24 on sweeper PASS, 20/20 qualifying runs — probe retired.)
- Deferred with issue refs: internal battery splitting (#8006 remainder),
  intra-leg parallelism (#8231), affected-suites local gate (#8322),
  pre-commit battery cost (#8045), contention ceiling (#8163).

## Rejected alternatives

- **Bare K bump.** Measured: K=5 → ~21.5 min worst leg, K=8 → ~13.6 min.
  Round-robin cannot separate the heavies regardless of K.
- **LPT/duration-aware partition.** The shard chokepoint has no cross-leg
  coordination channel; a static weights table is a driftable duplicate
  registry. Rejected in #8006 for the same reason.
- **Splitting the battery internally.** Its green-baseline preflight re-runs
  ~2×5 min of subject suites per leg, so splitting multiplies fixed cost —
  the carve-out gets the same tail reduction without it.
