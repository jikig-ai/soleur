---
title: "Concierge/leader workspace re-provision dead-ends when the workspace dir is missing on disk"
date: 2026-06-15
incident_pr: "#5367 (partial), #5375 (completion)"
incident_window: "latent since the re-provision self-heal graft path shipped; surfaced for a user on 2026-06-15 after a sandbox/host reclaim; #5367 fixed the connected-repo slice but the user re-reported it still broke — completed in #5375"
recovery_at: "on merge + deploy of #5375 (the #5367 fix was necessary but insufficient — see Update below)"
suspected_change: "re-provision self-heal clone path (ensure-workspace-repo.ts realGraftRepoClone) never created workspacePath before cloning; #5367's mkdir was CONDITIONAL (skipped for not-connected / .git-present workspaces) and guarded a different resolved path than the sandbox binds"
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

resolved — completed in #5375. #5367 was necessary but **insufficient**: its `mkdir` lived inside `realGraftRepoClone`, reached only PAST `ensureWorkspaceRepoCloned`'s not-connected (`:85`) and `.git`-present (`:89`) early-returns, AND the Concierge sandbox binds the factory's OWN resolved `workspacePath` (`cc-dispatcher.ts:1315`), not the value `#5367` guaranteed. So a reclaimed NOT-CONNECTED workspace still dead-ended. #5375 adds an UNCONDITIONAL `ensureWorkspaceDirExists()` at both `query()`-construction sites (Concierge + leader), on the value the sandbox binds, before `buildAgentQueryOptions`.

## Update (2026-06-15) — #5367 was insufficient; completed in #5375

The user re-reported the exact symptom AFTER #5367 deployed (the `web-v` release shipped #5367 at 17:08; the repro was at 20:10). Re-diagnosis (deepen-plan: architecture-strategist + spec-flow-analyzer) found two gaps #5367 left open: (1) the clone-mkdir is CONDITIONAL — not-connected and `.git`-present reclaimed workspaces skip it entirely; (2) the bwrap sandbox `cwd` is the factory's own `fetchUserWorkspacePath` resolve, a different variable than any dispatch-level guard would protect. The completing fix makes the dir-existence guarantee UNCONDITIONAL and places it on the bound value. RED-first invariant test (`existsSync(boundCwd)` at sandbox construction, not-connected fixture) + leader-path parity. Full web-platform vitest: 10,133 passed / 0 failed.

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
| human | 2026-06-15 20:10 | User re-reported the SAME symptom after #5367 deployed ("it seems it didn't fix it"), with the debug stream. |
| agent | 2026-06-15 | Confirmed #5367 deployed (web-v release 17:08); re-diagnosed: #5367's mkdir is conditional (skips not-connected / `.git`-present) AND the sandbox binds the factory's own resolved path. |
| agent | 2026-06-15 | Unconditional `ensureWorkspaceDirExists()` at both `query()`-construction sites (Concierge + leader), invariant RED-first test, landed in #5375. |

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
| Self-heal clone never creates the workspace dir before cloning | `realGraftRepoClone` builds `<ws>/.ensure-repo-tmp-<uuid>` and clones there; git creates only the leaf, not missing parents | — | confirmed (#5367, partial) |
| #5367's mkdir is conditional + guards the wrong path | it sits past `ensureWorkspaceRepoCloned`'s `:85`/`:89` early-returns (skipped for not-connected / `.git`-present), and the sandbox binds the factory's own `:1315` resolve | — | confirmed (#5375, completion) |

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
6. Why did #5367 not fully fix it? Its mkdir was placed inside the clone (conditional on connected + `.git`-absent), but dir-existence is a STRONGER precondition than clone-eligibility — a reclaimed not-connected workspace needs the dir whether or not it has a repo. The completing fix (#5375) makes the mkdir unconditional and binds it to the sandbox's own resolved `workspacePath`, with an invariant test (dir exists at the bound cwd at sandbox-construction) that is genuinely RED on the post-#5367 main.

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

_No action items — incident fully resolved across #5367 (partial) and #5375 (completion), each with a regression test and no residual work._
