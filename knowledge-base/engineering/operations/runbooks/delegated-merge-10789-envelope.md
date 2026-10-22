# Delegated merge of change 10789 (epic 9757)

## Production Envelope - merge 10789

Delegation: https://github.com/jikig-ai/soleur/issues/9757#issuecomment-6341824717
Epic: #9757
Scope item: 1

Command:

```text
gh pr merge 10789 --squash --auto
```

Blast radius: Repository instruction text only: one ship reference, one rule body, one lint-ignore line and one runbook. It touches no infrastructure apply path. Merging starts the standard automatic plugin release and web release workflows, which publish the new text and change no behaviour of the running app.
Preconditions:
- Gate: no-inflight-run apply-web-platform-infra.yml
Verification:
- `gh pr view 10789 --json state,mergedAt`
- `gh run list --workflow apply-web-platform-infra.yml --limit 3`
Abort: Stop before the merge if any required check is not green, if the recorded review is missing, or if the production deploy workflow is running.
Rollback: Undo by a revert change of the squash commit on the default branch, created under scope item 2 of the same delegation, then wait for the required checks and merge it through the queue.
Stop conditions: Halt if the merge queue ejects the change, if a required check turns red after queueing, or if the production deploy workflow starts during the merge.
