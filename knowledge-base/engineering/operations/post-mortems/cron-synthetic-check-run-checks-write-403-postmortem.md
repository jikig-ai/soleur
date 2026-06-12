---
title: "Cron synthetic check-runs 403 — GitHub App lacked checks:write"
date: 2026-06-12
incident_pr: 5226
incident_window: "ongoing until post-merge live-grant re-acceptance (≈ since checks:read was declared)"
recovery_at: "pending — gated on #5229 (gh api .permissions.checks == write)"
suspected_change: "github-app-manifest.json declared checks:read; POST /check-runs requires checks:write"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - github-app-permission-misconfiguration
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The Inngest cron `cron-content-publisher` (fnId `soleur-runtime-cron-content-publisher`)
— and 4 sibling crons sharing the same helper — logged a handled
`HttpError: Resource not accessible by integration` on every run when posting a
synthetic GitHub check-run. The GitHub App manifest declared `checks: read`, but
`POST /repos/{owner}/{repo}/check-runs` requires `checks: write`, so the
installation token 403'd. The error is caught and Sentry-mirrored
(`handled=yes`, op `safe-commit-check-run-failed`) — it does not crash the cron,
so content still published — but it floods Sentry daily and means the synthetic
checks the `CI Required` ruleset depends on are never posted, degrading the bot
PRs' ability to satisfy required checks / auto-merge cleanly.

## Status

ongoing — the code plane (manifest `checks:write` + regression test) lands in
PR #5226; full recovery requires the live App-permission widen + installation
re-acceptance (GitHub-UI-only plane), tracked by #5229.

## Symptom

`HttpError: Resource not accessible by integration` on `POST /api/inngest`,
`fnId=soleur-runtime-cron-content-publisher`, daily. Sentry id `17933ec4…`,
release `web-platform@0.122.10`, op `safe-commit-check-run-failed`.

## Incident Timeline

- **Start time (detected):** 2026-06-12 16:01 CEST (Sentry alert)
- **End time (recovered):** pending live-grant re-acceptance (#5229)
- **Duration (MTTR):** open

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-12 14:01 | Sentry "new issue" alert forwarded to the agent. |
| agent | 2026-06-12 | Traced the 403 to the shared helper `_cron-safe-commit.ts:683`; root-caused to manifest `checks:read`. |
| agent | 2026-06-12 | Flipped manifest to `checks:write` + added regression test + drift-suppress marker (PR #5226). |
| agent | post-merge | Live App-permission widen + installation re-accept via Playwright; `gh api` grant-verify (#5229). |

## Participants and Systems Involved

GitHub App `soleur-ai` (installation `122213433`); Inngest cron fleet
(content-publisher + compound-promote + content-vendor-drift + rule-prune +
weekly-analytics); the shared `safeCommitAndPr` helper; Sentry; the
`cron-github-app-drift-guard` cron.

## Detection (+ MTTD)

- **How detected:** Sentry high-priority issue notification (monitoring system).
- **MTTD:** the error is daily and handled; the alert surfaced it on the
  2026-06-12 run. Exact first-occurrence not pinpointed (handled noise).

## Triggered by

system — a declarative manifest permission that was narrower than the API call
the shared helper makes.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Manifest `checks:read` insufficient for POST /check-runs | manifest `:21` = read; GitHub docs require checks:write; live `gh api` grant = read | none | confirmed |
| Wrong token type (GITHUB_TOKEN vs App) | — | path uses App installation token only (`mintInstallationToken`); `hr-github-app-auth-not-pat` | rejected |

## Resolution

Two-plane fix (precedent #4174/#4189): (1) code plane — manifest
`checks: read`→`write` + parity-test value lock (PR #5226); (2) live-grant plane
— App permission widen + installation re-acceptance via Playwright MCP, verified
by `gh api … .permissions.checks == write` (#5229). `MANIFEST_DRIFT_SUPPRESS_UNTIL`
suppresses the self-inflicted drift alert in the deploy→re-accept window.

## Recovery verification

`gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.checks'`
returns `write`, AND the next `cron-content-publisher` run posts check-runs
`completed/success` with no `safe-commit-check-run-failed` Sentry op. Tracked by #5229.

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the cron 403? The installation token lacked `checks: write`.
2. Why did the token lack it? The App manifest declared `checks: read`.
3. Why was read sufficient until now? The synthetic-check POST path
   (`syntheticChecks`) needs write; read was never exercised against it / never
   value-locked.
4. Why was it not caught in CI? The parity test asserted key *presence*, not the
   `checks` *value* — a too-narrow value shipped green.
5. Why a daily flood and not a one-off? Five crons share the helper and run on
   their own schedules, so the 403 recurs across the fleet.

## Versions of Components

- **Version(s) that triggered the outage:** web-platform@0.122.10 (and prior — manifest checks:read)
- **Version(s) that restored the service:** the release carrying PR #5226 + live-grant re-acceptance

## Impact details

### Services Impacted

Cron fleet synthetic check-runs (5 crons); bot-PR auto-merge cleanliness; Sentry signal-to-noise.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none direct (content still published).
- Legal-document signer: none.
- Admin via Access: degraded cron-fleet green/red trust + Sentry noise.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Daily Sentry noise eroding the cron fleet's green/red signal; bot PRs unable to
satisfy synthetic required checks for clean auto-merge.

## Lessons Learned

### Where we got lucky

The error was handled — the cron still published content, so the only impact was
observability noise + auto-merge friction, not a content-publishing outage.

### What went well

The two-plane pattern + drift-suppress sequencing already existed (#4174/#4189),
so the fix was a low-risk replay with a regression test.

### What went wrong

The parity test guarded key presence but not the `checks` value, so a too-narrow
permission shipped green and surfaced only as production Sentry noise.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5229 | Widen live App `checks` permission + re-accept installation (Playwright); verify via `gh api`; force drift-guard green; delete `MANIFEST_DRIFT_SUPPRESS_UNTIL`; confirm Sentry op stops. | open |
