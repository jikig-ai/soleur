---
title: "sentry-issue-rate named-check fail-closed suppressed #5417's AC12 verdict for ~10 days"
date: 2026-06-29
incident_pr: 5670
incident_window: "2026-06-19T09:00:12Z – 2026-06-29 (verdict suppressed)"
recovery_at: "2026-06-29"
suspected_change: "AC12 one-time verification schedule armed for #5417 (no retry, 10s AbortController timeout)"
brand_survival_threshold: none
status: resolved
triggers:
  - provider transient (Sentry API abort on the single 09:00:12Z fire)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The `sentry-issue-rate` named-check (the AC12 post-deploy verification primitive
for #5417) fired once on 2026-06-19T09:00:12Z and fail-closed with
`This operation was aborted. No action taken.` Because the check was armed as a
**one-time** reminder with a **10s `AbortController` timeout and no retry**, a
single transient Sentry-API abort permanently suppressed the verdict. No result
comment was rendered on #5417, which then sat stalled-open for ~10 days until the
operator asked (2026-06-29) why the expected verdict never appeared.

This is an **operator-only tooling availability** incident: the affected surface
is an internal post-deploy verification check. No end-user surface, no user data,
and no credential exposure were involved.

## Status

resolved — PR #5670 hardens the check (bounded transient-retry + loud fail-closed
observability); the verification was re-run manually on 2026-06-29 and the verdict
rendered.

## Symptom

A single Sentry-issue-rate verification comment reading
`▎ sentry-issue-rate: fail-closed — Sentry query failed (This operation was
aborted). No action taken. — soleur-ai, 2026-06-19T09:00:12Z`, followed by 10 days
of silence on #5417 (no pass/fail/info verdict).

## Incident Timeline

- **Start time (detected):** 2026-06-29 (gap noticed when operator asked to confirm the 06-19 verdict)
- **End time (recovered):** 2026-06-29
- **Duration (MTTR):** same-session once detected; verdict-suppression window ~10 days

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-19T09:00:12Z | Named-check fired once; Sentry fetch aborted at the 10s timeout; fail-closed, no retry, no verdict. |
| human | 2026-06-29 | Operator asked whether the 06-19 AC12 verdict rendered; gap detected. |
| agent | 2026-06-29 | Verification re-run manually; verdict rendered; root cause traced to no-retry + one-time schedule. |
| agent | 2026-06-29 | PR #5670 implemented + reviewed (bounded transient-retry + every-fail-closed Sentry warning). |

## Participants and Systems Involved

Inngest self-hosted scheduled-reminder function (`event-scheduled-reminder.ts`,
`CHECK_REGISTRY["sentry-issue-rate"]`); Sentry REST API (EU region); GitHub issue
#5417 (the `report_to_issue` target). No operator credentials or user systems.

## Detection (+ MTTD)

- **How detected:** external/manual — operator follow-up asking for the verdict, NOT an alert. The fail-closed path was comment-only (no Sentry mirror), so monitoring had no signal. This is the detection gap PR #5670 closes.
- **MTTD (mean time to detect):** ~10 days (06-19 → 06-29).

## Triggered by

provider — a transient Sentry-API condition aborted the single in-flight fetch.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Single transient Sentry abort + no-retry + one-time schedule permanently fail-closed | The 09:00:12Z comment text "This operation was aborted"; no retry code in `sentryGet`; schedule was one-time | none | confirmed |

## Resolution

PR #5670: wrapped `sentryGet` in a bounded transient-retry — `AbortSignal.timeout`
(classified by the canonical `isRetryable` as `TimeoutError`) + 2 retries
(500ms, 1500ms) on transient network/timeout and HTTP 5xx/429; deterministic 4xx
stays single-shot. Every fail-closed path now mirrors a Sentry warning via
`warnSilentFallback` (`op=sentry-issue-rate-fail-closed`), eliminating the
comment-only-silent path that hid this for 10 days. The verdict math and
`close_on_pass` decision are unchanged.

## Recovery verification

The verification was re-run manually on 2026-06-29 and rendered a real verdict on
#5417. PR #5670 carries 9 new/updated retry test cases (transient-then-success for
5xx/timeout/network/429, 4xx no-retry, bounded-to-3 with `[[500],[1500]]` backoff,
env-unset warn, token-non-leak) — all green; `tsc` clean; inngest suite (2009
tests) green.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was no AC12 verdict on #5417?** The named-check fail-closed on its only fire.
2. **Why did it fail-closed?** The Sentry fetch was aborted at a 10s timeout.
3. **Why did the abort suppress the verdict permanently?** There was no retry, and the schedule was one-time — a single transient spike had no second chance.
4. **Why was the failure invisible for 10 days?** The fail-closed path wrote only a GitHub comment; it did not mirror to Sentry, so no monitoring layer surfaced it.
5. **Why was the check armed one-time rather than recurring?** AC12 framed verification as a single post-deploy probe; transient-resilience (retry + recurring) was not a stated requirement.

## Versions of Components

- **Version(s) that triggered the outage:** `event-scheduled-reminder.ts` pre-#5670 `sentryGet` (single-shot, 10s `AbortController`, comment-only fail-closed).
- **Version(s) that restored the service:** `event-scheduled-reminder.ts` as of PR #5670.

## Impact details

### Services Impacted

Internal post-deploy verification tooling only (`sentry-issue-rate` named-check). No production app surface.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

~10 days of false uncertainty about whether #5420's fix held; one operator follow-up and one hardening PR to resolve.

## Lessons Learned

### Where we got lucky

The underlying #5420 fix had in fact held (restart churn 40–60/day → 2.67/day all benign, zero OOM, heavy-cron kills gone) — so the suppressed verdict masked a *passing* state, not a regression. Had #5420 regressed, the same silence would have hidden a real one.

### What went well

Once detected, the root cause was unambiguous (the comment text named the abort) and the fix reused canonical retry/observability primitives (`isRetryable`, `delay`, `warnSilentFallback`).

### What went wrong

A fail-closed verification that emitted only a GitHub comment, on a one-time schedule with no retry, is a single-point-of-silence: one transient blip permanently suppresses the signal with no monitoring trace.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #5669 | Durable deploy-coupling substrate fix (graceful-drain vs isolated-cron-worker) so cron-platform verification is not coupled to deploy restarts — the root substrate behind the restart churn AC12 was verifying. | open |
