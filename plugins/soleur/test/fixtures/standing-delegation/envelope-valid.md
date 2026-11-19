# Example runbook (synthesized fixture)

## Production Envelope - first merge

Delegation: @URL@
Epic: #77
Scope item: 1

Command:

```text
gh pr merge 123 --squash
gh pr merge 123 --squash --auto
```

Blast radius: one example service, staging only.
Preconditions:
- Gate: no-inflight-run example-release.yml
- Gate: pr-merged 120
Verification:
- bash scripts/example-probe.sh --since 30m
- `EV=$(gh pr view 123 --json comments --jq 'x') && H=$(gh pr view 123 --json headRefOid --jq .headRefOid) && git merge-base --is-ancestor "$EV" "$H" && R=$(git rev-list --first-parent --no-merges "$EV..$H") && [ -z "$R" ]`
Abort: stop before the merge if any precondition is false.
Rollback: revert the squash commit with a new change and re-run the release.
Stop conditions: the probe reports a failure twice in a row.
