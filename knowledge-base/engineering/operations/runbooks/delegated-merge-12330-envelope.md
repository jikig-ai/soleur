# Delegated merge of change 12330 (epic 10390)

## Production Envelope - merge 12330

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6718712430
Epic: #10390
Scope item: 1

Command:

```text
gh pr merge 12330 --squash --auto
```

Blast radius: The squash merge of pull request 12330 admits a second Cloudflare Access service token id beside the live one in the deploy policy token list of apps/web-platform/infra/tunnel.tf, so the deploy webhook accepts either token during the rotation cutover. The merge fires apply-web-platform-infra.yml on push, which runs the production Terraform apply for the web-platform infra root, and it starts the standard release workflows. The old token id stays accepted, so nothing in flight is locked out.
Preconditions:
- Gate: no-inflight-run apply-web-platform-infra.yml
Verification:
- `gh pr view 12330 --json state,mergedAt`
- `gh run list --workflow apply-web-platform-infra.yml --limit 3`
Abort: Do not arm the merge if any required check is not green, if the recorded review is missing, if the pull request head moved past 7e6ebb174bda55518b2cd1a94d39fb274ba16113, or if the production apply workflow is already running.
Rollback: Undo by a revert change of the squash merge commit on the default branch, created under scope item 4 of the same delegation, then wait for the required checks and merge it through the queue.
Stop conditions: Halt if the merge queue ejects the change, if a required check turns red after queueing, or if the production apply run the merge fired ends in failure.
