---
title: "Tenant integration (dev-Supabase) Art-17 cascade failure — routine_runs orphan-migration WORM contradiction"
date: 2026-06-15
incident_pr: "#5376"
incident_window: "2026-06-15 ~15:31–18:40 UTC (main CI red)"
recovery_at: "2026-06-15 ~20:40 UTC (dev revert applied)"
suspected_change: "Orphan unmerged 104_routine_runs.sql (PR #5342) applied to shared dev at 14:02 UTC via ALLOW_UNMERGED_DEV_APPLY=1"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - "CI: standalone Tenant integration (dev-Supabase) workflow red on main, 5+ consecutive runs"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — after operator confirmation.
- `human` — operator did this directly.

# Incident Overview

The non-required `Tenant integration (dev-Supabase)` GitHub Actions workflow was red on `main` for ~4 hours. Every test that tears down a tenant user failed: the GoTrue admin `deleteUser` returned `status=500 code=unexpected_failure`, ending (after 5 `withGoTrueRetry` attempts) with `Database error deleting user`. This exercises the GDPR Art-17 account-delete / DSAR cascade.

**Scope: CI / test-surface, not a customer-facing production outage.** Sentry cron monitors were healthy throughout; the failure was confined to the dev-Supabase integration suite. The offending object (`routine_runs`) existed only on dev (applied from an unmerged PR), never on `main` or prod. The GDPR deletion path failed **safe** — it *blocked* (aborted the transaction), it did not expose or leak any personal data. The production Art-17 risk was latent and never realized.

## Status

resolved

## Symptom

`AssertionError: deleteAccount failed with error: Account deletion failed at auth-delete. Please try again.` across `account-delete.cascade.integration.test.ts`, `attachments-workspace-shared-cascade.integration.test.ts`, `dsar-export-workspace-tables.integration.test.ts`, plus `tearDownTenantUser: ... Database error deleting user` in ~8 tenant-isolation suites.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-15 14:02 | PR #5342's CI applied orphan `104_routine_runs.sql` to shared dev (`ALLOW_UNMERGED_DEV_APPLY=1`). |
| agent | 2026-06-15 ~15:31 | First red `Tenant integration` run on `main` (`4209e11f8`); normalized red for ~4h. |
| human | 2026-06-15 18:05 | Issue #5372 closed-as-completed (prematurely — CI still red). |
| agent | 2026-06-15 ~20:00 | `/soleur:go 5372` re-opened #5372 after confirming CI still failing on tip of main. |
| agent | 2026-06-15 ~20:40 | Dev revert applied; cascade suite green 3/3. |

## Detection (+ MTTD)

- **How detected:** incidentally, during postmerge verification of unrelated PR #5367; then re-confirmed via `/soleur:go 5372`.
- **MTTD:** ~hours (non-required workflow; no auto-page — it normalized red).

## Root Cause(s) — 5-Whys

1. Why did the cascade fail? → `auth.users` delete cascaded `UPDATE routine_runs SET actor_id=NULL`, which a WORM trigger rejected with `P0001`.
2. Why did the trigger fire on an empty table? → the WORM triggers are `FOR EACH STATEMENT`; a statement-level BEFORE UPDATE trigger fires on the cascade UPDATE even against 0 rows.
3. Why was `routine_runs` on dev at all? → it was applied from open WIP PR #5342 via the `ALLOW_UNMERGED_DEV_APPLY` local-iteration valve, and never reverted.
4. Why didn't a `app.worm_bypass` carve-out save it? → the cascade runs inside GoTrue's own transaction, where `account-delete.ts` cannot set the GUC.
5. Why was the contradiction shippable? → no gate checked the behavioural invariant "a WORM trigger must not sit on a users-delete cascade FK"; the orphan-drift probe is warning-only by design.

## Impact details

### Customer Impact (by role)
None. Dev-only / CI-surface; no production user attempted (and failed) an erasure. The Art-17 risk was latent.

### Revenue Impact
None.

### Team Impact
~4h of red `main` CI on a non-required workflow; one premature issue-close requiring re-open.

## Lessons Learned

### Where we got lucky
The contradiction lived only on dev (unmerged PR). Had `routine_runs` merged to `main` and reached prod, every prod user's erasure would have broken.

### What went well
The deletion failed safe (blocked, not leaked). Multi-agent review caught a follow-on flaw (the first gate design would have false-red main).

### What went wrong
A non-required workflow normalized red for ~4h without paging; the issue was closed before CI was green.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5342 | Fix the `routine_runs` migration at source before it merges (row-level WORM triggers + `app.worm_bypass` carve-out + `anonymise_routine_runs` step in `account-delete.ts`, or `ON DELETE RESTRICT` + pre-anonymise). Filed as a blocking review comment on PR #5342; enforced by the new `preflight-worm-cascade-contradiction` gate (its CI fails until fixed). | OPEN |
