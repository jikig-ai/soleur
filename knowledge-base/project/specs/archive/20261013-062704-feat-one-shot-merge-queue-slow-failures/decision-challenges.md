# Decision challenges (plan-review, headless)

## Taste: early-stop mechanism for e2e cascades
Reviewers disagreed: DHH kept `maxFailures: 10` and cut the probe; code-simplicity cut `maxFailures` and proposed `url:` readiness; CTO would apply a cap on merge_group only. Plan default: ship `url:` readiness only (zero new files), no `maxFailures`. Revisit if a new whole-environment cascade appears (auth server death was 2 of 303 e2e runs).

## Taste: Guard weight
Reviewers (DHH, simplicity, CTO) asked for a smaller Guard 1; the plan keeps the minimum the Guard Contract lint accepts (6 mutation rows, one floor) and drops the sha256-in-test and the probe guard.
