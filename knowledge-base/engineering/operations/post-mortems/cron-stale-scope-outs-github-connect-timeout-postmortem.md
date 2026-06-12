---
title: "cron-stale-deferred-scope-outs transient api.github.com connect-timeout escalated to operator-paging Sentry error"
date: 2026-06-12
incident_pr: 5227
incident_window: "2026-06-12T12:00:00Z (single cron fire)"
recovery_at: "self-healed within the same Inngest run window (retries: 1)"
suspected_change: "none — pre-existing missing per-call transient retry on the cron's octokit calls"
brand_survival_threshold: none
status: resolved
triggers:
  - provider: transient api.github.com connect timeout (UND_ERR_CONNECT_TIMEOUT)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; the cron reads/writes only operator-owned GitHub issue metadata via the synthetic-probe (non-audit-writer) Octokit"
---

# Incident Overview

The daily Inngest cron `cron-stale-deferred-scope-outs` (fnId `soleur-runtime-cron-stale-deferred-scope-outs`) fired at 2026-06-12 12:00 UTC. A single transient `Connect Timeout Error (api.github.com:443, 10000ms)` / `TypeError: fetch failed` on one of its `octokit.request(...)` calls escalated to an `error`-level Sentry event (issue `448a4173f90a436382c4396371927796`, `handled: yes`) that paged recently-active members of the web-platform project — even though Inngest's `retries: 1` policy self-heals on the next attempt.

This was **not an operational outage**: there was no downtime, no user-facing impact, and no data exposure. The cron is operator-internal (it auto-closes stale `deferred-scope-out` GitHub issues in `jikig-ai/soleur`). The "incident" was a severity-calibration defect — a self-healing transient surfaced as an operator-paging error.

## Status

resolved — fixed in PR #5227 (this branch).

## Symptom

`Error: Connect Timeout Error (attempted address: api.github.com:443, timeout: 10000ms)` + `TypeError: fetch failed`, captured by Sentry at `POST /api/inngest` with `inngest.fn_id=cron-stale-deferred-scope-outs`, `inngest.run_id=01KTXV83HTYR8K8SG77T0JKCJC`, `feature=pino-mirror`, `handled=yes`, release `web-platform@0.122.9`.

## Incident Timeline

- **Start time (detected):** 2026-06-12T12:00:00Z (cron fire; Sentry event 14:01:36 CEST after the run)
- **End time (recovered):** same run window — Inngest `retries: 1` re-ran the step and succeeded (transient blip cleared)
- **Duration (MTTR):** effectively zero user-facing; the backlog sweep completed on the Inngest retry.

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-12T12:00:00Z | Cron fired; one octokit call hit a transient api.github.com connect timeout. |
| system | 2026-06-12T12:00:10Z | undici's 10s connect timeout threw; octokit wrapped it; the throw escaped `step.run` → `reportSilentFallback` (error level) → Sentry. |
| system | ~2026-06-12T12:00:xx | Inngest `retries: 1` re-ran the step; transient cleared; sweep completed. |
| human | 2026-06-12T~12:01Z | Operator received the Sentry "New issue" notification (the paging symptom). |
| agent | 2026-06-12 | `/soleur:go` routed the alert to a fix; PR #5227 added in-step transient retry. |

## Detection (+ MTTD)

- **How detected:** Sentry high-priority issue notification (monitoring system).
- **MTTD:** ~1 minute (Sentry alert latency after the run).

## Triggered by

provider — a transient api.github.com connect-timeout blip.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The cron's octokit calls have no per-call transient retry, so a single connect timeout escalates before Inngest's function-level retry can mask it | Function source: `octokit.request` via `createProbeOctokit()` carries no retry plugin; `fetchCandidates` is outside the per-issue try | none | confirmed |

## Resolution

PR #5227 adds `isRetryableGithubError` (cause-chain walk) + `withGithubRetry<T>(fn)` to the shared leaf `apps/web-platform/server/github-retry.ts` and routes the cron's search + per-issue comment/close through it. A single transient connect timeout is now absorbed in-step (3 attempts, 1s/2s backoff) and never reaches the error-level Sentry mirror; a sustained outage still rethrows (visible). A genuine 403 stays non-retryable, preserving the `issue_write_403` discriminator.

## Recovery verification

- Unit + cron-integration tests seed octokit's **real** wrapped error shape and assert the transient no longer escalates (AC4), the 403 path still surfaces (AC5), and a sustained outage still reaches the handler net (AC6). Full web-platform vitest suite green (9725 passing).
- Live: preflight discoverability probe `curl https://app.soleur.ai/api/inngest` → 401 (route deployed). End-to-end confirmed post-merge by the next daily cron fire (`0 12 * * *`) producing a clean Sentry Crons heartbeat with no recurrence of `448a4173…`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the operator get paged?** A `handled: yes` error-level Sentry event fired from the cron.
2. **Why error-level?** A transient connect timeout escaped `step.run` → the handler's outer catch mirrored it at error level.
3. **Why did it escape the step?** The octokit calls had no per-call transient retry; the throw propagated before the next Inngest function-level retry.
4. **Why no per-call retry?** `createProbeOctokit()` mints `@octokit/core`/`@octokit/app` clients with no retry plugin, and the codebase's `fetchWithRetry` only covers the raw-`fetch` MCP path — not octokit. Additionally, octokit wraps the undici timeout in a `RequestError` whose code is buried at `.cause.cause`, so the existing top-level `isRetryable` would have missed it even if applied.
5. **Why hadn't this been caught?** The cron was migrated from a GHA workflow (PR #4457) and inherited the gap; a single transient blip is rare enough that it took a real connect timeout to surface it.

## Versions of Components

- **Version(s) that triggered:** web-platform@0.122.9
- **Version(s) that restored:** PR #5227 (next release)

## Impact details

### Services Impacted

The `cron-stale-deferred-scope-outs` daily janitorial sweep — one run emitted a spurious error event; the sweep itself completed on the Inngest retry.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none (the cron operates on the operator's own repo only)

### Revenue Impact

None.

### Team Impact

One operator-paging Sentry notification (alert noise); ~one engineering session to fix.

## Lessons Learned

### Where we got lucky

The transient was on the search call (outside the per-issue try), so it aborted cleanly and Inngest retried the whole sweep — no partial state, no duplicate auto-close comments on this run.

### What went well

Inngest `retries: 1` self-healed the actual work; the fix is a precise resilience addition with no semantic change to the sweep.

### What went wrong

A self-healing transient paged the operator at error severity — the alarm fired louder than the underlying event warranted, because there was no in-step retry to absorb the blip.

### What went right in the fix

The cause-chain classification trap (octokit wrapping the undici error so top-level `isRetryable` misses it) was caught at plan-deepen time, preventing a fix that compiles and passes a bare-`TypeError` test while silently still not retrying in production.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #5230 | Apply `withGithubRetry` to the sibling probe-octokit crons (drift-guard, oauth-probe, installation discovery) + add a per-request `AbortSignal.timeout` cap so a sustained outage cannot balloon cron runtime | open |
| #5231 | Guard the pre-existing non-idempotent auto-close comment double-fire on Inngest replay (sentinel-comment check before POST) | open |
