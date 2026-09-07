---
title: CI's contribution to the deploy gate is a declared, bounded budget
status: accepted
date: 2026-09-07
---

# ADR-208: CI's contribution to the deploy gate is a declared, bounded budget

- **Deciders:** Jean (operator), CTO agent (mechanism assessment), plan review panel
  (architecture-strategist, test-design-reviewer, code-simplicity-reviewer, spec-flow-analyzer)
- **Relates to:** #7902 (this change), [ADR-072](./ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md)
  (the gate this bounds; amended by the same PR), #5806 (deploy off `workflow_run` — still open,
  re-armed), [ADR-133](./ADR-133-test-all-advisory-lock-and-runtime-ceiling.md) (the runner
  contention layer, CI-exempt and unchanged), [ADR-181](./ADR-181-relevance-declines-are-counted-verdicts.md)
  (relevance declines are counted verdicts — why totality quantifies over ASSIGNED, not EXECUTED)

## Context

`web-platform-release.yml`'s `await-ci` job fail-closes the prod deploy when CI's `test`
aggregator check-run has not concluded within a wall-clock ceiling. On 2026-09-07 every deploy
was blocked: two consecutive runs died at 3005s and 3002s against a 3000s ceiling, on different
SHAs, while their CI runs were healthy. A production outage fix sat merged-but-undeployed
because of it.

The gate's fail-closed posture was correct and is not the defect. The defect was that CI's
duration and the gate's ceiling were coupled by nothing: CI could grow without limit, and the
only signal that it had outgrown the gate was a blocked production deploy.

## Decision

1. **The gated metric is time-to-`test`, not run wall clock.** `await-ci` polls the `test`
   check-run and exits 0 the moment it concludes success, so jobs outside `test`'s `needs`
   closure cannot delay it. Every sizing statement about this gate must be expressed in that
   quantity. ADR-072's item 4 sized the ceiling in run wall-clock terms — a quantity the gate
   does not measure — and that mis-framing is a root cause of this incident, not a footnote.

2. **CI's declared budget is bounded by the gate's ceiling, mechanically.** Every job in
   `test`'s `needs` closure declares `timeout-minutes`, and a guard asserts
   `max(closure ceilings) + test's own <= CEILING_S / 60`, reading `CEILING_S` out of
   `web-platform-release.yml` rather than restating it. `max`, not `sum`: the shards run in
   parallel and only the aggregator is serial after them — the same critical-path arithmetic
   `prod-version-drift-check.sh` already applies to `max(release, await-ci)`.

   A job with NO `timeout-minutes` reads as GitHub's 360-minute default, never as zero, so
   deleting a ceiling fails the guard instead of silently shrinking the computed bound.

3. **The bound is enforced at the moment of divergence.** The guard runs in CI, so growing a
   ceiling past what the gate can absorb reds a required check on the offending PR — rather
   than surfacing as a blocked deploy days later, which is how #7902 was discovered.

## Consequences

- Raising a CI job's ceiling is now a two-file change: the ceiling, and either headroom under
  `CEILING_S` or `CEILING_S` itself (which in turn moves `DRIFT_SUSTAINED_THRESHOLD_MIN`, in
  that order — B9 asserts threshold >= critical path and reds if the ceilings move first).
- The coupling is deliberate friction. It makes "CI got slower" a decision with a visible cost
  rather than a drift nobody owns.
- **Named residual:** the guard bounds DECLARED ceilings, which bound EXECUTION only. Runner
  dispatch delay (measured run-creation to job-start: p50 1.4, p90 12.4, max 21.0 min) sits
  outside every job timeout and is now the dominant term in time-to-`test`. That is tracked
  separately as runner-pool contention; this ADR does not claim to bound it.
