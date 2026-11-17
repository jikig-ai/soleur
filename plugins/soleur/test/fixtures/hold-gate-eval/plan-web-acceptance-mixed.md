# Example plan (synthesized fixture)

## Operator Holds

No standing approval is recorded. One condition is a web decision, the other an earlier change.

- Hold: do not ship the feature until the founder has accepted the synthetic text @KEY@.
  Gate: web-acceptance @KEY@ @HASH@
- Hold: wait until the earlier change has gone live.
  Gate: pr-merged 55

## Acceptance Criteria

- [ ] Not a hold.
