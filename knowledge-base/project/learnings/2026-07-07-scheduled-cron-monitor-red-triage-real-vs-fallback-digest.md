---
title: "Triaging a scheduled-cron monitor stuck RED: distinguish a real digest from a FAILED-fallback issue by BODY, not title"
date: 2026-07-07
category: integration-issues
module: apps/web-platform/server/inngest/functions
tags: [cron, inngest, sentry, better-stack, observability, output-aware-heartbeat, triage]
---

# Learning: a "cron monitor RED but output present" symptom is ambiguous until you read the issue BODY

## Problem

An operator forwarded two Better Stack "cron monitor failing" emails
(`scheduled-roadmap-review`, `scheduled-content-generator`) and asked whether they
were still failing. Both are output-aware Inngest crons (post-TR9): each run is
supposed to create a `[Scheduled] <Task> - <YYYY-MM-DD>` issue with the
`scheduled-<task>` label, and the terminal Sentry/Better Stack check-in is
credited only when that dated digest exists in the run window
(`resolveOutputAwareOk` / `verifyScheduledIssueCreated`).

I twice concluded "recovered / green" from a `gh issue list --label <slug>`
title listing that showed a fresh dated issue — and was twice **wrong**. The
operator's forwarded Sentry event (`cron-roadmap-review exited 0 but created no
"scheduled-roadmap-review" issue in the run window`) exposed it.

## Root cause of the misdiagnosis

When a run reaches the eval but produces **no** real digest, the handler's
safety net `ensureScheduledAuditIssue` files a **FAILED-fallback self-report**
issue that carries the **identical title prefix and the same `scheduled-<task>`
label** as a real digest (so the separate `cron-cloud-task-heartbeat` watchdog
stays green). Therefore:

> `gh issue list --label scheduled-<task>` (title + label only) CANNOT
> distinguish a healthy run from a failed one. A red monitor with a
> same-day-titled issue is the *expected* shape of a failure, not evidence of
> recovery.

The distinguishing signal lives in the **body**: a fallback issue opens with
`Automated FAILED self-report from \`cron-<task>\`` and carries a signal table
(`exitCode`, `stdoutTail`, `durationMs`). A real digest opens with the task's
actual content (e.g. `## Health Summary`).

## Solution — the triage recipe

1. Convert the operator's local date to **UTC** first (`date -u`) — cron
   schedules and monitor "failing since" timestamps are UTC; a local date can be
   a day ahead and mis-frame which run was "the last one due."
2. For each labeled issue in the window, classify by body:
   ```bash
   gh issue view <N> --json body -q '.body' \
     | grep -q 'Automated FAILED self-report' && echo FAILED-fallback || echo REAL-digest
   ```
3. Read each fallback's signal table to get the failure CLASS from `stdoutTail`:
   - `Credit balance is too low` + `exitCode: 1` + tiny `durationMs` (~2–4s) →
     **Anthropic API credit exhaustion** (systemic; hits *every* claude-eval
     cron in the same window — grep the blast radius with
     `gh search issues 'Credit balance is too low' --created '>=<date>'`).
   - `exitCode: 0` + full `durationMs` (~90s+) + agent prose about "skipping
     duplicate work" → the eval ran but a **prompt-level dedup rule** made it
     comment-and-exit instead of creating the dated digest (an output-contract
     bug, not an infra failure).
4. Confirm current health by checking whether *other* scheduled crons produced
   **real** digests today — that isolates a systemic cause (credit) from a
   per-cron cause (that cron's prompt).

## Key Insight

For output-aware crons, "the monitor is green" is a claim about a **delivered
check-in**, and the check-in is decoupled from the artifact you can see in a
title listing. Never assert recovery from a title/label listing — read the body,
or (better) force a fresh run via `soleur:trigger-cron` and verify the produced
issue is a real digest. Two distinct root causes present with the *same* red
monitor: transient **credit exhaustion** (self-clears on top-up) vs. a durable
**prompt/output-contract bug** (needs a code fix). The fix for the latter was to
remove roadmap-review's prompt-level 6-day DEDUP RULE so every run-day that
reaches the eval unconditionally creates its dated digest (see
`2026-07-07-fix-cron-roadmap-review-dedup-output-contract-plan.md`).

## Session Errors

- **Premature "monitor green" conclusion (×2)** — asserted recovery from a
  title-only `gh issue list`. Recovery: reclassified via the issue body marker.
  **Prevention:** the triage recipe above — classify by `Automated FAILED
  self-report` body marker before ever reporting a monitor as recovered.
- **jq quoting foot-gun (×2)** — `gh … --jq '"…join(\",\")"'` parse errors in
  the non-interactive Bash tool. **Prevention:** prefer per-field `-q '.field'`
  or a shell loop over embedding a quoted `join(...)` in a double-quoted jq
  string.
- **go→one-shot contextual `#N` scrub applied one step late** — the first
  one-shot invocation carried CLOSED contextual citations (#5781, #5674) that
  would have tripped the collision gate's closed-issue abort. Recovery:
  re-invoked with date-anchored prose. **Prevention:** already covered by the
  `soleur:go` "Scrub closed `#N` contextual citations before invoking one-shot"
  sharp edge — apply it at the router step, before the first invocation.

## Related

- Runbook: `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`
- `knowledge-base/project/learnings/2026-06-01-output-aware-cron-heartbeat-and-live-evidence-refutes-plan-hypothesis.md`
- Credit-exhaustion tracking is separate and was already resolved by top-up.
