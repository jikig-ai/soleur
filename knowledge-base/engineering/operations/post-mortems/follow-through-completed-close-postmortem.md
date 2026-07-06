---
title: "Follow-through monitor recorded timed-out issues as COMPLETED for ~3 months"
date: 2026-07-07
incident_pr: 6135
incident_window: "2026-04-22 → 2026-07-07 (first affected close #2615 → audit)"
recovery_at: "2026-07-07 (audit drain + monitor fix in #6135)"
suspected_change: "TR9 PR-2 (#4063) follow-through monitor Guard C — bare `gh issue close` on the 30-business-day timeout path"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - metric-integrity
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

The follow-through monitor (`cron-follow-through-monitor.ts`, the in-repo Inngest cron authenticating as `soleur-ai[bot]`) closed timed-out follow-through issues at its 30-business-day polling cap using a **bare `gh issue close`**, which the GitHub CLI records as `state_reason: COMPLETED`. So issues the automation was *giving up on* — post-deploy verifications, prod spot-checks, secret rotations, GDPR/compliance checks that never actually ran — were recorded as **done**, while still carrying the `needs-attention` label. A 2026-07-07 audit found 73 issues in this contradictory state. This is a metric/bookkeeping-integrity incident (not an availability outage or data breach): any audit trusting `state_reason` silently overcounted completed follow-throughs.

## Status

resolved — recurrence prevented in #6135; historical data tail tracked in #6140.

## Symptom

Follow-through issues closed with `state_reason: COMPLETED` + `needs-attention` label present + a "Maximum polling period reached … manual intervention required" give-up comment posted 2–4s before the close (same run).

## Incident Timeline

- **Start time (detected):** 2026-07-07 (2026-07-07 audit)
- **End time (recovered):** 2026-07-07 (audit drain + #6135 monitor fix)
- **Duration (MTTR):** same-day once detected; latent ~3 months prior

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-04-22 | First affected close (#2615) — timeout path records COMPLETED. |
| human | 2026-07-07 | 2026-07-07 audit detects 73 issues closed COMPLETED + needs-attention. |
| agent | 2026-07-07 | Audit drains issues (22 reopened, 35 reclassified COMPLETED→NOT_PLANNED, 16 legit); #6132 filed for recurrence prevention. |
| agent | 2026-07-07 | #6135 rewrites Guard C to close timeouts as not-planned + strip needs-attention. |
| agent | 2026-07-07 | #6135 preflight finds the audit drain was incomplete (historical tail); files #6140. |

## Participants and Systems Involved

`cron-follow-through-monitor.ts` (Inngest cron), GitHub Issues (`follow-through`/`needs-attention` labels, `state_reason`).

## Detection (+ MTTD)

- **How detected:** manual audit (2026-07-07), not an automated alert — the bug lived in issue metadata, not a runtime error path, so no Sentry/heartbeat signal fired.
- **MTTD:** ~3 months (latent from 2026-04-22).

## Resolution

Guard C of `FOLLOW_THROUGH_PROMPT` now (1) posts the give-up comment first, (2) strips `needs-attention` before closing, (3) closes with `--reason "not planned"`. Guard A (predicate-pass) keeps its correct COMPLETED close. The 73 pre-existing issues were drained by the 2026-07-07 audit (incompletely — see #6140).

## Root Cause(s) — 5-Whys

1. Why were timed-out issues marked COMPLETED? Guard C used a bare `gh issue close`.
2. Why does a bare close mean COMPLETED? `gh issue close` defaults `state_reason` to `completed`.
3. Why wasn't the give-up path distinguished? The original prompt (TR9 PR-2 #4063) never set an explicit close reason on the max-polling path.
4. Why undetected for months? The bug is in issue metadata, not a runtime error — no alert path observes `state_reason`.
5. Why did the invariant "needs-attention only on OPEN" not hold? No guard stripped the label on close.

## Impact details

Corpus-wide metric-integrity: every timed-out follow-through since 2026-04-22 was overcounted as completed. No customer-facing outage, no data exposure. The human audit/triage remained the control for any specific un-done item.

## Lessons Learned

- An automation's give-up path must set an explicit terminal state — never rely on a CLI default that means the opposite ("completed").
- A bug that lives in metadata (not an error path) is invisible to runtime observability; a periodic invariant query (the #6135 discoverability test) is the right detector.
- "Cleanup already applied" claims in a plan are hypotheses — a preflight live query verified the drain was incomplete.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6140 | Drain the historical tail — follow-through issues closed COMPLETED with the give-up comment before 2026-07-08 (per-issue judgment: reclassify vs strip label vs reopen). | open |
