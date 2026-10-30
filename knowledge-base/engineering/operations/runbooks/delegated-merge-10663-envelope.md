# Delegated merge of change 10663 (epic 9757)

## Production Envelope - merge 10663

Delegation: https://github.com/jikig-ai/soleur/issues/9757#issuecomment-6337725135
Epic: #9757
Scope item: 1

Command:

```text
gh pr merge 10663 --squash --auto
```

Blast radius: Repository only. The change edits one rehearsal workflow, one test suite, one deploy reference doc and an affected-test index. It touches no production path and no infrastructure apply path, so no production system changes when it merges.
Preconditions:
- Gate: no-inflight-run apply-web-platform-infra.yml
Verification:
- `gh pr view 10663 --json state,mergedAt`
- `gh run list --workflow apply-web-platform-infra.yml --limit 3`
Abort: Stop before the merge if any required check is not green, if the recorded review is missing, or if the production deploy workflow is running.
Rollback: Undo by a revert change of the squash commit on the default branch, created under scope item 2 of the same delegation, then wait for the required checks and merge it through the queue.
Stop conditions: Halt if the merge queue ejects the change, if a required check turns red after queueing, or if the production deploy workflow starts during the merge.
