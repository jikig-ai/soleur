# Ship-Merge Trigger UX

Migrated from GHA `scheduled-ship-merge.yml` to Inngest event function `event-ship-merge.ts` (TR9 Phase 2 E3, #3948).

## Trigger

The ship-merge function is event-triggered — it runs when an event is sent, not on a cron schedule.

### Via Inngest dashboard

Navigate to the Inngest dashboard → Events → Send Event:

```json
{
  "name": "ship-merge.manual-trigger",
  "data": {}
}
```

### Via CLI

```bash
inngest send '{"name":"ship-merge.manual-trigger","data":{}}'
```

### With PR override

To ship a specific PR instead of auto-selecting:

```json
{
  "name": "ship-merge.manual-trigger",
  "data": { "pr_number": 1234 }
}
```

## PR Selection Logic

When no `pr_number` override is provided, the function selects the oldest open PR that:

1. Is **not a draft**
2. Targets **main**
3. Is **older than 24 hours**
4. Does **not** have `ship/failed` or `no-auto-ship` labels

## Failure Handling

If the ship fails (claude-eval exits non-zero and the PR is still open):

1. The `ship/failed` label is added to the PR
2. A failure comment is posted

To re-queue the PR, remove the `ship/failed` label and re-trigger.

## Scheduling Recurring Runs

To run ship-merge on a recurring schedule, use Inngest's scheduled event sending or create a lightweight cron function that emits the event:

```bash
inngest send '{"name":"ship-merge.manual-trigger","data":{},"ts":"2026-05-27T14:00:00Z"}'
```
