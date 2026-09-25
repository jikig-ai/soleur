---
category: operations
tags: [sentry, inngest, leader-loop, dead-letter, adr-042, adr-251]
date: 2026-09-25
---

# Spawn dead-letter triage (`sentry_alert.spawn_agent_dead_letter`)

The alert emails you for a paged leader-loop dead-letter. The email subject is the Sentry message
`agent-on-spawn deadlettered: <reason> [<actionClass>]`, and sometimes it ends with a lifecycle
suffix. The suffix tells you which path produced the event (#8803, ADR-042 §I6, ADR-251):

| Suffix | Meaning |
|---|---|
| none | The handler caught the failure itself (`persistFailure`). |
| `(failed)` | The run failed past its retries. `onFailure` forwarded it, and `agent-on-spawn-settle` recorded the failure. |
| `(cancelled)` | Inngest cancelled the run (API, dashboard or bulk cancel) before the finish timeout. |
| `(timed_out)` | The run hit the 10-minute `timeouts.finish` cutoff (`extra.elapsedMs` ≥ 600000). |
| `(settle_failed)` | The settle step itself failed, or the lifecycle envelope failed validation. The card may still show "Working". |

Every step below reads data; none needs a host shell.

## 1. Read the event

```bash
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>
```

The fields to read:

- `extra.err.name` / `extra.err.message`: the error. On `(failed)`, this is the failed run's own final error.
- `extra.actionSendId`, `extra.messageId`, `extra.sourceRef`: the spawn. `userIdHash` is the pseudonymized founder.
- `extra.failedRunId`: the orphaned run's id. This is not the settle function's run.
- `extra.elapsedMs`: the time from when the spawn was queued to the lifecycle event. It is `null` when a timestamp was missing.

## 2. Per suffix

**`(failed)`.** Search Sentry for `inngest.run_id:<extra.failedRunId>` to find the failed run's own final-error capture (layer 1, from the correlation middleware). Its stack names the step that threw. Pino carries no per-run line for the leader loop, so do not look for run lines in Better Stack.

**`(timed_out)`.** A turn hung, or eight turns of retries outran ten minutes. This often happens during an Anthropic 429/5xx storm. Check whether the same class also shows `anthropic_rate_limited` or `anthropic_timeout` warnings around that time. If the founder clicked Stop before the timeout, the settle still pages: a Stop only sets `cancellation_requested_at`, so a hang that keeps the turn from reaching its cancel check is a defect.

**`(cancelled)`.** Someone cancelled the run at the Inngest level. If the founder had clicked Stop, the event is `cancelled_by_operator` at warning level and nobody is paged. A paged `(cancelled)` means no Stop was pending. Find out who cancelled it.

**`(settle_failed)`.** The card may still read "Working". If `extra.err.message` is `agent-on-spawn-settle: lifecycle envelope failed validation`, the envelope was malformed or foreign. Otherwise the settle step's database call failed past its retries. This PR ships no automated re-drive: record the `actionSendId` on #8839, which tracks the backstop.

**No suffix, `leader_internal_error`.** An in-step error that no classifier arm recognised, for example a failed cost write after billing. The first ~30 minutes after a deploy can bring one false page per in-flight retry: a StepError thrown by the previous build has no tag, so a genuine Anthropic error in `extra.err.message` reads as `leader_internal_error`. That is the known rollout artifact.

## 3. Artifacts without Undo (#8845)

A run that died after a `turn-N-tool-i` step created something on GitHub settles to the failure card without Undo. Reversal handles are written only at `mark-acknowledged`. For any lifecycle suffix, check the orphaned run's tool-step outputs in the Inngest run history (`extra.failedRunId`). Then tell the founder what landed, or reverse it.
