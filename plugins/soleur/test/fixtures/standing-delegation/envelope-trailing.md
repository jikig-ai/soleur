## Production Envelope - trailing space

Delegation: @URL@
Scope item: 2

Command:

```text
gh pr merge 123 --squash
gh pr merge 124 --squash@TRAILSP@
```

Blast radius: one example service.
Preconditions:
- Gate: pr-merged 123
Verification:
- bash scripts/example-probe.sh
Abort: stop if the earlier change is not live.
Rollback: revert the squash commit with a new change.
Stop conditions: the probe fails.
