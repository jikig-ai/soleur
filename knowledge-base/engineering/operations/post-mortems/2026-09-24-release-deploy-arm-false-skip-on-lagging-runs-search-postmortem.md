---
title: "2026-09-24 release deploy arm false skip on lagging runs search"
date: 2026-09-25
incident_pr: 8770
incident_window: "2026-09-24T19:45:04Z → 2026-09-24T19:59:13Z"
recovery_at: "2026-09-24T19:59:13Z"
suspected_change: "Web Platform Release deploy arm (resolve-target): single runs?event=push&head_sha= search read as absence; exposed by PR #8732 merge ee9f2c9424"
brand_survival_threshold: aggregate pattern
status: resolved
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach (availability/staleness only)"
classification_override:
  advisory: none
  chosen: aggregate pattern
  reason: "No user data or credential surface, but the defect is systemic: every merge whose runs search lags ships nothing while CI reports green, so silent staleness compounds across merges. Matches the fix plan's declared threshold."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The Web Platform Release deploy arm decided there was nothing to deploy for the merge of PR #8732 (ee9f2c9424) because a GitHub runs **search** answered empty while the release for that SHA had already been published. The run ended green, and production kept serving the previous build until a manual re-run about 14 minutes later.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

Deploy-arm run 36050118687 attempt 1: `resolve-target` succeeded at 19:45:04Z with a clean skip (`no_release_run`), so `deploy` and `live-verify` were skipped and `release-outcome` reported success. The push-arm release run 36047804812 for the same SHA had completed at 19:31:21Z. The same query returned that run minutes later.

## Incident Timeline

- **Start time (detected):** 2026-09-24T19:45:04Z
- **End time (recovered):** 2026-09-24T19:59:13Z
- **Duration (MTTR):** 0h14m

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-24T19:23:19Z | PR #8732 merged as ee9f2c9424; push-arm release run 36047804812 starts at 19:23:22Z. |
| agent | 2026-09-24T19:31:21Z | Push-arm release run 36047804812 publishes the release for ee9f2c9424. |
| agent | 2026-09-24T19:43:55Z | Deploy-arm run 36050118687 attempt 1 starts on main CI completion. |
| agent | 2026-09-24T19:45:04Z | `resolve-target` gets `[]` from `runs?event=push&head_sha=ee9f2c9424…`, clean-skips `no_release_run`; `deploy` skipped. Incident start. |
| human | 2026-09-24T19:49:10Z | Manual re-run of run 36050118687 (attempt 2). |
| agent | 2026-09-24T19:51:41Z | Attempt 2 `resolve-target` finds release run 36047804812. |
| agent | 2026-09-24T19:58:30Z | `deploy` succeeds. |
| agent | 2026-09-24T19:59:13Z | `live-verify` succeeds. Recovery. |

## Participants and Systems Involved

Operator (single founder); GitHub Actions workflow `web-platform-release.yml` (jobs `resolve-target`, `deploy`, `live-verify`, `release-outcome`); GitHub REST list-workflow-runs endpoint.

## Detection (+ MTTD)

- **How detected:** manual — the deploy arm reported the deploy as skipped for a SHA whose diff changed `apps/web-platform/**`; a manual re-run started four minutes after the skip. No monitor paged, because the skip was reported as a success.
- **MTTD (mean time to detect):** Unknown (external/manual report)

## Triggered by

provider — one of user / system / market movement / provider. (GitHub's runs search index lagged; the defect that turned the lag into a silent skip was ours.)

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `on.push.paths` declined the push, so no release was due | This is what `no_release_run` asserts | Release run 36047804812 existed for the SHA and had published 13 min earlier | Refuted |
| Runs search index lag (`event`/`head_sha` are search params) | The same query returned the run minutes later; the unfiltered run list was current | None | Confirmed |

## Resolution

Manual re-run of the deploy arm (attempt 2), which found the release run and deployed. Permanent fix in PR #8770: up to 4 lookups 20 s apart, each reading the filtered search and then the unfiltered run list; when both stay empty, the SHA's own diff under the release pathspec decides. An empty diff keeps the green clean skip, and a deployable or uncomputable diff fails loudly as `release_run_missing` and pages with the re-run command.

## Recovery verification

Run 36050118687 attempt 2: `deploy` success at 19:58:30Z, `live-verify` success at 19:59:13Z (`gh api repos/jikig-ai/soleur/actions/runs/36050118687/attempts/2/jobs`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did production not update? `resolve-target` clean-skipped the deploy (`no_release_run`).
2. Why did it clean-skip? Its single runs lookup returned `[]`, and an empty answer was read as "`on.push.paths` declined this push".
3. Why was the answer empty? `event` and `head_sha` are search parameters on the list-runs endpoint; the search index lagged at least 13 minutes behind the published run.
4. Why did nothing catch it? The verdict rested on absence alone, with no independent discriminator, and a clean skip is green, so neither notify-gated nor release-outcome paged.
5. Why was absence trusted? The design (ADR-217) treated the search as authoritative; over 200 runs, 1 of 10 attempt-1 `no_release_run` verdicts was false.

## Versions of Components

- **Version(s) that triggered the outage:** jikig-ai/soleur `web-platform-release.yml` resolve-target as of ee9f2c9424 (merge of PR #8732)
- **Version(s) that restored the service:** same workflow, run 36050118687 attempt 2 (manual re-run); permanent fix PR #8770

## Impact details

### Services Impacted

Web platform (app.soleur.ai) deployment freshness only. The app stayed up and served the previous build.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none.
- Authenticated app user: for about 14 minutes still served the pre-#8732 build (C4 render sandbox and stale-banner copy not yet live). No errors or data impact.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Unknown / N/A

### Team Impact

A manual re-run, plus a follow-up fix PR (#8770).

## Lessons Learned

### Where we got lucky

The skip was noticed within minutes. Nothing paged, so an unattended merge would have left production stale until the hourly drift alert crossed its roughly 4-hour threshold.

### What went well

A single re-run recovered, and the run history made the index-lag diagnosis quick, since the same query returned the run minutes later.

### What went wrong

A green verdict rested on an empty search result. While fixing it we also found that `::error::` annotations emitted inside `$( … )` captures in `resolve-target` were swallowed on every `github_api_unavailable`, so that failure mode paged with no cause in the log (fixed in #8770).

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8799 | Decide on the retry, and on the `release_run_missing` refinements (plain-language email arm, automatic delayed re-run, drift-alert de-duplication) deferred from #8770. | open |
