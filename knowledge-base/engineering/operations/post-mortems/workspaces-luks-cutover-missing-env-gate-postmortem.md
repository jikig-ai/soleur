---
title: "Near-miss: /workspaces LUKS cutover freeze had no provisioned authorization gate (would auto-approve)"
date: 2026-07-17
incident_pr: 6638
incident_window: "n/a — near-miss; the freeze was never dispatched, no production or user impact occurred"
recovery_at: "2026-07-17 (authorization gate provisioned by PR #6638, before any freeze dispatch)"
suspected_change: "PR #6610 (the /workspaces LUKS cutover mechanism) shipped a workflow_dispatch job declaring environment: workspaces-luks-cutover without a Terraform resource provisioning that environment"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - latent-security-gap
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach: this is a latent-control gap caught pre-dispatch; no data was accessed, altered, or lost"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

This is a **near-miss**, not a production incident: no freeze was ever dispatched, and no user data was accessed, altered, or lost.

While preparing to run the `/workspaces` LUKS cutover (operator request "run the cutover for LUKS"), the pre-flight state pull found that the freeze workflow `.github/workflows/workspaces-luks-cutover.yml` declares `environment: workspaces-luks-cutover` as — per its own sign-off comment — the **sole human authorization** on an irreversible freeze of sole-copy user source code (passphrase/header loss ⇒ unreadable forever), but that GitHub environment was **never provisioned** (`gh api …/environments/workspaces-luks-cutover` → 404; no Terraform resource). GitHub auto-creates a referenced-but-absent environment with **zero protection rules** on first use, so a freeze dispatch would have **auto-approved the irreversible freeze with no human ack** — the exact DP-11 F8 failure the workflow header warns about. The gap was caught **before** any dispatch.

## Status

resolved — the authorization gate is provisioned by PR #6638 (mirroring the `inngest-cutover` precedent); no freeze was dispatched during the exposure window.

## Symptom

`gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover` returned HTTP 404 while the merged freeze workflow referenced that environment as its sole human gate. No user-facing symptom occurred (the mechanism was never dispatched).

## Incident Timeline

- **Start time (detected):** 2026-07-17 (during cutover pre-flight state pull)
- **End time (recovered):** 2026-07-17 (gate provisioned in PR #6638, pre-dispatch)
- **Duration (MTTR):** near-miss — no active-incident window; remediated before any dispatch

Order of events:

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-17 | Pre-flight for the cutover pulled live state; found the env 404 + no Terraform resource. |
| agent | 2026-07-17 | Confirmed no cutover/verify/apply run had ever fired (zero exposure realized). |
| agent-with-ack | 2026-07-17 | Operator confirmed provisioning the gate via Terraform (reviewer @deruelle). |
| agent | 2026-07-17 | PR #6638 declared the `github_repository_environment.workspaces_luks_cutover` resource + wired the default-apply `-target` + added a fail-closed reviewer-non-empty CI guard. |

## Participants and Systems Involved

GitHub Actions environments; Terraform (`apps/web-platform/infra`); the `workspaces-luks-cutover.yml` freeze workflow; the `apply-web-platform-infra.yml` default apply.

## Detection (+ MTTD)

- **How detected:** self-pull of live GitHub API + Terraform state during cutover pre-flight (not a monitoring alert — the gap was a missing control, not a firing error). MTTD: caught on the first action of the cutover attempt, before any dispatch.

## Triggered by

system — a shipped workflow referenced a control (GitHub environment) that its accompanying IaC never provisioned; CI stays green because a missing environment is a runtime hole, not a build error.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| PR #6610 omitted the Terraform resource for the environment it referenced | env 404; no `github_repository_environment.workspaces_luks_cutover` in any `.tf`; the sibling `inngest_cutover` env IS TF-provisioned | none | confirmed |

## Resolution

Provisioned `github_repository_environment.workspaces_luks_cutover` (reviewer `[54279]` = @deruelle) in `workspaces-luks.tf`, wired into the default per-merge apply, corrected the runbook precondition (it had mis-framed the gate as a manual operator step), and added a fail-closed CI guard asserting every `github_repository_environment` keeps a non-empty `reviewers.users`. All in PR #6638.

## Recovery verification

Post-merge, the merge-triggered default apply provisions the environment; `gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover` returns 200 with a non-empty required-reviewer set (verified in-session by ship Phase 7 / postmerge). The new CI guard is mutation-verified (emptying `reviewers.users` → RED).

## 5 Whys — final root cause

1. Why would a freeze auto-approve? The `workspaces-luks-cutover` environment did not exist. → 2. Why didn't it exist? PR #6610 referenced it in the workflow but shipped no Terraform resource for it. → 3. Why did that pass review/CI? A missing GitHub environment is a runtime hole, not a build/test failure — nothing gated on its existence. → 4. Why was there no gate? The reviewer-non-empty / env-existence property had no pre-merge assertion (the sibling `inngest_cutover` env had the same posture). → 5. Root cause: a `workflow_dispatch` `environment:` safety gate was treated as self-provisioning; provisioning it is an IaC step, and its non-emptiness needs a CI assertion. Both are now in place for both cutover gates.

## Action Items & Follow-ups

_No action items — incident fully resolved by PR #6638 (gate provisioned via Terraform, reviewer-non-emptiness now CI-guarded for both cutover environments, runbook corrected). The downstream live freeze / verification window / volume wipe remain operator-dispatched, environment-gated steps tracked on #6604 and are out of scope for this near-miss._
