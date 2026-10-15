# Example runbook (synthesized fixture)

## Production Envelope - first merge

Delegation: @URL@
Scope item: 1

Command:

```text
gh pr merge 123 --squash
gh workflow run example-release.yml -f target=staging
```

Blast radius: one example service, staging only.
Preconditions:
- Gate: no-inflight-run example-release.yml
- Gate: pr-merged 120
Verification:
- bash scripts/example-probe.sh --since 30m
Abort: stop before the merge if any precondition is false.
Rollback: revert the squash commit with a new change and re-run the release.
Stop conditions: the probe reports a failure twice in a row.
