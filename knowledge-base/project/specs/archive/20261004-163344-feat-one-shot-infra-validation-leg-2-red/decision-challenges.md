# Decision challenges: feat-one-shot-infra-validation-leg-2-red

## DC-1 (Taste): add a repo lint for exact-141 assertions without a disposition marker

- Source: plan-review, CTO devex lens (advisory).
- Proposal: a cheap check (one grep in the existing lint set or guard-vacuity-floor) that flags any tracked `*.test.sh` asserting an exact `141` unless it also contains `trap '' PIPE`, a forced-disposition helper, or an explicit "accepts 141 or 1" marker, so the next suite cannot repeat this red. Advice alone (the 2026-08-20 learning) already failed once.
- Why it was not applied: the brief says "This PR is ONLY the SIGPIPE-disposition fix" and "Do not widen the fix beyond this suite unless the grep finds another deterministic failure". The fleet sweep found none.
- Default (the operator's stated direction): not applied. Decide whether to file it as a separate small follow-up.
