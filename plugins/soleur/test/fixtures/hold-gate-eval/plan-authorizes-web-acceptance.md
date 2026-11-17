# Example plan (synthesized fixture)

## Operator Holds

No standing approval is recorded. One hold waits on the operator's go; the other is a web decision on a text that is not in the project.

- Hold: Operator-authorizes: rotate the deploy credential after the checks pass.
  Gate: pr-merged 55
- Hold: do not ship the feature until the founder has accepted the synthetic text no-such-text.
  Gate: web-acceptance no-such-text 0000000000000000000000000000000000000000000000000000000000000000

## Acceptance Criteria

- [ ] Not a hold.
