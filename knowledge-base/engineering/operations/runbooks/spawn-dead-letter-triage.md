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
| `(timed_out)` | Probably the 10-minute `timeouts.finish` cutoff: `extra.elapsedMs` ≥ 600000. It is a heuristic, measured from when the event was queued, so a manual cancel of a run that waited in the queue can read as `timed_out`. |
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

**`(failed)`.** Search Sentry for `inngest.run_id:<extra.failedRunId>` to find the failed run's own final-error capture (layer 1, from the correlation middleware). `scripts/sentry-issue.sh` has no tag-query mode, so run it through the org events endpoint with the same read-only token: `doppler run -p soleur -c prd -- sh -c 'curl -sS -H "Authorization: Bearer $SENTRY_ISSUE_RO_TOKEN" "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/?query=inngest.run_id:<id>&field=title&field=id"'`. Its stack names the step that threw. Pino carries no per-run line for the leader loop, so do not look for run lines in Better Stack.

**`(timed_out)`.** A turn hung, or eight turns of retries outran ten minutes. During an Anthropic rate-limit or 5xx storm, finish timeouts become the likely ending, and they page as `leader_internal_error … (timed_out)` rather than as `anthropic_rate_limited`: before treating one as our defect, check Anthropic's status page and whether `(timed_out)` issues opened across several classes at once. This often happens during an Anthropic 429/5xx storm. Check whether the same class also shows `anthropic_rate_limited` or `anthropic_timeout` warnings around that time. If the founder clicked Stop before the timeout, the settle still pages: a Stop only sets `cancellation_requested_at`, so a hang that keeps the turn from reaching its cancel check is a defect.

**`(cancelled)`.** Someone cancelled the run at the Inngest level. If the founder had clicked Stop, the event is `cancelled_by_operator` at warning level and nobody is paged. A paged `(cancelled)` means no Stop was pending, or the envelope carried no timestamp to prove the cancel preceded the timeout. Who cancelled it is recorded only in the Inngest dashboard, which has no read path without a host shell today; note the run id and move on.

**`(settle_failed)`.** The card may still read "Working". If `extra.err.message` is `agent-on-spawn-settle: lifecycle envelope failed validation`, the envelope was malformed or foreign, and the event carries only `failedRunId` (when it had a valid shape). Otherwise the settle's database write, or the `onFailure` forward, failed past its retries. There is no automated re-drive: record each `actionSendId` on #8839, which tracks the backstop. The alert pages once per issue per day, so list every event in the issue (the events endpoint above, `query=` the issue's message), not only the latest one.

**No suffix, `leader_internal_error`.** An in-step error that no classifier arm recognised, for example a failed cost write after billing. The first ~10 minutes after a deploy (the finish timeout) can bring one false page per in-flight retry: a StepError thrown by the previous build has no tag, so a genuine Anthropic error in `extra.err.message` reads as `leader_internal_error`. That is the known rollout artifact.

## 3. Artifacts without Undo (#8845)

A run that died after a `turn-N-tool-i` step created something on GitHub settles to the failure card without Undo. Reversal handles are written only at `mark-acknowledged`. Which tool steps landed, and what they created, is recorded only in the orphaned run's step outputs in the Inngest dashboard, which has no read path without a host shell today. The Sentry step breadcrumbs cannot answer it: each covers only the HTTP invocation that emitted it. So for any lifecycle suffix on a class with write tools, tell the founder a tool step may have landed and ask them to check the repository named in `extra.sourceRef`.
