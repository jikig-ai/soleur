# Delegated drift dispatch (epic 10390)

## Production Envelope - dispatch scheduled-terraform-drift

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6718712430
Epic: #10390
Scope item: 3

Command:

```text
gh workflow run scheduled-terraform-drift.yml
```

Blast radius: The dispatched run reads Terraform state and plan output for the tracked roots and files or updates a drift issue on this repository. It changes no infrastructure and mints no credentials, so the only thing it can touch is the drift tracker issue and its own run log.
Preconditions:
- Gate: no-inflight-run apply-web-platform-infra.yml
- Gate: no-inflight-run scheduled-terraform-drift.yml
Verification:
- `gh run list --workflow scheduled-terraform-drift.yml --limit 2`
- `gh run list --workflow apply-web-platform-infra.yml --limit 3`
Abort: Do not dispatch while a production apply run is still queued or in progress, while a drift run is already queued or in progress, or if the merged change has not reached the default branch.
Rollback: The run only reads state and files a report, so undoing it means cancelling the queued run before it starts and closing the report issue it files.
Stop conditions: Halt if the apply run the merge fired is still in progress when checked, if a drift run is already in progress, or if the dispatched run ends in failure.
