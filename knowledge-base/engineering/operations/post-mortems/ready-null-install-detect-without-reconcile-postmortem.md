---
title: "ready+NULL-install solo workspace detected but not reconciled for ~5 weeks (founder KB freeze)"
date: 2026-06-29
incident_pr: 5684
incident_window: "~5 weeks (founder workspace reached repo_status='ready' with github_installation_id IS NULL; unreachable by push reconcile)"
recovery_at: "pending next 23:06 UTC cron fire post-deploy (automated reconcile)"
suspected_change: "arm-1 of cron-workspace-sync-health was a reporter, never a reconciler — the resolve/clone failures that produced the NULL-install state (multi-workspace-founder-resolve, concierge stale-installation) left a ready workspace with no install and no automated path back"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - single-user incident (founder's own KB stale for ~5 weeks)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/data-freshness incident, no personal-data breach (no unauthorised access, loss, or disclosure of personal data; the stuck credential was never exposed)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A founder workspace reached `repo_status='ready'` but `github_installation_id IS NULL` — a state unreachable by the push-based reconcile, so its KB never synced again. `cron-workspace-sync-health` arm-1 was built (#4709) precisely to *detect* this class, and it did: it emitted a folded `op:ready-null-installation` Sentry signal on every fire. But arm-1 only **reported** — it never **reconciled**, and the folded signal accreted occurrences without clearing for ~5 weeks. The detection worked; the remediation gap is the incident.

## Status

resolved — remediation (automated entitlement-scoped, solo-only reconcile) ships in PR #5684; producer-investigation residual tracked in #5689.

## Symptom

Founder's KB tree stale for ~5 weeks. No error surfaced to the user; the cron heartbeat stayed green (`ok:true`). The only signal was a folded Sentry issue that no automated step or operator action consumed.

## Incident Timeline

- **Start time (detected):** workspace entered ready+NULL-install (origin: the resolve/clone failures post-mortem'd in `multi-workspace-founder-resolve-and-ready-clone-postmortem.md` / `concierge-clone-stale-installation-gh403-postmortem.md`).
- **End time (recovered):** pending next 23:06 UTC cron fire post-deploy (automated reconcile).
- **Duration (MTTR):** ~5 weeks of freeze; remediation latency now bounded to one cron cycle (≤24h) once a workspace is detected.

| Actor | Time (UTC) | Action |
|---|---|---|
| system | T0 (~5 weeks pre-fix) | Workspace reaches ready+NULL-install; push reconcile cannot reach it. |
| system | daily | arm-1 detects + reports `op:ready-null-installation` (folded Sentry issue, occurrences climb). |
| human | 2026-06-29 | #5675 filed: arm-1 detects but does not reconcile. |
| agent | 2026-06-29 | PR #5684 — arm-1 report → reconcile (entitlement-scoped, solo-only). |

## Participants and Systems Involved

`cron-workspace-sync-health` (arm-1), `reachable-installations.ts`, `workspace-repo-mirror.ts` (`writeRepoColsToWorkspace`), GitHub App installation tokens, Supabase `workspaces`, Sentry (`op:ready-null-installation`), Better Stack.

## Detection (+ MTTD)

- **How detected:** monitoring — arm-1 of the sync-health cron (the probe built for this class). Detection was immediate and reliable; the gap was downstream (no remediation).
- **MTTD:** ~1 cron cycle (≤24h). The incident is the **remediation** latency, not detection.

## Triggered by

system — an internal state (ready+NULL-install) with no automated path back to a synced KB.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| arm-1 detects but never reconciles; folded signal accretes unactioned | the standing `op:ready-null-installation` issue gained occurrences for weeks with no remediation | — | confirmed |

## Resolution

PR #5684 makes arm-1 reconcile the recoverable subset: resolution is entitlement-scoped to the owner's reachable installs (`resolveReachableInstallationIds`) and restricted to solo workspaces; the backfill goes through the canonical `writeRepoColsToWorkspace` boundary. Unresolvable findings (`needs-reauth`, `team`, `malformed-repo-url`) keep the visible signal; an all-degraded GitHub sweep is `transient` (no write, self-recovers next fire).

## Recovery verification

- Discoverability probe (no-SSH, no-cred): `curl -sS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest` → `401` (Inngest serve HMAC challenge — function registered + serving). Verified green at ship time.
- Post-deploy soak (AC11/AC12): after the next 23:06 UTC fire reconciles the frozen workspace, the standing `op:ready-null-installation` occurrence count stops climbing and reconciled workspaces carry a non-NULL `github_installation_id`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the founder's KB freeze for ~5 weeks?** The workspace was ready+NULL-install, unreachable by the push reconcile.
2. **Why was it not recovered automatically?** arm-1 detected the state but only reported it.
3. **Why did reporting not lead to recovery?** The report was a folded Sentry signal with no automated consumer and no operator action.
4. **Why was there no automated consumer?** arm-1's role was scoped to detection at build time (#4709); reconcile was deferred.
5. **Why did the deferral persist 5 weeks?** A folded, level-agnostic signal does not page; "detected" was silently treated as "handled" — the recurring detection-without-remediation trap.

## Versions of Components

- **Version(s) that triggered the outage:** arm-1 report-only (pre-#5684).
- **Version(s) that restored the service:** PR #5684 (arm-1 reconcile).

## Impact details

### Services Impacted

KB sync for the affected (founder) workspace — stale tree, no new syncs.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: founder's own workspace KB stale ~5 weeks (single-user incident).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: the install existed but was never bound back to the ready workspace until this fix.

### Revenue Impact

None (pre-revenue; founder-as-tenant-zero).

### Team Impact

Founder dogfood friction; surfaced the reporter-vs-reconciler gap.

## Lessons Learned

### Where we got lucky

Single-user (founder) blast radius; the credential was never exposed (the stuck install was simply not bound, not leaked).

### What went well

The probe detected the exact class it was built for, reliably, every fire.

### What went wrong

Detection was treated as remediation. A folded non-paging signal accreted for weeks with no automated consumer — the freeze persisted invisibly to the user.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5675 | Primary remediation — arm-1 report → reconcile (entitlement-scoped, solo-only), PR #5684; stays open through the post-deploy soak (AC11/AC12) until the standing signal plateaus. | open |
| #5689 | Producer investigation (required-on-signal): why do ready workspaces reach NULL-install, and harden the producer so the reconcile backstop fires rarely. | open |
