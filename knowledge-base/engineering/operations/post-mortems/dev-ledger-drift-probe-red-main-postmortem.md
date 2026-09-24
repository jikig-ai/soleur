---
title: "Dev-ledger drift probe turned main's tenant-integration red on legitimately in-flight migrations"
date: 2026-09-23
incident_pr: 8602
incident_window: "2026-09-21T15:13Z–2026-09-21T19:51Z and 2026-09-22T10:14Z–2026-09-22T21:58Z"
recovery_at: "2026-09-22T21:58Z"
suspected_change: "#8475 (made the dev-vs-main migration drift probe blocking on push to main)"
brand_survival_threshold: none
status: resolved
triggers:
  - "tenant-integration push runs on main failing at 'Detect dev-vs-main migration drift'"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — CI signal on the shared dev database; no personal data involved"
---

## Actor key

- `agent`: Claude Code did this autonomously (no operator ack required).
- `agent-with-ack`: Claude Code did this AFTER the operator confirmed via a menu option, per `hr-menu-option-ack-not-prod-write-auth`.
- `human`: the operator did this directly.

# Incident Overview

#8475 made the dev-vs-main migration drift probe blocking on push to main. Its plan assumed that "on push … there is no legitimate unmerged-migration state". ADR-061 already said the opposite: the shared dev Supabase ledger holds main's migrations plus every open PR's applied-but-unmerged ones. From then on, main's `tenant-integration` went red whenever dev carried a row that main did not, including rows an open PR had legitimately applied.

## Status

resolved

## Symptom

`tenant-integration` push runs on main failed at `Detect dev-vs-main migration drift` and its post-section re-probe. The 2026-09-22 runs 35732801080 and 35736906203 reported `Missing-on-main: 139_openai_api_key_provider.sql`, a row applied by then-open PR #8507.

## Incident Timeline

- **Start time (detected):** 2026-09-21T15:13Z (first push run after #8475 merged: run 35617462157)
- **End time (recovered):** 2026-09-22T21:58Z (run 35789724725 green; every later drift-probe step on main is green)
- **Duration (MTTR):** two red windows, about 4.6 h and about 11.7 h

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-21T15:13 | #8475 merges; that push's `tenant-integration` run fails at the drift probe (35617462157). |
| agent | 2026-09-21T19:46 | #8520 filed for the red main. |
| agent | 2026-09-21T19:51 | Next push run is green (35647415987). |
| agent | 2026-09-21T21:00 | #8521 filed: edit-after-apply content drift as a root-cause class. |
| agent | 2026-09-22T10:14 | Red again at the drift probe (35714846793): `139_…` applied by open #8507, plus an in-place edit to `138_…` (#8583). |
| agent | 2026-09-22T14:52 | #8507 merges. |
| agent | 2026-09-22T21:58 | Main green (35789724725, #8588). |
| agent | 2026-09-23 | #8602 classifies missing-on-main rows by owning ref and fails the owning PR on edit, rename or delete after apply. |

## Participants and Systems Involved

The `tenant-integration` workflow, the `dev-migration-drift-probe` composite action, the shared dev Supabase project's `public._schema_migrations` ledger, and the open PRs that apply migrations to dev.

## Detection (+ MTTD)

- **How detected:** by monitoring. The fail-closed probe itself turned main's required check red.
- **MTTD:** 0. The first affected push failed.

## Triggered by

system (a CI gate change: #8475)

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The blocking probe does not tell an open PR's in-flight row apart from an orphan | The 2026-09-22 row `139_…` was owned by open #8507; ADR-061's rejected alternative predicted exactly this | none | confirmed |
| Content drift from edit-after-apply (#8521) caused the 2026-09-22 reds | 26 content-drift rows existed on 2026-09-21 | The 2026-09-22 reds were the in-flight arm and the #8583 arm, with zero #8521-arm rows | rejected as the 09-22 trigger; fixed anyway as its own class |

## Resolution

#8602 does two things. On the main side it runs `dev-ledger-parity.sh classify-missing`: a missing-on-main row that a fresh, unmerged origin branch owns among its files not on main is an in-flight warning. Ownerless, stale-owned, in-history and unclassifiable rows still block. On the PR side it adds a pre-apply `check`, which fails the owning PR when an applied migration was edited, renamed or deleted. #8597 separately blocks in-place edits to already-merged migrations (#8583).

## Recovery verification

Every `tenant-integration` push run on main from 35789724725 onward is green at the drift-probe steps. The one later red run (35876994524) failed in `Run tenant-isolation tests`, not in the drift probe. #8602's own heavy job printed `ledger-parity: clean (unmerged=0 … ledger-rows=166 …)` (run 35879273321).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was main red? The drift probe blocked on a row dev had and main did not.
2. Why did dev have it? An open PR's CI applied its migration to shared dev, which the design allows (`ALLOW_UNMERGED_DEV_APPLY`).
3. Why did that block main? The probe was made blocking on push without classifying rows by owning ref.
4. Why was it made blocking that way? #7964's plan (§M2) assumed that no legitimate unmerged state exists on push.
5. Why did no check catch that premise? The plan did not consult ADR-061, whose Context states the opposite, and nothing asks a plan that makes a shared-dev gate blocking to say who owns each row. A plan sharp-edge now does.

## Versions of Components

- **Version(s) that triggered the outage:** main at #8475's merge (2026-09-21T15:13Z)
- **Version(s) that restored the service:** #8588 (green main); #8602 (structural fix)

## Impact details

### Services Impacted

CI only: main's `tenant-integration` required check. No served application code path was involved.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none. No served code changed.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Main's required check was red for about 16 h in total. Whether that delayed any release was not measured.

## Lessons Learned

### Where we got lucky

The red was loud. A fail-open version of the same premise would have hidden real orphans.

### What went well

The fail-closed probe surfaced the contradiction on its first push.

### What went wrong

A premise from a sibling plan ("no legitimate unmerged state on push") was adopted without being checked against the ADR that governs the substrate.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8605 | Handle dev-ledger rows owned by closed-unmerged branches, and add a self-service dev-reconcile path for applied migrations | open |
| #8606 | Fix the `run-migrations.sh` unmerged-apply gate, which is vacuous when run from `apps/web-platform` (cwd-relative pathspec) | open |

### Status note — 2026-09-24

Both action items are resolved by PR #8642 (ADR-061 amendment for #8605/#8606):

- #8605: the probe now classifies rows held only by a branch whose PR closed unmerged at its tip as
  `closed-grace`, then `closed-tracked` or `closed`, and `dev-ledger-reconcile.yml` discards a PR's
  dev rows when it closes unmerged or on dispatch from `main`.
- #8606: `run-migrations.sh` anchors its unmerged-apply pathspecs with `:(top,literal)`, so the gate
  names the same paths from `apps/web-platform` as from the repo root.
