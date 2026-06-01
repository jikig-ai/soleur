---
title: Best-effort cron monitor must page on liveness, not work-success — and the non-paging signal must be off-host-queryable
date: 2026-06-01
category: bug-fixes
tags: [sentry, cron-monitor, inngest, observability, false-positive, alerting]
related_prs: []
related_issues: [4730]
related_learnings:
  - knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md
  - knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md
---

# Learning: best-effort cron monitor liveness ≠ work success; relaxed signal must stay off-host-queryable

## Problem

The `scheduled-bug-fixer` Sentry cron monitor (incident `5127648`) posted
`status=error` check-ins on 2026-05-31 and 2026-06-01 (last `ok` on 2026-05-30).
The alert email named the rule `auth-callback-no-code-burst` — a **coincidental
red herring** (an unrelated project-wide Sentry issue alert sharing only the
operator email channel; the exact same pairing is documented for the 2026-05-27
community-monitor incident).

The handler (`cron-bug-fixer.ts`) wired the cron-monitor heartbeat as
`ok: spawnResult.ok`, where `spawnResult.ok = (claude --print exit code === 0)`.
For an autonomous best-effort fixer, a non-zero `claude --print` exit (max-turns
exhaustion / "no fix landed today" terminal state) is the **normal daily
outcome**, not an operational error — so the monitor paged on the common case.

## Key distinction: error check-in ≠ missed check-in

- A **missed** check-in (the 2026-05-27 class) = the function never fired → root
  cause is Inngest scheduler desync → runbook H9 (restart inngest-server).
- An **error** check-in (this class) = the function **fired and ran to a
  heartbeat**, then deliberately posted `status=error`. H9 does NOT apply.
  Running the restart runbook here would be wasted action masking an app-code
  root cause.

## Diagnostic method (no SSH, no dashboard-eyeballing)

The load-bearing data-pull that distinguished "benign no-fix" (H1) from a genuine
infra fault (H3) — `reportSilentFallback` calls `Sentry.captureException`, so
every infra-fault path surfaces as a **searchable project issue**:

```bash
# 1. monitor check-ins (token: Doppler prd/SENTRY_API_TOKEN, org SENTRY_ORG)
curl -s -H "Authorization: Bearer $SENTRY_API_TOKEN" \
  "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-bug-fixer/checkins/?per_page=15" \
  | jq -r '.[] | "\(.dateCreated) status=\(.status)"'
# 2. search the PROJECT issues for the cron's reportSilentFallback ops
#    (org-wide /issues/ rejects the prd token; SENTRY_ISSUE_RW_TOKEN + project slug works)
curl -s -H "Authorization: Bearer $SENTRY_ISSUE_RW_TOKEN" \
  "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/?query=cron-bug-fixer&statsPeriod=14d"
```

**Verdict rule:** zero infra-fault issues over the failing window + `status=error`
posted ⟹ the error came from a post-spawn heartbeat gated on `spawnResult.ok`
⟹ **H1** (claude exited non-zero, no infra fault). A `claude-eval-timeout` /
`setup-ephemeral-workspace` / `child_process.spawn` issue near the failing fires
would have meant H2/H3 instead.

## Solution

**Decouple the cron-monitor heartbeat from work success.** A clean end-to-end run
(token minted → workspace set up → claude spawned and exited → PR-detection ran →
teardown ran) posts `status=ok` regardless of claude's exit code. Keep
`status=error` ONLY on genuine infrastructure/operator faults that already have
early-return error heartbeats (setup-workspace catch, parse-event-data). The dead
`overallOk = spawnResult.ok && !!detectedPr` was removed (`!!detectedPr` is always
true at the final heartbeat because the `!detectedPr` branch returns earlier).

## The review-caught refinement (this is the non-obvious half)

Relaxing the heartbeat is only half-right. The first cut logged the non-zero exit
with a bare `logger.warn` — which **three orthogonal review agents independently
flagged as invisible off-host**:

- pino `logger.warn` only `Sentry.addBreadcrumb`; a breadcrumb is flushed solely
  on a later `captureException`, which a clean `ok:true` run never produces → the
  warn is silently dropped at run-end.
- the handler runs in the `soleur-web-platform` Docker container (json-file log
  driver); Vector's journald source tails `inngest-server.service`, a *different*
  unit → the line never reaches Better Stack.

Net: a **chronically-broken-but-live** fixer (claude exits non-zero every day for
a real reason) would read green on the monitor with zero queryable signal — the
inverse failure of the one being fixed. Fix: emit a **WARNING-level Sentry event
via `warnSilentFallback`** (op-tagged, carries `selectedIssue`) instead of a bare
`logger.warn`. It does NOT page (no monitor status change, no warning-level
issue-alert rule) but is off-host-queryable, so "same issue failing N days
running" is diff-able week over week. `warnSilentFallback` is the canonical helper
for exactly this ("degraded-but-expected paths where every occurrence is worth
observing but shouldn't count as an error").

## Key Insight

For an autonomous **best-effort** worker, the cron monitor's contract is
**liveness** ("the pipeline fired and ran end-to-end without an infrastructure
fault"), NOT **work-success** ("it produced output today"). Wiring the heartbeat
to the work-result exit code converts a healthy signal into a daily false page
(the monitor-exit-condition-tightness anti-pattern). When you relax it, the
now-non-paging signal must still be **off-host-queryable** — a bare `logger.warn`
is invisible without SSH; route it through `warnSilentFallback` (warning-level
captureException/captureMessage), not pino alone. Distinguish error-check-in from
missed-check-in before reaching for the Inngest-desync runbook.

## Cohort

11 sibling claude-eval crons (`cron-roadmap-review`, `cron-legal-audit`,
`cron-growth-audit`, `cron-content-generator`, …) share the same latent
`ok: spawnResult.ok` semantic. They have not paged because their claude
invocations exit 0 reliably, but each carries the same false-page risk. Filed as
#4730 for a **per-cron** liveness-contract decision (an audit/review cron that
MUST produce an artifact may legitimately want a stricter contract than a
best-effort fixer) — NOT a blind sweep. Architecture review recommended a named
`HeartbeatContract = "liveness" | "artifact-required"` type in `_cron-shared.ts`
rather than a single shared boolean, so per-cron variance is greppable instead of
re-derived inline (drift surface).

## Session Errors

1. **Planning subagent could not spawn parallel review/research Task agents**
   (Task tool unavailable inside a pipeline subagent). Recovery: deepen research
   done inline with live verification. **Prevention:** known platform limitation
   (subagents cannot spawn subagents); plan-skill already falls back to inline.
2. **Planning subagent introduced a broken KB citation**, caught by the
   plan-quality grep gate. **Prevention:** already gate-enforced.
3. **Bash persistent-CWD trap:** after `cd apps/web-platform && <cmd>` persisted
   the CWD, a later identical `cd apps/web-platform` failed ("No such file or
   directory") and an `ls apps/web-platform/…` resolved against the wrong base.
   Recovery: re-anchored with an absolute-path `cd`. **Prevention:** always pass
   an absolute path in `cd <abs> && <cmd>` per Bash call; never assume CWD (the
   tool persists it across calls, which is the opposite of the common assumption
   and bites both ways).
4. **`gh issue create` PreToolUse hook denial aborted the entire Bash command:**
   the first attempt was BLOCKED for a missing `--milestone`, and because the
   hook denies the whole tool call, the same command's preceding
   `cat > /tmp/body.md` heredoc never executed — so the milestone-corrected
   retry failed "no such file." **Prevention:** (a) `gh issue create` always
   requires `--milestone` (default `Post-MVP / Later` for operational issues) —
   already hook-enforced; (b) write issue-body files with the Write tool in a
   SEPARATE step from `gh issue create`, never as a heredoc in the same Bash
   command as a hook-gated `gh` call, so a denial cannot orphan the body file.
