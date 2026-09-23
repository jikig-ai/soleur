---
title: "Sentry alert-rule API permanently removed (410) wedged the Sentry Terraform root for three days"
date: 2026-09-21
incident_pr: 8453
incident_window: "2026-09-18T10:10:30Z → 2026-09-21T22:07:12Z"
recovery_at: "2026-09-21T22:07:12Z"
suspected_change: "External: Sentry moved the legacy alert-rule endpoint projects/{org}/{proj}/rules/{id}/ from scheduled brownouts (see sentry-issue-alert-410-transient-wedge-postmortem.md, Supersession 2026-08-19) to permanent removal. The last two sentry_issue_alert resources still refreshed through it."
brand_survival_threshold: single-user incident
status: resolved
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data breached; the incident was a paging-configuration gap, not a data exposure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

From 2026-09-18 every full-root `terraform plan` of `apps/web-platform/infra/sentry/` failed with `410 {"detail":"This API no longer exists."}` on the two remaining `sentry_issue_alert` resources. The required `plan_pr` check was red on main and on every Sentry-infra PR, and the post-merge apply never ran. Reviewed alerting changes merged during that window were therefore not live in Sentry, including the new GDPR Art. 17 erasure-incomplete page.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

`apply-sentry-infra.yml` push runs on main failed at plan with a 410 on `sentry_issue_alert.auth_per_user_loop` and `sentry_issue_alert.sandbox_startup_failure`, on every retry attempt (3 of 3 measured on run 35333341158). The brownout retry ladder spent its attempts and reported the failure as a possible brownout. `plan_pr` failed the same way on every PR touching the Sentry root.

## Incident Timeline

- **Start time (detected):** 2026-09-18T10:10:30Z
- **End time (recovered):** 2026-09-21T22:07:12Z
- **Duration (MTTR):** 83h56m

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-15T20:45:34Z | Last successful push apply of `apply-sentry-infra.yml` on main (run 35021586669). |
| agent | 2026-09-18T10:10:30Z | Push apply run 35333341158 fails at plan: 410 on both `sentry_issue_alert` addresses, 3 of 3 attempts, apply skipped. |
| agent | 2026-09-18T10:21:04Z | The apply-failure filer opens #8282. |
| agent | 2026-09-19T08:19:28Z | Push apply run 35431690519 fails the same way. |
| agent | 2026-09-20T22:05:29Z | #8451 filed: the endpoint is removed, not browning out. |
| agent | 2026-09-20T22:46:20Z | Push apply run 35542672914 fails the same way. |
| agent | 2026-09-21 | PR #8453 adopts both rules as frozen `sentry_alert` (removed + import), deletes the retry ladder, and anchors gate windows on the last applied commit. |
| agent | 2026-09-21T21:55:06Z | PR #8453 merges as `f016a103d`. |
| agent | 2026-09-21T22:07:12Z | Push apply run 35659890761 applies: `2 imported, 2 added, 2 changed, 0 destroyed`. The backlog (`art17_erasure_incomplete`, `scheduled_devin_docs_drift`, both `git_data_boot_*` updates) is live. The job still ends red on its post-apply probe, on an unrelated UNMANAGED finding (#8267). |
| agent | 2026-09-22T11:23:57Z | PR #8545 registers Sentry's Seer default (#8267). Push apply run 35721054277 concludes `success` (`0 added, 0 changed, 0 destroyed`, live fidelity PASS), and its success step closes #8282. |

## Participants and Systems Involved

Operator (single founder); Claude Code; GitHub Actions `apply-sentry-infra.yml` (`plan_pr` and push `apply` jobs); Sentry API (org `jikigai-eu`); Terraform Sentry provider v0.15.7.

## Detection (+ MTTD)

- **How detected:** monitoring — the workflow's apply-failure filer opened #8282 from the failed push run.
- **MTTD (mean time to detect):** 0h10m

## Triggered by

provider — one of user / system / market movement / provider.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Another scheduled brownout of the deprecated API (the 2026-08-19 reading) | The same 410 body; brownouts were measured on 2026-08-19 | 410 on every attempt across three runs over ~60 hours, with no 200 window | Rejected |
| Permanent removal of the legacy alert-rule endpoint | 410 on every attempt since 2026-09-18; body says "This API no longer exists" | None observed | Accepted |

## Resolution

PR #8453. `removed { lifecycle { destroy = false } }` forgets the two old addresses without refreshing them, and `import {}` adopts the same live rules (566671, 669246) at `sentry_alert` addresses with frozen `legacy_trigger_conditions` and `ignore_changes = all`. The create tripwire refuses any write to a legacy-trigger rule. The brownout retry ladder is deleted, so a 410 is reported once, with the failing addresses. Gate windows are anchored on the last applied commit, so the backlog merged during the wedge is bounded and visible.

## Recovery verification

Recovered at 2026-09-21T22:07:12Z, when push run 35659890761 of `apply-sentry-infra.yml` on `f016a103d` completed its Terraform apply: `Apply complete! Resources: 2 imported, 2 added, 2 changed, 0 destroyed.` The imports were rules 566671 and 669246; the creates were `art17_erasure_incomplete` and `scheduled_devin_docs_drift`; the updates were `git_data_boot_fatal` and `git_data_boot_warning`. The post-apply frozen-rule pin compared both adopted rules against the committed capture with no divergence.

That run still concluded `failure`, on its post-apply live-fidelity probe, for one finding unrelated to this incident: the Sentry-created workflow "Send a notification when pull requests are ready", tracked since 2026-09-18 in #8267. PR #8545 registered it as a vendor default. Push run 35721054277 on `2cbf7b9ef` then concluded `success` at 2026-09-22T11:23:57Z with no changes and a live-fidelity PASS over all 30 in-scope rules, and its success step closed #8282.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did applies stop? The full-root plan refreshes every managed resource, and two of them 410 on refresh.
2. Why did they 410? They were `sentry_issue_alert` resources, which refresh through the legacy alert-rule endpoint that Sentry has now removed.
3. Why were they still `sentry_issue_alert`? The #7650 migration could not convert them: provider v0.15.7 cannot express their unique-user-frequency triggers natively, and it has no cross-type move.
4. Why was the removal read as a brownout for so long? The workflow's retry ladder was built for brownouts, so a permanent 410 looked like one that simply lasted longer.
5. Why did the wedge hide reviewed changes? Gates reasoned about "this PR's diff", while merged-but-unapplied blocks from other PRs accumulated with no single diff that showed them.

## Versions of Components

- **Version(s) that triggered the outage:** External (Sentry API); no Soleur change. Last green apply at main `d8b5fa1fd`.
- **Version(s) that restored the service:** PR #8453 (`f016a103d`); the workflow went fully green with PR #8545 (`2cbf7b9ef`)

## Impact details

### Services Impacted

Sentry alerting-as-code: `apply-sentry-infra.yml` plan and apply. The two adopted paging rules stayed live and unchanged throughout. The changes that did not reach Sentry were the `art17_erasure_incomplete` page (create), the `scheduled_devin_docs_drift` alert (create), and the `git_data_boot_fatal` and `git_data_boot_warning` updates.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none.
- Authenticated app user: no direct impact observed. A failed Art. 17 erasure during the window would not have paged the founder, because that page was not yet live. Whether any erasure was incomplete in the window has not been measured in this report.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Unknown / N/A

### Team Impact

Every Sentry-infra PR was blocked by a red required check for the window, and one engineering pipeline run (this PR) went to the migration.

## Lessons Learned

### Where we got lucky

The two affected rules stayed live in Sentry the whole time. A plan that fails at refresh writes nothing, so no paging rule was changed or lost.

### What went well

The apply-failure filer opened #8282 within ten minutes of the first failed run, and the run log named the exact addresses and the 410 body.

### What went wrong

The retry ladder framed a permanent removal as a brownout for about 60 hours. Gates scoped to one PR's diff could not see the backlog that the first green apply would carry.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #7985 | Convert the two frozen legacy-trigger `sentry_alert` rules to native triggers once the provider ships 0deba79, retiring the freeze. | open |
| #8483 | Give preflight Check 10 a terminal for discoverability probes that are only true after merge (this PR's probe reads the post-merge apply run). | open |
