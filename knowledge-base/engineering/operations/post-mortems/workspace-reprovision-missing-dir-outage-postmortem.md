---
title: "Concierge/leader workspace re-provision dead-ends when the workspace dir is missing on disk"
date: 2026-06-15
incident_pr: "#5367"
incident_window: "latent since the re-provision self-heal graft path shipped; surfaced for a user on 2026-06-15 after a sandbox/host reclaim"
recovery_at: "on merge + deploy of #5367"
suspected_change: "re-provision self-heal clone path (ensure-workspace-repo.ts realGraftRepoClone) never created workspacePath before cloning into a temp subdir of it"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability (Concierge/leader agent turns unusable for the affected user)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability outage, no personal-data breach (no data accessed, altered, or exposed; fix is a recursive mkdir of an already-UUID-validated per-tenant path)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

A user's Concierge dashboard reported every "Fix issue …" run dead-ending with **"the configured CWD `/workspaces/<uuid>` doesn't exist on disk"** and **"No Git repository found."** The `gh` CLI authenticated fine (it could read GitHub issues), but the workspace's local filesystem — where the worktree and code live — was inaccessible. The re-provision self-heal that exists to recover exactly this state never converged.

## Status

resolved — fix landed in #5367 (workspace dir is created before the self-heal clone).

## Symptom

Concierge (and leader) agent turns fail immediately after a sandbox/host reclaim: the shell's CWD is `/workspaces/<uuid>` but that path does not exist as a real directory, so git cannot find a repository and the task cannot proceed. The user perceives the workspace as permanently broken until manual intervention.

## Incident Timeline

- **Start time (detected):** 2026-06-15 (user-reported via Concierge; latent since the graft self-heal shipped)
- **End time (recovered):** on merge + deploy of #5367
- **Duration (MTTR):** ~same-session fix once diagnosed

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-15 | User reported via Concierge that "the workspace fix is still not correctly done" (the prior CWE-22 hardening had not fixed the symptom). |
| agent | 2026-06-15 | Traced root cause to `realGraftRepoClone` cloning into a temp subdir of a possibly-missing `workspacePath`. |
| agent | 2026-06-15 | RED-first test + one-line `mkdir(workspacePath,{recursive:true})` fix landed in #5367. |

## Participants and Systems Involved

Soleur web-platform Concierge + leader agent runtime; per-user/per-tenant workspaces at `/workspaces/<uuid>`; `ensure-workspace-repo.ts` self-heal; GitHub App installation token (untouched).

## Detection (+ MTTD)

- **How detected:** external/manual — user reported via the Concierge chat. No monitor fired because the self-heal failure surfaced as a degraded "workspace reclaimed" message rather than an unhandled error spike.
- **MTTD:** unknown (latent; reported when the user re-ran the task).

## Triggered by

system — a sandbox/host reclaim removed the workspace directory; the self-heal that should recover it could not.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| CWE-22 UUID-validation PR (merged 2026-06-15) should have fixed it | the prior PR touched the resolver feeding this path | it only validates the workspaceId shape before join(); never creates the dir | rejected |
| Self-heal clone never creates the workspace dir before cloning | `realGraftRepoClone` builds `<ws>/.ensure-repo-tmp-<uuid>` and clones there; git creates only the leaf, not missing parents | — | confirmed |

## Resolution

Added `await mkdir(workspacePath, { recursive: true })` as the first statement of `realGraftRepoClone()` (the shared chokepoint for both the leader `agent-runner.ts` and Concierge `cc-reprovision.ts` callers), mirroring the operative behavior the signup path (`workspace.ts:111`) already had. One production line + a RED-first ordering test.

## Recovery verification

`grep -c 'await mkdir(workspacePath' apps/web-platform/server/ensure-workspace-repo.ts` → `1`; graft-race + 5 consumer suites green (76 tests); full web-platform vitest suite 10,105 passed / 0 failed; `tsc --noEmit` clean. Post-deploy: a cold dispatch against a reclaimed workspace recreates the dir and clones successfully.

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the workspace dead-end? The CWD `/workspaces/<uuid>` did not exist on disk and git found no repo.
2. Why didn't the self-heal recover it? `realGraftRepoClone` cloned into a temp subdir of `workspacePath` and `git clone` failed on the missing parent.
3. Why was the parent missing? A sandbox/host reclaim removed the workspace directory.
4. Why didn't the clone create it? The function assumed the parent already existed — only the signup path called `ensureDir(workspacePath)`; the re-provision path never did.
5. Why was the asymmetry not caught? The two paths (signup vs. self-heal) were never tested against a genuinely-absent workspace dir; the self-heal's own tests mocked the parent as present.

## Versions of Components

- **Version(s) that triggered the outage:** all builds carrying the graft self-heal path without the parent-dir mkdir.
- **Version(s) that restored the service:** the build deploying #5367.

## Impact details

### Services Impacted

Concierge dashboard and leader agent sessions for any user whose workspace directory was reclaimed.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: high for affected users — agent work fully blocked until recovery; the self-heal that should have been transparent did not converge.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none (no charge/data effect).
- OAuth installation owner: none (token auth unaffected; only the local clone failed).

### Revenue Impact

None directly; degraded product experience for affected user(s).

### Team Impact

One diagnosis/fix session.

## Lessons Learned

### Where we got lucky

The failure was fail-soft (a degraded "workspace reclaimed" message, not data loss) — no corruption, and the fix is a single idempotent mkdir.

### What went well

The prior CWE-22 hardening was correctly ruled out fast; the root cause was traced to the exact chokepoint shared by both callers, so one line fixes both.

### What went wrong

The signup and self-heal paths diverged on a load-bearing precondition (does the workspace dir exist?) and the divergence was invisible until a real reclaim hit a user.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR (#5367) with a regression test and no residual work._
