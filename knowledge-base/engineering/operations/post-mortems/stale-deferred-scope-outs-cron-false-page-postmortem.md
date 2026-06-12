---
title: "scheduled-stale-deferred-scope-outs cron false page on a transient GitHub fault"
date: 2026-06-12
incident_pr: 5228
incident_window: "2026-06-12 ~12:00 UTC (single error check-in; Sentry incident 5468023)"
recovery_at: "2026-06-12 (self-healed on the cron's own Inngest retry within the run window; monitor clears on the next ok check-in, recovery_threshold=1)"
suspected_change: "No code change. A transient upstream GitHub fault (401-after-budget / 403 secondary-rate-limit / 429 / 5xx) on createProbeOctokit() or GET /search/issues threw on Inngest attempt 0. The handler posted the status=error Sentry heartbeat BEFORE its retries:1 retry ran — a latent page-before-retry bug present since the cron migrated GHA→Inngest in #4457."
brand_survival_threshold: none
status: resolved
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The Sentry Crons monitor `scheduled-stale-deferred-scope-outs` (monitor.id
`87e37238-6e05-4507-af82-ff10f70ccfe4`) fired a high-priority **"An error
check-in was detected"** page (incident `5468023`) at ~12:00 UTC on 2026-06-12.
This was a **false page**: the cron's only job (auto-closing stale
`deferred-scope-out` GitHub issues via the synthetic-probe Octokit) was never
actually broken. A single transient GitHub fault threw on Inngest attempt 0; the
function's `retries: 1` policy recovered on attempt 1. The bug was purely that
the handler posted the `status=error` heartbeat at the end of attempt 0 —
**before** the retry that would have (and did) recover — so the operator was
paged by a fault the very next attempt fixed.

## Status

resolved — root cause fixed in the source PR (#5228); monitor clears to `ok` on
the next successful check-in (recovery_threshold = 1).

## Symptom

High-priority Sentry alert "An error check-in was detected", `environment=production`,
`level=error`, for monitor `scheduled-stale-deferred-scope-outs`. Last successful
check-in `2026-06-11T12:00:05+00:00`; first failure `2026-06-12 ~12:00 UTC`.

## Incident Timeline

- **Start time (detected):** 2026-06-12 ~12:00 UTC (Sentry page)
- **End time (recovered):** 2026-06-12 (cron self-healed on its own Inngest retry within the run window; the false `error` check-in is cleared by the next `ok` check-in)
- **Duration (MTTR):** ~seconds of actual cron impact (the retry recovered in the same run window); the *monitor* showed error until the next ok check-in. No production sweep work was lost.

Order of events:

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-12 ~12:00 | Cron fired; a transient GitHub fault threw inside `step.run("sweep…")` on attempt 0. |
| system | 2026-06-12 ~12:00 | Handler posted `status=error` heartbeat (before the retry) → Sentry monitor flipped to error, incident 5468023 opened, operator paged. |
| system | 2026-06-12 ~12:00 | Inngest `retries: 1` re-ran the sweep on attempt 1; it succeeded. |
| human | 2026-06-12 | Operator received the Sentry notification and ran `/soleur:go`. |
| agent | 2026-06-12 | Root-caused (control-flow trace), fixed (heartbeat gated on final attempt), shipped PR #5228. |

## Participants and Systems Involved

Inngest cron `cron-stale-deferred-scope-outs`; the synthetic-probe Octokit
(`createProbeOctokit`); GitHub `GET /search/issues`; Sentry Crons monitor.
No founder data, no audit-ledger writes, no customer-facing surface.

## Detection (+ MTTD)

- **How detected:** Sentry Crons monitor (`failure_issue_threshold = 1`) auto-paged on the first error check-in.
- **MTTD:** immediate (monitor fired on the failing run).

## Triggered by

provider — a transient GitHub API fault (401-after-budget / 403 secondary-rate-limit / 429 / 5xx).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `issues:write` consent drift (per-issue 403) | the cron does issue writes | per-issue 403s are caught in-loop and never set `sweepFailed`; only a thrown sweep flips the monitor | rejected |
| Transient fault on auth/search path + page-before-retry | succeeded 06-11, failed once 06-12; `error` requires a thrown `step.run`; heartbeat posts before the rethrow that triggers `retries: 1` | none | confirmed |

## Resolution

Gate the Sentry `error` heartbeat on the final Inngest attempt. The handler now
reads the zero-indexed `ctx.attempt` / `ctx.maxAttempts` (added as optional
`HandlerArgs` fields); on a non-final failed attempt it skips the heartbeat
`step.run` entirely (memoization-safe), keeps the `reportSilentFallback`
breadcrumb, and rethrows to let Inngest retry. Only a fault that throws on the
final attempt pages. PR #5228.

## Recovery verification

Unit suite (10/10, cases A1–A6) proves a non-final transient does not page and a
final-attempt failure still does. Post-deploy, the manual-trigger dry-run
(`trigger-cron/scripts/trigger.sh cron/stale-deferred-scope-outs.manual-trigger`)
produces an `ok` heartbeat and the monitor clears (recovery_threshold = 1).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the operator get paged?** The Sentry monitor received a `status=error` check-in.
2. **Why an error check-in?** The handler set `sweepFailed = true` (the sweep `step.run` threw) and posted the heartbeat with `ok: false`.
3. **Why did the sweep throw?** A transient GitHub fault (401-after-budget / 403 secondary-rate-limit / 429 / 5xx) on `createProbeOctokit()` or `GET /search/issues` — neither had transient-retry wrapping.
4. **Why did a transient fault page, given `retries: 1` recovers it?** The handler posted the `error` heartbeat at the end of *every* failed attempt, *before* the rethrow that triggers the retry — so attempt 0 paged before attempt 1 recovered.
5. **Why was the page-before-retry timing never caught?** It was a latent bug since the GHA→Inngest migration (#4457); no in-repo cron handler read `ctx.attempt`, so retry-aware heartbeating had no precedent.

## Versions of Components

- **Version(s) that triggered the outage:** the cron handler as of #4457 (page-before-retry timing).
- **Version(s) that restored the service:** #5228 (heartbeat gated on final attempt).

## Impact details

### Services Impacted

`cron-stale-deferred-scope-outs` monitor only. The cron's actual work (closing
stale issues) was never broken — the retry succeeded in the same run window.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.
- Operator: a single false-positive high-priority page (alert fatigue) — the impact this fix targets.

### Revenue Impact

None.

### Team Impact

One false page to the solo operator; ~one session to root-cause and fix.

## Lessons Learned

### Where we got lucky

The cron self-healed on its own retry, so no stale-issue sweep work was lost —
the only damage was the false page. Had the fault been persistent, the existing
behavior would (correctly) have paged.

### What went well

The failure *signal* (an `error` check-in requires a thrown `step.run`, not a
caught per-issue error) immediately narrowed the root cause and falsified the
first-pass "consent drift" hypothesis. Multi-agent review independently verified
the load-bearing Inngest memoization reasoning against the SDK.

### What went wrong

A latent page-before-retry timing bug shipped in the GHA→Inngest migration and
sat dormant until a transient fault surfaced it ~weeks later.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
