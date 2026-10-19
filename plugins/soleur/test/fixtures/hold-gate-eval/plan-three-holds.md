# Example plan (synthesized fixture)

## Overview

Nothing in this section is a hold.

## Operator Holds

This section is read by ship Phase 6 step 5, not from conversation.

Delegation: @URL@
Envelope: env-valid.md

- Hold: do not ship until the earlier change has gone live.
  Gate: pr-merged 55
- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
- Hold: wait until the second earlier change has gone live.
  Gate: pr-merged 120

## Acceptance Criteria

- [ ] Not a hold.
