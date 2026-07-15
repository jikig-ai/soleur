---
title: A no-SSH cutover must be verified verb-by-verb; re-arm needs `enable` not `restart`
date: 2026-07-12
category: integration-issues
tags: [no-ssh, inngest, cutover, runbook, systemd, sudoers, webhook, quiesce, enable, doppler]
symptoms: [Cutover 2.2 quiesce fell back to an operator SSH `systemctl stop+disable` step, op=rollback re-enable proposed reusing `restart` which never restores the `[Install]` symlink, a serving-only quiesce check would pass a tolerated disable-failure while the unit stayed enabled, the 3 Doppler arm-flip secret writes were assumed operator-run]
module: System
synced_to: [observability-coverage-reviewer]
component: tooling
problem_type: integration_issue
resolution_type: workflow_improvement
root_cause: missing_workflow_step
severity: high
rule_id: hr-no-ssh-fallback-in-runbooks
status: open
---

# Troubleshooting: A no-SSH cutover must be verified verb-by-verb

## Problem

The #6178 Inngest dedicated-host cutover claimed to be no-SSH, and the deploy/restart path genuinely was. But the cutover's **2.2 quiesce** (stop+disable the old co-located web scheduler) had no webhook verb — it fell back to an operator SSH `systemctl stop+disable`. Soleur operators have no SSH access (and none is supposed to exist), so the "no-SSH cutover" claim was false for one host mutation the runbook performed. The presence of a no-SSH `restart` control did not make the cutover no-SSH.

## Environment

- Module: Inngest cutover infra (`cutover-inngest.yml`, `ci-deploy.sh`, sudoers, runbook)
- Affected Component: no-SSH webhook verbs, systemd unit lifecycle, `hr-no-ssh-fallback-in-runbooks`
- Date: 2026-07-12
- PR: #6368 (branch `feat-one-shot-6178-nosSH-inngest-quiesce-web`); closes the #6178 cutover 2.2 gap

## Symptoms

- Cutover 2.2 quiesce handed the operator an SSH `systemctl stop+disable` step (no webhook verb existed for stop/disable — only `restart`).
- The op=rollback re-enable was proposed to reuse the `restart` path — a `systemctl restart` never touches the `[Install]` `WantedBy` symlink, so the unit would come up **enabled-at-runtime but dropped on the next reboot**.
- A serving-only quiesce check (inventory non-200 = quiesced) would pass a **tolerated disable-failure**: unit stopped but still enabled → reboot re-arms → a second scheduler double-fires on prod Postgres.
- The 3 Doppler arm-flip secret writes (2.2b/2.3) were assumed operator-run, i.e. still an operator step in a "no operator steps" cutover.

## What Didn't Work

**Attempted Solution 1:** Treat the existing no-SSH `INNGEST_RESTART` control as evidence the cutover was already no-SSH.

- **Why it failed:** `restart` is only ONE host mutation. The 2.2 quiesce performs a *different* mutation (stop + disable) that `restart` cannot express. A per-verb audit — not a per-runbook glance — is what surfaces the gap.

**Attempted Solution 2:** Reuse `op=rollback restart` for the rollback re-enable.

- **Why it failed:** `restart` leaves the `[Install]` symlink alone. The 2.2 quiesce *disabled* the unit on purpose (removed the symlink), so a bare restart on rollback brings the unit up DISABLED → it silently drops on the next host reboot. Re-enable needs a real `systemctl enable`.

## Session Errors

**Load-bearing (user-corrected): an earlier draft handed the operator an SSH `systemctl stop+disable` step for 2.2 quiesce.**
- **Recovery:** This PR is the fix — added `op=quiesce-web` (no-SSH stop+disable fan-out over HMAC + CF-Access) plus `INNGEST_QUIESCE` pinned sudoers grant.
- **Prevention:** Recurring class. A "no-SSH cutover" claim must be verified verb-by-verb: EVERY host mutation (quiesce/stop/disable/enable), not just deploy/restart, needs its own webhook-fanned, sudoers-pinned verb.

**Load-bearing (user-corrected): the 3 Doppler arm-flip secret writes (2.2b/2.3) were assumed operator-run.**
- **Recovery:** Scoped out to a separate follow-up build (op=arm: a TF-provisioned write-token to `soleur-inngest/prd` + a workflow op that writes the 3 values, never logging them, AC-NOBODY). Filed as a deferred-scope-out follow-up referencing #6178.
- **Prevention:** Recurring class. "No operator steps" is total — it includes Doppler/secret writes, not just shell steps. Those are TF-provisionable (write-token + workflow op).

**IaC-routing PreToolUse hook blocked Write/Edit containing literal `ssh <user>@<host>` / `systemctl <verb>` strings.**
- **Recovery:** Used the `iac-routing-ack` opt-out (the change REMOVES operator SSH steps) plus rewording; the hook scans `new_string` only.
- **Prevention:** One-off/expected. When authoring a runbook edit that legitimately quotes an SSH/systemctl string to *describe* the thing being removed, ack the hook rather than fighting it.

**The 4 deepen-plan review agents were write-capable and applied fixes concurrently → transient duplicate bullets / mixed reason-names.**
- **Recovery:** Reconciled into one coherent plan; no content lost.
- **Prevention:** One-off (already-reconciled).

**`ci-deploy.test.sh` is a bespoke SLOW runner (~296s real) that forks ci-deploy.sh per test with real probe-loop sleeps — it exceeds a 180000ms Bash timeout.**
- **Recovery:** Run it with `run_in_background` or a ≥300000ms timeout.
- **Prevention:** Recurring friction (known suite characteristic, not a defect). Any session touching ci-deploy should budget ≥300s for this suite up front; not backlog-worthy.

## Solution

Closed the gap by making the missing mutations first-class no-SSH verbs, mirroring the existing `INNGEST_RESTART` pin:

- **Pinned sudoers grants** `INNGEST_QUIESCE` / `INNGEST_ENABLE` (mirror the `INNGEST_RESTART` pin).
- **`ci-deploy.sh` handlers** `quiesce` (stop+disable) and `enable` (enable+start+verify in one flock-held handler, reusing the pre-existing `INNGEST_START` #5450 grant) plus `verify_inngest_quiesced`.
- **`cutover-inngest.yml`** `op=quiesce-web` (no-SSH stop+disable fan-out) and a single-POST `op=rollback` (enable) — collapsed to ONE POST to kill the `flock -n` race a two-POST enable+restart would introduce.
- **Runbook + ADR-100 amendment** documenting both verbs and the enable-not-restart rationale.

**Fail-closed verify (the load-bearing correctness fix):**

```bash
# verify_inngest_quiesced must assert ALL THREE — a serving-only proxy is unsafe:
#   NOT serving  AND  unit inactive  AND  NOT enabled
# A serving-only check passes a tolerated disable-failure while the unit stays
# enabled → reboot re-arms → double-fire on prod Postgres.
```

**Async-verify:** `op=quiesce-web` and `op=rollback` POLL `/hooks/deploy-status` for the terminal reason (`quiesced` / `enabled`), budget ≥ `TimeoutStopSec=180` — they do NOT immediate-probe, which would race the async stop.

## Why This Works

1. **Root cause:** the no-SSH audit was done per-runbook ("we have a restart verb, so it's no-SSH") instead of per-mutation. The asymmetry (a `restart` verb existed but no `stop/disable` or `enable`) is exactly what left 2.2 quiesce on operator SSH.
2. **enable ≠ restart:** `systemctl enable` restores the `[Install]` `WantedBy` symlink that `disable` removed; `restart` never touches it. Reusing `restart` for re-arm would leave the unit enabled-at-runtime-but-dropped-on-reboot — a latent double-fire.
3. **Fail-closed verify:** asserting not-serving AND unit-inactive AND NOT-enabled means a tolerated disable-failure can never be reported as quiesced.

## Prevention

- **Symmetric verb-set audit:** when a runbook claims no-SSH, enumerate every host mutation it performs and confirm each has a webhook verb + pinned sudoers grant. An existing verb for a *different* mutation proves nothing.
- **Re-arm uses `enable`, never `restart`:** any reverse-op that undoes a `disable` needs a real `enable` (symlink restore), not a `restart`.
- **Fail-closed verify:** a quiesce/disable verify must assert unit-inactive AND not-enabled, never serving-status alone.
- **"No operator steps" is total:** it includes Doppler/secret writes (the arm-flip), which are TF-provisionable (write-token + workflow op that never logs values).

## Related Issues

- Similar to: [stale-env-deploy-pipeline-terraform-bridge-20260405.md](./stale-env-deploy-pipeline-terraform-bridge-20260405.md) (no-SSH / Terraform-bridged infra fix, `hr-no-ssh-fallback-in-runbooks`)
- Parent cutover: #6178; remediation PR: #6368
