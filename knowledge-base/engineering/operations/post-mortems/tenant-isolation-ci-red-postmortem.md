---
title: "Tenant-isolation CI guard silently red on main for ~2 days (schema drift after ADR-044 column drop)"
date: 2026-06-19
incident_pr: 5583
incident_window: "2026-06-17T22:38:00Z — 2026-06-19"
recovery_at: "2026-06-19"
suspected_change: "mig 112 / PR #5508 (dbf0e89d0) — ADR-044 PR-2b dropped users.{workspace_path,repo_url,github_installation_id}"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - safety-net (tenant-isolation regression guard) silently non-functional
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The **Tenant integration (dev-Supabase)** workflow (`.github/workflows/tenant-integration.yml`) — the only live verification that one founder's JWT cannot read another founder's `users`/repo/session-sync/email-triage rows — was **red on `main` from ~2026-06-17 22:38 UTC**. Because it is a path-filtered, non-required check, PRs kept auto-merging while the cross-tenant isolation property went **unverified in CI** for ~2 days. No production outage and no user-facing impact occurred (these are CI tests, not runtime code); the incident is the **safety-net being down**, the same class as the 2026-06-02 chat-RLS outage that motivated the Incident-PIR gate.

## Status

resolved — fixed in PR #5583 (this PR).

## Symptom

Two deterministic failures in the `*.tenant-isolation.test.ts` suites:
1. `42703 undefined_column` on the seed `UPDATE users` in `beforeAll` (test ↔ dev schema drift).
2. GoTrue admin `deleteUser` → `500 unexpected_failure` storm (the teardown helper FK-blocked on `ON DELETE RESTRICT`).

## Incident Timeline

- **Start time (detected):** 2026-06-19 (surfaced during PR #5580 ship post-merge verification; filed as #5582)
- **End time (recovered):** 2026-06-19 (PR #5583 merged; suites green against dev Supabase)
- **Duration (MTTR):** ~hours from detection to fix (the latent regression existed ~2 days before detection)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-17 22:38 | mig 112 / PR #5508 (ADR-044 PR-2b) lands, dropping `users.{workspace_path,repo_url,github_installation_id}`; first red `tenant-integration.yml` run. |
| system | 2026-06-17 → 06-19 | Suite stays red across subsequent merges; non-required check, so PRs keep auto-merging. |
| human | 2026-06-19 | Surfaced during PR #5580 post-merge verification; filed as #5582 (P1). |
| agent | 2026-06-19 | PR #5583: retarget suites off dropped columns + teardown FK-cascade parity + drift guard; verified green against dev Supabase. |

## Participants and Systems Involved

`apps/web-platform` tenant-isolation test suites, the `tenant-isolation-teardown.ts` helper, dev Supabase project, `tenant-integration.yml` workflow.

## Detection (+ MTTD)

- **How detected:** manual — noticed during another PR's (#5580) ship post-merge verification, not by an alert. MTTD ~2 days.
- **MTTD (mean time to detect):** ~2 days (the gap this incident exposes).

## Triggered by

system — a schema migration (mig 112) decommissioned columns the test suites still referenced.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Test ↔ dev schema drift after a column drop | mig 112 drops the exact columns the seeds SELECT/UPDATE; `42703` is undefined_column | — | CONFIRMED |
| Dev GoTrue/Auth backend in a bad state (issue's initial guess) | deleteUser 500s | The 500 is a deterministic FK RESTRICT block (missing anonymise RPC), not a transient backend outage | REJECTED |

## Resolution

PR #5583: (1) retargeted the tenant-isolation suites off the dropped `users` columns — Class-1 deny probes moved to surviving columns (`email`/`role`), `github_installation_id` deny moved to the `resolve_workspace_installation_id` RPC, repo-state seeds moved to `workspaces`; (2) brought `tenant-isolation-teardown.ts` to full FK-cascade parity (21 anonymise RPCs in production order, correct per-RPC arg names, fatality-class fail-loud); (3) added a source/migration drift guard (`teardown-anonymise-parity.test.ts`) that runs in the default CI shard.

## Recovery verification

All 5 affected suites run **green against dev Supabase** (23 + 11 tests pass) with **zero `42703`, zero `withGoTrueRetry[deleteUser` warnings, zero `unexpected_failure`** (the two original symptoms). Authoritative ongoing signal: `gh run list --workflow=tenant-integration.yml` green on the PR (AC10).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was the suite red? The seed `UPDATE users` threw `42703` and the teardown FK-blocked deleteUser.
2. Why? mig 112 dropped `users.{workspace_path,repo_url,github_installation_id}`; the tests still referenced them, and the teardown's anonymise sequence was frozen at a pre-mig-064 8-RPC subset.
3. Why didn't the column-drop PR (#5508) update the tests? The tenant-isolation suites are env-gated (`TENANT_INTEGRATION_TEST=1`) and `skipIf`-skip in the default `ci.yml`, so #5508's CI was green; the drift only surfaces in the separate dev-Supabase workflow.
4. Why did the redness persist ~2 days? `tenant-integration.yml` is path-filtered and **not a required check**, so a red run does not block merges and no alert fired.
5. Root cause: a load-bearing cross-tenant-isolation guard runs only in a non-required, non-alerting workflow, so its breakage was invisible to the merge pipeline.

## Versions of Components

- **Version(s) that triggered:** main at `dbf0e89d0` (mig 112 applied) onward.
- **Version(s) that restored:** PR #5583 merge commit.

## Impact details

### Services Impacted

CI verification only. No production service impacted.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none directly — but the cross-tenant isolation property was **unverified in CI** for the window; a real RLS regression could have shipped behind the red-for-environment suite.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

~2-day window where a tenant-isolation regression could have merged undetected; one P1 triage + fix cycle.

## Lessons Learned

### Where we got lucky

No cross-tenant RLS regression actually landed during the ~2-day blind window — the guard was down but nothing it guards against occurred.

### What went well

The fix was verifiable locally against dev Supabase (zero original symptoms), and a new always-on drift guard now catches the teardown-vs-account-delete divergence class in the default CI shard.

### What went wrong

A column-decommission migration (#5508) shipped green without sweeping the env-gated suites that referenced the dropped columns, and the guard's redness was invisible because the workflow is neither required nor alerting.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5585 | Make `tenant-integration.yml` a required check (or alerting) without blocking unrelated PRs, so a red tenant-isolation guard cannot sit unnoticed. | open |
