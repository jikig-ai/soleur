# Two envelopes in one file (synthesized fixture)

## Production Envelope - alpha merge

Delegation: @URL@
Scope item: 1

Command:

```text
gh pr merge 123 --squash
```

Blast radius: one example service.
Preconditions:
- Gate: pr-merged 120
Verification:
- bash scripts/example-probe.sh
Abort: stop before the merge.
Rollback: revert the squash commit with a new change.
Stop conditions: the probe fails.

## Production Envelope - beta dispatch

Delegation: @URL@
Scope item: 3

Command:

```text
gh workflow run example-release.yml -f target=staging
```

Blast radius: one example service.
Preconditions:
- Gate: no-inflight-run example-release.yml
Verification:
- bash scripts/example-probe.sh
Abort: stop before the dispatch.
Rollback: dispatch the previous release.
Stop conditions: the probe fails.
