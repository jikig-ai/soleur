## Production Envelope - trailing space

Delegation: @URL@
Epic: #77
Scope item: 2

Command:

```text
gh pr merge 124 --squash --auto
gh pr merge 124 --squash@TRAILSP@
```

Blast radius: one example service.
Preconditions:
- Gate: pr-merged 123
Verification:
- bash scripts/example-probe.sh
- `EV=$(gh pr view 124 --json comments --jq 'x') && H=$(gh pr view 124 --json headRefOid --jq .headRefOid) && git merge-base --is-ancestor "$EV" "$H" && R=$(git rev-list --first-parent --no-merges "$EV..$H") && [ -z "$R" ]`
Abort: stop if the earlier change is not live.
Rollback: revert the squash commit with a new change.
Stop conditions: the probe fails.
