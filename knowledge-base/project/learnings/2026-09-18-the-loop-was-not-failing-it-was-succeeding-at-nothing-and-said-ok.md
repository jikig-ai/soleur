---
module: System
date: 2026-09-18
problem_type: workflow_issue
component: tooling
symptoms:
  - "cron-compound-promote enabled since 2026-07-06 has opened zero PRs; promotion-log.md has zero rows"
  - "0 Sentry events for feature:cron-compound-promote in 90d, while a has:feature control query returns live rows"
  - "Better Stack shows a completed Anthropic call of 516,512 input tokens on the 2026-09-13 run"
  - "Every refusal marker (target-path-refused, byte-budget-overflow, git-apply-check-failed, ...) returns 0 hits over ~83 days"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [observability, silent-success, self-improvement-loop, heartbeat, subagent-claims, telemetry, enumerating-probe]
synced_to: [brainstorm]
---

# Learning: the loop was not failing — it was succeeding at nothing, and saying ok

## Problem

`cron-compound-promote` is Soleur's only machine writer in the self-improvement loop. It has
been `enabled: true` since 2026-07-06. In ~10 weeks it has opened **zero** PRs, and
`promotion-log.md` has **zero** rows.

The obvious hypothesis — and the one a CTO subagent produced this session — was that it crashes
every run: `collect-corpus` sends the first 10 lines of all 2,309 learnings in one message, which
looks like a context overflow into `handler-top-level`.

That hypothesis is wrong, and the way it is wrong is the lesson.

## Investigation

Three queries, in this order:

1. **Sentry, scoped:** `feature:cron-compound-promote`, 90d → **0 events**. On its own this is
   worthless, because an empty result and a broken query look identical.
2. **Sentry, control:** `has:feature`, 7d → live rows for `feature-flags`,
   `cron-cloud-task-heartbeat`, `github-webhook`, `cron-anthropic-cost-report`. The channel works,
   so the silence in (1) is real. The handler is **not** erroring.
3. **Better Stack:** a `SOLEUR_CLAUDE_COST` marker with `id: cron-compound-promote`,
   `input_tokens: 516512`, `output_tokens: 7623`, `model: claude-sonnet-5`, `capture_status: ok`.
   The call **completed**.

So: it runs, it pays for a very large Anthropic call, it returns successfully, and it produces
nothing.

## Root cause

Read the handler's terminal paths (`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`):

```ts
// disabled / deduped / week-cap-reached / no-qualifying-clusters / completed
await step.run("sentry-heartbeat-ok-no-clusters", () =>
  postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, ... }),
);
return { ok: true, status: "no-qualifying-clusters" };
```

Every non-error exit posts `ok: true` and returns a status **into the void**. The status string
is never emitted as a marker, so it reaches no log and no dashboard. Errors are instrumented well
(`reportSilentFallback` on eight distinct refusal paths, all measuring 0). Success is not
instrumented at all.

The result: a weekly job that spends real money and does nothing, whose reason for doing nothing
is **structurally unknowable** from outside. Five candidate explanations — disabled flag, dedup
hit, week cap, zero qualifying clusters, or clusters that all failed to commit — are
indistinguishable from the telemetry, three months in.

## Key insight

**A heartbeat proves liveness, not work. A silent success path is exactly as undiagnosable as a
silent failure, and it is far more likely to survive review — because `ok: true` reads as health.**

The existing rule `hr-no-dashboard-eyeball-pull-data-yourself` and the "empty telemetry is not
evidence of absence" sharp edge both point at *error* channels. This is the mirror case: the
error channel was fine, and it was the **success** channel that had nothing in it. When a
component reports success but its downstream effect is absent, instrument the component's own
**outcome**, not just its exceptions.

Corollary for any cron with multiple non-error exits: the exit *reason* is the load-bearing datum.
`return { ok: true, status }` where `status` is never emitted is the anti-pattern.

## Solution

Captured as FR1/FR2 of `knowledge-base/project/specs/feat-wikiskill-skill-evolution/spec.md` (#8281):

- Emit `SOLEUR_COMPOUND_PROMOTE_OUTCOME` on **every** terminal path, carrying the status, the
  cluster count, and each per-cluster refusal reason.
- Fire a Sentry alert after 4 consecutive zero-output weeks, so "quietly does nothing" cannot
  persist for a quarter again.

## Prevention

- When a scheduled job has more than one non-error exit, treat the exit reason as required
  telemetry, the same way an error path is. `ok: true` with an unemitted `status` is a defect.
- Before diagnosing a producer that "produces nothing", check that it *runs* and that it *costs*
  something. A cost marker settles run-vs-not-run faster than reading the handler.
- Pair every scoped telemetry query with a control query in the same call, before reading silence
  as a finding.

## Session Errors

- **A subagent's root-cause hypothesis was nearly carried into the spec as a finding.** The CTO
  reported the promoter "is probably failing on every run" with a context-overflow into
  `handler-top-level`. It labelled the claim a hypothesis; the risk was that a confident,
  plausible mechanism reads as a finding once it is quoted downstream. Refuted in three queries.
  — **Recovery:** re-derived from Sentry + Better Stack before writing the brainstorm.
  — **Prevention:** a subagent's **root-cause story** is a claim to re-derive, exactly like its
  counts. The repo already rules that a subagent's COUNT must be re-derived; a causal mechanism is
  the same class and is more persuasive, because it explains rather than merely asserts.
- **An empty Sentry query was nearly read as evidence of absence.** — **Recovery:** ran a
  `has:feature` control query, which returned live rows. — **Prevention:** the existing sharp edge
  ("an empty telemetry query is not evidence of absence until you have verified the signal is
  instrumented") fired correctly; it is worth noting it applies to a *scoped-query typo* as much as
  to a missing allowlist entry.
- **I misread a documented default as an instrument flaw.** `betterstack-query.sh` returned exactly
  100 rows; I treated the cap as truncation-without-notice. It is `LIMIT=100` by default and
  `--limit N` is documented in the script's own usage header. — **Recovery:** read the script.
  — **Prevention:** this is the enumerating-probe default-cap class the repo already records for
  `gh issue list --limit`, recurring in a second tool. Before calling a cap a flaw, grep the tool
  for `limit`.
- **A raw-SQL Better Stack query returned no output and no error, and I did not diagnose it.**
  The convenience-flag mode worked for the same data. — **Recovery:** used the convenience mode.
  — **Prevention:** unresolved; a query mode that exits 0 with no rows and no diagnostic is the
  same silent-success class this learning is about. Worth a follow-up issue against the script.
- **The session-start gate no-opped.** `CLAUDE_PLUGIN_ROOT` was empty, so `/soleur:go` emitted
  `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified`; `cleanup-merged` and the
  `.mcp.json` restore never ran. — **Recovery:** proceeded; the marker made the skip visible
  (which is the #7442 design working as intended). — **Prevention:** the marker is emitted but
  nothing consumes it; a session that silently skips worktree hygiene every time is itself an
  instance of this learning's pattern.

## Related

- `knowledge-base/project/learnings/2026-09-10-six-instruments-reported-could-not-measure-as-clean.md`
- `knowledge-base/project/learnings/2026-09-15-every-instrument-i-checked-my-own-work-with-returned-an-answer.md`
- `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md`
- `knowledge-base/project/brainstorms/2026-09-18-wikiskill-skill-evolution-brainstorm.md` (#8281)
